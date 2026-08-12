<#
.SYNOPSIS
    Aplica as correcoes de portabilidade que o MCO 0.11.0 precisa para rodar no Windows.

.DESCRIPTION
    O MCO 0.11.0 assume um ambiente POSIX e nao funciona no Windows sem patch.
    Sao tres defeitos, em ordem de severidade:

      1. os.getuid() em runtime/adapters/shim.py e runtime/acp/adapter.py.
         Nao existe no Windows -> AttributeError em toda invocacao. Nada roda.

      2. subprocess.Popen(["claude", ...]) sem resolver PATHEXT.
         No Windows os CLIs sao shims .CMD e o Popen so aceita argv[0] com
         caminho completo -> WinError 2 em claude e gemini. O codex escapa
         porque tem um .exe nativo no PATH.

      3. Despacho via cmd.exe trunca argumentos com quebra de linha.
         Este e o mais traicoeiro: nao da erro. O prompt do MCO e multilinha,
         entao o agente recebia so a primeira linha (o cabecalho) e respondia
         "nao recebi nenhuma tarefa". A correcao resolve o shim .CMD ate o
         binario nativo (claude.exe) ou ate o par node + entrypoint (gemini.js),
         tirando o cmd.exe do caminho.

    O script e idempotente: rodar de novo em cima de um pacote ja corrigido nao
    muda nada. Reaplique depois de cada `npm install -g @tt-a1i/mco`.

.EXAMPLE
    .\scripts\patch-mco-windows.ps1
    .\scripts\patch-mco-windows.ps1 -WhatIf
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$McoRoot
)

$ErrorActionPreference = 'Stop'

function Resolve-McoRoot {
    param([string]$Explicit)

    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) {
            throw "Caminho informado nao existe: $Explicit"
        }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }

    $npmPrefix = (& npm prefix -g 2>$null)
    if (-not $npmPrefix) {
        throw 'Nao consegui descobrir o prefixo global do npm. Passe -McoRoot manualmente.'
    }

    $candidate = Join-Path $npmPrefix 'node_modules\@tt-a1i\mco'
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw "MCO nao encontrado em $candidate. Instale com: npm install -g @tt-a1i/mco@latest"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

# Substitui $Old por $New em $Path. Devolve 'patched', 'already' ou 'missing'.
# $Marker identifica um patch ja aplicado, garantindo idempotencia.
function Set-FileContentPatch {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Old,
        [Parameter(Mandatory)][string]$New,
        [Parameter(Mandatory)][string]$Marker
    )

    if (-not (Test-Path -LiteralPath $Path)) { return 'missing' }

    $content = Get-Content -LiteralPath $Path -Raw
    if ($content.Contains($Marker)) { return 'already' }
    if (-not $content.Contains($Old)) { return 'missing' }

    if ($PSCmdlet.ShouldProcess($Path, 'Aplicar patch de portabilidade')) {
        $backup = "$Path.orig"
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $Path -Destination $backup
        }
        # -NoNewline preserva o arquivo byte a byte fora do trecho substituido.
        Set-Content -LiteralPath $Path -Value $content.Replace($Old, $New) -NoNewline -Encoding utf8
    }
    return 'patched'
}

$root = Resolve-McoRoot -Explicit $McoRoot
Write-Host "MCO: $root"

$shimPath = Join-Path $root 'runtime\adapters\shim.py'
$acpPath = Join-Path $root 'runtime\acp\adapter.py'

$results = [ordered]@{}

# --- Defeito 1: os.getuid() ------------------------------------------------

$getuidOld = '"artifact_root", os.path.join(tempfile.gettempdir(), "mco-{}".format(os.getuid())),'
$getuidNew = @'
"artifact_root", os.path.join(tempfile.gettempdir(), "mco-{}".format(
                os.getuid() if hasattr(os, "getuid") else os.environ.get("USERNAME", "user")
            )),
'@.TrimEnd("`r", "`n")

