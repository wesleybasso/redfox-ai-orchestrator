[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InstallDirectory,
    [string]$ProfilePath = $PROFILE.CurrentUserCurrentHost,
    [switch]$SkipPathUpdate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$consolePath = Join-Path $InstallDirectory 'RedFox.Console.ps1'
if (-not (Test-Path -LiteralPath $consolePath)) { throw "Console RedFox ausente: $consolePath" }

$escapedConsole = $consolePath.Replace("'", "''")
$startMarker = '# >>> RedFox Console >>>'
$endMarker = '# <<< RedFox Console <<<'
$block = @"
$startMarker
function redfox {
    & '$escapedConsole' @args
}
Set-Alias raposa redfox -Scope Global
$endMarker
"@

$profileDirectory = Split-Path -Parent $ProfilePath
if ($profileDirectory) { [IO.Directory]::CreateDirectory($profileDirectory) | Out-Null }
$content = if (Test-Path -LiteralPath $ProfilePath) { Get-Content -LiteralPath $ProfilePath -Raw } else { '' }
$updated = $content

$newPattern = '(?s)' + [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker)
if ($updated -match $newPattern) {
    $updated = [regex]::Replace($updated, $newPattern, $block, 1)
} else {
    $legacyMarker = '# === RedFox: coordenador de IAs (Ollama) ==='
    $legacyStart = $updated.IndexOf($legacyMarker, [StringComparison]::Ordinal)
    if ($legacyStart -ge 0) {
        $tail = $updated.Substring($legacyStart)
        $aliasMatch = [regex]::Match($tail, '(?m)^Set-Alias\s+raposa\s+redfox\s*$')
        if ($aliasMatch.Success) {
            $legacyEnd = $legacyStart + $aliasMatch.Index + $aliasMatch.Length
            while ($legacyEnd -lt $updated.Length -and $updated[$legacyEnd] -in "`r", "`n") { $legacyEnd++ }
            $updated = $updated.Substring(0, $legacyStart) + $block + "`r`n" + $updated.Substring($legacyEnd)
        }
    }
    if ($updated -notmatch [regex]::Escape($startMarker)) {
        if ($updated.Length -gt 0 -and -not $updated.EndsWith("`n")) { $updated += "`r`n" }
        $updated += $block + "`r`n"
    }
}

if ($updated -ne $content) {
    if (Test-Path -LiteralPath $ProfilePath) { Copy-Item -LiteralPath $ProfilePath -Destination "$ProfilePath.redfox-backup" -Force }
    [IO.File]::WriteAllText($ProfilePath, $updated, [Text.UTF8Encoding]::new($false))
}

if (-not $SkipPathUpdate) {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathParts = @($userPath -split ';' | Where-Object { $_ })
    if ($InstallDirectory -notin $pathParts) {
        [Environment]::SetEnvironmentVariable('Path', (($pathParts + $InstallDirectory) -join ';'), 'User')
    }
}

[pscustomobject]@{ ProfilePath=$ProfilePath; ConsolePath=$consolePath; Updated=($updated -ne $content) }
