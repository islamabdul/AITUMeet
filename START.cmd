@echo off
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Please install Node.js 22.13 or newer from https://nodejs.org
  pause
  exit /b 1
)
echo Open http://127.0.0.1:3000
node server.mjs
pause
