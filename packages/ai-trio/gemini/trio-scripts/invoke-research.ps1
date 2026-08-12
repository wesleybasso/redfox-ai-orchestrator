[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [Alias('Pergunta', 'Task')]
    [ValidateNotNullOrEmpty()]
    [string]$Query,

    [ValidateNotNullOrEmpty()]
    [string]$Repo = (Get-Location).Path,

    # modelo que redige a resposta citada
    [ValidateNotNullOrEmpty()]
    [string]$Writer = 'claude',

    # modelo que verifica as citacoes (deve ser diferente do Writer)
    [ValidateNotNullOrEmpty()]
    [string]$Verifier = 'codex',

    [ValidateRange(1, 10)]
    [int]$MaxResults = 5,

    # backend de busca web: auto usa a chave disponivel (Tavily tem prioridade)
    [ValidateSet('auto', 'tavily', 'brave')]
    [string]$SearchProvider = 'auto',

    [switch]$DryRun,   # nao busca nem chama modelos; usa fonte ficticia
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command mco -ErrorAction SilentlyContinue)) {
    throw 'MCO nao encontrado. Instale com: npm install -g @tt-a1i/mco@0.11.0'
}

foreach ($keyName in @('TAVILY_API_KEY', 'BRAVE_API_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($keyName, 'Process'))) {
        $userValue = [Environment]::GetEnvironmentVariable($keyName, 'User')
        if (-not [string]::IsNullOrWhiteSpace($userValue)) {
            [Environment]::SetEnvironmentVariable($keyName, $userValue, 'Process')
        }
    }
}

