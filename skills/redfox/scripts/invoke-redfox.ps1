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

    [ValidateSet('auto', 'especialista', 'pesquisa', 'conselho', 'trio', 'quinteto')]
    [string]$Mode = 'auto',

    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

# Prefer the persistent local RedFox service. It discovers every MCO-compatible
# agent on the machine and only admits authenticated, safe agents to the council.
$localClient = Join-Path $env:LOCALAPPDATA 'RedFox\RedFox.Client.ps1'
$localOnline = $false
if (Test-Path -LiteralPath $localClient) {
    try { $localOnline = (Invoke-RestMethod -Uri 'http://127.0.0.1:4777/health' -TimeoutSec 2).status -eq 'online' } catch {}
}
if ($localOnline) {
    if ($Task.ToLowerInvariant() -match '(quais|qual).*(ias|agentes)|agentes.*(encontr|instalad|dispon)|status.*redfox|quem.*conselho') {
        $inventory = & $localClient -Agents
        if ($Json) { $inventory | ConvertTo-Json -Depth 30 } else { $inventory }
        exit 0
    }
    $localMode = if ($Mode -in @('trio','quinteto')) { 'conselho' } else { $Mode }
    $localArgs = @{ Task=$Task; Mode=$localMode; Repo=$Repo; TargetPaths=$TargetPaths }
    if ($DryRun) { $localArgs.DryRun = $true }
    $localResult = & $localClient @localArgs
    if ($Json) { $localResult | ConvertTo-Json -Depth 30 } else { $localResult }
    exit 0
}

function Select-RedFoxMode {
    param([string]$Text)

    $normalized = $Text.ToLowerInvariant()
    if ($normalized -match '\b(quinteto|cinco ias|qwen|deepseek|profundidade maxima)\b') { return 'quinteto' }
    if ($normalized -match '\b(trio|tres ias|claude.*codex.*gemini)\b') { return 'trio' }
    if ($normalized -match '\b(pesquis|busque na web|procure na web|fontes|citacoes|documentacao atual|mais recente|noticias)\w*') { return 'pesquisa' }
    if ($normalized -match '\b(conselho|decisao|decidir|escolher|arquitetura|alto risco|compare alternativas|comparar alternativas)\w*') { return 'conselho' }
    return 'especialista'
}

function Find-TrioEngine {
    $homePath = [Environment]::GetFolderPath('UserProfile')
    $candidates = @(
        (Join-Path $homePath '.codex\skills\using-ai-trio\scripts'),
        (Join-Path $homePath '.agents\skills\using-ai-trio\scripts'),
        (Join-Path $homePath '.claude\skills\using-ai-trio\scripts')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath (Join-Path $candidate 'invoke-router.ps1')) { return $candidate }
    }
    throw 'A skill using-ai-trio nao foi encontrada. Instale ou restaure o motor do trio antes de usar RedFox.'
}

$selectedMode = if ($Mode -eq 'auto') { Select-RedFoxMode -Text $Task } else { $Mode }
$engine = Find-TrioEngine

$plan = [ordered]@{
    coordinator       = 'redfox'
    requested_mode    = $Mode
    mode              = $selectedMode
    execution_mode    = 'read_only'
    providers         = @()
    synthesis_provider = $null
    delegated_script  = $null
    would_execute     = (-not $DryRun)
}

switch ($selectedMode) {
    'especialista' {
        $plan.providers = @('dynamic: claude|codex|gemini|qwen|pi')
        $plan.delegated_script = Join-Path $engine 'invoke-router.ps1'
        $arguments = @('-Task', $Task, '-Repo', $Repo, '-TargetPaths', $TargetPaths)
    }
    'pesquisa' {
        $plan.providers = @('claude', 'codex')
        $plan.synthesis_provider = 'claude'
        $plan.delegated_script = Join-Path $engine 'invoke-research.ps1'
        $arguments = @('-Query', $Task, '-Repo', $Repo)
    }
    'conselho' {
        $plan.providers = @('claude', 'codex', 'gemini')
        $plan.synthesis_provider = 'elected leader with peer review'
        $plan.delegated_script = Join-Path $engine 'invoke-council.ps1'
        $arguments = @('-Task', $Task, '-Repo', $Repo, '-TargetPaths', $TargetPaths)
    }
    'trio' {
        $plan.providers = @('claude', 'codex', 'gemini')
        $plan.synthesis_provider = 'claude'
        $plan.delegated_script = Join-Path $engine 'invoke-trio.ps1'
        $arguments = @('-Task', $Task, '-Repo', $Repo, '-TargetPaths', $TargetPaths, '-Team', 'trio')
    }
    'quinteto' {
        $plan.providers = @('claude', 'codex', 'gemini', 'qwen', 'pi')
        $plan.deepseek_model = 'deepseek/deepseek-v4-flash-0731'
        $plan.synthesis_provider = 'claude'
        $plan.delegated_script = Join-Path $engine 'invoke-trio.ps1'
        $arguments = @('-Task', $Task, '-Repo', $Repo, '-TargetPaths', $TargetPaths, '-Team', 'quintet')
    }
}

if ($DryRun) {
    if ($Json) { $plan | ConvertTo-Json -Depth 5 } else { $plan | Format-List | Out-String }
    exit 0
}

Write-Host ("RedFox | modo: {0} | coordenando: {1}" -f $selectedMode, ($plan.providers -join ', '))
if ($Json) { $arguments += '-Json' }
& $plan.delegated_script @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
