@echo off
setlocal

set "SCRIPT_BASE=%AGENTX_INSTALL_SCRIPT_BASE_URL%"
if "%SCRIPT_BASE%"=="" set "SCRIPT_BASE=https://agentx.aelus.tech/cli/agentx-listing-generation"

set "INSTALL_PS1=%TEMP%\alg-install-%RANDOM%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -UseBasicParsing -Uri '%SCRIPT_BASE%/install.ps1' -OutFile '%INSTALL_PS1%'"
if errorlevel 1 exit /b %errorlevel%

powershell -NoProfile -ExecutionPolicy Bypass -File "%INSTALL_PS1%" %*
set "EXIT_CODE=%ERRORLEVEL%"
del "%INSTALL_PS1%" >nul 2>nul
exit /b %EXIT_CODE%
