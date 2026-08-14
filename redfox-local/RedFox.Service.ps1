[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$Port = 4777,
    [string]$DataDirectory = $(if ($IsWindows) {
        Join-Path $env:LOCALAPPDATA 'RedFox'
    } else {
        $base = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $env:HOME '.local/share' }
        Join-Path $base 'redfox'
    }),
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
    # Se o cliente desconectou (aba fechada, timeout do proxy), escrever a resposta
    # lanca. Sem este try/catch a excecao sobe e derruba o servico inteiro.
    try {
        $json = $Value | ConvertTo-Json -Depth 20
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        $Context.Response.StatusCode = $Status
        $Context.Response.ContentType = 'application/json; charset=utf-8'
        $Context.Response.ContentLength64 = $bytes.Length
        $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $Context.Response.Close()
    } catch {
        Write-RedFoxLog "Cliente desconectou antes da resposta; requisicao descartada."
        try { $Context.Response.Abort() } catch { }
    }
}

$script:agents = @()
$script:lastRefresh = [datetime]::MinValue
$script:refreshJob = $null
Update-AgentState

$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()
Write-RedFoxLog "RedFox online em 127.0.0.1:$Port."

try {
    while ($listener.IsListening) {
        # A descoberta chama varios CLIs e leva ~45 s. Rodando aqui de forma
        # sincrona, o servico ficava inacessivel nesse intervalo inteiro. Agora
        # ela roda numa thread e o listener continua atendendo enquanto isso.
        if (-not $script:refreshJob -and ((Get-Date) - $lastRefresh).TotalSeconds -ge $RefreshSeconds) {
            $script:refreshJob = Start-ThreadJob -ScriptBlock {
                param($root)
                Import-Module (Join-Path $root 'RedFox.Core.psm1') -Force
                Import-Module (Join-Path $root 'RedFox.Setup.psm1') -Force
                Update-RedFoxProcessPath | Out-Null
                @(Get-RedFoxAgents -DoctorData (Get-RedFoxDoctorData))
            } -ArgumentList $PSScriptRoot
        }
        if ($script:refreshJob -and $script:refreshJob.State -in @('Completed', 'Failed', 'Stopped')) {
            try {
                $fresh = @(Receive-Job -Job $script:refreshJob -ErrorAction Stop)
                if ($fresh.Count) {
                    $script:agents = $fresh
                    $snapshot = [ordered]@{ updated_at = (Get-Date).ToString('o'); agents = $script:agents }
                    [IO.File]::WriteAllText($statePath, ($snapshot | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
                    Write-RedFoxLog "Descoberta atualizada em segundo plano: $(@($script:agents | Where-Object Ready).Count) prontos."
                }
            } catch {
                Write-RedFoxLog "Falha na descoberta em segundo plano: $($_.Exception.Message)"
            }
            Remove-Job -Job $script:refreshJob -Force -ErrorAction SilentlyContinue
            $script:refreshJob = $null
            $script:lastRefresh = Get-Date
        }
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
            # Sob Set-StrictMode, ler um campo ausente do JSON lanca excecao. Os
            # campos opcionais precisam ser checados via PSObject.Properties.
            $has = { param($name) $null -ne $body.PSObject.Properties[$name] }
            if (-not (& $has 'task') -or -not $body.task) { throw 'O campo task e obrigatorio.' }
            $requestedMode = if ((& $has 'mode') -and $body.mode) { [string]$body.mode } else { 'auto' }
            $brain = $null
            if ($requestedMode -eq 'auto' -and (Test-Path -LiteralPath $configPath)) {
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
            $requestedDebate = (& $has 'debate') -and [bool]$body.debate
            $plan = Select-RedFoxCouncil -Agents $agents -Task ([string]$body.task) -Mode $effectiveMode -PreferredProvider $preferred -Debate:$requestedDebate
            $brainName = if ($brain) { 'ollama' } else { 'deterministic_fallback' }
            $brainReason = if ($brain) { $brain.Reason } else { $null }
            $plan | Add-Member -NotePropertyName Brain -NotePropertyValue $brainName
            $plan | Add-Member -NotePropertyName BrainReason -NotePropertyValue $brainReason
            if ($path -eq '/plan') {
                Send-JsonResponse $context 200 $plan
                continue
            }
            $repo = if ((& $has 'repo') -and $body.repo) { [string]$body.repo } else { (Get-Location).Path }
            $targets = if ((& $has 'target_paths') -and $body.target_paths) { [string]$body.target_paths } else { '.' }
            $dryRun = (& $has 'dry_run') -and [bool]$body.dry_run
            $missionId = 'redfox-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0,6))
            $requestedRounds = if ($body.PSObject.Properties['max_rounds']) { [int]$body.max_rounds } else { 1 }
            $maxRounds = if ($plan.Debate) { [Math]::Min([Math]::Max($requestedRounds,1),3) } else { 1 }
            $originalTask = [string]$body.task
            $executor = {
                param($prompt, $round)
                Invoke-RedFoxMco -Plan $plan -Task $prompt -Repo $repo -TargetPaths $targets -DryRun:$dryRun
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
