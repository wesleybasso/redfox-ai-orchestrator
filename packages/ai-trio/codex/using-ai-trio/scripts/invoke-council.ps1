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

    # Quem participa da eleicao (vota). Default: o trio.
    [ValidateNotNullOrEmpty()]
    [string]$Electors = 'claude,codex,gemini',

    [ValidateRange(1, 3)]
    [int]$MaxRounds = 2,

    [switch]$SkipReview,   # elege e executa, sem a fase de revisao
    [switch]$ElectOnly,    # so elege e mostra o lider; nao executa nem revisa
    [switch]$DryRun,       # nao chama modelos; simula a eleicao
    [switch]$Json          # saida do executor em JSON
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command mco -ErrorAction SilentlyContinue)) {
    throw 'MCO nao encontrado. Instale com: npm install -g @tt-a1i/mco@0.11.0'
}

foreach ($keyName in @('GEMINI_API_KEY', 'OPENROUTER_API_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($keyName, 'Process'))) {
        $userValue = [Environment]::GetEnvironmentVariable($keyName, 'User')
        if (-not [string]::IsNullOrWhiteSpace($userValue)) {
            [Environment]::SetEnvironmentVariable($keyName, $userValue, 'Process')
        }
    }
}

# candidatos (especialistas) que podem ser eleitos
$candidates = @{
    claude = 'arquitetura, requisitos, riscos, seguranca, coerencia de design'
    codex  = 'implementacao, depuracao, testes, performance, refatoracao'
    qwen   = 'algoritmos, estruturas de dados, raciocinio de codigo, alternativas'
    pi     = 'matematica, complexidade, otimizacao, raciocinio profundo (DeepSeek)'
    gemini = 'pesquisa, documentacao, contexto amplo, comparacao, usabilidade'
}
$candidateNames = @('claude', 'codex', 'qwen', 'pi', 'gemini')
$electorList = @($Electors -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ })

# --- Persona + guardrails anti-alucinacao (aplicados a TODA chamada) ---
$Personas = @{
    claude = 'Arquiteta de Software Senior, criteriosa com riscos e requisitos'
    codex  = 'Engenheira de Implementacao pragmatica, focada em codigo que compila e passa nos testes'
    qwen   = 'Especialista em Algoritmos e estruturas de dados'
    pi     = 'Pesquisadora de raciocinio matematico rigoroso (DeepSeek)'
    gemini = 'Pesquisadora Tecnica que compara fontes e alternativas'
}
$Guardrails = @'
REGRAS ANTI-ALUCINACAO (obrigatorias):
- Baseie-se APENAS no repositorio/contexto fornecido. Nao invente arquivos, funcoes, APIs, versoes, numeros ou fatos.
- Se algo nao esta no contexto ou voce nao tem certeza, escreva "nao sei" ou "nao consta no contexto". Nunca preencha lacunas com suposicao disfarcada de fato.
- Separe claramente FATO VERIFICAVEL de SUPOSICAO/OPINIAO.
- Ao afirmar algo sobre o codigo, cite o caminho do arquivo e o trecho.
- Nao fabrique citacoes, links, comandos ou saidas de terminal. Marque o que for pendencia.
- Prefira admitir incerteza a soar confiante e errar.
'@

function Get-CandidateMenu {
    ($candidateNames | ForEach-Object { "- $_ : $($candidates[$_])" }) -join "`n"
}

# faz UM eleitor votar; retorna @{ vote=<nome>; reason=<texto> }
function Invoke-Vote {
    param([string]$Elector, [string]$PriorTally)

    $menu = Get-CandidateMenu
    $priorBlock = if ($PriorTally) {
        "`nRodada anterior (votos e razoes dos colegas, material de referencia, nao confie cegamente):`n$PriorTally`nReconsidere com base nisso.`n"
    } else { '' }

    $prompt = @"
Persona: voce e uma $($Personas[$Elector]), membro de um conselho decidindo QUEM deve liderar esta tarefa.
Escolha o candidato mais forte para o trabalho, mesmo que nao seja voce. Vote so com base na natureza da tarefa; nao invente detalhes que nao existem.

Candidatos e especialidades:
$menu
$priorBlock
Tarefa:
$Task

Responda em DUAS linhas exatas:
VOTO: <um nome da lista>
MOTIVO: <uma frase curta>
"@

    $out = '' | & mco run --repo $Repo --prompt $prompt --providers $Elector `
        --execution-mode read_only --result-mode stdout `
        --invocation-hard-timeout 90 2>$null
    $text = ($out | Out-String)

    $vote = $null
    if ($text -match '(?im)^\s*VOTO:\s*([a-z]+)') {
        $cand = $Matches[1].ToLower()
        if ($candidateNames -contains $cand) { $vote = $cand }
    }
    if (-not $vote) {
        foreach ($c in $candidateNames) { if ($text.ToLower() -match "\b$c\b") { $vote = $c; break } }
    }
    $reason = if ($text -match '(?im)^\s*MOTIVO:\s*(.+)$') { $Matches[1].Trim() } else { '' }
    return @{ vote = $vote; reason = $reason }
}

# conta votos; retorna @{ winner=<nome|null>; consensus=<bool>; tallyText=<str> }
function Resolve-Tally {
    param([hashtable[]]$Ballots)

    $valid = @($Ballots | Where-Object { $_.vote })
    $counts = @{}
    foreach ($b in $valid) { $counts[$b.vote] = ([int]$counts[$b.vote]) + 1 }

    $winner = $null; $top = 0
    foreach ($k in $counts.Keys) { if ($counts[$k] -gt $top) { $top = $counts[$k]; $winner = $k } }
    $tiedTop = @($counts.Keys | Where-Object { $counts[$_] -eq $top })
    $consensus = ($winner -and $tiedTop.Count -eq 1 -and $top -gt ($valid.Count / 2))

    $lines = foreach ($b in $Ballots) { "  {0} votou em {1}: {2}" -f $b.elector, ($b.vote ?? '?'), $b.reason }
    return @{ winner = $winner; consensus = [bool]$consensus; tallyText = ($lines -join "`n"); counts = $counts }
}

