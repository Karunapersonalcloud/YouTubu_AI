# PATCH_EDGE_TTS.ps1
# - Installs edge-tts in main venv
# - Writes scripts\tts_edge.py
# - Patches scripts\agent_server.py to use Edge-TTS fallback when XTTS not available
# - Verifies edge-tts import

$ErrorActionPreference = "Stop"

$Root = "F:\YouTubu_AI"
$VenvPy = Join-Path $Root ".venv\Scripts\python.exe"
$ScriptsDir = Join-Path $Root "scripts"
$EdgePy = Join-Path $ScriptsDir "tts_edge.py"
$AgentPy = Join-Path $ScriptsDir "agent_server.py"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }
function Warn($m){ Write-Host $m -ForegroundColor Yellow }

if (-not (Test-Path $VenvPy)) { throw "Main venv python not found: $VenvPy" }
if (-not (Test-Path $ScriptsDir)) { New-Item -ItemType Directory -Force $ScriptsDir | Out-Null }

Step "[1/4] Installing edge-tts into .venv..."
& $VenvPy -m pip install --upgrade edge-tts | Out-Null
& $VenvPy -c "import edge_tts; print('edge-tts OK')"
OK "edge-tts installed."

Step "[2/4] Writing scripts\tts_edge.py..."
@'
import argparse
import asyncio
from pathlib import Path
import edge_tts

VOICE_EN = "en-IN-NeerjaNeural"
VOICE_TE = "te-IN-ShrutiNeural"

async def _run(text: str, out_mp3: Path, voice: str):
    out_mp3.parent.mkdir(parents=True, exist_ok=True)
    communicate = edge_tts.Communicate(text=text, voice=voice)
    await communicate.save(str(out_mp3))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text_file", required=True)
    ap.add_argument("--out_mp3", required=True)
    ap.add_argument("--lang", required=True, choices=["en", "te"])
    args = ap.parse_args()

    text = Path(args.text_file).read_text(encoding="utf-8").strip()
    out_mp3 = Path(args.out_mp3)
    voice = VOICE_EN if args.lang == "en" else VOICE_TE

    asyncio.run(_run(text, out_mp3, voice))
    print(str(out_mp3))

if __name__ == "__main__":
    main()
'@ | Out-File -Encoding UTF8 $EdgePy
OK "Written: $EdgePy"

if (-not (Test-Path $AgentPy)) { throw "agent_server.py not found: $AgentPy" }

Step "[3/4] Patching scripts\agent_server.py (Edge-TTS fallback)..."

$agent = Get-Content $AgentPy -Raw

# We patch by replacing the XTTS-blocking section:
# current code has:
#   py_tts = ROOT_DIR / ".venv_tts/Scripts/python.exe"
#   tts = ROOT_DIR / "scripts/tts_xtts.py"
#   if not py_tts.exists(): return BLOCKED ...
# We'll replace that with a safe fallback block.

$pattern = [regex]::Escape('    # Use separate venv for TTS if available') + '.*?make_basic_video'
$rx = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)

if (-not $rx.IsMatch($agent)) {
  Warn "Could not find the exact XTTS section to replace automatically."
  Warn "I will add fallback block near the current py_tts check instead."
} else {
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

    if py_xtts.exists() and xtts_script.exists() and ref.exists():
        # XTTS voice clone
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
        # Edge-TTS fallback (no cloning required)
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

    # Videos
    make_basic_video(outdir / "long.mp4", pkg_long.get("title",""), long_wav, vertical=False)
    make_basic_video(outdir / "short.mp4", pkg_short.get("title",""), short_wav, vertical=True)

    # Thumb placeholder
    ensure_ffmpeg()
    subprocess.run(["ffmpeg", "-y", "-f", "lavfi", "-i", "color=c=gray:s=1280x720:d=1", "-frames:v", "1", str(outdir / "thumb.png")],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
'@

  # Replace from the XTTS comment section up to before "make_basic_video" usage in old code
  $agent = $rx.Replace($agent, $replacement + "`n`n    # (patched) make_basic_video", 1)
}

# Additional safety: ensure Path is imported (it already is in your file, but keep safe)
if ($agent -notmatch 'from pathlib import Path') {
  $agent = $agent -replace 'import os, json, uuid, subprocess', 'import os, json, uuid, subprocess' + "`nfrom pathlib import Path"
}

Set-Content -Path $AgentPy -Value $agent -Encoding UTF8
OK "Patched: $AgentPy"

Step "[4/4] Quick verify: Edge-TTS can generate an mp3..."
$tempTxt = Join-Path $Root "runs\_edge_test.txt"
$tempMp3 = Join-Path $Root "runs\_edge_test.mp3"
New-Item -ItemType Directory -Force (Split-Path $tempTxt) | Out-Null
"Hello Karuna. This is a quick edge tts test." | Out-File -Encoding UTF8 $tempTxt

& $VenvPy $EdgePy --text_file $tempTxt --out_mp3 $tempMp3 --lang en | Out-Null
if (Test-Path $tempMp3) { OK "Edge-TTS test OK: $tempMp3" } else { throw "Edge-TTS test failed (mp3 not created)." }

OK "DONE. Agent will use Edge-TTS automatically when XTTS is not installed."