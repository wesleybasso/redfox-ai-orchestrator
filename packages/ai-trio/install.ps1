[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateNotNullOrEmpty()]
    [string]$Hosts = 'Codex,Claude,Gemini',

    [ValidateNotNullOrEmpty()]
    [string]$UserHome = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile),

    [switch]$SkipDependencyCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'Este instalador requer PowerShell 7 ou superior (pwsh).'
}

$packageRoot = [IO.Path]::GetFullPath($PSScriptRoot)
$resolvedUserHome = [IO.Path]::GetFullPath($UserHome)
$allowedHosts = @('Codex', 'Claude', 'Gemini')
$selectedHosts = @($Hosts -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

if ($selectedHosts.Count -eq 0) {
    throw 'Informe ao menos um host: Codex, Claude ou Gemini.'
}

$invalidHosts = @($selectedHosts | Where-Object { $_ -notin $allowedHosts })
if ($invalidHosts.Count -gt 0) {
    throw "Host(s) invalido(s): $($invalidHosts -join ', '). Valores aceitos: $($allowedHosts -join ', ')."
}

function Assert-DestinationInsideUserHome {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = [IO.Path]::GetFullPath($Path)
    $homeWithSeparator = $resolvedUserHome.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($resolvedPath -ne $resolvedUserHome -and -not $resolvedPath.StartsWith($homeWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Destino fora do perfil informado: $resolvedPath"
    }
    return $resolvedPath
}

function Ensure-Directory {
    param([Parameter(Mandatory)][string]$Path)

    $resolvedPath = Assert-DestinationInsideUserHome -Path $Path
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        if ($PSCmdlet.ShouldProcess($resolvedPath, 'Criar diretorio')) {
            New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
            Write-Host "[Created] $resolvedPath"
        }
    }
    return $resolvedPath
}

function Backup-ExistingFile {
    param([Parameter(Mandatory)][string]$Path)

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = "$Path.ai-trio-backup-$timestamp"
    $counter = 1
    while (Test-Path -LiteralPath $backupPath) {
        $backupPath = "$Path.ai-trio-backup-$timestamp-$counter"
        $counter++
    }

    Copy-Item -LiteralPath $Path -Destination $backupPath
    Write-Host "[Backup] $backupPath" -ForegroundColor Yellow
}

function Copy-ManagedFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Arquivo de origem ausente: $Source"
    }

    $resolvedDestination = Assert-DestinationInsideUserHome -Path $Destination
    Ensure-Directory -Path (Split-Path -Parent $resolvedDestination) | Out-Null

    if (Test-Path -LiteralPath $resolvedDestination) {
        $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $Source).Hash
        $destinationHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $resolvedDestination).Hash
        if ($sourceHash -eq $destinationHash) {
            Write-Host "[Unchanged] $resolvedDestination"
            return
        }
    }

    if ($PSCmdlet.ShouldProcess($resolvedDestination, 'Instalar arquivo gerenciado')) {
        if (Test-Path -LiteralPath $resolvedDestination) {
            Backup-ExistingFile -Path $resolvedDestination
        }
        Copy-Item -LiteralPath $Source -Destination $resolvedDestination
        Write-Host "[Installed] $resolvedDestination" -ForegroundColor Green
    }
}

function Merge-GeminiContext {
    param(
        [Parameter(Mandatory)][string]$FragmentPath,
        [Parameter(Mandatory)][string]$DestinationPath
    )

    $startMarker = '<!-- ai-trio:start -->'
    $endMarker = '<!-- ai-trio:end -->'
    $fragment = [IO.File]::ReadAllText($FragmentPath)
    if (-not ($fragment.Contains($startMarker) -and $fragment.Contains($endMarker))) {
        throw 'O fragmento GEMINI nao contem os marcadores gerenciados obrigatorios.'
    }

    $resolvedDestination = Assert-DestinationInsideUserHome -Path $DestinationPath
    Ensure-Directory -Path (Split-Path -Parent $resolvedDestination) | Out-Null

    $hasBom = $false
    if (Test-Path -LiteralPath $resolvedDestination) {
        $bytes = [IO.File]::ReadAllBytes($resolvedDestination)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $existing = [IO.File]::ReadAllText($resolvedDestination)
        $startMatches = [regex]::Matches($existing, [regex]::Escape($startMarker))
        $endMatches = [regex]::Matches($existing, [regex]::Escape($endMarker))

        if ($startMatches.Count -eq 0 -and $endMatches.Count -eq 0) {
            $newline = if ($existing.Contains("`r`n")) { "`r`n" } else { "`n" }
            $separator = if ($existing.EndsWith("`n")) { $newline } else { $newline + $newline }
            $merged = $existing + $separator + $fragment.TrimEnd("`r", "`n") + $newline
        }
        elseif ($startMatches.Count -eq 1 -and $endMatches.Count -eq 1 -and $startMatches[0].Index -lt $endMatches[0].Index) {
            $blockEnd = $endMatches[0].Index + $endMatches[0].Length
            $merged = $existing.Substring(0, $startMatches[0].Index) + $fragment.TrimEnd("`r", "`n") + $existing.Substring($blockEnd)
        }
        else {
            throw "Marcadores ai-trio invalidos ou duplicados em $resolvedDestination. O arquivo foi preservado."
        }

        if ($merged -ceq $existing) {
            Write-Host "[Unchanged] $resolvedDestination"
            return
        }
    }
    else {
        $merged = $fragment
    }

    if ($PSCmdlet.ShouldProcess($resolvedDestination, 'Mesclar bloco gerenciado AI Trio')) {
        if (Test-Path -LiteralPath $resolvedDestination) {
            Backup-ExistingFile -Path $resolvedDestination
        }
        [IO.File]::WriteAllText($resolvedDestination, $merged, [Text.UTF8Encoding]::new($hasBom))
        Write-Host "[Merged] $resolvedDestination" -ForegroundColor Green
    }
}

