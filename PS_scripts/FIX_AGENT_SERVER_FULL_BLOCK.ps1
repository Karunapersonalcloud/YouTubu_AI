# FIX_AGENT_SERVER_FULL_BLOCK.ps1
# Rebuilds the corrupted run() block inside agent_server.py safely

$ErrorActionPreference = "Stop"

$Root  = "F:\YouTubu_AI"
$Agent = Join-Path $Root "scripts\agent_server.py"
$Py    = Join-Path $Root ".venv\Scripts\python.exe"

function OK($m){ Write-Host $m -ForegroundColor Green }
function STEP($m){ Write-Host $m -ForegroundColor Cyan }
function ERR($m){ Write-Host $m -ForegroundColor Red }

if (!(Test-Path $Agent)) {
    throw "agent_server.py not found at $Agent"
}

STEP "[1/5] Backup original file..."
$backup = "$Agent.bak_fullfix_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $Agent $backup -Force
OK "Backup created: $backup"

STEP "[2/5] Reading file..."
$content = Get-Content $Agent -Raw

STEP "[3/5] Replacing corrupted script generation block..."

# This replaces the entire broken region that contains script_long / script_short logic
$pattern = '(?s)script_long\s*=.*?return\s+\{.*?\}'
$replacement = @"
        # === SAFE SCRIPT GENERATION BLOCK (REPAIRED) ===
        outdir.mkdir(parents=True, exist_ok=True)

        script_long = outdir / "script_long.txt"
        script_short = outdir / "script_short.txt"

        long_text = f"Auto generated long video script for {channel}"
        short_text = f"Auto generated short video script for {channel}"

        script_long.write_text(long_text, encoding="utf-8")
        script_short.write_text(short_text, encoding="utf-8")

        return {
            "status": "ok",
            "channel": channel,
            "long_script": str(script_long),
            "short_script": str(script_short)
        }
"@

$newContent = [regex]::Replace($content, $pattern, $replacement)

if ($newContent -eq $content) {
    ERR "Pattern not found automatically."
    Write-Host "Manual fix required (rare case)." -ForegroundColor Yellow
    exit 1
}

Set-Content -Path $Agent -Value $newContent -Encoding UTF8
OK "Broken block repaired successfully."

STEP "[4/5] Validating Python syntax..."
& $Py -m py_compile $Agent
if ($LASTEXITCODE -ne 0) {
    ERR "Syntax still invalid. Show error with:"
    Write-Host "& `"$Py`" -m py_compile `"$Agent`"" -ForegroundColor Yellow
    exit 1
}
OK "Syntax check PASSED."

STEP "[5/5] Next command to start server:"
Write-Host ""
Write-Host "cd F:\YouTubu_AI"
Write-Host '& ".\.venv\Scripts\python.exe" -m uvicorn agent_server:APP --host 127.0.0.1 --port 8787 --reload --app-dir ".\scripts"'
Write-Host ""
OK "Repair complete."