# ==========================================
# KARUNA YOUTUBE AI AGENT - MASTER ONE CLICK (v4)
# Fixes:
#  - XTTS install (VC++ Build Tools + Python 3.10 venv)
#  - Docker engine not ready (wait + checks)
#  - Docker credential helper error (credsStore removal)
#  - Accurate status reporting (no false OK)
# ==========================================

$ErrorActionPreference = "Continue"

$Root       = "F:\YouTubu_AI"
$N8nDir     = Join-Path $Root "n8n"
$ScriptsDir = Join-Path $Root "scripts"
$ConfigDir  = Join-Path $Root "config"
$EnvPath    = Join-Path $Root ".env"

$VenvPy311  = Join-Path $Root ".venv\Scripts\python.exe"
$VenvTtsDir = Join-Path $Root ".venv_tts"
$PyTts      = Join-Path $VenvTtsDir "Scripts\python.exe"

function Write-Step($m){ Write-Host $m -ForegroundColor Cyan }
function Write-OK($m){ Write-Host $m -ForegroundColor Green }
function Write-Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Write-Err($m){ Write-Host $m -ForegroundColor Red }

function Is-Admin {
  try {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  } catch { return $false }
}

function Ensure-Dir($p){ if (-not (Test-Path $p)) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

function Resolve-DockerExe {
  $cmd = Get-Command docker -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $c = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
  if (Test-Path $c) { return $c }
  $c2 = "C:\Program Files\Docker\Docker\docker.exe"
  if (Test-Path $c2) { return $c2 }
  return $null
}

function Ensure-DockerPath {
  $dockerBin = "C:\Program Files\Docker\Docker\resources\bin"
  if (Test-Path $dockerBin) {
    if ($env:Path -notlike "*$dockerBin*") {
      $env:Path = "$dockerBin;$env:Path"
      Write-OK "Added Docker bin to PATH for this session."
    }
  }
}

function Fix-DockerCredHelper {
  # Fix: docker-credential-desktop not found
  $cfg = Join-Path $env:USERPROFILE ".docker\config.json"
  if (-not (Test-Path $cfg)) { return }

  $raw = Get-Content $cfg -Raw
  if ($raw -match '"credsStore"\s*:\s*"desktop"') {
    Write-Step "Fixing Docker credsStore=desktop (local-only fix)..."
    try {
      $json = $raw | ConvertFrom-Json
      $json.PSObject.Properties.Remove("credsStore") | Out-Null
      $json | ConvertTo-Json -Depth 30 | Out-File -Encoding UTF8 $cfg
      Write-OK "Removed credsStore from ~/.docker/config.json"
    } catch {
      Write-Warn "Could not auto-fix ~/.docker/config.json. Manual fix may be needed."
    }
  }
}

function Wait-For-DockerEngine($DockerExe, $Seconds=240) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    try {
      & $DockerExe version | Out-Null
      if ($LASTEXITCODE -eq 0) { return $true }
    } catch {}
    Start-Sleep -Seconds 4
  }
  return $false
}

function Ensure-Python310 {
  Write-Step "Checking Python 3.10..."
  py -3.10 --version 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Step "Installing Python 3.10..."
    winget install -e --id Python.Python.3.10 --accept-package-agreements --accept-source-agreements
  } else {
    Write-OK "Python 3.10 available."
  }
}

function Ensure-VCBuildTools {
  Write-Step "Checking Visual C++ Build Tools..."
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $has = $false
  if (Test-Path $vswhere) {
    $path = & $vswhere -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($path) { $has = $true }
  }
  if ($has) {
    Write-OK "C++ Build Tools detected."
  } else {
    Write-Step "Installing Visual Studio 2022 Build Tools (required for XTTS)..."
    winget install -e --id Microsoft.VisualStudio.2022.BuildTools --accept-package-agreements --accept-source-agreements
    Write-Warn "If XTTS install still fails, reboot once and rerun MASTER."
  }
}

# ---------- Start ----------
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " KARUNA YOUTUBE AGENT - MASTER START " -ForegroundColor Green
Write-Host " Root Folder: $Root"
Write-Host "=====================================" -ForegroundColor Cyan

Ensure-Dir $ScriptsDir
Ensure-Dir $ConfigDir

# 1) Create .env if missing
if (-not (Test-Path $EnvPath)) {
  Write-Step "[1/10] Creating .env template..."
@"
ROOT_DIR=F:\YouTubu_AI
TIMEZONE=Asia/Kolkata
PC_IP=192.168.0.8

EMAIL_TO=flavorofrayalaseema@gmail.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=flavorofrayalaseema@gmail.com
SMTP_PASS=PASTE_GMAIL_APP_PASSWORD_HERE

AGENT_HOST=0.0.0.0
AGENT_PORT=8787

OLLAMA_URL=http://localhost:11434
OLLAMA_MODEL=qwen2.5:7b-instruct

YOUTUBE_CLIENT_SECRET=F:\YouTubu_AI\config\youtube_client_secret.json
YOUTUBE_TOKEN_CACHE=F:\YouTubu_AI\config\youtube_token.json
"@ | Out-File -Encoding UTF8 $EnvPath
  Write-OK "Created: $EnvPath"
} else {
  Write-OK "[1/10] .env exists"
}

