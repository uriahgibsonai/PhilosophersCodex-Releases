@echo off
setlocal
cd /d "%~dp0"
echo Philosopher's Codex updater
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-PhilosophersCodex.ps1" %*
set ERR=%ERRORLEVEL%
echo.
if not "%ERR%"=="0" (
  echo Update failed. If Windows blocked the script, right-click the .ps1, choose Properties, and unblock it.
) else (
  echo Done.
)
echo.
pause
exit /b %ERR%
