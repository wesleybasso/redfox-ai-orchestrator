[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('Tarefa')]
    [ValidateNotNullOrEmpty()]
    [string]$Task,

    [ValidateNotNullOrEmpty()]
    [string]$Repo = (Get-Location).Path,

    [ValidateNotNullOrEmpty()]
    [string]$TargetPaths = '.',

    [ValidateSet('auto', 'especialista', 'pesquisa', 'conselho', 'equipe', 'trio', 'quinteto')]
    [string]$Mode = 'auto',

    [switch]$Debate,
    [switch]$RefreshAgents,
    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# Prefer the persistent local RedFox service. It discovers every MCO-compatible
# agent on the machine and only admits authenticated, safe agents to the council.
$localDataDirectory = if ($IsWindows) {
    Join-Path $env:LOCALAPPDATA 'RedFox'
} else {
    $base = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $env:HOME '.local/share' }
    Join-Path $base 'redfox'
}
$localClient = Join-Path $localDataDirectory 'RedFox.Client.ps1'
$localOnline = $false
if (Test-Path -LiteralPath $localClient) {
    $healthClient = [Net.Http.HttpClient]::new()
    try {
        $healthClient.Timeout = [TimeSpan]::FromMilliseconds(250)
        $health = $healthClient.GetStringAsync('http://127.0.0.1:4777/health').GetAwaiter().GetResult() | ConvertFrom-Json
        $localOnline = $health.status -eq 'online'
    } catch {} finally { $healthClient.Dispose() }
}
if ($localOnline) {
    if ($Task.ToLowerInvariant() -match '(quais|qual).*(ias|agentes)|agentes.*(encontr|instalad|dispon)|status.*redfox|quem.*conselho') {
        $inventory = & $localClient -Agents
        if ($Json) { $inventory | ConvertTo-Json -Depth 30 } else { $inventory }
        exit 0
    }
    $localArgs = @{ Task=$Task; Mode=$Mode; Repo=$Repo; TargetPaths=$TargetPaths }
    if ($Debate) { $localArgs.Debate = $true }
    if ($DryRun) { $localArgs.DryRun = $true }
    $localResult = & $localClient @localArgs
    if ($Json) { $localResult | ConvertTo-Json -Depth 30 } else { $localResult }
    exit 0
}

function Select-RedFoxMode {
    param([string]$Text)

    $normalized = $Text.ToLowerInvariant()
    if ($normalized -match '\b(equipe|qualquer ia|quaisquer ias|todas as ias|todos os agentes)\b') { return 'equipe' }
    if ($normalized -match '\b(quinteto|cinco ias|profundidade maxima)\b') { return 'quinteto' }
    if ($normalized -match '\b(trio|tres ias)\b') { return 'trio' }
    if ($normalized -match '\b(pesquis|busque na web|procure na web|fontes|citacoes|documentacao atual|mais recente|noticias)\w*') { return 'pesquisa' }
    if ($normalized -match '\b(conselho|decisao|decidir|escolher|arquitetura|alto risco|compare alternativas|comparar alternativas)\w*') { return 'conselho' }
    return 'especialista'
}

function Find-TrioEngine {
    $homePath = [Environment]::GetFolderPath('UserProfile')
    $candidates = @(
        (Join-Path $homePath '.codex/skills/using-ai-trio/scripts'),
        (Join-Path $homePath '.agents/skills/using-ai-trio/scripts'),
        (Join-Path $homePath '.claude/skills/using-ai-trio/scripts')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'invoke-router.ps1')) { return $candidate }
    }
    throw 'A skill using-ai-trio nao foi encontrada. Instale ou restaure o motor do trio antes de usar RedFox.'
}

