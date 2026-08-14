$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$entrypoint = Join-Path $root 'skills\redfox\scripts\invoke-redfox.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('redfox-dynamic-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null

$oldLocalAppData = $env:LOCALAPPDATA
$oldHome = $env:HOME
$global:RedFoxDoctorCalls = 0
function global:mco {
    if ($args[0] -ne 'doctor') { throw "Chamada MCO inesperada no dry-run: $($args -join ' ')" }
    $global:RedFoxDoctorCalls++
    @'
{"providers":{
  "alpha":{"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}},
  "beta":{"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"workspace_write"}},
  "gamma":{"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}},
  "future-ai":{"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"read_only"}},
  "unsafe":{"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"approval_bypass"}},
  "unknown-risk":{"detected":true,"auth_ok":true,"ready":true,"reason":"ok","risk":{"level":"unknown"}}
}}
'@
    $global:LASTEXITCODE = 0
}

try {
    $env:LOCALAPPDATA = $temp
    $env:HOME = $temp

    $council = & $entrypoint -Task 'Revise esta arquitetura' -Mode conselho -DryRun -Json | Out-String | ConvertFrom-Json
    if (@($council.providers).Count -ne 3) { throw 'Conselho fallback deveria selecionar tres provedores.' }
    if ($council.debate) { throw 'Conselho fallback nao deveria debater automaticamente.' }

    $team = & $entrypoint -Task 'Use todas as IAs' -Mode equipe -DryRun -Json | Out-String | ConvertFrom-Json
    $teamNames = @($team.providers)
    foreach ($expected in @('alpha','beta','gamma','future-ai')) {
        if ($expected -notin $teamNames) { throw "Equipe fallback ignorou provedor pronto: $expected" }
    }
    foreach ($blocked in @('unsafe','unknown-risk')) {
        if ($blocked -in $teamNames) { throw "Equipe fallback incluiu provedor inseguro: $blocked" }
    }
    if ($global:RedFoxDoctorCalls -ne 1) { throw "Cache deveria evitar segundo doctor; chamadas: $global:RedFoxDoctorCalls" }

    $withDebate = & $entrypoint -Task 'Debata isto' -Mode conselho -Debate -DryRun -Json | Out-String | ConvertFrom-Json
    if (-not $withDebate.debate) { throw 'Fallback perdeu debate explicito.' }
    Write-Host 'PASS: fallback dinamico, economico, seguro e com cache.'
} finally {
    Remove-Item Function:\mco -ErrorAction SilentlyContinue
    Remove-Variable RedFoxDoctorCalls -Scope Global -ErrorAction SilentlyContinue
    $env:LOCALAPPDATA = $oldLocalAppData
    $env:HOME = $oldHome
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
