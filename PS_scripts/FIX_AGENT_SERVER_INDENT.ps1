# FIX_AGENT_SERVER_INDENT.ps1 (PowerShell-safe)
# Fixes IndentationError in scripts\agent_server.py caused by broken Edge-TTS insertion
# Creates backup and validates compilation.

$ErrorActionPreference = "Stop"

$Root  = "F:\YouTubu_AI"
$Agent = Join-Path $Root "scripts\agent_server.py"
$Py    = Join-Path $Root ".venv\Scripts\python.exe"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Err($m){ Write-Host $m -ForegroundColor Red }

if (-not (Test-Path $Agent)) { throw "Missing: $Agent" }
if (-not (Test-Path $Py))    { throw "Missing: $Py" }

Step "[1/4] Backup agent_server.py..."
$bak = "$Agent.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Copy-Item $Agent $bak -Force
OK "Backup: $bak"

Step "[2/4] Patching broken if-block..."

$txt = Get-Content $Agent -Raw

# Match the exact symptom:
# an "if ...:" line followed immediately by "py_main = ROOT_DIR / ".venv/Scripts/python.exe""
# (meaning the if has NO indented body -> IndentationError)
$pattern = @'
(?ms)^[ \t]*if[^\r\n]*:\s*\r?\n[ \t]*py_main[ \t]*=[ \t]*ROOT_DIR[ \t]*/[ \t]*"\.venv/Scripts/python\.exe"[^\r\n]*\r?$
'@

$rx = [regex]::new($pattern)

if (-not $rx.IsMatch($txt)) {
  Err "Could not find the exact broken 'if ...:' -> 'py_main=...' pattern."
  Err "Open: $Agent and paste lines 105–130 here, I will patch precisely."
  exit 1
}

$replacement = @'
    # ---- TTS (XTTS preferred, Edge-TTS fallback) ----
    ensure_ffmpeg()

    py_xtts = ROOT_DIR / ".venv_tts/Scripts/python.exe"
    xtts_script = ROOT_DIR / "scripts/tts_xtts.py"
    py_main = ROOT_DIR / ".venv/Scripts/python.exe"
    edge_script = ROOT_DIR / "scripts/tts_edge.py"

    long_wav = outdir / "long.wav"
    short_wav = outdir / "short.wav"

    def mp3_to_wav(mp3_path: Path, wav_path: Path):
        subprocess.run(["ffmpeg", "-y", "-i", str(mp3_path), str(wav_path)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # If XTTS exists AND voice ref exists, use clone. Otherwise use Edge-TTS.
    if py_xtts.exists() and xtts_script.exists() and ref.exists():
        subprocess.run([str(py_xtts), str(xtts_script),
                        "--text_file", str(script_long),
                        "--ref_wav", str(ref),
                        "--out_wav", str(long_wav),
                        "--lang", lang], check=True)
        subprocess.run([str(py_xtts), str(xtts_script),
                        "--text_file", str(script_short),
                        "--ref_wav", str(ref),
                        "--out_wav", str(short_wav),
                        "--lang", lang], check=True)
    else:
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

        mp3_to_wav(mp3_long, long_wav)
        mp3_to_wav(mp3_short, short_wav)
'@

$txt2 = $rx.Replace($txt, $replacement, 1)

Set-Content -Path $Agent -Value $txt2 -Encoding UTF8
OK "Patched: $Agent"

Step "[3/4] Validate Python syntax..."
& $Py -m py_compile $Agent
OK "Syntax OK."

Step "[4/4] Start uvicorn (run this next):"
Write-Host "cd F:\YouTubu_AI" -ForegroundColor Gray
Write-Host '& ".\.venv\Scripts\python.exe" -m uvicorn agent_server:APP --host 127.0.0.1 --port 8787 --reload --app-dir ".\scripts"' -ForegroundColor Gray
OK "Then test: http://localhost:8787/health"