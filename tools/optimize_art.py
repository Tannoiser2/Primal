#!/usr/bin/env python3
"""Riduce il peso degli asset estratti.

- ridimensiona le immagini troppo grandi (le carte TTS arrivano a 5000x5000);
- converte in JPEG le immagini senza trasparenza utile (le carte),
  lasciando in PNG quelle con canale alpha (standee, token).

Idempotente: puo' essere rieseguito dopo extract_assets.py.
"""
import glob
import os

from PIL import Image

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

MAX_SIDE = {"card": 1100, "board": 2048, "texture": 2048}
ALPHA_THRESHOLD = 250   # sotto questo valore consideriamo l'alpha significativo


def cap_for(path: str) -> int:
    name = os.path.basename(path)
    if "board" in name or "battle_map" in name:
        return MAX_SIDE["board"]
    if "diffuse" in name or "standee" in name:
        return MAX_SIDE["texture"]
    return MAX_SIDE["card"]


def has_alpha(img: Image.Image) -> bool:
    if img.mode not in ("RGBA", "LA", "PA"):
        return False
    alpha = img.getchannel("A")
    return alpha.getextrema()[0] < ALPHA_THRESHOLD


def main() -> None:
    before = after = 0
    converted = 0
    for path in sorted(glob.glob(os.path.join(PROJECT, "art", "**", "*.png"), recursive=True)):
        before += os.path.getsize(path)
        img = Image.open(path)
        cap = cap_for(path)
        if max(img.size) > cap:
            img.thumbnail((cap, cap), Image.LANCZOS)

        if has_alpha(img):
            img.save(path, optimize=True)
            after += os.path.getsize(path)
            continue

        jpg = path[:-4] + ".jpg"
        img.convert("RGB").save(jpg, quality=88, optimize=True)
        if os.path.getsize(jpg) < os.path.getsize(path):
            os.remove(path)
            converted += 1
            after += os.path.getsize(jpg)
        else:
            os.remove(jpg)
            img.save(path, optimize=True)
            after += os.path.getsize(path)

    print("art: %.0f MB -> %.0f MB (%d immagini convertite in JPEG)"
          % (before / 1e6, after / 1e6, converted))


if __name__ == "__main__":
    main()
