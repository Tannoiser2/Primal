#!/usr/bin/env python3
"""Costruisce i dati per deck-building e forge.

Unisce due sorgenti che non si conoscono fra loro:
  - primal_database.xlsm  -> nomi, statistiche e testi delle carte
  - il mod TTS            -> le immagini, identificate solo da un CardID

Per le carte potenziamento l'abbinamento e' automatico: ogni track dell'albero
delle abilita' contiene due mazzetti da 2 carte (tier 1 e tier 2) e il database
dice quali sottotipi (attack/maneuver/dodge/parry) stanno in ciascun tier.
Il sottotipo si legge dall'immagine campionando il colore della fascia in alto,
quindi si incrociano le due cose. Dove la coppia ha due carte dello stesso colore
l'abbinamento resta ambiguo e va risolto a mano: lo script lo segnala.

Uscita:
  ../art/<hunter>/upgrade_*.png  ../data/loadouts.json
"""
import csv
import itertools
import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from collections import defaultdict

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SAVE = os.path.join(ROOT, "Mods", "Workshop", "3257255055.json")
IMAGES = os.path.join(ROOT, "Mods", "Images")
XLSM = os.path.join(ROOT, "primal_database.xlsm")

# Nel database i nomi sono scritti male: "Daeron" per Dareon e "Thoerg" per
# Thoreg. Le carte, che sono la fonte buona, dicono Dareon e Thoreg.
HUNTERS = {"dareon": "Daeron", "mirah": "Mirah", "thoreg": "Thoerg",
           "karah": "Karah", "ljonar": "Ljonar", "heleren": "Heleren"}

# Colore medio della fascia superiore della carta -> tipo (Regolamento p.103).
# Valori misurati sulle carte starter, di cui il tipo e' noto.
CARD_COLORS = {
    "attack": (206, 87, 84),
    "maneuver": (95, 118, 181),
    "dodge": (158, 184, 116),
    "parry": (230, 191, 88),
}
COLOR_BAND = (0.44, 0.02, 0.56, 0.08)   # x0, y0, x1, y1 in frazioni della carta

# Abbinamenti che il colore non riesce a distinguere (due carte dello stesso
# tipo nello stesso tier), risolti leggendo le carte una per una.
MANUAL = {
    ("dareon", "B1", 214300): "Wrath of Blood",
    ("dareon", "B1", 213000): "Blind Rage",
    ("dareon", "C2", 214500): "Sentinel",
    ("dareon", "C2", 213300): "Exhausting Defense",
    # Thoreg B2: le due carte del tier sono entrambe maneuver, quindi il colore
    # non basta. Letto dall'immagine: la 216300 e' Skull Crasher.
    ("thoreg", "B2", 216300): "Skull Crasher",
    # Karah: due tier dove le due carte hanno lo stesso colore. Lette dalle
    # immagini: la 205800 e' Endless Strike, la 205900 e' Evasive Dance.
    ("karah", "B1", 205800): "Endless Strike",
    ("karah", "D1", 205900): "Evasive Dance",
    # Ljonar A2: le due carte del tier sono entrambe attack. Letta l'immagine:
    # la 213900 e' Retribution.
    ("ljonar", "A2", 213900): "Retribution",
}

# Errori del database fan-made, verificati sulle immagini delle carte originali.
# Su queste due i nomi sono scambiati: costi e testi sono giusti, e' l'etichetta
# a stare sulla riga sbagliata.
# Chiave: (cacciatore, track, frammento distintivo del testo) -> nome corretto.
DB_NAME_FIXES = {
    ("Daeron", "C2", "When you or another play in your sector"): "Sentinel",
    ("Daeron", "C2", "Remove 1 struggle for each"): "Exhausting Defense",
}

_sheets = {}


def norm(url):
    return re.sub(r"[^A-Za-z0-9]", "", url or "")


def sheet(url):
    key = norm(url)
    if key not in _sheets:
        path = None
        for f in os.listdir(IMAGES):
            if os.path.splitext(f)[0] == key:
                path = os.path.join(IMAGES, f)
                break
        _sheets[key] = Image.open(path).convert("RGB") if path else None
    return _sheets[key]


