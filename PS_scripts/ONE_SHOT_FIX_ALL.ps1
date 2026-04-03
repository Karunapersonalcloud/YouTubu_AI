# ==========================================
# ONE SHOT FIX: XTTS + Docker creds + Start All
# ==========================================
$ErrorActionPreference = "Continue"

$Root = "F:\YouTubu_AI"
$N8nDir = Join-Path $Root "n8n"
$ScriptsDir = Join-Path $Root "scripts"
$VenvTts = Join-Path $Root ".venv_tts"
$PyTts = Join-Path $VenvTts "Scripts\python.exe"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Err($m){ Write-Host $m -ForegroundColor Red }

function Resolve-DockerExe {
  $cmd = Get-Command docker -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $c = "C:\Program Files\Docker\Docker\resources\bin\docker.exe"
  if (Test-Path $c) { return $c }
  return $null
}

function Ensure-DockerPath {
  $dockerBin = "C:\Program Files\Docker\Docker\resources\bin"
  if (Test-Path $dockerBin) {
    if ($env:Path -notlike "*$dockerBin*") {
      $env:Path = "$dockerBin;$env:Path"
      OK "Added Docker bin to PATH for this session."
    }
  }
}

function Fix-DockerCredHelper {
  # If Docker is configured to use "desktop" credential store but helper missing, pulls fail.
  $cfg = Join-Path $env:USERPROFILE ".docker\config.json"
  if (-not (Test-Path $cfg)) { return }

  $txt = Get-Content $cfg -Raw
  if ($txt -match '"credsStore"\s*:\s*"desktop"') {
    Step "Docker config uses credsStore=desktop. Applying safe local fallback..."
    try {
      $json = $txt | ConvertFrom-Json
      $json.PSObject.Properties.Remove("credsStore") | Out-Null
      $json | ConvertTo-Json -Depth 20 | Out-File -Encoding UTF8 $cfg
      OK "Removed credsStore from ~/.docker/config.json (local-only fix)."
    } catch {
      Warn "Could not edit Docker config automatically. You may need manual fix."
    }
  }
}

function Ensure-Python310 {
  Step "Checking Python 3.10..."
  py -3.10 --version 2>$null
  if ($LASTEXITCODE -ne 0) {
    Step "Installing Python 3.10..."
    winget install -e --id Python.Python.3.10 --accept-package-agreements --accept-source-agreements
  } else {
    OK "Python 3.10 available."
  }
}

function Install-VCBuildTools {
  # Required to build TTS C-extension on Windows
  Step "Ensuring Microsoft C++ Build Tools (VC++ 14+)..."
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $hasMSVC = $false

  if (Test-Path $vswhere) {
    $out = & $vswhere -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($out) { $hasMSVC = $true }
  }

  if ($hasMSVC) {
    OK "C++ Build Tools detected."
    return
  }

  Step "Installing C++ Build Tools (this may prompt admin/UAC)..."
  winget install -e --id Microsoft.VisualStudio.2022.BuildTools --accept-package-agreements --accept-source-agreements

  Warn "After Build Tools install, you may need to RESTART PowerShell once."
}

function Install-XTTS {
  Step "Installing XTTS (Coqui TTS) into .venv_tts..."
  Remove-Item -Recurse -Force $VenvTts -ErrorAction SilentlyContinue
  py -3.10 -m venv $VenvTts

  & $PyTts -m pip install --upgrade pip setuptools wheel
  & $PyTts -m pip install "numpy<2"

  # Install TTS (will compile extensions; needs VC++)
  & $PyTts -m pip install TTS
  if ($LASTEXITCODE -ne 0) {
    Err "TTS install failed (likely VC++ tools not fully available yet)."
    return $false
  }

  & $PyTts -c "from TTS.api import TTS; print('XTTS OK')"
  if ($LASTEXITCODE -eq 0) {
    OK "XTTS installed successfully."
    return $true
  } else {
    Err "XTTS import failed."
    return $false
  }
}

function Start-Docker-N8n {
  Step "Starting Docker Desktop..."
  Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -ErrorAction SilentlyContinue | Out-Null
  Start-Sleep -Seconds 10

  Ensure-DockerPath
  Fix-DockerCredHelper

  $dockerExe = Resolve-DockerExe
  if (-not $dockerExe) {
    Err "Docker CLI not found. Restart PowerShell and rerun."
    return
  }

  Step "Checking Docker engine..."
  & $dockerExe version | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Warn "Docker engine not ready yet. Wait until Docker Desktop shows 'Engine running', then rerun."
    return
  }
  OK "Docker engine OK."

  Step "Starting n8n..."
  Set-Location $N8nDir
  & $dockerExe compose up -d
  OK "n8n compose command executed."
}

function Start-Agent {
  Step "Starting Agent Server..."
  $py311 = Join-Path $Root ".venv\Scripts\python.exe"
  if (-not (Test-Path $py311)) {
    Err ".venv Python not found. Run ONE_CLICK_SETUP or MASTER script first."
    return
  }
  Start-Process powershell -ArgumentList "-NoExit", "-Command", "& `"$py311`" -m uvicorn agent_server:APP --host 0.0.0.0 --port 8787 --reload --app-dir `"$ScriptsDir`""
  Start-Sleep -Seconds 2
  Start-Process "http://localhost:5678" | Out-Null
  Start-Process "http://localhost:8787/health" | Out-Null
  OK "Agent Server started."
}

# -------- RUN ALL --------
Step "=== ONE SHOT FIX ALL (XTTS + Docker + Start) ==="

Ensure-Python310
Install-VCBuildTools

$xttsOk = Install-XTTS
if (-not $xttsOk) {
  Warn "XTTS is not ready yet. If Build Tools just installed, restart PowerShell and run this script again."
}

Start-Docker-N8n
Start-Agent

Step "=== DONE ==="
Warn "Next: Place voice refs:"
Warn "  F:\YouTubu_AI\voice\dataset\en\ref.wav"
Warn "  F:\YouTubu_AI\voice\dataset\te\ref.wav"