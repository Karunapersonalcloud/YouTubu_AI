import argparse
from pathlib import Path
from TTS.api import TTS

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--text_file", required=True)
    ap.add_argument("--ref_wav", required=True)
    ap.add_argument("--out_wav", required=True)
    ap.add_argument("--lang", required=True, choices=["en", "te"])
    args = ap.parse_args()

    text = Path(args.text_file).read_text(encoding="utf-8").strip()
    ref = Path(args.ref_wav)
    out = Path(args.out_wav)
    out.parent.mkdir(parents=True, exist_ok=True)

    tts = TTS("tts_models/multilingual/multi-dataset/xtts_v2", progress_bar=False)
    tts.tts_to_file(text=text, speaker_wav=str(ref), language=args.lang, file_path=str(out))

if __name__ == "__main__":
    main()