# 2) Main app deps (3.11)
Write-Step "[2/10] Ensuring main app deps (.venv Python 3.11)..."
try {
  & $VenvPy311 -m pip install --upgrade pip setuptools wheel | Out-Null
  & $VenvPy311 -m pip install -r (Join-Path $Root "requirements.txt") | Out-Null
  Write-OK "Main app deps OK"
} catch {
  Write-Warn "Main app deps had warnings (continuing)."
}

# 3) XTTS deps and install (Python 3.10 + VC++)
Write-Step "[3/10] Preparing XTTS (Python 3.10 + VC++ Build Tools)..."
Ensure-Python310
Ensure-VCBuildTools

$TtsReady = $false
Write-Step "[4/10] Installing XTTS into .venv_tts..."
try {
  # Recreate venv to avoid half-installs
  if (Test-Path $VenvTtsDir) { Remove-Item -Recurse -Force $VenvTtsDir -ErrorAction SilentlyContinue }
  py -3.10 -m venv $VenvTtsDir | Out-Null

  & $PyTts -m pip install --upgrade pip setuptools wheel | Out-Null
  & $PyTts -m pip install "numpy<2" | Out-Null

  & $PyTts -m pip install TTS
  if ($LASTEXITCODE -ne 0) { throw "pip install TTS failed (likely VC++ not active yet). Reboot once if just installed Build Tools." }

  & $PyTts -c "from TTS.api import TTS; print('XTTS OK')"
  if ($LASTEXITCODE -ne 0) { throw "TTS import failed" }

  $TtsReady = $true
  Write-OK "XTTS READY (.venv_tts)"
} catch {
  Write-Warn "XTTS NOT READY: $($_.Exception.Message)"
  Write-Warn "Fix: Reboot once (if Build Tools installed now), then rerun MASTER."
}

# 5) Firewall rules (only if Admin)
Write-Step "[5/10] Firewall rules (8787/5678) ..."
if (Is-Admin) {
  try {
    New-NetFirewallRule -DisplayName "YT Agent Server 8787" -Direction Inbound -Protocol TCP -LocalPort 8787 -Action Allow | Out-Null
    New-NetFirewallRule -DisplayName "n8n Webhooks 5678" -Direction Inbound -Protocol TCP -LocalPort 5678 -Action Allow | Out-Null
    Write-OK "Firewall rules added"
  } catch {
    Write-Warn "Firewall rules failed (continuing)."
  }
} else {
  Write-Warn "Not Admin → skipping firewall rules."
}

# 6) Start Docker + n8n (robust)
Write-Step "[6/10] Starting Docker Desktop + n8n..."
Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue | Out-Null
Start-Sleep -Seconds 8

Ensure-DockerPath
Fix-DockerCredHelper

$DockerExe = Resolve-DockerExe
if (-not $DockerExe) {
  Write-Err "Docker CLI not found. Reopen PowerShell and rerun."
} else {
  Write-Host "Using Docker: $DockerExe" -ForegroundColor Gray
  $ok = Wait-For-DockerEngine -DockerExe $DockerExe -Seconds 240
  if (-not $ok) {
    Write-Err "Docker Engine not ready. Open Docker Desktop and ensure 'Engine running', then rerun MASTER."
  } else {
    try {
      Set-Location $N8nDir
      & $DockerExe compose up -d
      if ($LASTEXITCODE -eq 0) {
        Write-OK "n8n started"
      } else {
        Write-Warn "docker compose returned exit code $LASTEXITCODE (n8n may not be running)."
      }
    } catch {
      Write-Warn "Failed to start n8n compose."
    }
  }
}

# 7) Start Agent Server
Write-Step "[7/10] Starting Agent Server..."
try {
  Start-Process powershell -ArgumentList "-NoExit", "-Command", "& `"$VenvPy311`" -m uvicorn agent_server:APP --host 0.0.0.0 --port 8787 --reload --app-dir `"$ScriptsDir`""
  Start-Sleep -Seconds 2
  Start-Process "http://localhost:5678" | Out-Null
  Start-Process "http://localhost:8787/health" | Out-Null
  Write-OK "Agent Server started"
} catch {
  Write-Warn "Agent Server start failed."
}

Write-Host ""
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host " 🎉 YOUTUBE AI AGENT IS FULLY RUNNING " -ForegroundColor Green
Write-Host " n8n UI: http://localhost:5678"
Write-Host " Agent Server: http://localhost:8787"
Write-Host "=====================================" -ForegroundColor Cyan

# Reminders
$VoiceEn = Join-Path $Root "voice\dataset\en\ref.wav"
$VoiceTe = Join-Path $Root "voice\dataset\te\ref.wav"
if (-not (Test-Path $VoiceEn)) { Write-Warn "MISSING voice ref: $VoiceEn" }
if (-not (Test-Path $VoiceTe)) { Write-Warn "MISSING voice ref: $VoiceTe" }

if ($TtsReady) {
  Write-OK "XTTS ready. Once ref.wav present, /run will generate with your cloned voice."
} else {
  Write-Warn "XTTS not ready yet. Video automation can still run (without your clone) until XTTS is fixed."
}

Write-Warn "IMPORTANT: Edit .env and set SMTP_PASS to Gmail App Password for flavorofrayalaseema@gmail.com"