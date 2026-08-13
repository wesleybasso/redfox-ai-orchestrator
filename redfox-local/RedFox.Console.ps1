[CmdletBinding()]
param(
    [string]$Task,
    [ValidateSet('auto','especialista','pesquisa','conselho')][string]$Mode = 'auto',
    [ValidateRange(1024,65535)][int]$Port = 4777,
    [string]$Repo = (Get-Location).Path,
    [switch]$Preview,
    [switch]$NoColor
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:UseColor = -not $NoColor -and $Host.Name -ne 'ServerRemoteHost'
$script:Palette = @{
    Fox = 'DarkRed'; Accent = 'Red'; Gold = 'Yellow'; Text = 'White'
    Muted = 'DarkGray'; Good = 'Green'; Warn = 'Yellow'; Bad = 'Red'; User = 'Cyan'
}

function Write-RedFoxText {
    param([AllowEmptyString()][string]$Text = '', [string]$Color = 'Text', [switch]$NoNewline)
    $parameters = @{ Object = $Text; NoNewline = [bool]$NoNewline }
    if ($script:UseColor) { $parameters.ForegroundColor = $script:Palette[$Color] }
    Write-Host @parameters
}

function Show-RedFoxHeader {
    Write-RedFoxText ''
    Write-RedFoxText '                 /\     /\' Fox
    Write-RedFoxText '                /  \___/  \' Fox
    Write-RedFoxText '               /  ●     ●  \' Gold
    Write-RedFoxText '              |      ▲      |' Fox
    Write-RedFoxText '               \   \___/   /' Fox
    Write-RedFoxText '                \_________/' Fox
    Write-RedFoxText '             ╭─────────────────╮' Accent
    Write-RedFoxText '             │  R E D F O X  AI │' Gold
    Write-RedFoxText '             ╰─────────────────╯' Accent
    Write-RedFoxText '        Sua coordenadora local de inteligências' Muted
    Write-RedFoxText ''
    Write-RedFoxText '  Conselho  ' Accent -NoNewline
    Write-RedFoxText 'Claude  •  Codex  •  Gemini  •  Copilot' Text
    Write-RedFoxText '  Modos     ' Accent -NoNewline
    Write-RedFoxText 'automático  especialista  pesquisa  conselho' Muted
    Write-RedFoxText '  Comandos  ' Accent -NoNewline
    Write-RedFoxText '/agentes  /status  /modo  /ajuda  /limpar  /sair' Muted
    Write-RedFoxText ''
    Write-RedFoxText '  Digite sua missao e a RedFox escolherá quem deve ajudar.' Text
    Write-RedFoxText '  ─────────────────────────────────────────────────────────' Accent
}

function Show-RedFoxHelp {
    Write-RedFoxText ''
    Write-RedFoxText '  Como conversar com a RedFox' Gold
    Write-RedFoxText '  Escreva normalmente:  Revise a segurança deste projeto' Text
    Write-RedFoxText '  /agentes              mostra as IAs encontradas' Muted
    Write-RedFoxText '  /status               verifica o serviço local' Muted
    Write-RedFoxText '  /modo auto|especialista|pesquisa|conselho' Muted
    Write-RedFoxText '  /limpar               redesenha esta tela' Muted
    Write-RedFoxText '  /sair                 encerra a RedFox' Muted
    Write-RedFoxText ''
}

function Write-RedFoxObject {
    param([object]$Value)
    if ($null -eq $Value) { return }
    if ($Value -is [string]) { Write-RedFoxText $Value Text; return }
    $text = $Value | ConvertTo-Json -Depth 30
    Write-RedFoxText $text Text
}

function Show-RedFoxMissionResult {
    param([object]$Value)
    $outputs = @($Value.mission.FinalResult.outputs | Where-Object { $_.status -eq 'success' -and $_.output })
    if ($outputs.Count -eq 0) { Write-RedFoxObject $Value; return }

    $synthProvider = [string]$Value.plan.SynthProvider
    $preferred = @($outputs | Where-Object { $_.provider -eq $synthProvider })
    $selected = if ($preferred.Count -gt 0) { $preferred[-1] } else { $outputs[-1] }
    Write-RedFoxText ''
    Write-RedFoxText ('  RedFox — {0} • {1}' -f $Value.plan.Mode, $selected.provider) Accent
    Write-RedFoxText '  ─────────────────────────────────────────────────────────' Muted
    Write-RedFoxText ([string]$selected.output).Trim() Text
    Write-RedFoxText ''
    Write-RedFoxText ('  missão {0}' -f $Value.mission_id) Muted
    Write-RedFoxText ''
}

function Invoke-RedFoxConsoleTask {
    param([Parameter(Mandatory)][string]$Prompt)
    try {
        Write-RedFoxText '  ◌ RedFox está organizando o conselho...' Gold
        $result = & $clientPath -Task $Prompt -Mode $Mode -Repo $Repo -Port $Port
        Show-RedFoxMissionResult $result
    } catch {
        Write-RedFoxText "  Não consegui concluir a missão: $($_.Exception.Message)" Bad
        Write-RedFoxText '  Use /status para verificar o serviço local.' Muted
    }
}

function Show-RedFoxAgents {
    param([object[]]$Agents)
    Write-RedFoxText ''
    Write-RedFoxText '  IAs encontradas' Gold
    foreach ($agent in @($Agents)) {
        $ready = [bool]$agent.Ready
        $mark = if ($ready) { '●' } else { '○' }
        $state = if ($ready) { 'pronta' } elseif ($agent.Detected) { 'precisa autenticar' } else { 'não instalada' }
        $color = if ($ready) { 'Good' } elseif ($agent.Detected) { 'Warn' } else { 'Muted' }
        Write-RedFoxText ('  {0} {1,-12} {2}' -f $mark, $agent.Name, $state) $color
    }
    Write-RedFoxText ''
}

Show-RedFoxHeader
if ($Preview) { return }

$clientPath = Join-Path $PSScriptRoot 'RedFox.Client.ps1'
if (-not (Test-Path -LiteralPath $clientPath)) {
    throw "Cliente local ausente: $clientPath"
}
if (-not [string]::IsNullOrWhiteSpace($Task)) {
    Invoke-RedFoxConsoleTask -Prompt $Task
    return
}

while ($true) {
    Write-RedFoxText ('  redfox [{0}] ❯ ' -f $Mode) User -NoNewline
    $inputText = Read-Host
    if ([string]::IsNullOrWhiteSpace($inputText)) { continue }
    $command = $inputText.Trim()

    if ($command -eq '/sair') {
        Write-RedFoxText '  RedFox encerrada. Até a próxima missão.' Gold
        break
    }
    if ($command -eq '/ajuda') { Show-RedFoxHelp; continue }
    if ($command -eq '/limpar') { Clear-Host; Show-RedFoxHeader; continue }
    if ($command -eq '/status') {
        try {
            $health = & $clientPath -Status -Port $Port
            Write-RedFoxText ("  ● RedFox online — cérebro: {0}" -f $health.brain) Good
        } catch { Write-RedFoxText "  ○ Serviço offline — $($_.Exception.Message)" Bad }
        continue
    }
    if ($command -eq '/agentes') {
        try { Show-RedFoxAgents -Agents @(& $clientPath -Agents -Port $Port) }
        catch { Write-RedFoxText "  Não consegui consultar as IAs: $($_.Exception.Message)" Bad }
        continue
    }
    if ($command -match '^/modo(?:\s+(auto|especialista|pesquisa|conselho))?$') {
        if ($Matches[1]) {
            $Mode = $Matches[1]
            Write-RedFoxText "  Modo alterado para $Mode." Good
        } else {
            Write-RedFoxText "  Modo atual: $Mode" Gold
        }
        continue
    }
    if ($command.StartsWith('/')) {
        Write-RedFoxText '  Comando desconhecido. Use /ajuda.' Warn
        continue
    }

    Invoke-RedFoxConsoleTask -Prompt $command
}
