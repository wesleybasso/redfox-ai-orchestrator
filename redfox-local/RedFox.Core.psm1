Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Update-RedFoxProcessPath {
    param([string]$MachinePath, [string]$UserPath)
    if (-not $IsWindows) {
        $homePath = [Environment]::GetFolderPath('UserProfile')
        $parts = @(
            $MachinePath,
            $UserPath,
            (Join-Path $homePath '.local/bin'),
            (Join-Path $homePath '.local/share/redfox-runtime/npm/bin'),
            $env:PATH
        ) | Where-Object { $_ }
        $env:PATH = $parts -join [IO.Path]::PathSeparator
        return $env:PATH
    }
    if (-not $PSBoundParameters.ContainsKey('MachinePath')) { $MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine') }
    if (-not $PSBoundParameters.ContainsKey('UserPath')) { $UserPath = [Environment]::GetEnvironmentVariable('Path','User') }
    $parts = @($MachinePath, $UserPath) -join ';'
    $env:Path = $parts
    return $parts
}

function Get-RedFoxDoctorData {
    if (-not (Get-Command mco -ErrorAction SilentlyContinue)) {
        throw 'MCO nao encontrado; a RedFox precisa dele para diagnosticar e chamar agentes.'
    }
    $raw = & mco doctor --json 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw 'O diagnostico do MCO nao respondeu corretamente.'
    }
    return ($raw | ConvertFrom-Json)
}

function Get-RedFoxAgents {
    param([Parameter(Mandatory)][object]$DoctorData)

    foreach ($property in $DoctorData.providers.PSObject.Properties) {
        $name = $property.Name
        $item = $property.Value
        $riskProperty = $item.PSObject.Properties['risk']
        $risk = if ($riskProperty -and $riskProperty.Value.PSObject.Properties['level']) { [string]$riskProperty.Value.level } else { 'unknown' }
        $binaryProperty = $item.PSObject.Properties['binary_path']
        $versionProperty = $item.PSObject.Properties['version']
        $safe = $risk -in @('read_only', 'workspace_write')
        $ready = [bool]$item.ready -and $safe
        [pscustomobject]@{
            Name       = $name
            Detected   = [bool]$item.detected
            AuthOk     = [bool]$item.auth_ok
            Ready      = $ready
            Safe       = $safe
            Risk       = $risk
            Reason     = [string]$item.reason
            State      = if ($ready) { 'ready' } elseif ($item.detected) { 'installed_not_ready' } else { 'not_installed' }
            BinaryPath = if ($binaryProperty) { [string]$binaryProperty.Value } else { $null }
            Version    = if ($versionProperty) { [string]$versionProperty.Value } else { $null }
        }
    }
}

function Resolve-RedFoxMode {
    param([Parameter(Mandatory)][string]$Task)

    $text = $Task.ToLowerInvariant()
    if ($text -match '\b(equipe|qualquer ia|quaisquer ias|todos os agentes|todas as ias)\b') { return 'equipe' }
    if ($text -match '\b(quinteto|cinco ias|profundidade maxima)\b') { return 'quinteto' }
    if ($text -match '\b(trio|tres ias)\b') { return 'trio' }
    if ($text -match '\b(conselho|decid|escolh|arquitetura|alto risco|alternativas)\w*') { return 'conselho' }
    if ($text -match '\b(pesquis|fontes|citacoes|web|noticias|mais recente)\w*') { return 'pesquisa' }
    return 'especialista'
}

function Get-PreferredSpecialist {
    param([string]$Task, [object[]]$ReadyAgents)

    $names = @($ReadyAgents.Name)
    $text = $Task.ToLowerInvariant()
    $preference = if ($text -match '\b(algorit|estrutura de dados|otimiz)\w*') {
        @('qwen', 'codex', 'pi', 'claude', 'gemini')
    } elseif ($text -match '\b(matem|calculo|complexidade|prova)\w*') {
        @('pi', 'qwen', 'codex', 'claude', 'gemini')
    } elseif ($text -match '\b(pesquis|document|fontes|web|noticias)\w*') {
        @('gemini', 'claude', 'codex', 'pi', 'qwen')
    } elseif ($text -match '\b(arquitet|requisit|seguranca|risco)\w*') {
        @('claude', 'codex', 'gemini', 'pi', 'qwen')
    } else {
        @('codex', 'claude', 'gemini', 'qwen', 'pi')
    }
    foreach ($candidate in $preference) {
        if ($candidate -in $names) { return $candidate }
    }
    if ($names.Count -gt 0) { return $names[0] }
    throw 'Nenhum agente autenticado e seguro foi encontrado.'
}

