# FIX_UNEXPECTED_INDENT_139.ps1
# Dedents the block starting at: script_long = outdir / "script_long.txt"
# by 4 spaces, until indentation returns to the parent level.

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
$bak = "$Agent.bak_dedent_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $Agent $bak -Force
OK "Backup: $bak"

Step "[2/4] Loading file + locating target line..."
$lines = Get-Content $Agent

$targetPattern = 'script_long\s*=\s*outdir\s*/\s*"script_long\.txt"'
$start = -1
for ($i=0; $i -lt $lines.Count; $i++) {
  if ($lines[$i] -match $targetPattern) { $start = $i; break }
}

if ($start -lt 0) {
  Err "Could not find: script_long = outdir / ""script_long.txt"""
  exit 1
}

# Determine current indentation of the target line
$line = $lines[$start]
$lead = ($line -replace '^([ \t]*).*$', '$1')
$indentLen = $lead.Length

# We expect this to be inside a function at 4 spaces, but it's unexpectedly indented.
# If it's <=4, we won't change anything.
if ($indentLen -le 4) {
  Warn "Target line indent is $indentLen (<=4). Not dedenting. Your error might be elsewhere."
  exit 0
}

# Dedent amount = 4 spaces (most common). If tabs are used, still remove 4 chars from leading whitespace.
$dedent = 4

Warn "Dedenting block from line $($start+1) by $dedent spaces (current indent: $indentLen)..."

# Dedent contiguous block: all following lines that are indented >= current indent
# Stop when indentation drops below current indent (end of block).
for ($j = $start; $j -lt $lines.Count; $j++) {
  $t = $lines[$j]

  # keep empty lines as-is
  if ($t.Trim() -eq "") { continue }

  $leadJ = ($t -replace '^([ \t]*).*$', '$1')
  $lenJ  = $leadJ.Length

  if ($j -eq $start) {
    # always dedent the target line
  } elseif ($lenJ -lt $indentLen) {
    break
  }

  # Dedent only if line has at least 4 leading whitespace chars
  if ($lenJ -ge $dedent) {
    $lines[$j] = $t.Substring($dedent)
  }
}

Set-Content -Path $Agent -Value $lines -Encoding UTF8
OK "Dedent patch applied."

Step "[3/4] Validate syntax..."
& $Py -m py_compile $Agent
if ($LASTEXITCODE -ne 0) {
  Err "py_compile still failing. Show the exact error with: & $Py -m py_compile $Agent"
  exit 1
}
OK "Syntax OK."

Step "[4/4] Start uvicorn (run next):"
Write-Host "cd F:\YouTubu_AI" -ForegroundColor Gray
Write-Host '& ".\.venv\Scripts\python.exe" -m uvicorn agent_server:APP --host 127.0.0.1 --port 8787 --reload --app-dir ".\scripts"' -ForegroundColor Gray
OK "Then test: Invoke-RestMethod http://127.0.0.1:8787/health"