@echo off
echo ============================================
echo   YouTubu AI - First Time Setup
echo ============================================
echo.

:: Create required directories
echo [1/5] Creating directories...
if not exist "n8n\n8n_data" mkdir "n8n\n8n_data"
if not exist "n8n\n8n-files" mkdir "n8n\n8n-files"
if not exist "videos\approved\EN" mkdir "videos\approved\EN"
if not exist "videos\approved\TE" mkdir "videos\approved\TE"
if not exist "videos\review\EN" mkdir "videos\review\EN"
if not exist "videos\review\TE" mkdir "videos\review\TE"
if not exist "videos\processed\EN" mkdir "videos\processed\EN"
if not exist "videos\processed\TE" mkdir "videos\processed\TE"
if not exist "videos\uploaded" mkdir "videos\uploaded"
if not exist "output\EN" mkdir "output\EN"
if not exist "output\TE" mkdir "output\TE"
if not exist "config\oauth" mkdir "config\oauth"
if not exist "logs" mkdir "logs"
if not exist "runs" mkdir "runs"
if not exist "assets\stock_cache" mkdir "assets\stock_cache"
if not exist "assets\thumbs" mkdir "assets\thumbs"
if not exist "assets\fonts" mkdir "assets\fonts"
if not exist "tools\ffmpeg\bin" mkdir "tools\ffmpeg\bin"
if not exist "tools\piper" mkdir "tools\piper"
echo    Done.

:: Check Docker
echo.
echo [2/5] Checking Docker...
docker --version >nul 2>&1
if errorlevel 1 (
    echo    ERROR: Docker not found. Install Docker Desktop from https://docker.com
    pause
    exit /b 1
)
echo    Docker found.

:: Check Ollama
echo.
echo [3/5] Checking Ollama...
ollama --version >nul 2>&1
if errorlevel 1 (
    echo    WARNING: Ollama not found. Install from https://ollama.com
    echo    Then run: ollama pull llama3.1:8b
) else (
    echo    Ollama found. Pulling model...
    ollama pull llama3.1:8b
)

:: Start containers
echo.
echo [4/5] Starting Docker containers...
docker-compose -f docker-compose.web.yml up --build -d
if errorlevel 1 (
    echo    ERROR: Docker Compose failed. Check the output above.
    pause
    exit /b 1
)
echo    Containers started.

:: Import n8n workflow
echo.
echo [5/5] Importing n8n workflow...
echo    Waiting for n8n to start...
timeout /t 15 /nobreak >nul
docker exec yt_agent_n8n n8n import:workflow --input=/data/n8n/n8n_workflow_template.json 2>nul
if errorlevel 1 (
    echo    WARNING: Could not auto-import workflow. Import manually:
    echo    1. Open http://localhost:5678
    echo    2. Go to Workflows ^> Import from File
    echo    3. Select n8n/n8n_workflow_template.json
) else (
    echo    Workflow imported.
)

echo.
echo ============================================
echo   Setup Complete!
echo ============================================
echo.
echo   Frontend:  http://localhost:3000
echo   Backend:   http://localhost:8000/docs
echo   n8n:       http://localhost:5678
echo.
echo   NEXT STEPS:
echo   1. Open n8n (http://localhost:5678)
echo   2. Go to Credentials
echo   3. Add YouTube OAuth2 for each channel
echo   4. Edit config/channels.json with your channel info
echo.
pause
