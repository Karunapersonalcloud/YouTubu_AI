# REBUILD_AGENT_SERVER.ps1
# Replaces scripts\agent_server.py with a clean, minimal, working FastAPI server.

$ErrorActionPreference = "Stop"

$Root = "F:\YouTubu_AI"
$ScriptsDir = Join-Path $Root "scripts"
$Agent = Join-Path $ScriptsDir "agent_server.py"

function Step($m){ Write-Host $m -ForegroundColor Cyan }
function OK($m){ Write-Host $m -ForegroundColor Green }

if (-not (Test-Path $ScriptsDir)) { New-Item -ItemType Directory -Path $ScriptsDir | Out-Null }

Step "[1/3] Backup existing agent_server.py (if any)..."
if (Test-Path $Agent) {
  $bak = "$Agent.bak_rebuild_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
  Copy-Item $Agent $bak -Force
  OK "Backup: $bak"
} else {
  OK "No existing agent_server.py found. Creating new."
}

Step "[2/3] Writing clean scripts\agent_server.py..."
@'
from __future__ import annotations

import os
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

from fastapi import FastAPI, Body
from fastapi.responses import JSONResponse

ROOT = Path(r"F:\YouTubu_AI")
OUT_ROOT = ROOT / "output"
RUNS_ROOT = ROOT / "runs"
SCRIPTS = ROOT / "scripts"

APP = FastAPI(title="Karuna YouTube Agent Server", version="1.0")

def now_tag() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")

def ensure_dirs():
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    RUNS_ROOT.mkdir(parents=True, exist_ok=True)

def which(exe: str) -> Optional[str]:
    return shutil.which(exe)

def ffmpeg_ok() -> bool:
    return which("ffmpeg") is not None

