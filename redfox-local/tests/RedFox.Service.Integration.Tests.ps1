$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$service = Join-Path $root 'RedFox.Service.ps1'
$port = Get-Random -Minimum 48000 -Maximum 58000
$data = Join-Path ([IO.Path]::GetTempPath()) ('redfox-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($data) | Out-Null
[IO.File]::WriteAllText((Join-Path $data 'service.token'), 'integration-test-token')
$job = $null

try {
    $job = Start-Job -ScriptBlock {
        & $using:service -Port $using:port -DataDirectory $using:data -RefreshSeconds 3600
    }
    $deadline = (Get-Date).AddSeconds(45)
    do {
        Start-Sleep -Milliseconds 500
        try { $first = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2 } catch { $first = $null }
    } until ($first -or (Get-Date) -ge $deadline)
    if (-not $first) { throw 'O servico nao iniciou dentro do prazo.' }

    $second = Invoke-RestMethod -Uri "http://127.0.0.1:$port/agents" -TimeoutSec 5
    if (-not $second.agents) { throw 'A segunda chamada nao retornou os agentes.' }
    $third = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 5
    if ($third.status -ne 'online') { throw 'A terceira chamada nao confirmou o servico online.' }
    Write-Host 'PASS: servico responde a chamadas HTTP consecutivas.'
} finally {
    if ($job) { Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $data) { Remove-Item -LiteralPath $data -Recurse -Force }
}
