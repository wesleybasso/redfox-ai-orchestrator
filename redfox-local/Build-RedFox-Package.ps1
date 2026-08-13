[CmdletBinding()]
param(
    [string]$TrioSource = (Join-Path (Split-Path -Parent $PSScriptRoot) 'packages\ai-trio'),
    [string]$OutputRoot = (Join-Path $env:USERPROFILE 'Downloads'),
    [string]$PackageName = 'RedFox-Instalador'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $TrioSource 'install.ps1'))) { throw "Pacote ai-trio-skills invalido: $TrioSource" }

$target = Join-Path $OutputRoot $PackageName
if (Test-Path $target) { $target = Join-Path $OutputRoot ("$PackageName-" + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$redfoxTarget = Join-Path $target 'redfox-local'
$trioTarget = Join-Path $target 'packages\ai-trio'
$skillTarget = Join-Path $target 'skills\redfox'
[IO.Directory]::CreateDirectory($redfoxTarget) | Out-Null
[IO.Directory]::CreateDirectory($trioTarget) | Out-Null
[IO.Directory]::CreateDirectory($skillTarget) | Out-Null

foreach ($name in @('RedFox.Core.psm1','RedFox.Setup.psm1','RedFox.Service.ps1','RedFox.Client.ps1','RedFox.Console.ps1','Install-RedFoxCommand.ps1','Install-RedFox.ps1','Install-RedFox-Suite.ps1','Configure-RedFox.ps1','patch-mco-windows.ps1','install-linux.sh','configure-linux.sh')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $redfoxTarget $name)
}
Copy-Item -Path (Join-Path $TrioSource '*') -Destination $trioTarget -Recurse
Copy-Item -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\redfox\*') -Destination $skillTarget -Recurse
foreach ($name in @('install.ps1','install-skill.ps1','install-linux.sh','install-skill.sh')) {
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) $name) -Destination (Join-Path $target $name)
}

$installCmd = @'
@echo off
setlocal
set "ROOT=%~dp0"
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if not exist "%PWSH%" (
  echo Instalando PowerShell 7...
  winget install --id Microsoft.PowerShell --exact --accept-package-agreements --accept-source-agreements --silent
)
if not exist "%PWSH%" (
  echo Nao foi possivel localizar o PowerShell 7. Atualize o App Installer e tente novamente.
  pause
  exit /b 1
)
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%ROOT%install.ps1" -PackageRoot "%ROOT%"
echo.
pause
'@
$configureCmd = @'
@echo off
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\RedFox\Configure-RedFox.ps1"
pause
'@
[IO.File]::WriteAllText((Join-Path $target 'INSTALAR-REDFOX.cmd'), $installCmd, [Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $target 'CONFIGURAR-CONTAS.cmd'), $configureCmd, [Text.Encoding]::ASCII)
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'install-linux.sh') -Destination (Join-Path $target 'INSTALAR-REDFOX.sh')

$zipPath = "$target.zip"
Compress-Archive -Path (Join-Path $target '*') -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "Pacote criado: $target" -ForegroundColor Green
Write-Host "ZIP para compartilhar: $zipPath" -ForegroundColor Green