def card_image(obj):
    """Ritaglia l'immagine di una carta dal suo sprite sheet."""
    cd = obj.get("CustomDeck") or {}
    cid = obj.get("CardID")
    spec = cd.get(str(cid // 100)) if cid is not None else None
    if spec is None:
        return None
    img = sheet(spec["FaceURL"])
    if img is None:
        return None
    nw, nh = spec["NumWidth"], spec["NumHeight"]
    if nw * nh == 1:
        return img
    w, h = img.width // nw, img.height // nh
    slot = cid % 100
    col, row = slot % nw, slot // nw
    return img.crop((col * w, row * h, (col + 1) * w, (row + 1) * h))


def detect_type(img):
    """Legge il tipo della carta dal colore della fascia in alto."""
    w, h = img.size
    band = img.crop((int(w * COLOR_BAND[0]), int(h * COLOR_BAND[1]),
                     int(w * COLOR_BAND[2]), int(h * COLOR_BAND[3])))
    px = list(band.get_flattened_data())
    avg = tuple(sum(c[i] for c in px) // len(px) for i in range(3))
    best, best_dist = None, 1e9
    for name, ref in CARD_COLORS.items():
        dist = sum((avg[i] - ref[i]) ** 2 for i in range(3))
        if dist < best_dist:
            best, best_dist = name, dist
    return best, avg


# --------------------------------------------------------------- database

def read_database():
    ns = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    z = zipfile.ZipFile(XLSM)
    strings = []
    for si in ET.fromstring(z.read("xl/sharedStrings.xml")):
        strings.append("".join(t.text or "" for t in si.iter(ns + "t")))

    def colnum(ref):
        n = 0
        for ch in re.match(r"([A-Z]+)", ref).group(1):
            n = n * 26 + ord(ch) - 64
        return n - 1

    rows = []
    for r in ET.fromstring(z.read("xl/worksheets/sheet1.xml")).iter(ns + "row"):
        cells = {}
        for c in r.iter(ns + "c"):
            v = c.find(ns + "v")
            if v is None:
                continue
            cells[colnum(c.get("r"))] = strings[int(v.text)] if c.get("t") == "s" else (v.text or "")
        if cells:
            rows.append([cells.get(i, "") for i in range(max(cells) + 1)])

    header = [h.split("\n")[0] for h in rows[1]]
    width = len(header)
    return [dict(zip(header, row + [""] * (width - len(row)))) for row in rows[2:]]


def as_int(value, default=0):
    """Alcune carte hanno costo variabile ('X'): lo trattiamo come 0 + testo."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def fixed_name(row):
    for (hunter, track, fragment), name in DB_NAME_FIXES.items():
        if row["Hunter"] == hunter and row["Card ID"] == track and fragment in row["Card text"]:
            return name
    return row["Card name"]


def action_card(row):
    return {
        "name": fixed_name(row),
        "type": row["Subtype"].lower(),
        "cost": as_int(row["Stamina cost"]),
        "variable_cost": row["Stamina cost"] == "X",
        "stamina": as_int(row["Stamina icons"], 1),
        "aggro": row["Aggro icon"] not in ("", "0"),
        "traits": [t.strip().lower() for t in (row["Card trait"] or "").split(",") if t.strip()],
        "text": row["Card text"].strip(),
        "track": row["Card ID"],
    }


def equipment(row):
    item = {"name": row["Card name"], "level": as_int(row["Level"], 1),
            "text": row["Card text"].strip(), "element": row["Element"]}
    if row["Card type"] == "Weapon":
        item["damage"] = as_int(row["Damage"])
        item["composition"] = parse_composition(row["Deck composition"])
    if row["Card type"] in ("Armor", "Helm"):
        # Il database fan-made ha qualche casella salute vuota (es. Totemic Plate
        # livello 2): lo segnaliamo invece di far passare uno 0 per un valore vero.
        if row["Health"] == "":
            item["health_missing"] = True
        else:
            item["health"] = as_int(row["Health"])
    elif row["Health"]:
        item["health"] = as_int(row["Health"])
    return item


def parse_composition(text):
    """'6A 6M 6P 6D' -> {'attack': 6, 'maneuver': 6, 'parry': 6, 'dodge': 6}"""
    letters = {"A": "attack", "M": "maneuver", "P": "parry", "D": "dodge"}
    out = {v: 0 for v in letters.values()}
    for count, letter in re.findall(r"(\d+)\s*([AMPD])", text or ""):
        out[letters[letter]] = int(count)
    return out


# ------------------------------------------------------------------- TTS

def find_bag(objs, nickname):
    for o in objs:
        if o.get("Nickname") == nickname and o.get("ContainedObjects"):
            return o
        r = find_bag(o.get("ContainedObjects", []), nickname)
        if r:
            return r
    return None


def upgrade_tracks(save, hunter):
    """{'A': [ [card, card], [card, card] ], ...} — i due tier di ogni track."""
    bag = find_bag(save["ObjectStates"], "%s Deck Upgrades" % hunter.capitalize())
    out = {}
    if bag is None:
        return out
    for track in bag["ContainedObjects"]:
        letter = str(track.get("Nickname", "")).replace("Track ", "").strip()
        tiers = [c["ContainedObjects"] for c in track["ContainedObjects"]
                 if c.get("Name") == "Deck"]
        if letter and len(tiers) == 2:
            out[letter] = tiers
    return out


def match_track(hunter, letter, tiers, wanted, warnings):
    """Abbina le 2+2 carte TTS del track alle 4 righe del database."""
    typed = []
    for tier in tiers:
        entry = []
        for card in tier:
            img = card_image(card)
            kind, avg = detect_type(img) if img else (None, None)
            entry.append({"card": card, "image": img, "type": kind, "rgb": avg})
        typed.append(entry)

    # Quale mazzetto e' il tier 1? Quello i cui colori combaciano con i sottotipi
    # che il database elenca per il tier 1.
    def multiset(items):
        return sorted(x["type"] for x in items)

    want1 = sorted(c["type"] for c in wanted[letter + "1"])
    want2 = sorted(c["type"] for c in wanted[letter + "2"])
    if multiset(typed[0]) == want1 and multiset(typed[1]) == want2:
        order = [0, 1]
    elif multiset(typed[1]) == want1 and multiset(typed[0]) == want2:
        order = [1, 0]
    else:
        warnings.append("%s track %s: colori %s / %s non combaciano con %s / %s"
                        % (hunter, letter, multiset(typed[0]), multiset(typed[1]), want1, want2))
        order = [0, 1]

    matched = []
    for tier_index, slot in enumerate(order):
        code = "%s%d" % (letter, tier_index + 1)
        pool = list(wanted[code])
        for entry in typed[slot]:
            cid = entry["card"]["CardID"]
            manual = MANUAL.get((hunter, code, cid))
            row = None
            if manual:
                row = next((c for c in pool if c["name"] == manual), None)
            if row is None:
                same = [c for c in pool if c["type"] == entry["type"]]
                if len(same) == 1:
                    row = same[0]
                elif same:
                    warnings.append("%s %s carta %d: ambigua fra %s"
                                    % (hunter, code, cid, [c["name"] for c in same]))
                    row = same[0]
            if row is None:
                warnings.append("%s %s carta %d: nessuna corrispondenza (%s)"
                                % (hunter, code, cid, entry["type"]))
                continue
            pool.remove(row)
            card = dict(row)
            card["id"] = cid
            card["image"] = entry["image"]
            matched.append(card)
    return matched


# ------------------------------------------------------------------ main

def main():
    save = json.load(open(SAVE))
    db = read_database()
    warnings = []
    out = {"_note": "Generato da tools/build_loadouts.py: non modificare a mano.",
           "upgrades_per_level": {"1": 2, "2": 4, "3": 6},
           "hunters": {}, "shared": {}}

    # equipaggiamento condiviso
    for kind, key in (("Armor", "armor"), ("Helm", "helm"), ("Potion", "potion")):
        items = [equipment(r) for r in db
                 if r["Card"] == "Equipment" and r["Card type"] == kind]
        # nomi ripetuti a livelli diversi: teniamo tutte le combinazioni
        out["shared"][key] = items

    for slug, db_name in HUNTERS.items():
        art_dir = os.path.join(PROJECT, "art", slug)
        os.makedirs(art_dir, exist_ok=True)
        hunter_out = {"weapons": [], "masteries": [], "upgrades": []}

        hunter_out["weapons"] = [equipment(r) for r in db
                                 if r["Card"] == "Equipment" and r["Card type"] == "Weapon"
                                 and r["Hunter"] == db_name]
        for r in db:
            if r["Hunter"] == db_name and r["Card type"] == "Mastery":
                hunter_out["masteries"].append({
                    "name": r["Card name"], "track": r["Card ID"],
                    "text": r["Card text"].strip()})

        wanted = defaultdict(list)
        for r in db:
            if (r["Hunter"] == db_name and r["Card"] == "Hunter"
                    and r["Card ID"] not in ("S", "") and r["Card type"] != "Mastery"):
                wanted[r["Card ID"]].append(action_card(r))

        for letter, tiers in sorted(upgrade_tracks(save, slug).items()):
            if letter + "1" not in wanted:
                continue
            for card in match_track(slug, letter, tiers, wanted, warnings):
                img = card.pop("image", None)
                if img is not None:
                    # Come le altre carte: JPEG ridimensionato, non serve alpha.
                    rel = "art/%s/upgrade_%d.jpg" % (slug, card["id"])
                    img.thumbnail((1100, 1100), Image.LANCZOS)
                    img.convert("RGB").save(os.path.join(PROJECT, rel),
                                            quality=88, optimize=True)
                    card["art"] = "res://" + rel
                hunter_out["upgrades"].append(card)

        hunter_out["upgrades"].sort(key=lambda c: (c["track"], c["name"]))
        out["hunters"][slug] = hunter_out
        print("%s: %d weapon, %d mastery, %d potenziamenti"
              % (slug, len(hunter_out["weapons"]), len(hunter_out["masteries"]),
                 len(hunter_out["upgrades"])))

    with open(os.path.join(PROJECT, "data", "loadouts.json"), "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    if warnings:
        print("\nAvvisi:")
        for w in warnings:
            print("  !", w)
        return 1
    print("\nAbbinamento immagini/statistiche completo, nessuna ambiguita'.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
