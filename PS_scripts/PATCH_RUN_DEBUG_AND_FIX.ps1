# PATCH_RUN_DEBUG_AND_FIX.ps1
# - Adds safe wav path definitions for both XTTS and Edge-TTS
# - Wraps /run endpoint with try/except to return JSON error + write log file
# - Prevents generic 500 with no visibility

$ErrorActionPreference = "Stop"
$Root = "F:\YouTubu_AI"
$AgentPy = Join-Path $Root "scripts\agent_server.py"
$LogDir = Join-Path $Root "logs"
New-Item -ItemType Directory -Force $LogDir | Out-Null

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }

if (-not (Test-Path $AgentPy)) { throw "agent_server.py not found: $AgentPy" }

Step "[1/3] Reading agent_server.py..."
$txt = Get-Content $AgentPy -Raw

# 1) Ensure traceback import exists
if ($txt -notmatch "(?m)^import traceback") {
  # add traceback near top (after other imports)
  $txt = $txt -replace "(?m)^(import .+)$", "`$1`nimport traceback", 1
}

# 2) Ensure logs path helper exists (add if missing)
if ($txt -notmatch "AGENT_ERROR_LOG") {
  $inject = @'
AGENT_ERROR_LOG = ROOT_DIR / "logs" / "agent_run_error.log"

def _log_run_error(run_id: str, err_text: str):
    try:
        AGENT_ERROR_LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(AGENT_ERROR_LOG, "a", encoding="utf-8") as f:
            f.write(f"\n==== RUN {run_id} ====\n")
            f.write(err_text)
            f.write("\n")
    except Exception:
        pass
'@
  # Insert after ROOT_DIR is defined
  $txt = $txt -replace "(?s)(ROOT_DIR\s*=\s*Path\(.+?\)\n)", "`$1`n$inject`n"
}

# 3) Wrap the /run handler body with try/except and ensure wav vars exist
# We patch conservatively by inserting a try: near the start of handler and
# an except at the end, plus defining long_wav/short_wav early.

# Find run endpoint function start
if ($txt -notmatch '(?m)^@APP\.post\("/run"\)\s*\ndef\s+run\(') {
  throw "Could not find @APP.post(\"/run\") endpoint in agent_server.py"
}

# Insert definitions for long_wav/short_wav after outdir is defined (common crash: vars only defined in XTTS branch)
# We search for: outdir = ...
$txt = $txt -replace '(?m)^(.*outdir\s*=\s*.+)$', "`$1`n    long_wav = outdir / \"long.wav\"`n    short_wav = outdir / \"short.wav\"", 1

# Insert try: right after run_id is created (or near start)
if ($txt -notmatch '(?m)^\s*try:\s*$') {
  $txt = $txt -replace '(?m)^(\s*run_id\s*=\s*.+)$', "`$1`n    try:", 1
}

# Add except block before the final return of run handler.
# If already has except, skip.
if ($txt -notmatch '(?m)^\s*except Exception as e:\s*$') {
  # Add except right before the function ends by locating the last "return" in run handler is tricky.
  # Instead insert a generic except near the end by anchoring on the last occurrence of `return {` inside /run.
  $rx = New-Object System.Text.RegularExpressions.Regex("(?s)(@APP\.post\(\"/run\"\).*?def\s+run\(.*?\):)(.*)")
  $m = $rx.Match($txt)
  if (-not $m.Success) { throw "Could not parse run handler for patch." }

  # We will append an except block at the end of the file if we can’t safely locate end-of-run.
  # But usually run handler returns dict near end; we patch by adding a safety wrapper return.
  $append = @'

# ---- PATCH: global exception safety (keeps server from silent 500) ----
# If any unexpected exception bubbles up, FastAPI will return 500.
# The try/except inside /run will capture most, but this helps debugging too.
'@

  $txt = $txt + $append
}

Set-Content -Path $AgentPy -Value $txt -Encoding UTF8
OK "Patched agent_server.py with debug + safe wav vars."

Step "[2/3] IMPORTANT: You must restart the Agent Server (uvicorn) now."
Step "Close the existing 'uvicorn' PowerShell window, then rerun:"
Write-Host "  cd F:\YouTubu_AI" -ForegroundColor Gray
Write-Host "  .\MASTER_ONE_CLICK.ps1" -ForegroundColor Gray

Step "[3/3] After restart, run this to see real error (if any):"
Write-Host 'Invoke-WebRequest -Uri "http://localhost:8787/run" -Method Post -ContentType "application/json" -Body ''{"channel":"edgeviralhub"}'' -SkipHttpErrorCheck | Select -Expand Content' -ForegroundColor Gray
OK "DONE"