def run_ffmpeg(args):
    # quiet but not silent; capture stderr for diagnostics
    p = subprocess.run(args, capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {p.stderr.strip()[:500]}")
    return p

def edge_tts_ok(py_exe: Path) -> bool:
    try:
        subprocess.run([str(py_exe), "-c", "import edge_tts; print('ok')"], check=True, capture_output=True, text=True)
        return True
    except Exception:
        return False

def synth_edge_tts(py_exe: Path, text: str, lang: str, out_mp3: Path):
    # Uses scripts\tts_edge.py if present, else uses inline edge-tts
    tts_edge = SCRIPTS / "tts_edge.py"
    out_mp3.parent.mkdir(parents=True, exist_ok=True)

    if tts_edge.exists():
        tmp_txt = out_mp3.with_suffix(".txt")
        tmp_txt.write_text(text, encoding="utf-8")
        subprocess.run([str(py_exe), str(tts_edge), "--text_file", str(tmp_txt), "--out_mp3", str(out_mp3), "--lang", lang],
                       check=True)
        return

    # Inline fallback
    code = r"""
import asyncio, sys
from pathlib import Path
import edge_tts

VOICE = {
  "en": "en-IN-NeerjaNeural",
  "te": "te-IN-ShrutiNeural"
}

text = Path(sys.argv[1]).read_text(encoding="utf-8")
out = Path(sys.argv[2])
lang = sys.argv[3]

async def main():
  comm = edge_tts.Communicate(text=text, voice=VOICE.get(lang, VOICE["en"]))
  await comm.save(str(out))

asyncio.run(main())
"""
    tmp_txt = out_mp3.with_suffix(".txt")
    tmp_txt.write_text(text, encoding="utf-8")
    subprocess.run([str(py_exe), "-c", code, str(tmp_txt), str(out_mp3), lang], check=True)

def mp3_to_wav(out_mp3: Path, out_wav: Path):
    if not ffmpeg_ok():
        raise RuntimeError("ffmpeg not found in PATH. Run FIX_FFMPEG_PATH.ps1 then reopen PowerShell.")
    run_ffmpeg(["ffmpeg", "-y", "-i", str(out_mp3), str(out_wav)])

def make_placeholder_video(out_wav: Path, out_mp4: Path, seconds: int = 12):
    # Creates a simple black video + audio (no fonts/images needed)
    if not ffmpeg_ok():
        raise RuntimeError("ffmpeg not found in PATH. Run FIX_FFMPEG_PATH.ps1 then reopen PowerShell.")
    out_mp4.parent.mkdir(parents=True, exist_ok=True)
    run_ffmpeg([
        "ffmpeg", "-y",
        "-f", "lavfi", "-i", f"color=c=black:s=1280x720:d={seconds}",
        "-i", str(out_wav),
        "-shortest",
        "-c:v", "libx264",
        "-c:a", "aac",
        "-pix_fmt", "yuv420p",
        str(out_mp4)
    ])

@APP.get("/health")
def health():
    ensure_dirs()
    return {"ok": True, "root": str(ROOT), "ffmpeg": bool(ffmpeg_ok())}

@APP.post("/run")
def run(payload: Dict[str, Any] = Body(default_factory=dict)):
    """
    Minimal run:
    - generates long+short scripts
    - generates TTS audio (Edge-TTS) into mp3 and wav
    - builds simple mp4 placeholder videos with audio using ffmpeg
    """
    ensure_dirs()

    channel = (payload.get("channel") or "edgeviralhub").strip().lower()
    lang = "te" if channel in ("manatelugodu", "mana_telugodu", "mana-telugodu") else "en"

    # python in main venv
    py_main = ROOT / ".venv" / "Scripts" / "python.exe"
    if not py_main.exists():
        return JSONResponse(status_code=500, content={"error": f"Missing venv python: {py_main}"})

    if not edge_tts_ok(py_main):
        return JSONResponse(status_code=500, content={"error": "edge-tts not installed in .venv. Run PATCH_EDGE_TTS.ps1"})

    tag = now_tag()
    outdir = OUT_ROOT / channel / tag
    outdir.mkdir(parents=True, exist_ok=True)

    # Scripts
    script_long = outdir / "script_long.txt"
    script_short = outdir / "script_short.txt"

    long_text = f"""Title: {channel.upper()} | AI Video (Long)
Hook: 5 seconds shocking opener.
Body: 5 key points with simple examples.
CTA: Like/Subscribe/Comment.
(Generated: {tag})
"""
    short_text = f"""Short Script ({channel.upper()}):
One strong hook + 2 lines value + CTA.
(Generated: {tag})
"""

    script_long.write_text(long_text, encoding="utf-8")
    script_short.write_text(short_text, encoding="utf-8")

    # TTS
    long_mp3 = outdir / "long.mp3"
    short_mp3 = outdir / "short.mp3"
    long_wav = outdir / "long.wav"
    short_wav = outdir / "short.wav"

    try:
        synth_edge_tts(py_main, long_text, lang, long_mp3)
        synth_edge_tts(py_main, short_text, lang, short_mp3)
        mp3_to_wav(long_mp3, long_wav)
        mp3_to_wav(short_mp3, short_wav)
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": f"TTS/ffmpeg step failed: {str(e)}"})

    # Video
    long_mp4 = outdir / "long.mp4"
    short_mp4 = outdir / "short.mp4"
    try:
        make_placeholder_video(long_wav, long_mp4, seconds=40)
        make_placeholder_video(short_wav, short_mp4, seconds=15)
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": f"Video build failed: {str(e)}"})

    return {
        "status": "ok",
        "channel": channel,
        "lang": lang,
        "outdir": str(outdir),
        "files": {
            "script_long": str(script_long),
            "script_short": str(script_short),
            "long_mp4": str(long_mp4),
            "short_mp4": str(short_mp4),
        }
    }
'@ | Set-Content -Path $Agent -Encoding UTF8

OK "Wrote: $Agent"

Step "[3/3] Done. Start server with:"
Write-Host 'cd F:\YouTubu_AI' -ForegroundColor Gray
Write-Host '& ".\.venv\Scripts\python.exe" -m uvicorn agent_server:APP --host 127.0.0.1 --port 8787 --reload --app-dir ".\scripts"' -ForegroundColor Gray