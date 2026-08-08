@echo off
setlocal
cd /d "%~dp0"

where docker >nul 2>nul
if errorlevel 1 (
  echo [gargantua] Docker not found on PATH.
  exit /b 1
)

if /i "%~1"=="clean" (
  echo [gargantua] Stopping and removing volumes - Postgres and MinIO data will be lost...
  docker compose down -v
) else (
  echo [gargantua] Stopping. Data is kept in volumes; run "stop.bat clean" to wipe it.
  docker compose down
)
endlocal
