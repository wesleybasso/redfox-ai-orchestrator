$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'RedFox.Setup.psm1'
if (-not (Test-Path -LiteralPath $module)) { throw 'RED: RedFox.Setup.psm1 ainda nao existe.' }
Import-Module $module -Force

$missing = [pscustomobject]@{
    Winget = $true; Ollama = $false; Node = $false; Pwsh = $false
    Mco = $false; Claude = $false; Codex = $false; Gemini = $false
    Model = $false; Integration = $false; Service = $false
}
$plan = @(Get-RedFoxSetupPlan -State $missing -Model 'gemma3:1b')
foreach ($id in @('powershell','node','ollama','mco','claude','codex','gemini','model','integration','service')) {
    if ($id -notin $plan.Id) { throw "Plano nao incluiu: $id" }
}
if (($plan | Where-Object Id -eq 'model').Command -notmatch 'gemma3:1b') { throw 'Modelo local incorreto no plano.' }

$ready = $missing.PSObject.Copy()
foreach ($property in $ready.PSObject.Properties) { if ($property.Name -ne 'Winget') { $property.Value = $true } }
if (@(Get-RedFoxSetupPlan -State $ready -Model 'gemma3:1b').Count -ne 0) { throw 'Plano deveria estar vazio em maquina pronta.' }

$parsed = ConvertFrom-RedFoxBrainAnswer -Text '{"mode":"conselho","specialist":"claude","reason":"arquitetura"}' -AllowedProviders @('claude','codex')
if ($parsed.Mode -ne 'conselho' -or $parsed.Specialist -ne 'claude') { throw 'Resposta valida do cerebro nao foi interpretada.' }
$fallback = ConvertFrom-RedFoxBrainAnswer -Text 'texto invalido' -AllowedProviders @('claude','codex')
if ($fallback) { throw 'Resposta invalida deveria acionar fallback deterministico.' }

$decision = Invoke-RedFoxLocalBrain -Task 'Escolha a arquitetura' -Providers @('claude','codex') -Model 'gemma3:1b' -Transport {
    param($Uri, $Body)
    [pscustomobject]@{ message = [pscustomobject]@{ content = '{"mode":"conselho","specialist":"claude","reason":"decisao importante"}' } }
}
if ($decision.Mode -ne 'conselho' -or $decision.Specialist -ne 'claude') { throw 'Cerebro local nao aplicou a resposta do transporte.' }

$evaluation = Test-RedFoxMissionCompletion -Task 'Revise a arquitetura' -ResultText 'A resposta deixou riscos sem analisar.' -Model 'gemma3:1b' -Transport {
    param($Uri, $Body)
    [pscustomobject]@{ message=[pscustomobject]@{ content='{"complete":false,"follow_up":"Analise os riscos omitidos","reason":"incompleto"}' } }
}
if ($evaluation.Complete -or $evaluation.FollowUp -notmatch 'riscos') { throw 'A RedFox nao transformou critica local em nova instrucao.' }
$contradiction = Test-RedFoxMissionCompletion -Task 'Revise' -ResultText 'parcial' -Transport {
    param($Uri, $Body)
    [pscustomobject]@{ message=[pscustomobject]@{ content='{"complete":true,"follow_up":"Verifique a seguranca","reason":"ainda falta"}' } }
}
if ($contradiction.Complete) { throw 'Avaliacao contraditoria com follow-up nao pode encerrar a missao.' }

Write-Host 'PASS: plano de instalacao e interpretacao do cerebro local.'
