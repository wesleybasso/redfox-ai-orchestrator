$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$builder = Join-Path $root 'Build-RedFox-Editions.ps1'
if (-not (Test-Path -LiteralPath $builder)) { throw 'RED: o gerador das duas edicoes ainda nao existe.' }

$temp = Join-Path ([IO.Path]::GetTempPath()) ('redfox-editions-' + [guid]::NewGuid().ToString('N'))
try {
    & $builder -OutputRoot $temp
    $skill = Join-Path $temp 'RedFox-Somente-Skill'
    $complete = Join-Path $temp 'RedFox-Programa-Completo'
    foreach ($path in @(
        (Join-Path $skill 'redfox\SKILL.md'),
        (Join-Path $skill 'redfox\scripts\invoke-redfox.ps1'),
        (Join-Path $skill 'INSTALAR-SOMENTE-SKILL.cmd'),
        (Join-Path $skill 'INSTALAR-SOMENTE-SKILL.sh'),
        "$skill.zip",
        (Join-Path $complete 'redfox-local\Install-RedFox-Suite.ps1'),
        (Join-Path $complete 'redfox-local\RedFox.Console.ps1'),
        (Join-Path $complete 'redfox-local\Install-RedFoxCommand.ps1'),
        (Join-Path $complete 'packages\ai-trio\install.ps1'),
        (Join-Path $complete 'skills\redfox\SKILL.md'),
        (Join-Path $complete 'install.ps1'),
        (Join-Path $complete 'install-skill.ps1'),
        (Join-Path $complete 'install-skill.sh'),
        (Join-Path $complete 'INSTALAR-REDFOX.sh'),
        (Join-Path $complete 'redfox-local\install-linux.sh'),
        "$complete.zip"
    )) { if (-not (Test-Path -LiteralPath $path)) { throw "Edicao incompleta: $path" } }
    if (Test-Path (Join-Path $skill 'redfox-local')) { throw 'Pacote somente skill incluiu o programa local.' }
    if (Test-Path (Join-Path $skill 'ai-trio-skills')) { throw 'Pacote somente skill incluiu o motor completo do trio.' }
    Write-Host 'PASS: skill isolada e programa completo foram empacotados separadamente.'
} finally {
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
