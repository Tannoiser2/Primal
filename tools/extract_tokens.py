#!/usr/bin/env python3
"""Estrae le immagini dei segnalini dal mod TTS.

Nel save i segnalini stanno in `Infinite_Bag` il cui nickname finisce con
"Tokens": basta prendere l'immagine dell'oggetto contenuto.
"""
import json, os, re, sys
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
IMAGES = os.path.join(ROOT, "Mods", "Images")
OUT = os.path.join(PROJECT, "art", "tokens")

WANTED = {
    "Struggle Tokens": "struggle", "Aggro": "aggro", "Threatened Tokens": "threatened",
    "Stamina Tokens": "stamina", "Vulnerable Tokens": "vulnerable",
    "Stunned Tokens": "stun", "Blinded Tokens": "blind", "Burning Tokens": "burning",
    "KO'D Tokens": "ko", "Depleted Tokens": "depleted", "Counter Tokens": "counter",
    "1/5 Damage Tokens": "damage", "Dust Tokens": "dust",
}

def norm(u): return re.sub(r"[^A-Za-z0-9]", "", u or "")

def main():
    save = json.load(open(os.path.join(ROOT, "Mods", "Workshop", "3257255055.json")))
    index = {os.path.splitext(f)[0]: os.path.join(IMAGES, f) for f in os.listdir(IMAGES)}
    os.makedirs(OUT, exist_ok=True)
    found = {}

    def visit(objs):
        for o in objs:
            nick = str(o.get("Nickname", ""))
            slug = WANTED.get(nick)
            kids = o.get("ContainedObjects", [])
            if slug and slug not in found and kids:
                img_url = (kids[0].get("CustomImage") or {}).get("ImageURL")
                src = index.get(norm(img_url))
                if src:
                    img = Image.open(src).convert("RGBA")
                    img.thumbnail((256, 256), Image.LANCZOS)
                    img.save(os.path.join(OUT, slug + ".png"))
                    found[slug] = True
            visit(kids)

    visit(save["ObjectStates"])
    missing = sorted(set(WANTED.values()) - set(found))
    print("%d segnalini estratti" % len(found))
    if missing:
        print("non trovati:", missing)
    return 0

if __name__ == "__main__":
    sys.exit(main())
