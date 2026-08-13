[CmdletBinding()]
param(
    [string]$Task,
    [ValidateSet('auto','especialista','pesquisa','conselho')][string]$Mode = 'auto',
    [ValidateRange(1024,65535)][int]$Port = 4777,
    [string]$Repo = (Get-Location).Path,
    [switch]$Status,
    [switch]$Agents,
    [switch]$Preview,
    [switch]$NoColor,
    [int]$Width = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$script:UseColor = -not $NoColor -and $Host.Name -ne 'ServerRemoteHost'
$script:Palette = @{
    Fox='DarkRed'; Flame='Red'; Amber='Yellow'; Text='White'; Muted='DarkGray'
    Good='Green'; Warn='Yellow'; Bad='Red'; User='Cyan'; Panel='DarkCyan'
}

function Get-RedFoxTerminalWidth {
    param([int]$RequestedWidth)
    if ($RequestedWidth -gt 0) { return [Math]::Min(160, [Math]::Max(44, $RequestedWidth)) }
    try { $detected = [Console]::WindowWidth } catch { $detected = 90 }
    if ($detected -le 1) { $detected = 90 }
    [Math]::Min(120, [Math]::Max(44, $detected))
}

$script:TerminalWidth = Get-RedFoxTerminalWidth -RequestedWidth $Width
$script:InnerWidth = $script:TerminalWidth - 4

function Write-RedFoxText {
    param([AllowEmptyString()][string]$Text='', [string]$Color='Text', [switch]$NoNewline)
    $parameters = @{ Object=$Text; NoNewline=[bool]$NoNewline }
    if ($script:UseColor) { $parameters.ForegroundColor = $script:Palette[$Color] }
    Write-Host @parameters
}

function Get-RedFoxCenteredText {
    param([string]$Text, [int]$Width)
    if ($Text.Length -ge $Width) { return $Text.Substring(0, $Width) }
    $left = [Math]::Floor(($Width - $Text.Length) / 2)
    (' ' * $left) + $Text + (' ' * ($Width - $Text.Length - $left))
}

function Write-RedFoxRule {
    param([string]$Left='╭', [string]$Fill='─', [string]$Right='╮', [string]$Color='Flame')
    Write-RedFoxText ('  ' + $Left + ($Fill * $script:InnerWidth) + $Right) $Color
}

function Write-RedFoxPanelLine {
    param([AllowEmptyString()][string]$Text='', [string]$Color='Text')
    $value = if ($Text.Length -gt $script:InnerWidth) { $Text.Substring(0, $script:InnerWidth) } else { $Text }
    Write-RedFoxText ('  │' + $value.PadRight($script:InnerWidth) + '│') $Color
}

function Show-RedFoxWideHeader {
    $fox = @(
        '      ╱╲     ╱╲      ',
        '     ╱  ╲___╱  ╲     ',
        '    ╱  ◉     ◉  ╲    ',
        '    ╲     ▲     ╱    ',
        '     ╲  ╰───╯  ╱     ',
        '      ╲__╱ ╲__╱      '
    )
    $wordmark = @(
        '██████╗ ███████╗██████╗ ███████╗ ██████╗ ██╗  ██╗',
        '██╔══██╗██╔════╝██╔══██╗██╔════╝██╔═══██╗╚██╗██╔╝',
        '██████╔╝█████╗  ██║  ██║█████╗  ██║   ██║ ╚███╔╝ ',
        '██╔══██╗██╔══╝  ██║  ██║██╔══╝  ██║   ██║ ██╔██╗ ',
        '██║  ██║███████╗██████╔╝██║     ╚██████╔╝██╔╝ ██╗',
        '╚═╝  ╚═╝╚══════╝╚═════╝ ╚═╝      ╚═════╝ ╚═╝  ╚═╝'
    )
    Write-RedFoxRule
    Write-RedFoxPanelLine ''
    for ($i=0; $i -lt $wordmark.Count; $i++) {
        Write-RedFoxPanelLine (($fox[$i] + $wordmark[$i])) $(if ($i -in 0,2,4) { 'Flame' } else { 'Amber' })
    }
    Write-RedFoxPanelLine ''
    Write-RedFoxPanelLine (Get-RedFoxCenteredText 'LOCAL AI ORCHESTRATOR' $script:InnerWidth) Amber
    Write-RedFoxRule -Left '├' -Right '┤' -Color 'Fox'
    Write-RedFoxPanelLine (Get-RedFoxCenteredText '● SYSTEM ONLINE   │   ◈ MODE AUTO   │   ⌁ 127.0.0.1:4777' $script:InnerWidth) Good
    Write-RedFoxPanelLine (Get-RedFoxCenteredText 'REDFOX // CONSELHO  ·  CLAUDE  ·  CODEX  ·  GEMINI  ·  COPILOT' $script:InnerWidth) Muted
    Write-RedFoxRule -Left '╰' -Right '╯'
}

function Show-RedFoxCompactHeader {
    Write-RedFoxRule
    Write-RedFoxPanelLine ''
    Write-RedFoxPanelLine (Get-RedFoxCenteredText '╱╲_╱╲   REDFOX // LOCAL AI' $script:InnerWidth) Flame
    Write-RedFoxPanelLine (Get-RedFoxCenteredText '( ◉ ▲ ◉ )  ● ONLINE' $script:InnerWidth) Amber
    Write-RedFoxPanelLine (Get-RedFoxCenteredText '╲  ╰─╯  ╱  CONSELHO INTELIGENTE' $script:InnerWidth) Muted
    Write-RedFoxPanelLine ''
    Write-RedFoxRule -Left '╰' -Right '╯'
}

function Show-RedFoxHeader {
    Write-RedFoxText ''
    if ($script:TerminalWidth -ge 88) { Show-RedFoxWideHeader } else { Show-RedFoxCompactHeader }
    Write-RedFoxText ''
    Write-RedFoxText '  COMANDOS  ' Flame -NoNewline
    Write-RedFoxText '/agentes  /status  /modo  /ajuda  /limpar  /sair' Muted
    Write-RedFoxText '  QUAL E A MISSAO?  ' Amber -NoNewline
    Write-RedFoxText 'Digite sua missão e pressione Enter.' Text
    Write-RedFoxText ''
}

function Show-RedFoxHelp {
    Write-RedFoxText ''
    Write-RedFoxRule -Color 'Panel'
    Write-RedFoxPanelLine '  CENTRAL DE COMANDOS' Amber
    Write-RedFoxRule -Left '├' -Right '┤' -Color 'Panel'
    Write-RedFoxPanelLine '  missão livre          descreva normalmente o que precisa' Text
    Write-RedFoxPanelLine '  /agentes              veja o conselho detectado' Muted
    Write-RedFoxPanelLine '  /status               confira o núcleo local' Muted
    Write-RedFoxPanelLine '  /modo <nome>          auto | especialista | pesquisa | conselho' Muted
    Write-RedFoxPanelLine '  /limpar               redesenhe o console' Muted
    Write-RedFoxPanelLine '  /sair                 encerre a sessão' Muted
    Write-RedFoxRule -Left '╰' -Right '╯' -Color 'Panel'
    Write-RedFoxText ''
}

function ConvertTo-RedFoxWrappedLines {
    param([AllowEmptyString()][string]$Text, [int]$MaxWidth)
    foreach ($rawLine in ($Text -split "`r?`n")) {
        if ($rawLine.Length -eq 0) { ''; continue }
        $remaining = $rawLine
        while ($remaining.Length -gt $MaxWidth) {
            $cut = $remaining.LastIndexOf(' ', $MaxWidth)
            if ($cut -lt [Math]::Floor($MaxWidth * .55)) { $cut = $MaxWidth }
            $remaining.Substring(0, $cut).TrimEnd()
            $remaining = $remaining.Substring($cut).TrimStart()
        }
        $remaining
    }
}

function Write-RedFoxObject {
    param([object]$Value)
    if ($null -eq $Value) { return }
    $text = if ($Value -is [string]) { $Value } else { $Value | ConvertTo-Json -Depth 30 }
    foreach ($line in ConvertTo-RedFoxWrappedLines -Text $text -MaxWidth ($script:InnerWidth - 4)) {
        Write-RedFoxPanelLine ('  ' + $line) Text
    }
}

function Show-RedFoxMissionResult {
    param([object]$Value)
    $outputs = @($Value.mission.FinalResult.outputs | Where-Object { $_.status -eq 'success' -and $_.output })
    if ($outputs.Count -eq 0) { Write-RedFoxObject $Value; return }
    $synthProvider = [string]$Value.plan.SynthProvider
    $preferred = @($outputs | Where-Object { $_.provider -eq $synthProvider })
    $selected = if ($preferred.Count -gt 0) { $preferred[-1] } else { $outputs[-1] }

    Write-RedFoxText ''
    Write-RedFoxRule -Color 'Panel'
    Write-RedFoxPanelLine ('  ◆ RESPOSTA UNIFICADA   ◈ {0}   ● {1}' -f ([string]$Value.plan.Mode).ToUpperInvariant(), ([string]$selected.provider).ToUpperInvariant()) Amber
    Write-RedFoxRule -Left '├' -Right '┤' -Color 'Panel'
    Write-RedFoxObject ([string]$selected.output).Trim()
    Write-RedFoxRule -Left '├' -Right '┤' -Color 'Panel'
    Write-RedFoxPanelLine ('  MISSÃO  {0}' -f $Value.mission_id) Muted
    Write-RedFoxRule -Left '╰' -Right '╯' -Color 'Panel'
    Write-RedFoxText ''
}

function Invoke-RedFoxConsoleTask {
    param([Parameter(Mandatory)][string]$Prompt)
    try {
        Write-RedFoxText '  ◆ MISSÃO RECEBIDA' Flame
        Write-RedFoxText '  ├─ analisando contexto e custo' Muted
        Write-RedFoxText '  ├─ selecionando especialistas disponíveis' Muted
        Write-RedFoxText '  └─ coordenando resposta...' Amber
        $result = & $clientPath -Task $Prompt -Mode $Mode -Repo $Repo -Port $Port
        Show-RedFoxMissionResult $result
    } catch {
        Write-RedFoxText '  ╭─ FALHA NA MISSÃO' Bad
        Write-RedFoxText ("  │  {0}" -f $_.Exception.Message) Bad
        Write-RedFoxText '  ╰─ use /status para verificar o núcleo local' Muted
    }
}

function Show-RedFoxAgents {
    param([object[]]$Agents)
    $all = @($Agents)
    $readyCount = @($all | Where-Object Ready).Count
    Write-RedFoxText ''
    Write-RedFoxRule -Color 'Panel'
    Write-RedFoxPanelLine ('  ◈ CONSELHO DETECTADO                         PRONTAS  {0}/{1}' -f $readyCount, $all.Count) Amber
    Write-RedFoxRule -Left '├' -Right '┤' -Color 'Panel'
    foreach ($agent in $all) {
        $ready = [bool]$agent.Ready
        $safeProperty = $agent.PSObject.Properties['Safe']
        $safe = if ($safeProperty) { [bool]$safeProperty.Value } else { $true }
        $mark = if ($ready) { '●' } elseif ($agent.Detected) { '◐' } else { '○' }
        $state = if ($ready) { 'pronta' } elseif ($agent.Detected -and -not $safe) { 'bloqueada por segurança' } elseif ($agent.Detected) { 'precisa autenticar' } else { 'não instalada' }
        $color = if ($ready) { 'Good' } elseif ($agent.Detected -and -not $safe) { 'Bad' } elseif ($agent.Detected) { 'Warn' } else { 'Muted' }
        Write-RedFoxPanelLine ('  {0} {1,-14} {2}' -f $mark, ([string]$agent.Name).ToLowerInvariant(), $state) $color
    }
    Write-RedFoxRule -Left '╰' -Right '╯' -Color 'Panel'
    Write-RedFoxText ''
}

function Invoke-RedFoxAgentPanel {
    $response = & $clientPath -Agents -Port $Port
    $list = if ($response.PSObject.Properties['agents']) { @($response.agents) } else { @($response) }
    Show-RedFoxAgents -Agents $list
}

function Invoke-RedFoxStatusPanel {
    $health = & $clientPath -Status -Port $Port
    Write-RedFoxText ("  ● NÚCLEO ONLINE   cérebro: {0}   porta: {1}" -f $health.brain, $Port) Good
}

Show-RedFoxHeader
if ($Preview) { return }
$clientPath = Join-Path $PSScriptRoot 'RedFox.Client.ps1'
if (-not (Test-Path -LiteralPath $clientPath)) { throw "Cliente local ausente: $clientPath" }
if ($Status) { Invoke-RedFoxStatusPanel; return }
if ($Agents) { Invoke-RedFoxAgentPanel; return }
if (-not [string]::IsNullOrWhiteSpace($Task)) { Invoke-RedFoxConsoleTask -Prompt $Task; return }

while ($true) {
    Write-RedFoxText '  ╭─ VOCÊ ' User
    Write-RedFoxText ('  ╰─ redfox [{0}] ❯ ' -f $Mode) User -NoNewline
    $inputText = Read-Host
    if ([string]::IsNullOrWhiteSpace($inputText)) { continue }
    $command = $inputText.Trim()
    if ($command -eq '/sair') { Write-RedFoxText '  ◇ Sessão encerrada. A raposa volta quando você chamar.' Amber; break }
    if ($command -eq '/ajuda') { Show-RedFoxHelp; continue }
    if ($command -eq '/limpar') { Clear-Host; Show-RedFoxHeader; continue }
    if ($command -eq '/status') {
        try { Invoke-RedFoxStatusPanel } catch { Write-RedFoxText "  ○ NÚCLEO OFFLINE — $($_.Exception.Message)" Bad }
        continue
    }
    if ($command -eq '/agentes') {
        try { Invoke-RedFoxAgentPanel } catch { Write-RedFoxText "  Não consegui consultar as IAs: $($_.Exception.Message)" Bad }
        continue
    }
    if ($command -match '^/modo(?:\s+(auto|especialista|pesquisa|conselho))?$') {
        if ($Matches[1]) { $Mode=$Matches[1]; Write-RedFoxText "  ◈ MODO ALTERADO — $($Mode.ToUpperInvariant())" Good }
        else { Write-RedFoxText "  ◈ MODO ATUAL — $($Mode.ToUpperInvariant())" Amber }
        continue
    }
    if ($command.StartsWith('/')) { Write-RedFoxText '  Comando desconhecido. Use /ajuda.' Warn; continue }
    Invoke-RedFoxConsoleTask -Prompt $command
}