# ---------------- 1) BUSCA WEB (Tavily ou Brave) ----------------
function Invoke-TavilySearch {
    param([string]$Q, [int]$Max)
    $body = @{
        api_key        = $env:TAVILY_API_KEY
        query          = $Q
        search_depth   = 'advanced'
        max_results    = $Max
        include_answer = $true
    } | ConvertTo-Json
    $resp = Invoke-RestMethod -Method Post -Uri 'https://api.tavily.com/search' `
        -ContentType 'application/json' -Body $body -TimeoutSec 30
    $sources = @(); $i = 0
    foreach ($r in $resp.results) {
        $i++
        $sources += [pscustomobject]@{ n = $i; title = $r.title; url = $r.url; content = ($r.content -replace '\s+', ' ').Trim() }
    }
    return @{ sources = $sources; answer = $resp.answer }
}

function Invoke-BraveSearch {
    param([string]$Q, [int]$Max)
    $uri = 'https://api.search.brave.com/res/v1/web/search?q={0}&count={1}' -f [uri]::EscapeDataString($Q), $Max
    $headers = @{ 'X-Subscription-Token' = $env:BRAVE_API_KEY; 'Accept' = 'application/json' }
    $resp = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers -TimeoutSec 30
    $sources = @(); $i = 0
    foreach ($r in $resp.web.results) {
        if ($i -ge $Max) { break }
        $i++
        $snippet = ($r.description -replace '<[^>]+>', '' -replace '\s+', ' ').Trim()
        $sources += [pscustomobject]@{ n = $i; title = $r.title; url = $r.url; content = $snippet }
    }
    return @{ sources = $sources; answer = '' }
}

function Invoke-WebSearch {
    param([string]$Q, [int]$Max, [string]$Provider)

    $hasTavily = -not [string]::IsNullOrWhiteSpace($env:TAVILY_API_KEY)
    $hasBrave  = -not [string]::IsNullOrWhiteSpace($env:BRAVE_API_KEY)

    if ($Provider -eq 'auto') {
        if ($hasTavily) { $Provider = 'tavily' }
        elseif ($hasBrave) { $Provider = 'brave' }
        else { throw 'Nenhuma chave de busca definida. Execute configure-search.ps1 (Tavily: https://app.tavily.com ou Brave: https://brave.com/search/api).' }
    }

    switch ($Provider) {
        'tavily' {
            if (-not $hasTavily) { throw 'TAVILY_API_KEY nao definida. Execute configure-search.ps1.' }
            Write-Host 'Backend de busca: Tavily' -ForegroundColor DarkGray
            return Invoke-TavilySearch -Q $Q -Max $Max
        }
        'brave' {
            if (-not $hasBrave) { throw 'BRAVE_API_KEY nao definida. Execute configure-search.ps1.' }
            Write-Host 'Backend de busca: Brave' -ForegroundColor DarkGray
            return Invoke-BraveSearch -Q $Q -Max $Max
        }
    }
}

if ($DryRun) {
    Write-Host '[dry-run] busca web ignorada; usando 1 fonte ficticia.' -ForegroundColor Yellow
    $search = @{ answer = ''; sources = @([pscustomobject]@{ n = 1; title = 'Fonte ficticia'; url = 'https://exemplo.test'; content = 'Conteudo de teste.' }) }
} else {
    Write-Host "Buscando na web: $Query" -ForegroundColor Cyan
    $search = Invoke-WebSearch -Q $Query -Max $MaxResults -Provider $SearchProvider
    if (-not $search.sources -or $search.sources.Count -eq 0) {
        throw 'A busca web nao retornou fontes. Refine a pergunta ou tente novamente.'
    }
    Write-Host ("Fontes encontradas: {0}" -f $search.sources.Count) -ForegroundColor Green
}

# bloco de fontes numeradas, reutilizado nas duas fases
$sourcesBlock = ($search.sources | ForEach-Object {
    "[{0}] {1}`n    URL: {2}`n    Trecho: {3}" -f $_.n, $_.title, $_.url, $_.content
}) -join "`n`n"

Write-Host "== FONTES ==" -ForegroundColor DarkCyan
$search.sources | ForEach-Object { Write-Host ("[{0}] {1} — {2}" -f $_.n, $_.title, $_.url) }

# ---------------- 2) RASCUNHO CITADO ----------------
$writerPrompt = @"
Voce e uma Pesquisadora Tecnica rigorosa. Responda a PERGUNTA usando SOMENTE as FONTES abaixo.

REGRAS OBRIGATORIAS:
- Cite a fonte com [n] logo apos cada afirmacao factual.
- Use APENAS o que esta nas fontes. Nao use conhecimento externo como fato.
- Se as fontes nao cobrem parte da pergunta, escreva "as fontes nao cobrem isso".
- Nao invente URLs, numeros, datas ou citacoes.
- Ao final, liste "Fontes usadas:" com [n] e a URL.

PERGUNTA:
$Query

FONTES:
$sourcesBlock
"@

$draftTaskId = 'research-draft-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
Write-Host "== RASCUNHO ($Writer) ==" -ForegroundColor Cyan

$writerArgs = @(
    'run', '--repo', $Repo, '--prompt', $writerPrompt, '--providers', $Writer,
    '--execution-mode', 'read_only', '--result-mode', 'stdout',
    '--include-token-usage', '--invocation-hard-timeout', '180', '--task-id', $draftTaskId
)
if ($DryRun) { $writerArgs += '--dry-run' }

$draft = '' | & mco @writerArgs 2>$null | Out-String
Write-Host $draft

if ($DryRun) { Write-Host '[dry-run] verificacao ignorada.' -ForegroundColor Yellow; exit 0 }

# ---------------- 3) VERIFICACAO CETICA ----------------
$verifierPrompt = @"
Voce e um verificador cetico e independente. Recebe uma PERGUNTA, as FONTES e um RASCUNHO de resposta.
Para CADA afirmacao factual do rascunho, verifique se a fonte citada realmente a sustenta.

Marque cada afirmacao como:
- SUSTENTADO (a fonte citada confirma)
- NAO-SUSTENTADO (a fonte citada nao confirma ou contradiz)
- SEM-FONTE (afirmacao sem citacao)

Liste os problemas encontrados e sugira correcoes.
NAO use conhecimento externo como fato; julgue apenas contra as FONTES.
Termine com uma linha: CONFIABILIDADE: alta | media | baixa

PERGUNTA:
$Query

FONTES:
$sourcesBlock

RASCUNHO A VERIFICAR:
$draft
"@

Write-Host "== VERIFICACAO ($Verifier) ==" -ForegroundColor Cyan
$verifierArgs = @(
    'run', '--repo', $Repo, '--prompt', $verifierPrompt, '--providers', $Verifier,
    '--execution-mode', 'read_only', '--invocation-hard-timeout', '180'
)
if ($Json) { $verifierArgs += '--json' } else { $verifierArgs += @('--stream', 'live') }

'' | & mco @verifierArgs
$verifierExit = $LASTEXITCODE

if ($verifierExit -ne 0) {
    Write-Host ''
    Write-Warning ("A verificacao ($Verifier) falhou ou expirou (exit $verifierExit). A RESPOSTA acima (do redator '$Writer') foi PRESERVADA, mas NAO passou pela verificacao independente. Trate-a como nao-verificada e tente outro verificador, por exemplo: -Verifier claude, ou rode de novo.")
    exit 0
}

exit 0
