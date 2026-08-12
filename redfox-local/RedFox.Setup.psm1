Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-OllamaExecutable {
    $command = Get-Command ollama -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($path in @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
        (Join-Path $env:ProgramFiles 'Ollama\ollama.exe')
    )) {
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

function Test-RedFoxModel {
    param([string]$OllamaPath, [string]$Model)
    if (-not $OllamaPath) { return $false }
    try {
        $lines = & $OllamaPath list 2>$null | Out-String
        return $lines -match ('(?m)^' + [regex]::Escape($Model) + '\s')
    } catch { return $false }
}

function Get-RedFoxMachineState {
    param(
        [string]$Model = 'gemma3:1b',
        [string]$TrioPackagePath,
        [string]$ServiceSourcePath
    )
    $ollama = Resolve-OllamaExecutable
    [pscustomobject]@{
        Winget      = [bool](Get-Command winget -ErrorAction SilentlyContinue)
        Ollama      = [bool]$ollama
        Node        = [bool](Get-Command node -ErrorAction SilentlyContinue)
        Pwsh        = [bool](Get-Command pwsh -ErrorAction SilentlyContinue)
        Mco         = [bool](Get-Command mco -ErrorAction SilentlyContinue)
        Claude      = [bool](Get-Command claude -ErrorAction SilentlyContinue)
        Codex       = [bool](Get-Command codex -ErrorAction SilentlyContinue)
        Gemini      = [bool](Get-Command gemini -ErrorAction SilentlyContinue)
        Model       = Test-RedFoxModel -OllamaPath $ollama -Model $Model
        Integration = Test-Path -LiteralPath (Join-Path $env:USERPROFILE '.codex\skills\using-ai-trio\SKILL.md')
        Service     = Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'RedFox\RedFox.Service.ps1')
    }
}

function New-SetupStep([string]$Id, [string]$Title, [string]$Command) {
    [pscustomobject]@{ Id=$Id; Title=$Title; Command=$Command }
}

function Get-RedFoxSetupPlan {
    param([Parameter(Mandatory)][object]$State, [string]$Model = 'gemma3:1b')

    if (-not $State.Winget) { throw 'winget nao encontrado. Atualize o App Installer pela Microsoft Store.' }
    if (-not $State.Pwsh) { New-SetupStep 'powershell' 'Instalar PowerShell 7' 'winget install --id Microsoft.PowerShell --exact' }
    if (-not $State.Node) { New-SetupStep 'node' 'Instalar Node.js LTS' 'winget install --id OpenJS.NodeJS.LTS --exact' }
    if (-not $State.Ollama) { New-SetupStep 'ollama' 'Instalar Ollama' 'winget install --id Ollama.Ollama --exact' }
    if (-not $State.Mco) { New-SetupStep 'mco' 'Instalar motor MCO' 'npm install --global @tt-a1i/mco@0.11.0' }
    if (-not $State.Claude) { New-SetupStep 'claude' 'Instalar Claude Code CLI' 'npm install --global @anthropic-ai/claude-code@2.1.185' }
    if (-not $State.Codex) { New-SetupStep 'codex' 'Instalar Codex CLI' 'npm install --global @openai/codex@0.147.0' }
    if (-not $State.Gemini) { New-SetupStep 'gemini' 'Instalar Gemini CLI' 'npm install --global @google/gemini-cli@0.55.1' }
    if (-not $State.Model) { New-SetupStep 'model' "Baixar cerebro local $Model" "ollama pull $Model" }
    if (-not $State.Integration) { New-SetupStep 'integration' 'Instalar integracao do trio' 'ai-trio-skills/install.ps1' }
    if (-not $State.Service) { New-SetupStep 'service' 'Instalar servico local RedFox' 'redfox-local/Install-RedFox.ps1' }
}

function ConvertFrom-RedFoxBrainAnswer {
    param([string]$Text, [string[]]$AllowedProviders)
    try {
        $clean = $Text.Trim()
        if ($clean -match '```(?:json)?\s*([\s\S]*?)```') { $clean = $Matches[1].Trim() }
        $value = $clean | ConvertFrom-Json
        if ($value.mode -notin @('especialista','pesquisa','conselho')) { return $null }
        $specialist = if ($value.specialist -in $AllowedProviders) { [string]$value.specialist } else { $null }
        [pscustomobject]@{ Mode=[string]$value.mode; Specialist=$specialist; Reason=[string]$value.reason }
    } catch { return $null }
}

