[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Write-Host 'REDFOX - CONFIGURACAO GUIADA' -ForegroundColor Red
Write-Host 'As senhas e chaves nao serao mostradas nem salvas no projeto.'

if ((Read-Host 'Configurar login do Claude agora? (s/n)') -match '^(s|sim)$') {
    Write-Host 'O Claude abrira o fluxo de login. Finalize e volte aqui.' -ForegroundColor Yellow
    & claude
}
if ((Read-Host 'Configurar login do Codex agora? (s/n)') -match '^(s|sim)$') {
    & codex login
}
if ((Read-Host 'Configurar chave do Gemini agora? (s/n)') -match '^(s|sim)$') {
    $secure = Read-Host 'Cole a GEMINI_API_KEY (ficara invisivel)' -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
        [Environment]::SetEnvironmentVariable('GEMINI_API_KEY',$plain,'User')
        $env:GEMINI_API_KEY = $plain
    } finally {
        if ($plain) { $plain = $null }
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
    Write-Host 'Chave Gemini armazenada no perfil do Windows.' -ForegroundColor Green
}

if ((Read-Host 'Instalar ou configurar GitHub Copilot CLI agora? (s/n)') -match '^(s|sim)$') {
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path','User')
    $env:Path = "$machinePath;$userPath"
    if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
        & winget install --id GitHub.Copilot --exact --accept-package-agreements --accept-source-agreements
        $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
    }
    if (Get-Command copilot -ErrorAction SilentlyContinue) {
        & copilot login
    } else {
        Write-Warning 'Copilot CLI foi instalado, mas ainda nao apareceu no PATH. Abra um novo terminal e rode: copilot login'
    }
}

Write-Host "`nDiagnostico final:" -ForegroundColor Cyan
& mco doctor --json
Write-Host "`nQuando quiser, a RedFox podera configurar Qwen, DeepSeek e pesquisa web na proxima etapa." -ForegroundColor Green
