#!/usr/bin/env python3
"""Scontorna le illustrazioni dei cacciatori per usarle come sagome 3D.

Le immagini figurine del mod TTS hanno lo sfondo pieno (una sfumatura chiara).
Qui lo rendiamo trasparente con un flood fill dai bordi, cosi' che in Godot
la Sprite3D si veda come una sagoma ritagliata e non come un rettangolo.

Va eseguito dopo extract_assets.py e prima di optimize_art.py.
"""
import os
import sys
from collections import deque

from PIL import Image

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
MIN_LUMA = 168          # lo sfondo TTS e' una sfumatura chiara e desaturata
MAX_CHROMA = 42         # differenza massima fra canali per considerarlo grigio
FEATHER_ALPHA = 96      # alpha dei pixel di bordo, per ammorbidire il taglio


def cutout(path: str) -> None:
    img = Image.open(path).convert("RGBA")
    w, h = img.size
    px = img.load()

    def is_background(r, g, b):
        luma = 0.299 * r + 0.587 * g + 0.114 * b
        chroma = max(r, g, b) - min(r, g, b)
        return luma >= MIN_LUMA and chroma <= MAX_CHROMA

    visited = bytearray(w * h)
    queue = deque()
    for x in range(w):
        queue.append((x, 0))
        queue.append((x, h - 1))
    for y in range(h):
        queue.append((0, y))
        queue.append((w - 1, y))

    removed = 0
    while queue:
        x, y = queue.popleft()
        if x < 0 or y < 0 or x >= w or y >= h:
            continue
        i = y * w + x
        if visited[i]:
            continue
        visited[i] = 1
        r, g, b, _a = px[x, y]
        if not is_background(r, g, b):
            continue
        px[x, y] = (r, g, b, 0)
        removed += 1
        queue.append((x + 1, y))
        queue.append((x - 1, y))
        queue.append((x, y + 1))
        queue.append((x, y - 1))

    # Ammorbidisce il bordo: i pixel opachi adiacenti a uno trasparente
    # ricevono un alpha intermedio.
    edge = []
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            if px[x, y][3] == 0:
                continue
            if px[x - 1, y][3] == 0 or px[x + 1, y][3] == 0 \
               or px[x, y - 1][3] == 0 or px[x, y + 1][3] == 0:
                edge.append((x, y))
    for x, y in edge:
        r, g, b, _ = px[x, y]
        px[x, y] = (r, g, b, FEATHER_ALPHA)

    img = img.crop(img.getbbox())
    img.save(path)
    print("  %s: rimossi %d pixel di sfondo -> %dx%d"
          % (os.path.basename(path), removed, img.width, img.height))


def main() -> None:
    targets = sys.argv[1:]
    if not targets:
        models = os.path.join(PROJECT, "art", "models")
        targets = [os.path.join(models, f) for f in sorted(os.listdir(models))
                   if f.endswith("_standee.png")]
    for path in targets:
        cutout(path)


if __name__ == "__main__":
    main()
