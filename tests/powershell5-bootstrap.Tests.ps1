$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$legacyPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $legacyPowerShell)) {
    Write-Host 'SKIP: Windows PowerShell 5 nao encontrado.' -ForegroundColor Yellow
    exit 0
}

$output = & $legacyPowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'install.ps1') -PackageRoot $root -SkipConfiguration -WhatIf 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Bootstrap pelo CMD/PowerShell 5 falhou:`n$output" }
if ($output -notmatch 'REDFOX - INSTALACAO COMPLETA') { throw "O bootstrap nao abriu o instalador completo:`n$output" }

Write-Host 'PASS: bootstrap do CMD encontra e abre PowerShell 7.' -ForegroundColor Green
