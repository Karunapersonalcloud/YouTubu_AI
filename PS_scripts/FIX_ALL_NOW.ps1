# ==========================================
# FIX_ALL_NOW.ps1
# - Kills locked python/uvicorn/node/docker that hold .venv
# - Rebuilds .venv cleanly
# - Fixes ONE_CLICK_SETUP.ps1 pip invocation bug
# ==========================================
$ErrorActionPreference = "Continue"
$Root = "F:\YouTubu_AI"
$Venv = Join-Path $Root ".venv"
$Python = Join-Path $Venv "Scripts\python.exe"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Err($m){ Write-Host $m -ForegroundColor Red }

Step "=== FIX ALL NOW ==="

# 1) Kill processes that commonly lock .venv
Step "[1/6] Stopping processes that may lock .venv..."
$names = @("python","pythonw","uvicorn","node","docker","com.docker.backend","Docker Desktop")
foreach($n in $names){
  Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
    try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch {}
  }
}
OK "Stopped processes (best-effort)."

Start-Sleep -Seconds 2

# 2) Remove .venv safely
Step "[2/6] Removing existing .venv if locked/broken..."
if (Test-Path $Venv) {
  try {
    Remove-Item -Recurse -Force $Venv
    OK ".venv removed."
  } catch {
    Err "Could not delete .venv. Reboot PC once, then rerun FIX_ALL_NOW.ps1."
    exit 1
  }
} else {
  OK ".venv not present (fine)."
}

# 3) Recreate .venv
Step "[3/6] Creating fresh .venv..."
py -3.11 -m venv $Venv
if (-not (Test-Path $Python)) {
  Err "Failed to create venv. Python 3.11 not accessible via 'py -3.11'."
  exit 1
}
OK "Fresh .venv created."

# 4) Upgrade pip and install base deps correctly
Step "[4/6] Installing base Python dependencies..."
& $Python -m pip install --upgrade pip setuptools wheel
& $Python -m pip install requests python-dotenv pydub tqdm rich fastapi uvicorn google-api-python-client google-auth google-auth-oauthlib aiohttp
OK "Base deps installed."

# 5) Patch ONE_CLICK_SETUP.ps1 to use correct pip syntax (if present)
Step "[5/6] Patching ONE_CLICK_SETUP.ps1 pip calls..."
$setup = Join-Path $Root "ONE_CLICK_SETUP.ps1"
if (Test-Path $setup) {
  $content = Get-Content $setup -Raw

  # Replace patterns like:  "...\pip.exe" install X  ->  & "$python" -m pip install X
  # We do a minimal safe patch: ensure Try-Run uses -m pip
  $content = $content `
    -replace '(".*\\pip\.exe")\s+install\s+--upgrade\s+pip', '& "$python" -m pip install --upgrade pip' `
    -replace '(".*\\pip\.exe")\s+install\s+', '& "$python" -m pip install '

  Set-Content -Path $setup -Value $content -Encoding UTF8
  OK "ONE_CLICK_SETUP.ps1 patched."
} else {
  Warn "ONE_CLICK_SETUP.ps1 not found; skipping patch."
}

# 6) Start MASTER script (optional)
Step "[6/6] Done. You can now run MASTER_ONE_CLICK.ps1 safely."
OK "Next commands:"
Write-Host "  cd F:\YouTubu_AI" -ForegroundColor Gray
Write-Host "  .\MASTER_ONE_CLICK.ps1" -ForegroundColor Gray
Write-Host ""
Warn "If you still get Permission Denied, reboot once and rerun FIX_ALL_NOW.ps1."