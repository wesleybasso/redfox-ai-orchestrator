[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = Split-Path -Parent $PSScriptRoot
$failures = [System.Collections.Generic.List[string]]::new()

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        $failures.Add($Message)
    }
}

function Get-TreeFingerprint {
    param([Parameter(Mandatory)][string]$Root)

    if (-not (Test-Path -LiteralPath $Root)) {
        return ''
    }

    $items = foreach ($file in Get-ChildItem -Recurse -File -LiteralPath $Root | Sort-Object FullName) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        '{0}|{1}' -f $relative, (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
    }
    return ($items -join "`n")
}

function Invoke-Installer {
    param(
        [Parameter(Mandatory)][string]$UserHome,
        [string[]]$Hosts = @('Codex', 'Claude', 'Gemini'),
        [switch]$WhatIf
    )

    $arguments = @(
        '-NoProfile',
        '-File', (Join-Path $packageRoot 'install.ps1'),
        '-UserHome', $UserHome,
        '-Hosts', ($Hosts -join ','),
        '-SkipDependencyCheck'
    )
    if ($WhatIf) {
        $arguments += '-WhatIf'
    }

    & pwsh @arguments | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) "O instalador retornou codigo $LASTEXITCODE."
}

$requiredFiles = @(
    'install.ps1',
    'versions.lock.json',
    'gemini/GEMINI.fragment.md',
    'gemini/commands/trio.toml',
    'gemini/commands/quinteto.toml'
)
foreach ($relativePath in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot $relativePath)) "Arquivo obrigatorio ausente: $relativePath"
}

$skillFiles = @(
    'claude-code/using-ai-trio/SKILL.md',
    'codex/using-ai-trio/SKILL.md'
)
foreach ($relativePath in $skillFiles) {
    $path = Join-Path $packageRoot $relativePath
    if (Test-Path -LiteralPath $path) {
        $content = Get-Content -Raw -LiteralPath $path
        Assert-True ($content -notmatch 'REQUIRED SUB-SKILL.*mco-cli') "$relativePath ainda exige a skill externa mco-cli."
        Assert-True ($content -match 'does not require another Agent Skill') "$relativePath nao declara a dependencia autocontida."
    }
}

