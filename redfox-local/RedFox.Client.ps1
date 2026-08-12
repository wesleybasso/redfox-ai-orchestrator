[CmdletBinding(DefaultParameterSetName='Task')]
param(
    [Parameter(Mandatory, ParameterSetName='Task')][string]$Task,
    [Parameter(ParameterSetName='Task')][ValidateSet('auto','especialista','pesquisa','conselho')][string]$Mode = 'auto',
    [Parameter(ParameterSetName='Task')][string]$Repo = (Get-Location).Path,
    [Parameter(ParameterSetName='Task')][string]$TargetPaths = '.',
    [Parameter(ParameterSetName='Task')][switch]$DryRun,
    [Parameter(ParameterSetName='Task')][ValidateRange(1,3)][int]$MaxRounds = 2,
    [Parameter(Mandatory, ParameterSetName='Status')][switch]$Status,
    [Parameter(Mandatory, ParameterSetName='Agents')][switch]$Agents,
    [ValidateRange(1024,65535)][int]$Port = 4777,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'RedFox')
)

$ErrorActionPreference = 'Stop'
$base = "http://127.0.0.1:$Port"
if ($Status) { Invoke-RestMethod -Uri "$base/health"; exit 0 }
if ($Agents) { Invoke-RestMethod -Uri "$base/agents"; exit 0 }

$tokenPath = Join-Path $DataDirectory 'service.token'
if (-not (Test-Path -LiteralPath $tokenPath)) { throw 'RedFox nao instalada. Execute Install-RedFox.ps1.' }
$headers = @{ 'X-RedFox-Token' = [IO.File]::ReadAllText($tokenPath).Trim() }
$body = @{ task=$Task; mode=$Mode; repo=$Repo; target_paths=$TargetPaths; dry_run=[bool]$DryRun; max_rounds=$MaxRounds } | ConvertTo-Json
$endpoint = if ($DryRun) { 'plan' } else { 'run' }
Invoke-RestMethod -Method Post -Uri "$base/$endpoint" -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $body