function Select-RedFoxCouncil {
    param(
        [Parameter(Mandatory)][object[]]$Agents,
        [Parameter(Mandatory)][string]$Task,
        [ValidateSet('auto', 'especialista', 'pesquisa', 'conselho', 'equipe', 'trio', 'quinteto')]
        [string]$Mode = 'auto',
        [string]$PreferredProvider,
        [switch]$Debate
    )

    $resolvedMode = if ($Mode -eq 'auto') { Resolve-RedFoxMode -Task $Task } else { $Mode }
    $ready = @($Agents | Where-Object { $_.Ready -and $_.Safe } | Sort-Object Name)
    if ($ready.Count -eq 0) { throw 'Nenhum agente pronto e seguro esta disponivel.' }

    $lead = if ($PreferredProvider -and $PreferredProvider -in $ready.Name) {
        $PreferredProvider
    } else {
        Get-PreferredSpecialist -Task $Task -ReadyAgents $ready
    }
    $ranked = [string[]]@($lead) + [string[]]@($ready.Name | Where-Object { $_ -ne $lead })
    $providers = if ($resolvedMode -eq 'equipe') {
        @($ranked)
    } elseif ($resolvedMode -eq 'quinteto') {
        @($ranked | Select-Object -First 5)
    } elseif ($resolvedMode -in @('conselho', 'trio')) {
        @($ranked | Select-Object -First 3)
    } elseif ($PreferredProvider -and $PreferredProvider -in $ready.Name) {
        @($PreferredProvider)
    } else {
        @($lead)
    }
    $providerArray = [string[]]@($providers)
    $synth = if ('claude' -in $providerArray) { 'claude' } else { $providerArray[0] }

    [pscustomobject]@{
        Coordinator   = 'redfox-local'
        Mode          = $resolvedMode
        Providers     = $providerArray
        SynthProvider = $synth
        ExecutionMode = 'read_only'
        Debate        = [bool]$Debate
        Discovered    = @($Agents | Where-Object Detected).Count
        Ready         = $ready.Count
    }
}

function Invoke-RedFoxMco {
    param(
        [Parameter(Mandatory)][object]$Plan,
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][string]$Repo,
        [string]$TargetPaths = '.',
        [switch]$DryRun
    )

    $args = @(
        'review', '--repo', $Repo, '--prompt', $Task,
        '--providers', ($Plan.Providers -join ','),
        '--target-paths', $TargetPaths,
        '--execution-mode', 'read_only',
        '--result-mode', 'stdout', '--quiet',
        '--invocation-hard-timeout', '180',
        '--review-hard-timeout', '600'
    )
    if (@($Plan.Providers).Count -gt 1) {
        $args += @('--synthesize', '--synth-provider', $Plan.SynthProvider)
        if ($Plan.Debate) { $args += '--debate' }
    }
    if ($DryRun) { $args += '--dry-run' }

    $raw = & mco @args 2>&1 | Out-String
    if ($LASTEXITCODE -gt 1) { throw "MCO falhou: $raw" }
    return [pscustomobject]@{ status = 'complete'; output = $raw.Trim() }
}

function Invoke-RedFoxAgentLoop {
    param(
        [Parameter(Mandatory)][string]$InitialPrompt,
        [ValidateRange(1,3)][int]$MaxRounds = 2,
        [Parameter(Mandatory)][scriptblock]$Executor,
        [Parameter(Mandatory)][scriptblock]$Evaluator
    )
    $rounds = [Collections.Generic.List[object]]::new()
    $prompt = $InitialPrompt
    $status = 'max_rounds'
    $finalResult = $null
    for ($round = 1; $round -le $MaxRounds; $round++) {
        $result = & $Executor $prompt $round
        $evaluation = & $Evaluator $result $round
        if (-not $evaluation) { $evaluation = [pscustomobject]@{ Complete=$true; FollowUp=$null; Reason='avaliador indisponivel; resultado operacional preservado' } }
        $rounds.Add([pscustomobject]@{ Round=$round; Prompt=$prompt; Result=$result; Evaluation=$evaluation })
        $finalResult = $result
        if ([bool]$evaluation.Complete) { $status = 'complete'; break }
        if ([string]::IsNullOrWhiteSpace([string]$evaluation.FollowUp)) { $status = 'needs_attention'; break }
        $prompt = "$InitialPrompt`n`nRevisao da RedFox apos a rodada ${round}:`n$($evaluation.FollowUp)"
    }
    [pscustomobject]@{ Status=$status; Rounds=$rounds.ToArray(); FinalResult=$finalResult }
}

Export-ModuleMember -Function Update-RedFoxProcessPath, Get-RedFoxDoctorData, Get-RedFoxAgents, Resolve-RedFoxMode, Select-RedFoxCouncil, Invoke-RedFoxMco, Invoke-RedFoxAgentLoop
