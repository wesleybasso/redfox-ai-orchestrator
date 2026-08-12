[CmdletBinding()]
param(
    # Quais backends configurar. 'ambos' pergunta pelas duas chaves.
    [ValidateSet('tavily', 'brave', 'ambos')]
    [string]$Provider = 'ambos'
)

$ErrorActionPreference = 'Stop'

# Guarda a chave informada em User + Process, sem exibi-la.
function Set-SearchKey {
    param(
        [Parameter(Mandatory)][string]$KeyName,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Where,
        [string]$Hint
    )

    $existing = [Environment]::GetEnvironmentVariable($KeyName, 'User')
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        Write-Host "$KeyName ja esta definida. Nada a fazer." -ForegroundColor Green
        return
    }

    Write-Host "Crie uma chave para $Label em $Where." -ForegroundColor Cyan
    if ($Hint) { Write-Host $Hint -ForegroundColor DarkGray }
    $secure = Read-Host "Cole a chave do $Label (ela nao sera exibida; ENTER em branco para pular)" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        if ([string]::IsNullOrWhiteSpace($plain)) {
            Write-Host "$Label pulado." -ForegroundColor Yellow
            return
        }
        [Environment]::SetEnvironmentVariable($KeyName, $plain, 'User')
        [Environment]::SetEnvironmentVariable($KeyName, $plain, 'Process')
        Write-Host "$KeyName salva." -ForegroundColor Green
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
        $plain = $null
    }
}

if ($Provider -in @('tavily', 'ambos')) {
    Set-SearchKey -KeyName 'TAVILY_API_KEY' -Label 'Tavily' -Where 'https://app.tavily.com' -Hint 'A chave comeca com "tvly-". Faixa gratis para busca web voltada a LLM.'
}
if ($Provider -in @('brave', 'ambos')) {
    Set-SearchKey -KeyName 'BRAVE_API_KEY' -Label 'Brave Search' -Where 'https://brave.com/search/api' -Hint 'Assine o plano (ha faixa gratis) e copie o token de Subscription.'
}

Write-Host 'Concluido. Abra uma nova sessao do host. O modo pesquisa usa a chave disponivel (Tavily tem prioridade; force com -SearchProvider brave).' -ForegroundColor Green