$results['shim.py / os.getuid'] = Set-FileContentPatch -Path $shimPath `
    -Old $getuidOld -New $getuidNew -Marker 'hasattr(os, "getuid")'

$results['acp/adapter.py / os.getuid'] = Set-FileContentPatch -Path $acpPath `
    -Old $getuidOld -New $getuidNew -Marker 'hasattr(os, "getuid")'

# --- Defeitos 2 e 3: resolucao do shim .CMD --------------------------------

$results['shim.py / import re'] = Set-FileContentPatch -Path $shimPath `
    -Old "import json`nimport os`nimport shutil" `
    -New "import json`nimport os`nimport re`nimport shutil" `
    -Marker 'import re'

$unwrapOld = @'
    return env


class ShimAdapterBase:
'@
$unwrapNew = @'
    return env


# npm shims quote their target path and reference the shim directory as %dp0%.
_SHIM_TARGET_RE = re.compile(r'"([^"]*%dp0%[^"]*)"')


def _unwrap_windows_shim(executable: str) -> List[str]:
    """Resolve an npm .cmd/.bat shim down to the native command it wraps.

    Returns an argv prefix: [foo.exe] for native binaries, [node, cli.js] for
    Node entrypoints. Falls back to [executable] whenever the shim shape is not
    recognised, and is a no-op off Windows.
    """
    if os.name != "nt" or not executable.lower().endswith((".cmd", ".bat")):
        return [executable]
    try:
        text = Path(executable).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return [executable]

    shim_dir = os.path.dirname(executable)
    # The real target is the last quoted path; earlier ones are probe branches.
    for raw in reversed(_SHIM_TARGET_RE.findall(text)):
        target = os.path.normpath(raw.replace("%dp0%", shim_dir + os.sep))
        if not os.path.isfile(target):
            continue
        lowered = target.lower()
        if lowered.endswith(".exe"):
            return [target]
        if lowered.endswith((".js", ".mjs", ".cjs")):
            node = shutil.which("node")
            if node:
                return [node, target]
    return [executable]


class ShimAdapterBase:
'@

$results['shim.py / _unwrap_windows_shim'] = Set-FileContentPatch -Path $shimPath `
    -Old $unwrapOld -New $unwrapNew -Marker '_unwrap_windows_shim'

