@echo off
setlocal
set "INSTALLER=%~dp0install.ps1"
set "DOWNLOADED="

if not exist "%INSTALLER%" (
  set "INSTALLER=%TEMP%\install-redfox.ps1"
  set "DOWNLOADED=1"
  curl.exe -fsSL "https://raw.githubusercontent.com/wesleybasso/redfox-ai-orchestrator/main/install.ps1" -o "%INSTALLER%"
  if errorlevel 1 (
    echo Nao foi possivel baixar o instalador RedFox.
    pause
    exit /b 1
  )
)

set "PWSH=%ProgramFiles%\PowerShell\7\pwsh.exe"
if exist "%PWSH%" (
  "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%"
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%INSTALLER%"
)
set "RESULT=%ERRORLEVEL%"
if defined DOWNLOADED del /q "%INSTALLER%" >nul 2>&1
echo.
if not "%RESULT%"=="0" echo A instalacao terminou com erro %RESULT%.
pause
exit /b %RESULT%