if (-not $SkipDependencyCheck) {
    $requiredCommands = @('pwsh', 'mco')
    if ('Codex' -in $selectedHosts) { $requiredCommands += 'codex' }
    if ('Claude' -in $selectedHosts) { $requiredCommands += 'claude' }
    if ('Gemini' -in $selectedHosts) { $requiredCommands += 'gemini' }

    $missingCommands = @($requiredCommands | Select-Object -Unique | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
    if ($missingCommands.Count -gt 0) {
        throw "Dependencia(s) ausente(s): $($missingCommands -join ', '). Consulte a secao Pre-requisitos do README.md."
    }

    foreach ($optionalCommand in @('qwen', 'pi')) {
        if (-not (Get-Command $optionalCommand -ErrorAction SilentlyContinue)) {
            Write-Warning "$optionalCommand nao encontrado; o trio funcionara, mas o quinteto requer esse comando."
        }
    }
}

foreach ($hostName in $selectedHosts) {
    switch ($hostName) {
        'Codex' {
            $sourceRoot = Join-Path $packageRoot 'codex/using-ai-trio'
            $destinationRoot = Join-Path $resolvedUserHome '.codex/skills/using-ai-trio'
            foreach ($relativePath in @('SKILL.md', 'scripts/configure-openrouter.ps1', 'scripts/configure-search.ps1', 'scripts/invoke-trio.ps1', 'scripts/invoke-router.ps1', 'scripts/invoke-council.ps1', 'scripts/invoke-research.ps1')) {
                Copy-ManagedFile -Source (Join-Path $sourceRoot $relativePath) -Destination (Join-Path $destinationRoot $relativePath)
            }
        }
        'Claude' {
            $sourceRoot = Join-Path $packageRoot 'claude-code/using-ai-trio'
            $destinationRoot = Join-Path $resolvedUserHome '.claude/skills/using-ai-trio'
            foreach ($relativePath in @('SKILL.md', 'scripts/configure-openrouter.ps1', 'scripts/configure-search.ps1', 'scripts/invoke-trio.ps1', 'scripts/invoke-router.ps1', 'scripts/invoke-council.ps1', 'scripts/invoke-research.ps1')) {
                Copy-ManagedFile -Source (Join-Path $sourceRoot $relativePath) -Destination (Join-Path $destinationRoot $relativePath)
            }
        }
        'Gemini' {
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/commands/trio.toml') -Destination (Join-Path $resolvedUserHome '.gemini/commands/trio.toml')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/commands/quinteto.toml') -Destination (Join-Path $resolvedUserHome '.gemini/commands/quinteto.toml')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/commands/especialista.toml') -Destination (Join-Path $resolvedUserHome '.gemini/commands/especialista.toml')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/commands/conselho.toml') -Destination (Join-Path $resolvedUserHome '.gemini/commands/conselho.toml')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/commands/pesquisa.toml') -Destination (Join-Path $resolvedUserHome '.gemini/commands/pesquisa.toml')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/trio-scripts/invoke-trio.ps1') -Destination (Join-Path $resolvedUserHome '.gemini/trio-scripts/invoke-trio.ps1')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/trio-scripts/invoke-router.ps1') -Destination (Join-Path $resolvedUserHome '.gemini/trio-scripts/invoke-router.ps1')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/trio-scripts/invoke-council.ps1') -Destination (Join-Path $resolvedUserHome '.gemini/trio-scripts/invoke-council.ps1')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/trio-scripts/invoke-research.ps1') -Destination (Join-Path $resolvedUserHome '.gemini/trio-scripts/invoke-research.ps1')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/trio-scripts/configure-search.ps1') -Destination (Join-Path $resolvedUserHome '.gemini/trio-scripts/configure-search.ps1')
            Copy-ManagedFile -Source (Join-Path $packageRoot 'gemini/trio-scripts/configure-openrouter.ps1') -Destination (Join-Path $resolvedUserHome '.gemini/trio-scripts/configure-openrouter.ps1')
            Merge-GeminiContext -FragmentPath (Join-Path $packageRoot 'gemini/GEMINI.fragment.md') -DestinationPath (Join-Path $resolvedUserHome '.gemini/GEMINI.md')
        }
    }
}

Write-Host "Instalacao concluida para: $($selectedHosts -join ', ')." -ForegroundColor Green
Write-Host 'Abra uma nova sessao do host para carregar a skill e os comandos.'
