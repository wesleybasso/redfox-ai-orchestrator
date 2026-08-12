[CmdletBinding()]
param(
    [string]$OutputRoot = (Join-Path $env:USERPROFILE 'Downloads'),
    [string]$SkillSource = (Join-Path (Split-Path -Parent $PSScriptRoot) 'skills\redfox'),
    [string]$TrioSource = (Join-Path (Split-Path -Parent $PSScriptRoot) 'packages\ai-trio'),
    [string]$SkillName = 'RedFox-Somente-Skill',
    [string]$CompleteName = 'RedFox-Programa-Completo'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not (Test-Path (Join-Path $SkillSource 'SKILL.md'))) { throw "Skill RedFox invalida: $SkillSource" }
if (-not (Test-Path (Join-Path $TrioSource 'install.ps1'))) { throw "Pacote do trio invalido: $TrioSource" }
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null

$skillTarget = Join-Path $OutputRoot $SkillName
if (Test-Path $skillTarget) { $skillTarget = Join-Path $OutputRoot ($SkillName + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
$skillFolder = Join-Path $skillTarget 'redfox'
[IO.Directory]::CreateDirectory((Join-Path $skillFolder 'scripts')) | Out-Null
Copy-Item -LiteralPath (Join-Path $SkillSource 'SKILL.md') -Destination (Join-Path $skillFolder 'SKILL.md')
Copy-Item -Path (Join-Path $SkillSource 'scripts\*') -Destination (Join-Path $skillFolder 'scripts')
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'install-skill.sh') -Destination (Join-Path $skillTarget 'INSTALAR-SOMENTE-SKILL.sh')

$skillInstaller = @'
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$source = Join-Path $PSScriptRoot 'redfox'
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($target in @(
    (Join-Path $env:USERPROFILE '.agents\skills\redfox'),
    (Join-Path $env:USERPROFILE '.claude\skills\redfox')
)) {
    [IO.Directory]::CreateDirectory((Split-Path $target)) | Out-Null
    if (Test-Path $target) { Copy-Item -LiteralPath $target -Destination "$target.backup-$timestamp" -Recurse }
    [IO.Directory]::CreateDirectory($target) | Out-Null
    Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse -Force
    Write-Host "Skill instalada: $target" -ForegroundColor Green
}
if (-not (Test-Path (Join-Path $env:USERPROFILE '.codex\skills\using-ai-trio\SKILL.md')) -and
    -not (Test-Path (Join-Path $env:USERPROFILE '.agents\skills\using-ai-trio\SKILL.md'))) {
    Write-Warning 'A RedFox Skill foi instalada, mas precisa da skill using-ai-trio/MCO ja configurada para chamar outras IAs.'
}
Write-Host 'Abra uma nova conversa e escreva: RedFox, qual e a missao?' -ForegroundColor Cyan
'@
$skillCmd = @'
@echo off
set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PWSH%" (
  "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALAR-SOMENTE-SKILL.ps1"
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0INSTALAR-SOMENTE-SKILL.ps1"
)
pause
'@
[IO.File]::WriteAllText((Join-Path $skillTarget 'INSTALAR-SOMENTE-SKILL.ps1'), $skillInstaller, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $skillTarget 'INSTALAR-SOMENTE-SKILL.cmd'), $skillCmd, [Text.Encoding]::ASCII)
$skillZip = "$skillTarget.zip"
Compress-Archive -Path (Join-Path $skillTarget '*') -DestinationPath $skillZip -CompressionLevel Optimal

& (Join-Path $PSScriptRoot 'Build-RedFox-Package.ps1') -TrioSource $TrioSource -OutputRoot $OutputRoot -PackageName $CompleteName
$completeCandidates = @(Get-ChildItem -LiteralPath $OutputRoot -Directory | Where-Object Name -like "$CompleteName*" | Sort-Object LastWriteTime -Descending)
$completeTarget = $completeCandidates[0].FullName

[pscustomobject]@{
    SkillFolder = $skillTarget
    SkillZip = $skillZip
    CompleteFolder = $completeTarget
    CompleteZip = "$completeTarget.zip"
}
