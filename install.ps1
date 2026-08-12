[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Model = 'gemma3:1b',
    [switch]$SkipConfiguration,
    [string]$PackageRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = 'wesleybasso/redfox-ai-orchestrator'
$temporaryRoot = $null

try {
    if ($PackageRoot) {
        $root = [IO.Path]::GetFullPath($PackageRoot)
    }
    elseif ($PSScriptRoot -and
        (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'redfox-local\Install-RedFox-Suite.ps1'))) {
        $root = $PSScriptRoot
    }
    else {
        $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('redfox-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
        $archive = Join-Path $temporaryRoot 'redfox.zip'
        $archiveUrl = "https://github.com/$repository/archive/refs/heads/main.zip"
        Write-Host 'Baixando o RedFox do GitHub...' -ForegroundColor Cyan
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath $temporaryRoot
        $root = (Get-ChildItem -LiteralPath $temporaryRoot -Directory | Select-Object -First 1).FullName
    }

    if ($PSVersionTable.PSVersion.Major -lt 7) {
        $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
        $pwshPath = if ($pwshCommand) { $pwshCommand.Source } else { Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe' }
        if (-not (Test-Path -LiteralPath $pwshPath)) {
            if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
                throw 'PowerShell 7 e winget nao foram encontrados. Atualize o App Installer pela Microsoft Store.'
            }
            Write-Host 'Instalando PowerShell 7...' -ForegroundColor Cyan
            & winget install --id Microsoft.PowerShell --exact --accept-package-agreements --accept-source-agreements --silent
            if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel instalar o PowerShell 7.' }
            $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
            if ($pwshCommand) { $pwshPath = $pwshCommand.Source }
        }
        if (-not (Test-Path -LiteralPath $pwshPath)) { throw "pwsh.exe nao encontrado em $pwshPath" }

        $relaunchArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'install.ps1'), '-PackageRoot', $root, '-Model', $Model)
        if ($SkipConfiguration) { $relaunchArgs += '-SkipConfiguration' }
        if ($WhatIfPreference) { $relaunchArgs += '-WhatIf' }
        & $pwshPath @relaunchArgs
        if ($LASTEXITCODE -ne 0) { throw "A instalacao RedFox falhou com codigo $LASTEXITCODE." }
        return
    }

    $suite = Join-Path $root 'redfox-local\Install-RedFox-Suite.ps1'
    $trio = Join-Path $root 'packages\ai-trio'
    $skillInstaller = Join-Path $root 'install-skill.ps1'
    foreach ($required in @($suite, (Join-Path $trio 'install.ps1'), $skillInstaller)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Pacote RedFox incompleto: $required" }
    }

    if ($WhatIfPreference) {
        & $suite -Model $Model -TrioPackagePath $trio -SkipConfiguration:$SkipConfiguration -WhatIf
    }
    else {
        & $suite -Model $Model -TrioPackagePath $trio -SkipConfiguration:$SkipConfiguration
    }
    if (-not $WhatIfPreference) { & $skillInstaller -SourceRoot $root }

    Write-Host "`nRedFox instalada. Abra uma nova conversa e escreva: RedFox, qual e a missao?" -ForegroundColor Green
}
finally {
    if ($temporaryRoot -and (Test-Path -LiteralPath $temporaryRoot)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
