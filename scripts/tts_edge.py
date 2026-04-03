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
