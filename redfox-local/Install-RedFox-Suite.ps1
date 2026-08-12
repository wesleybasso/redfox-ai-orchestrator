[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Model = 'gemma3:1b',
    [string]$TrioPackagePath = (Join-Path $env:USERPROFILE 'Downloads\ai-trio-skills'),
    [switch]$SkipConfiguration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedFox.Setup.psm1') -Force

function Refresh-ProcessPath {
    $machine = [Environment]::GetEnvironmentVariable('Path','Machine')
    $user = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = "$machine;$user"
    $ollamaDir = Join-Path $env:LOCALAPPDATA 'Programs\Ollama'
    if ((Test-Path $ollamaDir) -and $env:Path -notlike "*$ollamaDir*") { $env:Path += ";$ollamaDir" }
}

function Invoke-External([string]$File, [string[]]$Arguments) {
    Write-Host "`n>> $File $($Arguments -join ' ')" -ForegroundColor Cyan
    if ($PSCmdlet.ShouldProcess("$File $($Arguments -join ' ')", 'Executar etapa')) {
        & $File @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Etapa falhou com codigo ${LASTEXITCODE}: $File" }
    }
}

Write-Host 'REDFOX - INSTALACAO COMPLETA' -ForegroundColor Red
Write-Host 'Ollama + cerebro local + Claude + Codex + Gemini + MCO' -ForegroundColor White

$state = Get-RedFoxMachineState -Model $Model -TrioPackagePath $TrioPackagePath -ServiceSourcePath $PSScriptRoot
$plan = @(Get-RedFoxSetupPlan -State $state -Model $Model)
$planIds = @($plan | ForEach-Object Id)
if ($plan.Count -eq 0) { Write-Host 'Componentes principais ja instalados. Verificando configuracao...' -ForegroundColor Green }

foreach ($step in $plan) {
    Write-Host "`n[$($step.Id)] $($step.Title)" -ForegroundColor Yellow
    switch ($step.Id) {
        'powershell' { Invoke-External 'winget' @('install','--id','Microsoft.PowerShell','--exact','--accept-package-agreements','--accept-source-agreements','--silent'); Refresh-ProcessPath }
        'node'       { Invoke-External 'winget' @('install','--id','OpenJS.NodeJS.LTS','--exact','--accept-package-agreements','--accept-source-agreements','--silent'); Refresh-ProcessPath }
        'ollama'     { Invoke-External 'winget' @('install','--id','Ollama.Ollama','--exact','--accept-package-agreements','--accept-source-agreements','--silent'); Refresh-ProcessPath }
        'mco'        { Refresh-ProcessPath; Invoke-External 'npm' @('install','--global','@tt-a1i/mco@0.11.0') }
        'claude'     { Invoke-External 'npm' @('install','--global','@anthropic-ai/claude-code@2.1.185') }
        'codex'      { Invoke-External 'npm' @('install','--global','@openai/codex@0.147.0') }
        'gemini'     { Invoke-External 'npm' @('install','--global','@google/gemini-cli@0.55.1') }
        'model' {
            Refresh-ProcessPath
            $ollama = Resolve-OllamaExecutable
            if (-not $ollama) { throw 'Ollama foi instalado, mas o executavel nao foi localizado.' }
            try { Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 | Out-Null } catch { Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden; Start-Sleep -Seconds 3 }
            Invoke-External $ollama @('pull',$Model)
        }
        'integration' {
            $installer = Join-Path $TrioPackagePath 'install.ps1'
            if (-not (Test-Path $installer)) { throw "Pacote do trio nao encontrado em $TrioPackagePath" }
            if ($PSCmdlet.ShouldProcess($installer,'Instalar integracao Claude/Codex/Gemini')) { & $installer }
        }
        'service' {
            $installer = Join-Path $PSScriptRoot 'Install-RedFox.ps1'
            if ($PSCmdlet.ShouldProcess($installer,'Instalar servico RedFox')) { & $installer }
        }
    }
}

# O MCO 0.11.0 precisa desta camada de compatibilidade no Windows. O patch e
# idempotente e deve ser reaplicado apos qualquer atualizacao global do pacote.
$mcoPatch = Join-Path $PSScriptRoot 'patch-mco-windows.ps1'
if (-not (Test-Path -LiteralPath $mcoPatch)) { throw "Patch obrigatorio do MCO ausente: $mcoPatch" }
if ($WhatIfPreference) {
    if (Get-Command mco -ErrorAction SilentlyContinue) { & $mcoPatch -WhatIf }
    else { Write-Host 'WhatIf: o patch do MCO sera aplicado depois da instalacao.' }
}
else {
    & $mcoPatch
}

# Os instaladores sao idempotentes; execute novamente para atualizar uma
# instalacao existente sem apagar configuracoes ou credenciais.
if ('integration' -notin $planIds) {
    $trioInstaller = Join-Path $TrioPackagePath 'install.ps1'
    if ((Test-Path $trioInstaller) -and $PSCmdlet.ShouldProcess($trioInstaller,'Atualizar integracao do trio')) { & $trioInstaller }
}
if ('service' -notin $planIds) {
    $serviceInstaller = Join-Path $PSScriptRoot 'Install-RedFox.ps1'
    if ($PSCmdlet.ShouldProcess($serviceInstaller,'Atualizar servico RedFox')) { & $serviceInstaller }
}

$configPath = Join-Path $env:LOCALAPPDATA 'RedFox\config.json'
if ($PSCmdlet.ShouldProcess($configPath,'Configurar cerebro local')) {
    [IO.Directory]::CreateDirectory((Split-Path $configPath)) | Out-Null
    [IO.File]::WriteAllText($configPath, (@{ brain='ollama'; model=$Model; ollama_uri='http://127.0.0.1:11434' } | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}

if (-not $SkipConfiguration -and -not $WhatIfPreference) {
    & (Join-Path $PSScriptRoot 'Configure-RedFox.ps1')
}

Write-Host "`nRedFox Suite instalada. Abra um novo terminal e diga: RedFox, quais IAs voce encontrou?" -ForegroundColor Green
