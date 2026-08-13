$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$consolePath = Join-Path $root 'RedFox.Console.ps1'

if (-not (Test-Path -LiteralPath $consolePath)) {
    throw 'RED: a interface RedFox.Console.ps1 ainda nao existe.'
}

$preview = (& $consolePath -Preview -NoColor -Width 110 6>&1 | Out-String)
foreach ($expected in @(
    'REDFOX',
    'LOCAL AI ORCHESTRATOR',
    'SYSTEM ONLINE',
    'REDFOX // CONSELHO',
    '██████',
    '/agentes',
    '/ajuda',
    'QUAL E A MISSAO?'
)) {
    if ($preview -notmatch [regex]::Escape($expected)) {
        throw "A tela RedFox nao mostrou: $expected"
    }
}
if ($preview.Contains([char]27)) { throw 'O modo NoColor ainda emitiu codigos ANSI.' }

$compact = (& $consolePath -Preview -NoColor -Width 56 6>&1 | Out-String)
foreach ($expected in @('REDFOX // LOCAL AI', 'ONLINE', '/agentes', 'missão')) {
    if ($compact -notmatch [regex]::Escape($expected)) { throw "Layout compacto nao mostrou: $expected" }
}
if ($compact -match 'LOCAL AI ORCHESTRATOR') { throw 'Layout compacto usou o wordmark largo.' }

$source = Get-Content -LiteralPath $consolePath -Raw
if ($source -notmatch 'RedFox\.Client\.ps1') { throw 'A tela nao esta ligada ao cliente local RedFox.' }
if ($source -notmatch "'/sair'") { throw 'A tela nao oferece uma saida clara.' }
if ($source -notmatch 'Console\]::OutputEncoding' -or $source -notmatch 'Get-RedFoxTerminalWidth') {
    throw 'A interface nao prepara Unicode nem adapta a largura do terminal.'
}

$windowsInstaller = Get-Content -LiteralPath (Join-Path $root 'Install-RedFox.ps1') -Raw
if ($windowsInstaller -notmatch 'RedFox\.Console\.ps1' -or $windowsInstaller -notmatch 'redfox\.cmd') {
    throw 'O instalador Windows ainda nao cria o comando redfox.'
}
if ($windowsInstaller -notmatch 'chcp 65001' -or $windowsInstaller -notmatch 'title RedFox') {
    throw 'O atalho CMD nao prepara Unicode e identidade visual.'
}
$linuxInstaller = Get-Content -LiteralPath (Join-Path $root 'install-linux.sh') -Raw
if ($linuxInstaller -notmatch 'RedFox\.Console\.ps1' -or $linuxInstaller -notmatch '\.local/bin/redfox') {
    throw 'O instalador Linux ainda nao cria o comando redfox.'
}
$packageBuilder = Get-Content -LiteralPath (Join-Path $root 'Build-RedFox-Package.ps1') -Raw
if ($packageBuilder -notmatch "'RedFox\.Console\.ps1'") {
    throw 'A interface ainda nao entra no pacote completo.'
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ('redfox-console-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
try {
    Copy-Item -LiteralPath $consolePath -Destination (Join-Path $temp 'RedFox.Console.ps1')
    @'
param([string]$Task,[string]$Mode,[string]$Repo,[int]$Port,[switch]$Status,[switch]$Agents)
if ($Agents) {
    return [pscustomobject]@{ agents=@(
        [pscustomobject]@{ Name='claude'; Ready=$true; Detected=$true },
        [pscustomobject]@{ Name='gemini'; Ready=$false; Detected=$true }
    ) }
}
[pscustomobject]@{
    mission_id = 'teste-123'
    plan = [pscustomobject]@{ Mode='especialista'; SynthProvider='codex' }
    mission = [pscustomobject]@{
        FinalResult = [pscustomobject]@{
            outputs = @([pscustomobject]@{ provider='codex'; status='success'; output='Resposta bonita do conselho' })
        }
    }
}
'@ | Set-Content -LiteralPath (Join-Path $temp 'RedFox.Client.ps1') -Encoding utf8NoBOM
    $oneShot = (& (Join-Path $temp 'RedFox.Console.ps1') -Task 'missao de teste' -NoColor 6>&1 | Out-String)
    if ($oneShot -notmatch 'Resposta bonita do conselho' -or $oneShot -notmatch 'codex') {
        throw 'A tela nao apresentou a resposta unificada do agente.'
    }
    if ($oneShot -match '"mission"') { throw 'A tela exibiu JSON interno em vez da resposta amigavel.' }

    $agentPanel = (& (Join-Path $temp 'RedFox.Console.ps1') -Agents -NoColor -Width 100 6>&1 | Out-String)
    if ($agentPanel -notmatch 'claude\s+pronta' -or $agentPanel -notmatch 'gemini\s+precisa autenticar') {
        throw 'A tela nao interpretou a resposta envelopada do endpoint de agentes.'
    }
    if ($agentPanel -notmatch 'CONSELHO DETECTADO' -or $agentPanel -notmatch 'PRONTAS\s+1/2') {
        throw 'O painel de agentes nao mostrou titulo e resumo visual.'
    }
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force
}

Write-Host 'PASS: console RedFox possui mascote, cores opcionais, menu e integracao local.' -ForegroundColor Green
