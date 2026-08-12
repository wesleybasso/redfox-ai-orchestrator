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

    # 'auto' = um LLM barato classifica; ou force o dominio manualmente
    [ValidateSet('auto', 'arch', 'impl', 'algo', 'math', 'research')]
    [string]$Domain = 'auto',

    # modelo barato usado para classificar quando Domain = auto
    [ValidateNotNullOrEmpty()]
    [string]$Classifier = 'gemini',

    [switch]$DryRun,   # nao chama modelos; mostra o que faria
    [switch]$Json,     # saida do especialista em JSON
    [switch]$Explain   # so classifica e imprime o dominio; nao chama o especialista
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command mco -ErrorAction SilentlyContinue)) {
    throw 'MCO nao encontrado. Instale com: npm install -g @tt-a1i/mco@0.11.0'
}

# hidrata chaves do ambiente do usuario para o processo atual
foreach ($keyName in @('GEMINI_API_KEY', 'OPENROUTER_API_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($keyName, 'Process'))) {
        $userValue = [Environment]::GetEnvironmentVariable($keyName, 'User')
        if (-not [string]::IsNullOrWhiteSpace($userValue)) {
            [Environment]::SetEnvironmentVariable($keyName, $userValue, 'Process')
        }
    }
}

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

function New-Perspective {
    param([string]$Provider, [string]$Focus)
    "Persona: voce e uma $($Personas[$Provider]).`nFoco desta tarefa: $Focus`n`n$Guardrails"
}

# mapa dominio -> especialista
$specialists = @{
    arch     = @{ provider = 'claude'; role = 'Arquitetura, requisitos, riscos, seguranca e coerencia de design.' }
    impl     = @{ provider = 'codex';  role = 'Implementacao, depuracao, testes, performance e manutenibilidade.' }
    algo     = @{ provider = 'qwen';   role = 'Raciocinio de codigo, algoritmos, estruturas de dados e alternativas.' }
    math     = @{ provider = 'pi';     role = 'Raciocinio profundo, matematica, complexidade e eficiencia.' }
    research = @{ provider = 'gemini'; role = 'Pesquisa, documentacao, contexto amplo, alternativas e usabilidade.' }
}

function Invoke-Classifier {
    param([string]$TaskText, [string]$Model)

    $prompt = @"
Voce e um classificador. Leia a tarefa e escolha UMA categoria.
Responda APENAS com uma destas palavras, sem pontuacao, sem explicacao:
arch impl algo math research

Significados:
arch = arquitetura, design de sistema, seguranca, requisitos, revisao critica
impl = implementar/corrigir codigo, depurar, escrever testes, refatorar
algo = algoritmos, estruturas de dados, otimizacao de codigo, alternativas
math = matematica, provas, analise de complexidade, calculo numerico
research = pesquisa, documentacao, comparar ferramentas/abordagens, contexto amplo

Tarefa:
$TaskText
"@

    $out = '' | & mco run --repo $Repo --prompt $prompt --providers $Model `
        --execution-mode read_only --result-mode stdout `
        --invocation-hard-timeout 60 2>$null
    $text = ($out | Out-String).ToLower()

    foreach ($d in @('arch', 'impl', 'algo', 'math', 'research')) {
        if ($text -match "\b$d\b") { return $d }
    }
    return $null
}

# 1) decidir o dominio
if ($Domain -eq 'auto') {
    if ($DryRun) {
        Write-Host '[dry-run] classificador nao executado; assumindo dominio "arch".' -ForegroundColor Yellow
        $resolved = 'arch'
    } else {
        Write-Host "Classificando a tarefa com '$Classifier'..." -ForegroundColor Cyan
        $resolved = Invoke-Classifier -TaskText $Task -Model $Classifier
        if (-not $resolved) {
            Write-Host 'Classificador indeciso; usando "arch" como padrao seguro.' -ForegroundColor Yellow
            $resolved = 'arch'
        }
    }
} else {
    $resolved = $Domain
}

$spec = $specialists[$resolved]
Write-Host ("Dominio: {0}  ->  especialista: {1}" -f $resolved, $spec.provider) -ForegroundColor Green

if ($Explain) { return $resolved }

# 2) montar chamada do especialista
$perspectives = @{ $spec.provider = (New-Perspective -Provider $spec.provider -Focus $spec.role) } | ConvertTo-Json -Compress
$taskId = 'router-{0}-{1}' -f $resolved, (Get-Date -Format 'yyyyMMdd-HHmmss')

$mcoArgs = @(
    'run',
    '--repo', $Repo,
    '--prompt', $Task,
    '--providers', $spec.provider,
    '--target-paths', $TargetPaths,
    '--execution-mode', 'read_only',
    '--perspectives-json', $perspectives,
    '--include-token-usage',
    '--invocation-hard-timeout', '300',
    '--task-id', $taskId
)

# Qwen e DeepSeek exigem OpenRouter
if ($spec.provider -in @('qwen', 'pi')) {
    if ([string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY) -and -not $DryRun) {
        throw "O especialista '$($spec.provider)' usa OpenRouter. Execute configure-openrouter.ps1 uma vez."
    }
    if ($spec.provider -eq 'qwen') {
        $env:MCO_QWEN_AUTH_TYPE = 'openai'
    }
    if ($spec.provider -eq 'pi') {
        $deepSeekModel = @{ pi = @{ provider = 'openrouter'; model = 'deepseek/deepseek-v4-flash-0731' } } | ConvertTo-Json -Compress
        $mcoArgs += @('--provider-models-json', $deepSeekModel)
    }
}

if ($DryRun) { $mcoArgs += '--dry-run' }
if ($Json)   { $mcoArgs += '--json' } else { $mcoArgs += @('--stream', 'live') }

'' | & mco @mcoArgs
exit $LASTEXITCODE