function Invoke-RedFoxLocalBrain {
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][string[]]$Providers,
        [string]$Model = 'gemma3:1b',
        [string]$OllamaUri = 'http://127.0.0.1:11434',
        [scriptblock]$Transport
    )
    if ($Providers.Count -eq 0) { return $null }
    $system = "Classifique sem resolver a tarefa. Conselho para decisoes, arquitetura, alto risco ou varias IAs; pesquisa para fontes atuais; especialista para tarefa focada. Agentes: $($Providers -join ', ')."
    $schema = @{
        type = 'object'
        properties = @{
            mode = @{ type='string'; enum=@('especialista','pesquisa','conselho') }
            specialist = @{ type=@('string','null'); enum=@($Providers) + @($null) }
            reason = @{ type='string'; maxLength=100 }
        }
        required = @('mode','specialist','reason')
        additionalProperties = $false
    }
    $bodyObject = @{
        model = $Model
        stream = $false
        format = $schema
        messages = @(
            @{ role='system'; content=$system },
            @{ role='user'; content=$Task }
        )
        options = @{ temperature=0.0; num_predict=100 }
    }
    try {
        $response = if ($Transport) {
            & $Transport "$OllamaUri/api/chat" $bodyObject
        } else {
            Invoke-RestMethod -Method Post -Uri "$OllamaUri/api/chat" -ContentType 'application/json' -Body ($bodyObject | ConvertTo-Json -Depth 12) -TimeoutSec 60
        }
        return ConvertFrom-RedFoxBrainAnswer -Text ([string]$response.message.content) -AllowedProviders $Providers
    } catch { return $null }
}

function Test-RedFoxMissionCompletion {
    param(
        [Parameter(Mandatory)][string]$Task,
        [Parameter(Mandatory)][string]$ResultText,
        [string]$Model = 'gemma3:1b',
        [string]$OllamaUri = 'http://127.0.0.1:11434',
        [scriptblock]$Transport
    )
    $excerpt = if ($ResultText.Length -gt 12000) { $ResultText.Substring(0,12000) } else { $ResultText }
    $schema = @{
        type='object'
        properties=@{
            complete=@{type='boolean'}
            follow_up=@{type=@('string','null');maxLength=300}
            reason=@{type='string';maxLength=120}
        }
        required=@('complete','follow_up','reason')
        additionalProperties=$false
    }
    $bodyObject = @{
        model=$Model; stream=$false; format=$schema
        messages=@(
            @{role='system';content='Voce e a verificadora local RedFox. Decida se o resultado atende a missao. Se faltar algo importante, gere uma instrucao curta e acionavel para a proxima rodada. Nao resolva a missao.'},
            @{role='user';content="MISSAO:`n$Task`n`nRESULTADO:`n$excerpt"}
        )
        options=@{temperature=0.0;num_predict=140}
    }
    try {
        $response = if ($Transport) { & $Transport "$OllamaUri/api/chat" $bodyObject } else {
            Invoke-RestMethod -Method Post -Uri "$OllamaUri/api/chat" -ContentType 'application/json' -Body ($bodyObject|ConvertTo-Json -Depth 12) -TimeoutSec 90
        }
        $value = ([string]$response.message.content) | ConvertFrom-Json
        $followUp = if ($value.follow_up) { [string]$value.follow_up } else { $null }
        $complete = [bool]$value.complete -and [string]::IsNullOrWhiteSpace($followUp)
        [pscustomobject]@{ Complete=$complete; FollowUp=$followUp; Reason=[string]$value.reason }
    } catch { return $null }
}

Export-ModuleMember -Function Resolve-OllamaExecutable, Test-RedFoxModel, Get-RedFoxMachineState, Get-RedFoxSetupPlan, ConvertFrom-RedFoxBrainAnswer, Invoke-RedFoxLocalBrain, Test-RedFoxMissionCompletion
