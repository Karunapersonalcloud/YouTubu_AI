@echo off
REM YouTube AI Agent - Web App Startup Script
REM Setup and start the complete web application (Backend + Frontend + n8n)

setlocal enabledelayedexpansion
set ROOT=F:\YouTubu_AI

echo.
echo ========================================
echo  YouTube AI Agent - Web App Launcher
echo ========================================
echo.

REM Check if Docker is installed
where docker >nul 2>nul
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Docker is not installed or not in PATH
    echo Please install Docker Desktop from https://www.docker.com/products/docker-desktop
    pause
    exit /b 1
)

echo [1/3] Activating Python venv...
call "%ROOT%\.venv\Scripts\activate.bat"

echo [2/3] Starting Docker containers...
cd /d "%ROOT%"
docker-compose -f docker-compose.web.yml up -d

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to start Docker containers
    pause
    exit /b 1
)

echo.
echo ========================================
echo  ✅ Web App Started Successfully!
echo ========================================
echo.
echo 📡 Services:
echo   • Frontend:  http://localhost:3000
echo   • Backend:   http://localhost:8000
echo   • n8n:       http://localhost:5678
echo.
echo 🚀 Opening Frontend in 3 seconds...
timeout /t 3 /nobreak
start http://localhost:3000

echo.
echo 📚 Tips:
echo   • Check Backend Dockerfile exists: %ROOT%\webapp\backend\Dockerfile
echo   • Check Frontend Dockerfile exists: %ROOT%\webapp\frontend\Dockerfile
echo   • View logs: docker-compose -f docker-compose.web.yml logs -f
echo   • Stop all: docker-compose -f docker-compose.web.yml down
echo.
pause
