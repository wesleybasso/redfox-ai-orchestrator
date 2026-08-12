$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $root 'RedFox.Core.psm1'
$servicePath = Join-Path $root 'RedFox.Service.ps1'
$clientPath = Join-Path $root 'RedFox.Client.ps1'

if (-not (Test-Path -LiteralPath $modulePath)) { throw 'RED: RedFox.Core.psm1 ainda nao existe.' }
if (-not (Test-Path -LiteralPath $servicePath)) { throw 'RED: RedFox.Service.ps1 ainda nao existe.' }
if (-not (Test-Path -LiteralPath $clientPath)) { throw 'RED: RedFox.Client.ps1 ainda nao existe.' }

Import-Module $modulePath -Force

$originalProcessPath = $env:Path
try {
    $mergedPath = Update-RedFoxProcessPath -MachinePath 'C:\Windows' -UserPath 'C:\Ferramentas\Copilot'
    if ($mergedPath -notmatch [regex]::Escape('C:\Ferramentas\Copilot')) { throw 'PATH do usuario nao foi recarregado para descobrir novas IAs.' }
} finally {
    $env:Path = $originalProcessPath
}

$doctor = @'
{
  "providers": {
    "claude": {"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}},
    "codex": {"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"workspace_write"}},
    "gemini": {"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}},
    "qwen": {"detected":true,"auth_ok":false,"ready":false,"reason":"auth_failed","risk":{"level":"read_only"}},
    "pi": {"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}},
    "novaia": {"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}},
    "hermes": {"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"approval_bypass"}}
  }
}
'@ | ConvertFrom-Json

$agents = @(Get-RedFoxAgents -DoctorData $doctor)
if (($agents | Where-Object Name -eq 'qwen').State -ne 'installed_not_ready') { throw 'Qwen deveria estar registrado, mas fora do conselho.' }

$council = Select-RedFoxCouncil -Agents $agents -Task 'Decida a arquitetura' -Mode conselho
$names = @($council.Providers)
foreach ($expected in @('claude', 'codex', 'gemini', 'pi', 'novaia')) {
    if ($expected -notin $names) { throw "Conselho nao absorveu agente pronto: $expected" }
}
foreach ($blocked in @('qwen', 'hermes')) {
    if ($blocked -in $names) { throw "Conselho incluiu agente indisponivel ou inseguro: $blocked" }
}
if ($council.SynthProvider -ne 'claude') { throw 'Claude deveria ser o sintetizador preferencial.' }

$specialist = Select-RedFoxCouncil -Agents $agents -Task 'Corrija o bug e rode os testes' -Mode especialista
if (@($specialist.Providers).Count -ne 1 -or $specialist.Providers[0] -ne 'codex') { throw 'Tarefa de implementacao deveria ir somente ao Codex.' }

if ((Resolve-RedFoxMode -Task 'Precisamos escolher a arquitetura') -ne 'conselho') { throw 'Arquitetura deveria ativar conselho.' }
if ((Resolve-RedFoxMode -Task 'Corrija o formulario') -ne 'especialista') { throw 'Correcao simples deveria ativar especialista.' }

$script:executionCount = 0
$loop = Invoke-RedFoxAgentLoop -InitialPrompt 'Resolva a missao' -MaxRounds 2 -Executor {
    param($Prompt, $Round)
    $script:executionCount++
    [pscustomobject]@{ status='complete'; round=$Round; answer="resposta-$Round" }
} -Evaluator {
    param($Result, $Round)
    if ($Round -eq 1) { [pscustomobject]@{ Complete=$false; FollowUp='Revise os riscos restantes'; Reason='faltou revisao' } }
    else { [pscustomobject]@{ Complete=$true; FollowUp=$null; Reason='validado' } }
}
if ($script:executionCount -ne 2 -or $loop.Rounds.Count -ne 2 -or $loop.Status -ne 'complete') {
    throw 'O agente nao executou o ciclo planejar, avaliar e corrigir.'
}
if ($loop.Rounds[1].Prompt -notmatch 'Revise os riscos restantes') { throw 'A segunda rodada nao recebeu a critica local.' }

Write-Host 'PASS: descoberta dinamica, bloqueio seguro e selecao do conselho.'
