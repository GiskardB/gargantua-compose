@echo off
setlocal
cd /d "%~dp0"

where docker >nul 2>nul
if errorlevel 1 (
  echo [gargantua] Docker not found on PATH. Install Docker Desktop and retry.
  exit /b 1
)

if not exist ".env" (
  echo [gargantua] No .env found - creating one from .env.example
  copy /y ".env.example" ".env" >nul
)

echo [gargantua] Building and starting the stack. The first run can take a few minutes...
docker compose up -d --build --wait
if errorlevel 1 (
  echo [gargantua] Startup failed. Inspect logs with: docker compose logs
  exit /b 1
)

echo.
echo [gargantua] Up. Open (default ports; change them in .env if needed):
echo   Studio UI       http://localhost:18081
echo   Studio backend  http://localhost:18081/actuator/health
echo   Control Plane   http://localhost:18080/actuator/health
echo.
echo [gargantua] Stop with stop.bat   ^(stop.bat clean also removes the data volumes^)
endlocal
