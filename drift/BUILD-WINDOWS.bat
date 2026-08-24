@echo off
REM DRIFT - build a Windows executable.
REM Double-click this file. Nothing to type.
setlocal
cd /d "%~dp0"

echo.
echo   DRIFT - building a Windows executable
echo   ------------------------------------
echo.

where node >nul 2>nul
if errorlevel 1 (
  echo   Node.js is not installed.
  echo.
  echo   Get the LTS installer from https://nodejs.org
  echo   Accept the defaults, then double-click this file again.
  echo.
  pause
  exit /b 1
)

REM --portable produces one self-contained .exe with no installer,
REM which is the easiest thing to hand to someone to try.
node build.mjs --win --portable

echo.
if errorlevel 1 (
  echo   Build did not finish. The reason is above.
) else (
  echo   Your .exe is in the dist folder.
)
echo.
pause
