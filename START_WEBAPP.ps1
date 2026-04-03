<#
YouTube AI Agent - Web App Launcher (PowerShell)
Setup and start: Backend (FastAPI) + Frontend (React) + n8n + Original Agent
#>

$BASE = "F:\YouTubu_AI"
$WEBAPP = "$BASE\webapp"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  YouTube AI Agent - Web App Launcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check Docker
$docker = Get-Command docker -ErrorAction SilentlyContinue
if (-not $docker) {
    Write-Host "ERROR: Docker not found. Install Docker Desktop." -ForegroundColor Red
    exit 1
}

# Activate venv
Write-Host "[1/4] Activating Python environment..." -ForegroundColor Yellow
& "$BASE\.venv\Scripts\Activate.ps1"

# Install frontend dependencies
Write-Host "[2/4] Installing frontend dependencies..." -ForegroundColor Yellow
if (-not (Test-Path "$WEBAPP\frontend\node_modules")) {
    Push-Location "$WEBAPP\frontend"
    npm install
    Pop-Location
}

# Start Docker services
Write-Host "[3/4] Starting Docker containers..." -ForegroundColor Yellow
Push-Location $BASE
docker-compose -f docker-compose.web.yml up -d
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Docker startup failed" -ForegroundColor Red
    exit 1
}
Pop-Location

# Wait for services to be ready
Write-Host "[4/4] Waiting for services to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Test services
$frontendReady = $false
$backendReady = $false
$maxRetries = 10

for ($i = 0; $i -lt $maxRetries; $i++) {
    if (-not $frontendReady) {
        try {
            $response = Invoke-WebRequest -Uri http://localhost:3000 -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) { $frontendReady = $true }
        } catch {}
    }
    
    if (-not $backendReady) {
        try {
            $response = Invoke-WebRequest -Uri http://localhost:8000/health -UseBasicParsing -ErrorAction SilentlyContinue
            if ($response.StatusCode -eq 200) { $backendReady = $true }
        } catch {}
    }
    
    if ($frontendReady -and $backendReady) { break }
    Write-Host "  Checking services... ($($i+1)/$maxRetries)" -ForegroundColor Gray
    Start-Sleep -Seconds 2
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ✅ Web App Started Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""

Write-Host "📡 Services Running:" -ForegroundColor Cyan
Write-Host "   • Frontend:  💻 http://localhost:3000" -ForegroundColor Green
Write-Host "   • Backend:   🔌 http://localhost:8000" -ForegroundColor Green
Write-Host "   • n8n:       ⚙️  http://localhost:5678" -ForegroundColor Green
Write-Host ""

Write-Host "✨ Opening web app in browser..." -ForegroundColor Yellow
Start-Sleep -Seconds 1
Start-Process "http://localhost:3000"

Write-Host ""
Write-Host "📚 Useful Commands:" -ForegroundColor Cyan
Write-Host "   • View logs:         docker-compose -f docker-compose.web.yml logs -f" -ForegroundColor Gray
Write-Host "   • Stop all:          docker-compose -f docker-compose.web.yml down" -ForegroundColor Gray
Write-Host "   • Rebuild:           docker-compose -f docker-compose.web.yml build --no-cache" -ForegroundColor Gray
Write-Host ""
