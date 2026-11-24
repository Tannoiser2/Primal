#!/usr/bin/env python3
"""Controlla che ogni carattere mostrato dall'interfaccia esista nei font del gioco.

Un carattere che il font non ha compare come un quadratino: e' successo con le
frecce delle intestazioni pieghevoli. Qui si raccolgono tutti i testi tra
virgolette degli script e tutti i testi dei dati (nomi e traduzioni) e si
verifica che ogni carattere esista sia nel font dei testi (Barlow Semi
Condensed) sia, per i titoli, in Teko.

    python3 tools/controlla_glifi.py

Esce con codice 1 se manca qualcosa, cosi' l'azione di pubblicazione si ferma.
"""

import json
import pathlib
import re
import sys

from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
BODY = ["BarlowSemiCondensed-Medium.ttf", "BarlowSemiCondensed-Bold.ttf"]
TITLE = "Teko.ttf"

STRING = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
# Caratteri che non arrivano mai a schermo: escape e segnaposto del formato.
IGNORE = set("\n\t\r")


def cmap(name):
    return set(TTFont(ROOT / "fonts" / name).getBestCmap().keys())


def strings_from_scripts():
    found = {}
    for path in sorted((ROOT / "scripts").rglob("*.gd")):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            # i commenti in coda alla riga non vanno a schermo
            code = line.split(" #")[0] if '"' not in line.split(" #")[-1] else line
            for text in STRING.findall(code):
                for ch in text:
                    found.setdefault(ch, f"{path.relative_to(ROOT)}:{n}")
    return found


def strings_from_data():
    found = {}
    translated = json.loads((ROOT / "data" / "equipment_it.json").read_text(encoding="utf-8"))
    translated = translated.get("texts", {})

    def walk(node, where):
        if isinstance(node, dict):
            for k, v in node.items():
                if k.startswith("_"):
                    continue
                # Il testo inglese non va a schermo quando c'e' la traduzione.
                if k == "text" and ("it" in node or v in translated):
                    continue
                walk(v, where)
        elif isinstance(node, list):
            for v in node:
                walk(v, where)
        elif isinstance(node, str) and not node.startswith("res://"):
            for ch in node:
                found.setdefault(ch, where)

    for path in sorted((ROOT / "data").glob("*.json")):
        if path.name == "tts_manifest.json":
            continue
        walk(json.loads(path.read_text(encoding="utf-8")), str(path.relative_to(ROOT)))
    return found


def main():
    body = set.intersection(*(cmap(n) for n in BODY))
    title = cmap(TITLE)
    used = strings_from_data()
    used.update(strings_from_scripts())
    missing_body = {ch: w for ch, w in used.items() if ch not in IGNORE and ord(ch) not in body}
    # I titoli (Teko) mostrano nomi e intestazioni: lettere, cifre e punteggiatura.
    missing_title = {ch: w for ch, w in used.items()
                     if ch not in IGNORE and ch.isalnum() and ord(ch) not in title}
    ok = True
    for label, missing in (("Barlow", missing_body), ("Teko", missing_title)):
        for ch, where in sorted(missing.items()):
            ok = False
            print(f"manca in {label}: {ch!r} (U+{ord(ch):04X}) — primo uso in {where}")
    if ok:
        print(f"tutti i {len(used)} caratteri usati esistono nei font")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
