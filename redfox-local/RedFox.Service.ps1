[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$Port = 4777,
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'RedFox'),
    [ValidateRange(30, 3600)][int]$RefreshSeconds = 300
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'RedFox.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'RedFox.Setup.psm1') -Force

[IO.Directory]::CreateDirectory($DataDirectory) | Out-Null
$tokenPath = Join-Path $DataDirectory 'service.token'
$statePath = Join-Path $DataDirectory 'state.json'
$logPath = Join-Path $DataDirectory 'redfox.log'
$configPath = Join-Path $DataDirectory 'config.json'
$missionsPath = Join-Path $DataDirectory 'missions'
[IO.Directory]::CreateDirectory($missionsPath) | Out-Null
if (-not (Test-Path -LiteralPath $tokenPath)) { throw "Token local ausente: $tokenPath" }
$serviceToken = [IO.File]::ReadAllText($tokenPath).Trim()

function Write-RedFoxLog([string]$Message) {
    Add-Content -LiteralPath $logPath -Value ("{0:o} {1}" -f (Get-Date), $Message)
}

function Update-AgentState {
    try {
        Update-RedFoxProcessPath | Out-Null
        $copilotCommand = Get-Command copilot -ErrorAction SilentlyContinue
        Write-RedFoxLog ("Diagnostico Copilot antes do MCO: {0}" -f $(if ($copilotCommand) { $copilotCommand.Source } else { 'nao_encontrado' }))
        $doctor = Get-RedFoxDoctorData
        $script:agents = @(Get-RedFoxAgents -DoctorData $doctor)
        $snapshot = [ordered]@{ updated_at = (Get-Date).ToString('o'); agents = $script:agents }
        [IO.File]::WriteAllText($statePath, ($snapshot | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
        $script:lastRefresh = Get-Date
        Write-RedFoxLog "Descoberta atualizada: $(@($script:agents | Where-Object Ready).Count) prontos."
    } catch {
        Write-RedFoxLog "Falha na descoberta: $($_.Exception.Message)"
        if (-not $script:agents) { throw }
    }
}

function Send-JsonResponse($Context, [int]$Status, $Value) {
    $json = $Value | ConvertTo-Json -Depth 20
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $Context.Response.StatusCode = $Status
    $Context.Response.ContentType = 'application/json; charset=utf-8'
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

$script:agents = @()
$script:lastRefresh = [datetime]::MinValue
Update-AgentState

$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-RedFoxLog "RedFox online em 127.0.0.1:$Port."

try {
    while ($listener.IsListening) {
        if (((Get-Date) - $lastRefresh).TotalSeconds -ge $RefreshSeconds) { Update-AgentState }
        $context = $listener.GetContext()
        try {
            $path = $context.Request.Url.AbsolutePath.TrimEnd('/').ToLowerInvariant()
            if ($context.Request.HttpMethod -eq 'GET' -and $path -eq '/health') {
                Send-JsonResponse $context 200 ([ordered]@{ name='RedFox'; status='online'; pid=$PID; ready_agents=@($agents | Where-Object Ready).Count; updated_at=$lastRefresh.ToString('o') })
                continue
            }
            if ($context.Request.HttpMethod -eq 'GET' -and $path -eq '/agents') {
                Send-JsonResponse $context 200 ([ordered]@{ agents=$agents; updated_at=$lastRefresh.ToString('o') })
                continue
            }
            if ($context.Request.HttpMethod -ne 'POST' -or $path -notin @('/plan','/run')) {
                Send-JsonResponse $context 404 @{ error='not_found' }
                continue
            }
            if ($context.Request.Headers['X-RedFox-Token'] -ne $serviceToken) {
                Send-JsonResponse $context 401 @{ error='unauthorized' }
                continue
            }
            $reader = [IO.StreamReader]::new($context.Request.InputStream, $context.Request.ContentEncoding)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            if (-not $body.task) { throw 'O campo task e obrigatorio.' }
            $requestedMode = if ($body.mode) { [string]$body.mode } else { 'auto' }
            $brain = $null
            if (Test-Path -LiteralPath $configPath) {
                $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
                if ($config.brain -eq 'ollama') {
                    $readyNames = @($agents | Where-Object Ready | ForEach-Object Name)
                    $brain = Invoke-RedFoxLocalBrain -Task ([string]$body.task) -Providers $readyNames -Model ([string]$config.model) -OllamaUri ([string]$config.ollama_uri)
                }
            }
            $ruleMode = Resolve-RedFoxMode -Task ([string]$body.task)
            # The local model chooses the best specialist and explains why.
            # The deterministic policy owns team size so a tiny model cannot
            # accidentally turn routine work into an expensive full council.
            $effectiveMode = if ($requestedMode -eq 'auto') { $ruleMode } else { $requestedMode }
            $preferred = if ($brain) { $brain.Specialist } else { $null }
            $plan = Select-RedFoxCouncil -Agents $agents -Task ([string]$body.task) -Mode $effectiveMode -PreferredProvider $preferred
            $brainName = if ($brain) { 'ollama' } else { 'deterministic_fallback' }
            $brainReason = if ($brain) { $brain.Reason } else { $null }
            $plan | Add-Member -NotePropertyName Brain -NotePropertyValue $brainName
            $plan | Add-Member -NotePropertyName BrainReason -NotePropertyValue $brainReason
            if ($path -eq '/plan') {
                Send-JsonResponse $context 200 $plan
                continue
            }
            $repo = if ($body.repo) { [string]$body.repo } else { (Get-Location).Path }
            $targets = if ($body.target_paths) { [string]$body.target_paths } else { '.' }
            $missionId = 'redfox-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,6))
            $requestedRounds = if ($body.PSObject.Properties['max_rounds']) { [int]$body.max_rounds } else { 2 }
            $maxRounds = if ($plan.Mode -eq 'conselho') { [Math]::Min([Math]::Max($requestedRounds,1),3) } else { 1 }
            $originalTask = [string]$body.task
            $executor = {
                param($prompt, $round)
                Invoke-RedFoxMco -Plan $plan -Task $prompt -Repo $repo -TargetPaths $targets -DryRun:([bool]$body.dry_run)
            }
            $evaluator = {
                param($result, $round)
                if (-not $brain -or $maxRounds -eq 1) { return [pscustomobject]@{ Complete=$true; FollowUp=$null; Reason='rodada unica' } }
                $resultText = $result | ConvertTo-Json -Depth 20 -Compress
                Test-RedFoxMissionCompletion -Task $originalTask -ResultText $resultText -Model ([string]$config.model) -OllamaUri ([string]$config.ollama_uri)
            }
            $mission = Invoke-RedFoxAgentLoop -InitialPrompt $originalTask -MaxRounds $maxRounds -Executor $executor -Evaluator $evaluator
            $record = [ordered]@{ mission_id=$missionId; created_at=(Get-Date).ToString('o'); plan=$plan; mission=$mission }
            [IO.File]::WriteAllText((Join-Path $missionsPath "$missionId.json"), ($record | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
            Send-JsonResponse $context 200 $record
        } catch {
            Write-RedFoxLog "Erro de requisicao: $($_.Exception.Message)"
            Send-JsonResponse $context 500 @{ error='redfox_error'; message=$_.Exception.Message }
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
    Write-RedFoxLog 'RedFox encerrada.'
}
