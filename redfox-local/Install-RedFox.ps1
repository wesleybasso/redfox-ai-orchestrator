[CmdletBinding()]
param(
    [string]$InstallDirectory = (Join-Path $env:LOCALAPPDATA 'RedFox'),
    [ValidateRange(1024,65535)][int]$Port = 4777,
    [switch]$ForceRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

[IO.Directory]::CreateDirectory($InstallDirectory) | Out-Null
$needsRestart = $false
foreach ($name in @('RedFox.Core.psm1','RedFox.Setup.psm1','RedFox.Service.ps1','RedFox.Client.ps1','RedFox.Console.ps1','Install-RedFoxCommand.ps1','Configure-RedFox.ps1','Install-RedFox-Suite.ps1','patch-mco-windows.ps1')) {
    $source = Join-Path $PSScriptRoot $name
    $destination = Join-Path $InstallDirectory $name
    if (-not (Test-Path $destination) -or (Get-FileHash $source).Hash -ne (Get-FileHash $destination).Hash) { $needsRestart = $true }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}
if ($ForceRestart) { $needsRestart = $true }

$tokenPath = Join-Path $InstallDirectory 'service.token'
if (-not (Test-Path -LiteralPath $tokenPath)) {
    $bytes = [byte[]]::new(32)
    [Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
    [IO.File]::WriteAllText($tokenPath, [Convert]::ToHexString($bytes), [Text.UTF8Encoding]::new($false))
}

$startup = [Environment]::GetFolderPath('Startup')
$launcherPath = Join-Path $startup 'RedFox.vbs'
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$service = Join-Path $InstallDirectory 'RedFox.Service.ps1'
$log = Join-Path $InstallDirectory 'startup.log'
$vbs = @"
Set shell = CreateObject("WScript.Shell")
shell.Run Chr(34) & "$pwsh" & Chr(34) & " -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & "$service" & Chr(34) & " -Port $Port >> " & Chr(34) & "$log" & Chr(34) & " 2>&1", 0, False
"@
[IO.File]::WriteAllText($launcherPath, $vbs, [Text.UTF8Encoding]::new($false))

$console = Join-Path $InstallDirectory 'RedFox.Console.ps1'
$commandPath = Join-Path $InstallDirectory 'redfox.cmd'
$command = "@echo off`r`nchcp 65001 >nul`r`ntitle RedFox AI Orchestrator`r`n`"$pwsh`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$console`" %*`r`n"
[IO.File]::WriteAllText($commandPath, $command, [Text.Encoding]::ASCII)
& (Join-Path $InstallDirectory 'Install-RedFoxCommand.ps1') -InstallDirectory $InstallDirectory | Out-Null

$online = $false
try { $online = (Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2).status -eq 'online' } catch {}
if ($online -and $needsRestart) {
    $escapedService = [regex]::Escape($service)
    $running = @(Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine -match $escapedService })
    foreach ($process in $running) { Stop-Process -Id $process.ProcessId -Force }
    $online = $false
    Start-Sleep -Milliseconds 500
}
if (-not $online) {
    Start-Process -FilePath $pwsh -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$service,'-Port',"$Port") -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(90)
    do {
        Start-Sleep -Milliseconds 500
        try { $online = (Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2).status -eq 'online' } catch {}
    } until ($online -or (Get-Date) -ge $deadline)
}
if (-not $online) { throw "RedFox foi instalada, mas nao iniciou. Consulte $log e $(Join-Path $InstallDirectory 'redfox.log')." }

Write-Host "RedFox instalada e online em http://127.0.0.1:$Port" -ForegroundColor Green
Write-Host "Inicializacao automatica: $launcherPath"
Write-Host 'Abra um novo PowerShell e execute: redfox' -ForegroundColor Cyan
