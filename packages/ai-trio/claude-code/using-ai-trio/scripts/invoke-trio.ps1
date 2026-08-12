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

    [ValidateSet('trio', 'quintet')]
    [string]$Team = 'trio',

    [switch]$DryRun,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command mco -ErrorAction SilentlyContinue)) {
    throw 'MCO nao encontrado. Instale com: npm install -g @tt-a1i/mco@latest'
}

foreach ($keyName in @('GEMINI_API_KEY', 'OPENROUTER_API_KEY')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($keyName, 'Process'))) {
        $userValue = [Environment]::GetEnvironmentVariable($keyName, 'User')
        if (-not [string]::IsNullOrWhiteSpace($userValue)) {
            [Environment]::SetEnvironmentVariable($keyName, $userValue, 'Process')
        }
    }
}

if ($Team -eq 'quintet' -and -not $DryRun) {
    if ([string]::IsNullOrWhiteSpace($env:OPENROUTER_API_KEY)) {
        throw 'Qwen e DeepSeek sem credencial. Execute scripts/configure-openrouter.ps1 uma vez.'
    }
    $env:MCO_QWEN_AUTH_TYPE = 'openai'
}

$Guardrails = @'

REGRAS ANTI-ALUCINACAO (obrigatorias): baseie-se APENAS no repositorio/contexto; nao invente arquivos, funcoes, APIs, versoes ou numeros; se nao souber, escreva "nao sei"/"nao consta"; separe FATO de SUPOSICAO; cite o caminho do arquivo ao afirmar algo do codigo; nao fabrique citacoes, links ou saidas de terminal; prefira admitir incerteza a errar com confianca.
'@

$perspectives = @{
    claude = 'Persona: Arquiteta de Software Senior. Priorize arquitetura, requisitos, riscos, seguranca e coerencia.' + $Guardrails
    codex = 'Persona: Engenheira de Implementacao pragmatica. Priorize implementacao, depuracao, testes, performance e manutencao.' + $Guardrails
    gemini = 'Persona: Pesquisadora Tecnica. Priorize pesquisa, documentacao, contexto amplo, alternativas e usabilidade.' + $Guardrails
    qwen = 'Persona: Especialista em Algoritmos (Qwen3 Coder). Priorize raciocinio de codigo, alternativas algoritmicas e revisao independente.' + $Guardrails
    pi = 'Persona: Pesquisadora de raciocinio matematico rigoroso (DeepSeek V4 Flash). Priorize raciocinio profundo, matematica e eficiencia de tokens.' + $Guardrails
} | ConvertTo-Json -Compress

$taskId = 'trio-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$providers = if ($Team -eq 'quintet') { 'claude,codex,gemini,qwen,pi' } else { 'claude,codex,gemini' }
$mcoArgs = @(
    'review',
    '--repo', $Repo,
    '--prompt', $Task,
    '--providers', $providers,
    '--target-paths', $TargetPaths,
    '--execution-mode', 'read_only',
    '--perspectives-json', $perspectives,
    '--synthesize',
    '--synth-provider', 'claude',
    '--result-mode', 'both',
    '--include-token-usage',
    '--max-provider-parallelism', '3',
    '--invocation-hard-timeout', '300',
    '--review-hard-timeout', '900',
    '--task-id', $taskId
)

if ($Team -eq 'quintet') {
    $deepSeekModel = @{ pi = @{ provider = 'openrouter'; model = 'deepseek/deepseek-v4-flash-0731' } } | ConvertTo-Json -Compress
    $mcoArgs += @('--provider-models-json', $deepSeekModel)
}

if ($DryRun) {
    $mcoArgs += '--dry-run'
}

if ($Json) {
    $mcoArgs += '--json'
} else {
    $mcoArgs += @('--stream', 'live')
}

'' | & mco @mcoArgs
exit $LASTEXITCODE
