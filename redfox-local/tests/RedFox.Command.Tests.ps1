$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'Install-RedFoxCommand.ps1'
if (-not (Test-Path -LiteralPath $installer)) {
    throw 'RED: o reparador do comando redfox ainda nao existe.'
}
$mainInstaller = Get-Content -LiteralPath (Join-Path $root 'Install-RedFox.ps1') -Raw
if ($mainInstaller -notmatch 'Install-RedFoxCommand\.ps1') {
    throw 'RED: o instalador principal ainda nao aplica o reparo do comando.'
}
$packageBuilder = Get-Content -LiteralPath (Join-Path $root 'Build-RedFox-Package.ps1') -Raw
if ($packageBuilder -notmatch "'Install-RedFoxCommand\.ps1'") {
    throw 'RED: o reparador do comando ainda nao entra no pacote completo.'
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('redfox-command-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
try {
    $profilePath = Join-Path $temp 'Microsoft.PowerShell_profile.ps1'
    $installDirectory = Join-Path $temp 'RedFox'
    [IO.Directory]::CreateDirectory($installDirectory) | Out-Null
    Set-Content -LiteralPath (Join-Path $installDirectory 'RedFox.Console.ps1') -Value 'param(); "console aberto"' -Encoding utf8NoBOM
    @'
$global:AntesDaRedFox = $true
# === RedFox: coordenador de IAs (Ollama) ===
function redfox {
    param([Parameter(Mandatory)][string]$Task)
    "comando antigo: $Task"
}
Set-Alias raposa redfox
$global:DepoisDaRedFox = $true
'@ | Set-Content -LiteralPath $profilePath -Encoding utf8NoBOM

    & $installer -InstallDirectory $installDirectory -ProfilePath $profilePath -SkipPathUpdate | Out-Null
    $profileText = Get-Content -LiteralPath $profilePath -Raw
    if ($profileText -match 'Parameter\(Mandatory\)') { throw 'A funcao antiga obrigatoria permaneceu no perfil.' }
    if ($profileText -notmatch 'RedFox\.Console\.ps1') { throw 'O perfil nao abre o novo console.' }
    if ($profileText -notmatch 'AntesDaRedFox' -or $profileText -notmatch 'DepoisDaRedFox') {
        throw 'O reparo removeu configuracoes que nao pertencem a RedFox.'
    }

    $sessionResult = & pwsh -NoProfile -Command ". '$profilePath'; redfox" | Out-String
    if ($sessionResult -notmatch 'console aberto') { throw 'Digitar redfox sem Task ainda nao abre o console.' }
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

Write-Host 'PASS: comando redfox abre o console e substitui o atalho antigo com seguranca.' -ForegroundColor Green
