@echo off
setlocal
title Rime Smart Simplified Installer

echo Rime Smart Simplified - Windows installer
echo.
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" %*
set "RIME_INSTALL_EXIT=%ERRORLEVEL%"

echo.
if "%RIME_INSTALL_EXIT%"=="0" (
  echo Installation finished.
  echo Next: open the Weasel menu and choose Deploy, then select Rime Ice.
  echo Quick test: type nihao and choose the Chinese candidate; type rq for today's date.
) else (
  echo Installation failed with exit code %RIME_INSTALL_EXIT%.
)

echo.
pause
exit /b %RIME_INSTALL_EXIT%