foreach ($name in @('trio.toml', 'quinteto.toml')) {
    $path = Join-Path $packageRoot "gemini/commands/$name"
    if (Test-Path -LiteralPath $path) {
        $content = Get-Content -Raw -LiteralPath $path
        Assert-True ($content -notmatch '%USERPROFILE%') "$name ainda usa sintaxe de cmd.exe."
        Assert-True ($content -match '\$env:USERPROFILE') "$name nao usa USERPROFILE do PowerShell."
        Assert-True ($content -notmatch '"\{\{args\}\}"') "$name ainda adiciona aspas ao placeholder {{args}}."
    }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('ai-trio-package-test-' + [guid]::NewGuid().ToString('N'))
$resolvedTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$resolvedTestRoot = [IO.Path]::GetFullPath($temporaryRoot)
if (-not $resolvedTestRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'O diretorio de teste nao ficou dentro da pasta temporaria.'
}

try {
    New-Item -ItemType Directory -Path $resolvedTestRoot -Force | Out-Null

    if (Test-Path -LiteralPath (Join-Path $packageRoot 'install.ps1')) {
        $cleanHome = Join-Path $resolvedTestRoot 'clean-home'
        New-Item -ItemType Directory -Path $cleanHome -Force | Out-Null
        Invoke-Installer -UserHome $cleanHome

        Assert-True (Test-Path -LiteralPath (Join-Path $cleanHome '.codex/skills/using-ai-trio/SKILL.md')) 'Codex nao recebeu a skill na subpasta correta.'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $cleanHome '.codex/skills/SKILL.md'))) 'Codex recebeu SKILL.md diretamente na raiz de skills.'
        Assert-True (Test-Path -LiteralPath (Join-Path $cleanHome '.claude/skills/using-ai-trio/SKILL.md')) 'Claude nao recebeu a skill na subpasta correta.'
        Assert-True (Test-Path -LiteralPath (Join-Path $cleanHome '.gemini/commands/trio.toml')) 'O comando /trio nao foi instalado.'
        Assert-True (Test-Path -LiteralPath (Join-Path $cleanHome '.gemini/commands/quinteto.toml')) 'O comando /quinteto nao foi instalado.'

        $firstFingerprint = Get-TreeFingerprint -Root $cleanHome
        Invoke-Installer -UserHome $cleanHome
        $secondFingerprint = Get-TreeFingerprint -Root $cleanHome
        Assert-True ($firstFingerprint -eq $secondFingerprint) 'A segunda instalacao alterou arquivos; instalador nao e idempotente.'

        $geminiText = Get-Content -Raw -LiteralPath (Join-Path $cleanHome '.gemini/GEMINI.md')
        Assert-True (([regex]::Matches($geminiText, '<!-- ai-trio:start -->')).Count -eq 1) 'O bloco gerenciado do GEMINI.md foi duplicado.'

        $existingHome = Join-Path $resolvedTestRoot 'existing-home'
        $existingGeminiDir = Join-Path $existingHome '.gemini'
        New-Item -ItemType Directory -Path $existingGeminiDir -Force | Out-Null
        $existingText = "# Configuracao existente`r`n`r`nNAO APAGAR`r`n"
        [IO.File]::WriteAllText((Join-Path $existingGeminiDir 'GEMINI.md'), $existingText, [Text.UTF8Encoding]::new($false))
        Invoke-Installer -UserHome $existingHome -Hosts Gemini
        $mergedText = [IO.File]::ReadAllText((Join-Path $existingGeminiDir 'GEMINI.md'))
        Assert-True ($mergedText.Contains($existingText)) 'O merge do GEMINI.md nao preservou o conteudo existente.'
        Assert-True (([regex]::Matches($mergedText, '<!-- ai-trio:start -->')).Count -eq 1) 'O merge nao criou exatamente um bloco gerenciado.'

        $whatIfHome = Join-Path $resolvedTestRoot 'whatif-home'
        New-Item -ItemType Directory -Path $whatIfHome -Force | Out-Null
        Invoke-Installer -UserHome $whatIfHome -WhatIf
        Assert-True (@(Get-ChildItem -Force -LiteralPath $whatIfHome).Count -eq 0) '-WhatIf modificou o perfil de destino.'
    }
}
finally {
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -Recurse -Force -LiteralPath $resolvedTestRoot
    }
}

$parseErrors = [System.Collections.Generic.List[string]]::new()
foreach ($script in Get-ChildItem -Recurse -Filter '*.ps1' -File -LiteralPath $packageRoot) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($parseError in $errors) {
        $parseErrors.Add("$($script.FullName): $($parseError.Message)")
    }
}
Assert-True ($parseErrors.Count -eq 0) ("Erros de sintaxe PowerShell: " + ($parseErrors -join ' | '))

$claudeSkill = Join-Path $packageRoot 'claude-code/using-ai-trio'
$codexSkill = Join-Path $packageRoot 'codex/using-ai-trio'
if ((Test-Path -LiteralPath $claudeSkill) -and (Test-Path -LiteralPath $codexSkill)) {
    foreach ($relativePath in @('SKILL.md', 'scripts/configure-openrouter.ps1', 'scripts/invoke-trio.ps1')) {
        $left = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $claudeSkill $relativePath)).Hash
        $right = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $codexSkill $relativePath)).Hash
        Assert-True ($left -eq $right) "As copias Claude e Codex divergiram em $relativePath."
    }
}

Assert-True (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'reports'))) 'Artefatos de revisao foram incluidos no pacote distribuivel.'

$suspicious = foreach ($file in Get-ChildItem -Recurse -File -LiteralPath $packageRoot) {
    if ($file.Extension -in @('.md', '.ps1', '.toml', '.json')) {
        $content = Get-Content -Raw -LiteralPath $file.FullName
        if ($content -match 'C:\\Users\\wesle|sk-[A-Za-z0-9_-]{12,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----') {
            $file.FullName
        }
    }
}
Assert-True (@($suspicious).Count -eq 0) ("Possivel dado pessoal ou segredo encontrado: " + ($suspicious -join ', '))

if ($failures.Count -gt 0) {
    Write-Host "FALHOU: $($failures.Count) verificacao(oes)." -ForegroundColor Red
    foreach ($failure in $failures) {
        Write-Host " - $failure" -ForegroundColor Red
    }
    exit 1
}

Write-Host 'OK: pacote pronto para distribuicao.' -ForegroundColor Green
exit 0
