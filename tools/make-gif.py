# /// script
# requires-python = ">=3.11"
# dependencies = ["pillow"]
# ///
"""Složí animovaný GIF ze snímků, které hra uložila příkazem game.take_screenshot.

Spuštění: uv run tools/make-gif.py <složka se snímky> <výstup.gif> [--fps 15] [--width 800]
Snímky se řadí podle jména (f001.png, f002.png …). Postup snímání: docs/development.md → Obrázky a GIF ze hry.
"""

import argparse
import sys
from pathlib import Path

from PIL import Image


def load_frames(folder: Path, width: int | None) -> list[Image.Image]:
    """Načte snímky ze složky seřazené podle jména a volitelně je zmenší na šířku `width` (px)."""
    paths = sorted(p for p in folder.iterdir() if p.suffix.lower() in {".png", ".jpg", ".jpeg"})
    frames = []
    for path in paths:
        img = Image.open(path).convert("RGB")
        if width and img.width > width:
            img = img.resize((width, round(img.height * width / img.width)), Image.Resampling.LANCZOS)
        frames.append(img)
    return frames


def save_gif(frames: list[Image.Image], out: Path, fps: float) -> None:
    """Uloží snímky jako nekonečně opakovaný GIF.

    Paleta se počítá z prvního snímku a sdílí ji všechny – jinak barvy mezi snímky blikají.
    """
    palette = frames[0].quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    paletted = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
    paletted[0].save(out, save_all=True, append_images=paletted[1:], duration=round(1000 / fps), loop=0,
                     optimize=True)


def main() -> int:
    """Vstupní bod: argumenty z příkazové řádky, kontrola vstupu, uložení GIFu."""
    parser = argparse.ArgumentParser(description="GIF ze snímků hry (game.take_screenshot).")
    parser.add_argument("folder", type=Path, help="složka se snímky")
    parser.add_argument("out", type=Path, help="výstupní soubor .gif")
    parser.add_argument("--fps", type=float, default=15, help="snímků za sekundu (výchozí 15)")
    parser.add_argument("--width", type=int, default=800, help="největší šířka v px (výchozí 800, 0 = beze změny)")
    args = parser.parse_args()

    if not args.folder.is_dir():
        print(f"Složka neexistuje: {args.folder}", file=sys.stderr)
        return 1
    frames = load_frames(args.folder, args.width or None)
    if not frames:
        print(f"Ve složce nejsou snímky: {args.folder}", file=sys.stderr)
        return 1
    save_gif(frames, args.out, args.fps)
    size_kb = args.out.stat().st_size // 1024
    print(f"{args.out}: {len(frames)} snímků, {frames[0].width}×{frames[0].height}, {size_kb} kB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
