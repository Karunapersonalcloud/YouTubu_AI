# FIX_DANGLING_IF.ps1
# Fixes IndentationError in agent_server.py by removing dangling "if:" before py_main

$ErrorActionPreference = "Stop"

$Root  = "F:\YouTubu_AI"
$Agent = Join-Path $Root "scripts\agent_server.py"
$Py    = Join-Path $Root ".venv\Scripts\python.exe"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }
function Err($m){ Write-Host $m -ForegroundColor Red }

if (-not (Test-Path $Agent)) { throw "Missing: $Agent" }
if (-not (Test-Path $Py))    { throw "Missing: $Py" }

Step "[1/4] Backup agent_server.py..."
$bak = "$Agent.bak_fixif_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $Agent $bak -Force
OK "Backup created: $bak"

Step "[2/4] Scanning for broken if-block..."
$lines = Get-Content $Agent

# Find py_main line (from your traceback)
$idx = -1
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match 'py_main\s*=\s*ROOT_DIR') {
    $idx = $i
    break
  }
}

if ($idx -lt 0) {
  Err "Could not find py_main line. Cannot auto-fix."
  exit 1
}

# Search backwards for dangling 'if ...:'
$ifIdx = -1
for ($j = $idx - 1; $j -ge 0; $j--) {
  $t = $lines[$j].Trim()
  if ($t -eq "") { continue }
  if ($t.StartsWith("#")) { continue }
  if ($t -match '^\s*if\s+.+:\s*$') {
    $ifIdx = $j
    break
  }
  break
}

if ($ifIdx -ge 0) {
  Warn ("Removing dangling if line at index " + $ifIdx)
  $lines = $lines[0..($ifIdx-1)] + $lines[($ifIdx+1)..($lines.Count-1)]
  OK "Dangling if removed successfully."
} else {
  Warn "No dangling if found above py_main. File may already be partially fixed."
}

Step "[3/4] Saving patched file..."
Set-Content -Path $Agent -Value $lines -Encoding UTF8
OK "agent_server.py updated."

Step "[4/4] Checking Python syntax..."
& $Py -m py_compile $Agent
OK "Syntax check passed. IndentationError should be fixed."

Write-Host ""
Write-Host "NEXT COMMAND (run this):" -ForegroundColor Cyan
Write-Host 'cd F:\YouTubu_AI' -ForegroundColor White
Write-Host '& ".\.venv\Scripts\python.exe" -m uvicorn agent_server:APP --host 127.0.0.1 --port 8787 --reload --app-dir ".\scripts"' -ForegroundColor White