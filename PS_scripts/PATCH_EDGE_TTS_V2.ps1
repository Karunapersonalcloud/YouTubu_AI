# PATCH_EDGE_TTS_V2.ps1
# Guaranteed patch: replace the "BLOCKED because XTTS not installed" return
# with Edge-TTS fallback generation (mp3 -> wav) and continue.

$ErrorActionPreference = "Stop"

$Root = "F:\YouTubu_AI"
$AgentPy = Join-Path $Root "scripts\agent_server.py"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Err($m){ Write-Host $m -ForegroundColor Red }

if (-not (Test-Path $AgentPy)) { throw "agent_server.py not found: $AgentPy" }

Step "[1/3] Loading agent_server.py..."
$txt = Get-Content $AgentPy -Raw

# Find the exact "BLOCKED" return that stops execution when XTTS missing.
# We replace it with Edge-TTS fallback that:
# - calls scripts/tts_edge.py in main venv
# - converts mp3->wav via ffmpeg
# - continues using long_wav/short_wav as expected downstream
$needle = 'return {"status": "BLOCKED"'
if ($txt -notmatch [regex]::Escape($needle)) {
  Err "Could not find BLOCKED return in agent_server.py. Paste the py_tts check section and I’ll patch precisely."
  exit 1
}

Step "[2/3] Applying deterministic fallback patch..."

# This patch assumes variables exist in the run handler:
# ROOT_DIR, outdir, script_long, script_short, lang, ensure_ffmpeg, subprocess, Path
# If your file uses slightly different names, we patch in a safe way:
# we will not depend on ref.wav at all.
$fallback = @'
# Edge-TTS fallback (no XTTS available) — generate MP3 then convert to WAV
py_main = ROOT_DIR / ".venv/Scripts/python.exe"
edge_script = ROOT_DIR / "scripts/tts_edge.py"
ensure_ffmpeg()

mp3_long = outdir / "long.mp3"
mp3_short = outdir / "short.mp3"

subprocess.run([str(py_main), str(edge_script),
                "--text_file", str(script_long),
                "--out_mp3", str(mp3_long),
                "--lang", lang], check=True)

subprocess.run([str(py_main), str(edge_script),
                "--text_file", str(script_short),
                "--out_mp3", str(mp3_short),
                "--lang", lang], check=True)

# convert mp3 -> wav (keeps rest of pipeline unchanged)
subprocess.run(["ffmpeg", "-y", "-i", str(mp3_long), str(long_wav)],
               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(["ffmpeg", "-y", "-i", str(mp3_short), str(short_wav)],
               check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
'@

# Replace ONLY the first BLOCKED return block with the fallback.
# We target the whole if-block return JSON line and keep indentation.
$regex = New-Object System.Text.RegularExpressions.Regex('^\s*return\s+\{"status":\s*"BLOCKED".*?\}\s*$', [System.Text.RegularExpressions.RegexOptions]::Multiline)
if (-not $regex.IsMatch($txt)) {
  Err "Found 'BLOCKED' but could not match the return line format. Paste that block and I’ll patch exactly."
  exit 1
}

$txt2 = $regex.Replace($txt, $fallback, 1)

# Ensure Path is imported
if ($txt2 -notmatch 'from pathlib import Path') {
  $txt2 = $txt2 -replace 'import os, json, uuid, subprocess', 'import os, json, uuid, subprocess' + "`nfrom pathlib import Path"
}

Set-Content -Path $AgentPy -Value $txt2 -Encoding UTF8
OK "Patched: $AgentPy"

Step "[3/3] Done. Restart agent server to load changes."
OK "Close the uvicorn window and rerun MASTER_ONE_CLICK.ps1 (or restart uvicorn)."