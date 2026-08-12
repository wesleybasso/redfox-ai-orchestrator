[CmdletBinding()]
param([string]$SourceRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$temporaryRoot = $null

try {
    if ($SourceRoot) {
        $root = [IO.Path]::GetFullPath($SourceRoot)
    }
    elseif ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'skills\redfox\SKILL.md'))) {
        $root = $PSScriptRoot
    }
    else {
        $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) ('redfox-skill-' + [guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($temporaryRoot) | Out-Null
        $archive = Join-Path $temporaryRoot 'redfox.zip'
        Invoke-WebRequest -Uri 'https://github.com/wesleybasso/redfox-ai-orchestrator/archive/refs/heads/main.zip' -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath $temporaryRoot
        $root = (Get-ChildItem -LiteralPath $temporaryRoot -Directory | Select-Object -First 1).FullName
    }

    $source = Join-Path $root 'skills\redfox'
    if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md'))) { throw 'Skill RedFox nao encontrada no pacote.' }
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $targets = @(
        (Join-Path $env:USERPROFILE '.agents\skills\redfox'),
        (Join-Path $env:USERPROFILE '.codex\skills\redfox'),
        (Join-Path $env:USERPROFILE '.claude\skills\redfox')
    )
    foreach ($target in $targets) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
        if (Test-Path -LiteralPath $target) {
            Copy-Item -LiteralPath $target -Destination "$target.backup-$timestamp" -Recurse
            Remove-Item -LiteralPath $target -Recurse -Force
        }
        Copy-Item -LiteralPath $source -Destination $target -Recurse
        Write-Host "Skill instalada: $target" -ForegroundColor Green
    }
    Write-Host 'Abra uma nova conversa e escreva: RedFox, qual e a missao?' -ForegroundColor Cyan
}
finally {
    if ($temporaryRoot -and (Test-Path -LiteralPath $temporaryRoot)) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force
    }
}