$popenOld = @'
        stdout_file = stdout_path.open("w", encoding="utf-8")
        stderr_file = stderr_path.open("w", encoding="utf-8")
        try:
            process = subprocess.Popen(
                cmd,
'@
$popenNew = @'
        stdout_file = stdout_path.open("w", encoding="utf-8")
        stderr_file = stderr_path.open("w", encoding="utf-8")
        child_env = _sanitize_env()
        # On Windows the provider CLIs are .CMD shims. Popen does not resolve
        # PATHEXT for argv[0], and dispatching through cmd.exe truncates any
        # argument containing a newline -- which silently drops everything after
        # the first line of the prompt. Resolve the shim to the native command.
        resolved = shutil.which(cmd[0], path=child_env.get("PATH"))
        if resolved:
            cmd = [*_unwrap_windows_shim(resolved), *cmd[1:]]
        try:
            process = subprocess.Popen(
                cmd,
'@

$results['shim.py / resolver argv[0]'] = Set-FileContentPatch -Path $shimPath `
    -Old $popenOld -New $popenNew -Marker 'PATHEXT for argv[0]'

$envOld = @'
                text=True,
                start_new_session=True,
                env=_sanitize_env(),
            )
'@
$envNew = @'
                text=True,
                start_new_session=True,
                env=child_env,
            )
'@

$results['shim.py / reusar child_env'] = Set-FileContentPatch -Path $shimPath `
    -Old $envOld -New $envNew -Marker 'env=child_env,'

# --- Defeito 4: adapter Qwen desatualizado ---------------------------------
# O adapter foi escrito para o Qwen Code 0.10.x e passa o prompt como
# argumento posicional -- o que na 0.11+ cai em modo interativo e trava ate o
# stall timeout. Alem disso fixa --auth-type qwen-oauth, cujo tier gratuito foi
# descontinuado em 2026-04-15.

$qwenPath = Join-Path $root 'runtime\adapters\qwen.py'

$results['qwen.py / import os'] = Set-FileContentPatch -Path $qwenPath `
    -Old "from __future__ import annotations`n`nfrom typing import Any, List" `
    -New "from __future__ import annotations`n`nimport os`nfrom typing import Any, List" `
    -Marker 'import os'

$authHelperOld = @'
class QwenAdapter(ShimAdapterBase):
'@
$authHelperNew = @'
_QWEN_AUTH_TYPES = ("openai", "anthropic", "qwen-oauth", "gemini", "vertex-ai")


def _qwen_auth_type() -> str:
    """Auth type for the Qwen CLI, overridable via MCO_QWEN_AUTH_TYPE.

    Defaults to "openai" (DashScope or any OpenAI-compatible endpoint) because
    the qwen-oauth free tier was discontinued on 2026-04-15.
    """
    value = (os.environ.get("MCO_QWEN_AUTH_TYPE") or "").strip()
    return value if value in _QWEN_AUTH_TYPES else "openai"


class QwenAdapter(ShimAdapterBase):
'@

$results['qwen.py / auth-type configuravel'] = Set-FileContentPatch -Path $qwenPath `
    -Old $authHelperOld -New $authHelperNew -Marker '_qwen_auth_type'

$results['qwen.py / probe headless'] = Set-FileContentPatch -Path $qwenPath `
    -Old 'return [binary, "Reply with exactly OK", "--output-format", "text", "--auth-type", "qwen-oauth"]' `
    -New 'return [binary, "-p", "Reply with exactly OK", "--output-format", "text", "--auth-type", _qwen_auth_type()]' `
    -Marker '[binary, "-p", "Reply with exactly OK"'

$promptOld = @'
        return [
            "qwen", input_task.prompt, "--output-format", "json", "--auth-type", "qwen-oauth",
            "--approval-mode", str(mode),
        ]
'@
$promptNew = @'
        # Qwen Code >= 0.11 only runs headless when the prompt arrives via -p;
        # a positional prompt drops it into interactive mode, where the shim
        # would block until the stall timeout instead of answering.
        return [
            "qwen", "-p", input_task.prompt, "--output-format", "json", "--auth-type", _qwen_auth_type(),
            "--approval-mode", str(mode),
        ]
'@

$results['qwen.py / prompt via -p'] = Set-FileContentPatch -Path $qwenPath `
    -Old $promptOld -New $promptNew -Marker '"qwen", "-p", input_task.prompt'

$recordOld = @'
            "qwen", "<prompt>", "--output-format", "json", "--auth-type", "qwen-oauth",
'@
$recordNew = @'
            "qwen", "-p", "<prompt>", "--output-format", "json", "--auth-type", _qwen_auth_type(),
'@

$results['qwen.py / comando de registro'] = Set-FileContentPatch -Path $qwenPath `
    -Old $recordOld -New $recordNew -Marker '"qwen", "-p", "<prompt>"'

# --- Relatorio -------------------------------------------------------------

$failed = $false
foreach ($entry in $results.GetEnumerator()) {
    switch ($entry.Value) {
        'patched' { Write-Host ("  [OK]       {0}" -f $entry.Key) -ForegroundColor Green }
        'already' { Write-Host ("  [JA FEITO] {0}" -f $entry.Key) -ForegroundColor DarkGray }
        'missing' {
            Write-Host ("  [FALHOU]   {0} - trecho esperado nao encontrado" -f $entry.Key) -ForegroundColor Red
            $failed = $true
        }
    }
}

if ($failed) {
    Write-Host ''
    Write-Host 'Algum trecho mudou nesta versao do MCO. Verifique se ja existe correcao upstream.' -ForegroundColor Yellow
    exit 1
}

Write-Host ''
Write-Host 'Patches aplicados. Valide com: mco doctor' -ForegroundColor Green
