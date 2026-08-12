[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$existingKey = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'User')
if ([string]::IsNullOrWhiteSpace($existingKey)) {
    $secureKey = Read-Host 'Cole a chave do OpenRouter (ela nao sera exibida)' -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
    try {
        $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
        if ([string]::IsNullOrWhiteSpace($plainKey)) {
            throw 'A chave nao pode ficar vazia.'
        }
        [Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY', $plainKey, 'User')
        [Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY', $plainKey, 'Process')
    }
    finally {
        if ($ptr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
        }
        $plainKey = $null
    }
} else {
    [Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY', $existingKey, 'Process')
    $existingKey = $null
}

$settingsPath = Join-Path $env:USERPROFILE '.qwen\settings.json'
$settingsDirectory = Split-Path -Parent $settingsPath
if (-not (Test-Path -LiteralPath $settingsDirectory)) {
    New-Item -ItemType Directory -Path $settingsDirectory -Force | Out-Null
}

if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
} else {
    $settings = [pscustomobject]@{}
}

function Set-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    } else {
        $Object.$Name = $Value
    }
}

if ($null -eq $settings.PSObject.Properties['security']) { Set-ObjectProperty $settings 'security' ([pscustomobject]@{}) }
if ($null -eq $settings.security.PSObject.Properties['auth']) { Set-ObjectProperty $settings.security 'auth' ([pscustomobject]@{}) }
if ($null -eq $settings.security.auth.PSObject.Properties['selectedType']) { Set-ObjectProperty $settings.security.auth 'selectedType' 'openai' } else { $settings.security.auth.selectedType = 'openai' }

if ($null -eq $settings.PSObject.Properties['model']) { Set-ObjectProperty $settings 'model' ([pscustomobject]@{}) }
if ($null -eq $settings.model.PSObject.Properties['name']) { Set-ObjectProperty $settings.model 'name' 'qwen/qwen3-coder-next' } else { $settings.model.name = 'qwen/qwen3-coder-next' }

if ($null -eq $settings.PSObject.Properties['modelProviders']) { Set-ObjectProperty $settings 'modelProviders' ([pscustomobject]@{}) }
$otherOpenAiModels = @($settings.modelProviders.openai | Where-Object { $null -ne $_ -and $_.id -ne 'qwen/qwen3-coder-next' })
$qwenModel = [pscustomobject]@{
    id = 'qwen/qwen3-coder-next'
    name = 'Qwen3 Coder Next via OpenRouter'
    envKey = 'OPENROUTER_API_KEY'
    baseUrl = 'https://openrouter.ai/api/v1'
}
$openAiModels = @($otherOpenAiModels) + @($qwenModel)
if ($null -eq $settings.modelProviders.PSObject.Properties['openai']) { Set-ObjectProperty $settings.modelProviders 'openai' $openAiModels } else { $settings.modelProviders.openai = $openAiModels }

$settings | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $settingsPath -Encoding utf8
Write-Host 'OpenRouter configurado para Qwen e DeepSeek. Abra uma nova sessao do host.' -ForegroundColor Green