function Get-RedFoxReadyProviders {
    param([switch]$Refresh)

    if (-not (Get-Command mco -ErrorAction SilentlyContinue)) {
        throw 'MCO nao encontrado; a RedFox precisa dele para descobrir e chamar as IAs instaladas.'
    }
    $cacheDirectory = if ($IsWindows) { Join-Path $env:LOCALAPPDATA 'RedFox' } else { Join-Path $env:HOME '.cache/redfox' }
    $cachePath = Join-Path $cacheDirectory 'mco-ready-providers-cache.json'
    if (-not $Refresh -and (Test-Path -LiteralPath $cachePath)) {
        try {
            $cached = Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json
            if (((Get-Date) - [datetime]$cached.generated_at).TotalSeconds -lt 60 -and @($cached.providers).Count -gt 0) {
                return [string[]]@($cached.providers)
            }
        } catch {}
    }
    $raw = & mco doctor --json 2>$null | Out-String
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
        throw 'O diagnostico do MCO nao respondeu corretamente.'
    }
    $doctor = $raw | ConvertFrom-Json
    $providers = @(
        $doctor.providers.PSObject.Properties |
            Where-Object {
                $_.Value.ready -and
                $_.Value.risk.level -in @('read_only', 'workspace_write')
            } |
            ForEach-Object Name |
            Sort-Object
    )
    if ($providers.Count -eq 0) {
        throw 'Nenhuma IA autenticada, pronta e segura foi encontrada pelo MCO.'
    }
    try {
        [IO.Directory]::CreateDirectory($cacheDirectory) | Out-Null
        $cache = [ordered]@{ generated_at=(Get-Date).ToString('o'); providers=[string[]]$providers }
        [IO.File]::WriteAllText($cachePath, ($cache | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
    } catch {}
    return [string[]]$providers
}

function Get-RedFoxRankedProviders {
    param([string]$Text, [string[]]$ReadyProviders)

    $normalized = $Text.ToLowerInvariant()
    $preferences = if ($normalized -match '\b(algorit|estrutura de dados|otimiz)\w*') {
        @('qwen', 'codex', 'pi', 'claude')
    } elseif ($normalized -match '\b(matem|calculo|complexidade|prova)\w*') {
        @('pi', 'qwen', 'codex', 'claude')
    } elseif ($normalized -match '\b(pesquis|document|fontes|web|noticias)\w*') {
        @('claude', 'cursor', 'copilot', 'codex')
    } elseif ($normalized -match '\b(arquitet|requisit|seguranca|risco)\w*') {
        @('claude', 'codex', 'cursor', 'copilot')
    } else {
        @('codex', 'claude', 'cursor', 'copilot', 'opencode', 'qwen', 'pi')
    }
    $ranked = [Collections.Generic.List[string]]::new()
    foreach ($candidate in @($preferences) + @($ReadyProviders | Sort-Object)) {
        if ($candidate -in $ReadyProviders -and -not $ranked.Contains($candidate)) { $ranked.Add($candidate) }
    }
    return [string[]]$ranked.ToArray()
}

$selectedMode = if ($Mode -eq 'auto') { Select-RedFoxMode -Text $Task } else { $Mode }
$resolvedMode = $selectedMode
$engine = if ($resolvedMode -eq 'pesquisa') { Find-TrioEngine } else { $null }
$readyProviders = if ($resolvedMode -eq 'pesquisa') { @() } else { @(Get-RedFoxReadyProviders -Refresh:$RefreshAgents) }
$rankedProviders = if ($readyProviders.Count) { @(Get-RedFoxRankedProviders -Text $Task -ReadyProviders $readyProviders) } else { @() }

$plan = [ordered]@{
    coordinator       = 'redfox'
    requested_mode    = $Mode
    mode              = $resolvedMode
    execution_mode    = 'read_only'
    providers         = @()
    synthesis_provider = $null
    delegated_script  = $null
    debate            = [bool]$Debate
    would_execute     = (-not $DryRun)
}

switch ($resolvedMode) {
    'especialista' {
        $plan.providers = @($rankedProviders | Select-Object -First 1)
        $plan.synthesis_provider = $plan.providers[0]
        $plan.delegated_script = 'mco review'
    }
    'pesquisa' {
        $plan.providers = @('claude', 'codex')
        $plan.synthesis_provider = 'claude'
        $plan.delegated_script = Join-Path $engine 'invoke-research.ps1'
        $arguments = @('-Query', $Task, '-Repo', $Repo)
    }
    'conselho' {
        $plan.providers = [string[]]@($rankedProviders | Select-Object -First 3)
        $plan.synthesis_provider = if ('claude' -in $plan.providers) { 'claude' } else { $plan.providers[0] }
        $plan.delegated_script = 'mco review --synthesize'
    }
    'trio' {
        $plan.providers = [string[]]@($rankedProviders | Select-Object -First 3)
        $plan.synthesis_provider = if ('claude' -in $plan.providers) { 'claude' } else { $plan.providers[0] }
        $plan.delegated_script = 'mco review --synthesize'
    }
    'quinteto' {
        $plan.providers = [string[]]@($rankedProviders | Select-Object -First 5)
        $plan.synthesis_provider = if ('claude' -in $plan.providers) { 'claude' } else { $plan.providers[0] }
        $plan.delegated_script = 'mco review --synthesize'
    }
    'equipe' {
        $plan.providers = [string[]]$rankedProviders
        $plan.synthesis_provider = if ('claude' -in $plan.providers) { 'claude' } else { $plan.providers[0] }
        $plan.delegated_script = 'mco review --synthesize'
    }
}

if ($DryRun) {
    if ($Json) { $plan | ConvertTo-Json -Depth 5 } else { $plan | Format-List | Out-String }
    exit 0
}

Write-Host ("RedFox | modo: {0} | coordenando: {1}" -f $resolvedMode, ($plan.providers -join ', '))
if ($resolvedMode -eq 'pesquisa') {
    if ($Json) { $arguments += '-Json' }
    & $plan.delegated_script @arguments
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    exit 0
}

$mcoArguments = @(
    'review', '--repo', $Repo, '--prompt', $Task,
    '--providers', ($plan.providers -join ','),
    '--target-paths', $TargetPaths,
    '--execution-mode', 'read_only',
    '--result-mode', 'stdout',
    '--invocation-hard-timeout', '180',
    '--review-hard-timeout', '600'
)
if ($plan.providers.Count -gt 1) {
    $mcoArguments += @('--synthesize', '--synth-provider', $plan.synthesis_provider)
}
if ($Debate -and $plan.providers.Count -gt 1) { $mcoArguments += '--debate' }
if ($Json) { $mcoArguments += @('--json', '--include-token-usage') } else { $mcoArguments += '--quiet' }
& mco @mcoArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
