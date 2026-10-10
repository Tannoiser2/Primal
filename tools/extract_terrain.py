#!/usr/bin/env python3
"""Estrae le immagini dei segnalini terreno dal mod TTS.

Ogni tipo di terreno e' un `Custom_Model_Infinite_Bag` il cui mesh non e' nella
cache locale, ma il segnalino vero e' l'oggetto contenuto: un `Custom_Token` con
la sua immagine.
"""
import json, os, re, sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(PROJECT, "art", "terrain")

TERRAIN = ["Fire", "Rock", "Brush", "Jungle Brush", "Cyricae", "Baethanis",
           "Water", "Sand", "Ice", "Fog", "Swamp", "Plateau", "Wildmaw", "Synaerea"]


def norm(u):
    return re.sub(r"[^A-Za-z0-9]", "", u or "")


def main():
    save = json.load(open(os.path.join(ROOT, "Mods", "Workshop", "3257255055.json")))
    images = os.path.join(ROOT, "Mods", "Images")
    index = {os.path.splitext(f)[0]: os.path.join(images, f) for f in os.listdir(images)}
    os.makedirs(OUT, exist_ok=True)
    found = {}

    def visit(objs):
        for o in objs:
            name = str(o.get("Nickname", ""))
            kids = o.get("ContainedObjects", [])
            if name in TERRAIN and name not in found and kids:
                url = (kids[0].get("CustomImage") or {}).get("ImageURL")
                src = index.get(norm(url))
                if src:
                    img = Image.open(src).convert("RGBA")
                    img.thumbnail((256, 256), Image.LANCZOS)
                    slug = name.lower().replace(" ", "_")
                    img.save(os.path.join(OUT, slug + ".png"))
                    found[name] = slug
            visit(kids)

    visit(save["ObjectStates"])
    print("%d segnalini terreno estratti: %s" % (len(found), ", ".join(sorted(found.values()))))
    missing = sorted(set(TERRAIN) - set(found))
    if missing:
        print("non trovati:", missing)
    return 0


if __name__ == "__main__":
    sys.exit(main())
