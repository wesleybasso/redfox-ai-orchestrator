$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-File([string]$RelativePath) {
    $path = Join-Path $root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Arquivo publico ausente: $RelativePath"
    }
    return $path
}

$installPs1 = Assert-File 'install.ps1'
$installCmd = Assert-File 'install.cmd'
$installLinux = Assert-File 'install-linux.sh'
$skillInstall = Assert-File 'install-skill.ps1'
$skillInstallLinux = Assert-File 'install-skill.sh'
$skill = Assert-File 'skills\redfox\SKILL.md'
$skillScript = Assert-File 'skills\redfox\scripts\invoke-redfox.ps1'
$skillScriptLinux = Assert-File 'skills\redfox\scripts\invoke-redfox.sh'
$trioInstaller = Assert-File 'packages\ai-trio\install.ps1'
$mcoPatch = Assert-File 'redfox-local\patch-mco-windows.ps1'
$readme = Assert-File 'README.md'
$license = Assert-File 'LICENSE'
$funding = Assert-File '.github\FUNDING.yml'
$banner = Assert-File 'assets\redfox-banner.png'
$coffeeQr = Assert-File 'assets\buy-me-a-coffee-qr.png'

$psText = Get-Content -Raw $installPs1
foreach ($expected in @('redfox-local\Install-RedFox-Suite.ps1', 'packages\ai-trio', '-TrioPackagePath')) {
    if ($psText -notmatch [regex]::Escape($expected)) { throw "install.ps1 nao conecta o pacote completo: $expected" }
}
foreach ($expected in @('$PSVersionTable.PSVersion.Major -lt 7', 'Microsoft.PowerShell', 'pwsh.exe')) {
    if ($psText -notmatch [regex]::Escape($expected)) { throw "install.ps1 nao prepara PowerShell 7: $expected" }
}
if ($psText -match 'C:\\Users\\wesle|sk-or-v1-|AIza|gh[pousr]_') { throw 'install.ps1 contem dado local ou segredo.' }

$suiteText = Get-Content -Raw (Join-Path $root 'redfox-local\Install-RedFox-Suite.ps1')
if ($suiteText -notmatch [regex]::Escape('patch-mco-windows.ps1')) {
    throw 'O instalador completo nao aplica a compatibilidade obrigatoria do MCO no Windows.'
}

$editionBuilderText = Get-Content -Raw (Join-Path $root 'redfox-local\Build-RedFox-Editions.ps1')
foreach ($expected in @('skills\redfox', 'packages\ai-trio')) {
    if ($editionBuilderText -notmatch [regex]::Escape($expected)) { throw "Gerador publico nao usa fonte do repositorio: $expected" }
}

$cmdText = Get-Content -Raw $installCmd
if ($cmdText -notmatch 'install\.ps1') { throw 'install.cmd nao chama o instalador PowerShell.' }

$skillText = Get-Content -Raw $skill
if ($skillText -notmatch '(?m)^name:\s*redfox\s*$') { throw 'A skill nao pode ser descoberta como redfox.' }

$skillInstallText = Get-Content -Raw $skillInstall
foreach ($target in @('.agents\skills\redfox', '.claude\skills\redfox')) {
    if ($skillInstallText -notmatch [regex]::Escape($target)) { throw "Instalador da skill nao cobre $target" }
}
if ($skillInstallText -match 'Ollama|Install-RedFox-Suite') { throw 'Instalador somente-skill nao pode instalar o programa completo.' }

$readmeText = Get-Content -Raw $readme
foreach ($expected in @(
    'assets/redfox-banner.png',
    'img.shields.io',
    'buymeacoffee.com/wesleybasso',
    'install-linux.sh',
    'Ubuntu 24.04',
    'assets/buy-me-a-coffee-qr.png',
    'Escaneie o QR Code',
    'Como a RedFox trabalha',
    'Modos inteligentes',
    'Programa Completo',
    'Somente Skill',
    'irm ',
    'install.cmd',
    'npx skills add',
    'RedFox'
)) {
    if ($readmeText -notmatch [regex]::Escape($expected)) { throw "README sem instrucao publica: $expected" }
}

$fundingText = Get-Content -Raw $funding
if ($fundingText -notmatch [regex]::Escape('https://www.buymeacoffee.com/wesleybasso')) {
    throw 'FUNDING.yml nao aponta para o Buy Me a Coffee informado pelo autor.'
}
if ((Get-Item -LiteralPath $banner).Length -lt 10000) { throw 'Banner RedFox parece vazio ou invalido.' }
if ((Get-Item -LiteralPath $coffeeQr).Length -lt 10000) { throw 'QR Code do apoio parece vazio ou invalido.' }

$trackedCandidates = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object {
    $_.FullName -notmatch '\\.git\\|\\reports\\|\\skill-development\\.*-workspace\\'
}
$secretPatterns = @('sk-or-v1-[A-Za-z0-9_-]{20,}', 'AIza[0-9A-Za-z_-]{20,}', 'gh[pousr]_[A-Za-z0-9_]{20,}')
foreach ($file in $trackedCandidates) {
    $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    foreach ($pattern in $secretPatterns) {
        if ($text -match $pattern) { throw "Possivel segredo em $($file.FullName)" }
    }
}

Write-Host 'PASS: distribuicao publica RedFox validada.' -ForegroundColor Green