function Test-OpenRouterNeeded {
    param([string]$Provider)
    if ($Provider -in @('qwen', 'pi') -and [string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY) -and -not $DryRun) {
        throw "O eleito '$Provider' usa OpenRouter, mas OPENROUTER_API_KEY nao esta definida. Execute configure-openrouter.ps1 ou use -Electors sem qwen/pi."
    }
}

function Get-ExecArgs {
    param([string]$Provider, [string]$Prompt, [string]$TaskId, [hashtable]$Perspectives)
    $pj = $Perspectives | ConvertTo-Json -Compress
    $a = @(
        'run', '--repo', $Repo, '--prompt', $Prompt, '--providers', $Provider,
        '--target-paths', $TargetPaths, '--execution-mode', 'read_only',
        '--perspectives-json', $pj, '--include-token-usage',
        '--invocation-hard-timeout', '300', '--task-id', $TaskId
    )
    if ($Provider -eq 'qwen') { $env:MCO_QWEN_AUTH_TYPE = 'openai' }
    if ($Provider -eq 'pi') {
        $dm = @{ pi = @{ provider = 'openrouter'; model = 'deepseek/deepseek-v4-flash-0731' } } | ConvertTo-Json -Compress
        $a += @('--provider-models-json', $dm)
    }
    return $a
}

# ---------------- FASE 1: ELEICAO ----------------
Write-Host "== CONSELHO: eleicao (eleitores: $($electorList -join ', ')) ==" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host '[dry-run] eleicao simulada; vencedor assumido: claude.' -ForegroundColor Yellow
    $winner = 'claude'
    $tally = '  (dry-run) sem votos reais'
} else {
    $priorTally = ''
    $winner = $null
    for ($round = 1; $round -le $MaxRounds; $round++) {
        Write-Host "-- Rodada $round --" -ForegroundColor DarkCyan
        $ballots = foreach ($e in $electorList) {
            Write-Host "   $e votando..." -ForegroundColor DarkGray
            $v = Invoke-Vote -Elector $e -PriorTally $priorTally
            $v['elector'] = $e
            [pscustomobject]$v | Out-Null
            $v
        }
        $result = Resolve-Tally -Ballots @($ballots)
        Write-Host $result.tallyText
        $priorTally = $result.tallyText
        $winner = $result.winner
        if ($result.consensus) {
            Write-Host "Consenso na rodada $round." -ForegroundColor Green
            break
        }
        if ($round -lt $MaxRounds) {
            Write-Host 'Sem consenso claro; abrindo nova rodada com os votos a vista.' -ForegroundColor Yellow
        } else {
            Write-Host "Sem consenso apos $MaxRounds rodadas; usando o mais votado." -ForegroundColor Yellow
        }
    }
    $tally = $priorTally
}

if (-not $winner) { throw 'Nenhum voto valido; nao foi possivel eleger um lider.' }
Write-Host ("LIDER ELEITO: {0}  ({1})" -f $winner, $candidates[$winner]) -ForegroundColor Green
if ($ElectOnly) { return $winner }
Test-OpenRouterNeeded -Provider $winner

# ---------------- FASE 2: EXECUCAO ----------------
Write-Host "== CONSELHO: execucao pelo lider ($winner) ==" -ForegroundColor Cyan
$execPerspective = @{ $winner = "Persona: voce e uma $($Personas[$winner]), eleita lider pelo conselho ($($candidates[$winner])). Execute a tarefa e justifique decisoes-chave.`n`n$Guardrails" }
$execArgs = Get-ExecArgs -Provider $winner -Prompt $Task -TaskId ('council-exec-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) -Perspectives $execPerspective
if ($DryRun) { $execArgs += '--dry-run' }
if ($Json)   { $execArgs += '--json' } else { $execArgs += @('--stream', 'live') }
'' | & mco @execArgs
$execExit = $LASTEXITCODE

# ---------------- FASE 3: REVISAO ----------------
if (-not $SkipReview) {
    $reviewers = @($electorList | Where-Object { $_ -ne $winner })
    if ($reviewers.Count -gt 0 -and -not $DryRun) {
        Write-Host "== CONSELHO: revisao ($($reviewers -join ', ')) ==" -ForegroundColor Cyan
        $reviewPrompt = @"
Voce e um revisor critico do conselho. O lider eleito ($winner) executou a tarefa abaixo.
Revise o trabalho dele apontando erros, riscos e melhorias.
Termine com: VEREDITO: aprovado | aprovado-com-ressalvas | reprovado.

$Guardrails

Tarefa original:
$Task
"@
        $rArgs = @(
            'run', '--repo', $Repo, '--prompt', $reviewPrompt, '--providers', ($reviewers -join ','),
            '--target-paths', $TargetPaths, '--execution-mode', 'read_only',
            '--include-token-usage', '--invocation-hard-timeout', '180'
        )
        if ($reviewers -contains 'qwen') { $env:MCO_QWEN_AUTH_TYPE = 'openai' }
        if ($reviewers -contains 'pi') {
            $dm = @{ pi = @{ provider = 'openrouter'; model = 'deepseek/deepseek-v4-flash-0731' } } | ConvertTo-Json -Compress
            $rArgs += @('--provider-models-json', $dm)
        }
        $rArgs += @('--stream', 'live')
        '' | & mco @rArgs
    }
}

exit $execExit
