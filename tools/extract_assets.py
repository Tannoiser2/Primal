#!/usr/bin/env python3
"""Estrae dal mod TTS le immagini carta necessarie al progetto digitale.

Le carte in TTS vivono dentro sprite sheet (CustomDeck.NumWidth x NumHeight):
l'indice della carta nello sheet e' CardID % 100. Qui ritagliamo le singole
carte cosi' che Godot carichi una texture per carta.

Sorgenti:
  ../../Mods/Workshop/3257255055.json  (save TTS)
  ../../Mods/Images/                   (cache immagini, nome = URL senza caratteri non alfanumerici)

Uscita:
  ../art/{vyraxen,dareon,mirah,common}/
  ../data/tts_manifest.json
"""
import itertools
import json
import os
import re
import shutil
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SAVE = os.path.join(ROOT, "Mods", "Workshop", "3257255055.json")
IMAGES = os.path.join(ROOT, "Mods", "Images")
MODELS = os.path.join(ROOT, "Mods", "Models")
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUT = os.path.join(PROJECT, "art")
MODELS_OUT = os.path.join(PROJECT, "models")
DATA = os.path.join(PROJECT, "data")

# Oggetti 3D / standee da portare nella scena di gioco.
SCENE_OBJECTS = {
    ("Custom_Model", "Vyraxen"): "vyraxen",
    ("Custom_Model", "Kharja"): "kharja",
    ("Custom_Model", "Dygorax"): "dygorax",
    ("Custom_Model", "Toramat"): "toramat",
    ("Custom_Model", "Board"): "battle_board",
    ("Figurine_Custom", "Dareon"): "dareon",
    ("Figurine_Custom", "Mirah"): "mirah",
    ("Figurine_Custom", "Thoreg"): "thoreg",
    ("Figurine_Custom", "Karah"): "karah",
    ("Figurine_Custom", "Ljonar"): "ljonar",
    ("Figurine_Custom", "Heleren"): "heleren",
}

# Livello di aggression di ciascuna carta "Stance 1" di Vyraxen (letto dall'icona in alto a sinistra).
VYRAXEN_STANCE_LEVEL = {1470700: 0, 1417100: 1, 1418200: 2, 1419000: 3}

_index = None
_sheets = {}


def norm(url):
    return re.sub(r"[^A-Za-z0-9]", "", url or "")


def index():
    global _index
    if _index is None:
        _index = {os.path.splitext(f)[0]: os.path.join(IMAGES, f) for f in os.listdir(IMAGES)}
    return _index


def sheet(url):
    key = norm(url)
    if key not in _sheets:
        path = index().get(key)
        _sheets[key] = Image.open(path).convert("RGBA") if path else None
    return _sheets[key]


def find_bag(objs, nickname):
    for o in objs:
        if o.get("Nickname") == nickname and o.get("ContainedObjects"):
            return o
        r = find_bag(o.get("ContainedObjects", []), nickname)
        if r:
            return r
    return None


class Extractor:
    def __init__(self):
        self.manifest = {"cards": {}, "behavior_decks": {}, "missing": []}

    def _save(self, img, subdir, name, key, meta):
        os.makedirs(os.path.join(OUT, subdir), exist_ok=True)
        rel = os.path.join("art", subdir, name + ".png")
        img.save(os.path.join(PROJECT, rel))
        entry = self.manifest["cards"].setdefault(key, dict(meta))
        entry["image"] = "res://" + rel.replace(os.sep, "/")
        return entry

    def cut(self, url, num_w, num_h, slot, subdir, name, key, meta=None):
        """Ritaglia la carta `slot` dallo sheet e la salva come PNG singolo."""
        img = sheet(url)
        if img is None:
            self.manifest["missing"].append({"key": key, "url": url})
            return None
        if num_w * num_h == 1:
            card = img
        else:
            w, h = img.width // num_w, img.height // num_h
            col, row = slot % num_w, slot // num_w
            card = img.crop((col * w, row * h, (col + 1) * w, (row + 1) * h))
        return self._save(card, subdir, name, key, meta or {})

    def card(self, obj, subdir, name, key, meta=None, side="front"):
        """Estrae fronte (e/o retro) di un CardCustom / Card usando il suo CustomDeck."""
        cd = obj.get("CustomDeck") or {}
        cid = obj.get("CardID")
        deck_key = str(cid // 100) if cid is not None else None
        spec = cd.get(deck_key) if deck_key in cd else (next(iter(cd.values())) if len(cd) == 1 else None)
        if spec is None:
            self.manifest["missing"].append({"key": key, "url": "?"})
            return None
        slot = cid % 100 if cid is not None else 0
        out = None
        if side in ("front", "both"):
            out = self.cut(spec["FaceURL"], spec["NumWidth"], spec["NumHeight"], slot,
                           subdir, name, key, meta)
        if side in ("back", "both"):
            # Il retro e' sempre un'immagine singola (NumWidth/Height valgono solo per il fronte).
            self.cut(spec["BackURL"], 1, 1, 0, subdir, name + "_back", key + "/back", meta)
        return out

    def tile(self, obj, subdir, name, key, meta=None):
        url = (obj.get("CustomImage") or {}).get("ImageURL")
        return self.cut(url, 1, 1, 0, subdir, name, key, meta)

    # ---------------------------------------------------------------- Vyraxen

    def vyraxen(self, save):
        bag = find_bag(save["ObjectStates"], "Vyraxen")
        if bag is None:
            sys.exit("bag Vyraxen non trovata")

        for c in bag["ContainedObjects"]:
            if c.get("Nickname") != "Stance 1":
                continue
            lv = VYRAXEN_STANCE_LEVEL.get(c["CardID"])
            if lv is None:
                continue
            self.card(c, "vyraxen", "stance1_lv%d" % lv, "vyraxen/stance/1/%d" % lv,
                      {"kind": "stance", "stance": 1, "level": lv})
            # Stance II e III sono States TTS della stessa carta fisica.
            for state_no, state in (c.get("States") or {}).items():
                roman = int(state_no)
                self.card(state, "vyraxen", "stance%d_lv%d" % (roman, lv),
                          "vyraxen/stance/%d/%d" % (roman, lv),
                          {"kind": "stance", "stance": roman, "level": lv})
            if c.get("Nickname") == "Stance 1" and lv == 0:
                self.card(c, "vyraxen", "stance_back", "vyraxen/stance/back", side="back")

        behavior_decks = []
        for dk in [c for c in bag["ContainedObjects"] if c.get("Name") == "Deck"]:
            kids = dk.get("ContainedObjects", [])
            if len(kids) == 10:
                for i, c in enumerate(kids):
                    self.card(c, "common", "attrition_%02d" % i, "common/attrition/%d" % i,
                              {"kind": "attrition"}, side="both" if i == 0 else "front")
            elif len(kids) == 3:
                for c in kids:
                    cid = c["CardID"] // 100
                    self.card(c, "vyraxen", "peril_%d" % cid, "vyraxen/peril/%d" % cid,
                              {"kind": "peril", "tts_id": cid}, side="both")
            elif len(kids) == 9:
                behavior_decks.append(dk)

        # I 4 mazzi behavior sono i 4 livelli di aggression, ma nel file TTS non
        # sono in ordine. Il Regolamento (p.60) assegna a ogni livello un set di 3
        # icone aggression che scorre su 6 icone totali:
        #   L0 = A,B,C   L1 = B,C,D   L2 = C,D,E   L3 = D,E,F
        # Ne segue che due livelli adiacenti condividono 6 carte, a distanza 2 ne
        # condividono 3 e a distanza 3 nessuna. Ordiniamo i mazzi cercando la
        # permutazione che rispetta questa struttura: e' univoca (a meno del verso,
        # che si risolve sapendo che il livello 0 usa solo carte del set base).
        ordered = _order_behavior_decks(behavior_decks)
        seen = set()
        for lv, dk in enumerate(ordered):
            for c in dk["ContainedObjects"]:
                cid = c["CardID"] // 100
                if cid not in seen:
                    seen.add(cid)
                    self.card(c, "vyraxen", "behavior_%d" % cid, "vyraxen/behavior/%d" % cid,
                              {"kind": "behavior", "tts_id": cid}, side="both")
            self.manifest["behavior_decks"]["lv%d" % lv] = [
                c["CardID"] // 100 for c in dk["ContainedObjects"]]

        for c in bag["ContainedObjects"]:
            if c.get("Name") == "CardCustom" and not c.get("Nickname") and c.get("CardID"):
                cid = c["CardID"] // 100
                self.card(c, "vyraxen", "objective_%d" % cid, "vyraxen/objective/%d" % cid,
                          {"kind": "objective", "tts_id": cid}, side="both")

        board = next((c for c in bag["ContainedObjects"] if c.get("Name") == "Custom_Tile"), None)
        if board is not None:
            self.tile(board, "vyraxen", "monster_board", "vyraxen/board", {"kind": "board"})

    # ---------------------------------------------------------------- Hunters

    def hunter(self, save, name):
        bag = find_bag(save["ObjectStates"], "%s Set" % name)
        if bag is None:
            print("  ! bag '%s Set' non trovata" % name)
            return
        slug = name.lower()
        for child in bag["ContainedObjects"]:
            kids = child.get("ContainedObjects", [])
            nick = child.get("Nickname", "")
            kind = child.get("Name")

            if kind == "Deck" and len(kids) == 24:
                for c in kids:
                    cid = c["CardID"]
                    self.card(c, slug, "action_%d" % cid, "%s/action/%d" % (slug, cid),
                              {"kind": "action", "tts_id": cid})
                self.card(kids[0], slug, "action", "%s/action" % slug, side="back")
            elif kind == "Deck" and len(kids) == 3:
                c = kids[0]
                self.card(c, slug, "wound", "%s/wound" % slug, {"kind": "wound"}, side="both")
            elif kind == "CardCustom":
                label = re.sub(r"[^a-z0-9]+", "_", (nick or "card_%d" % c_id(child)).lower()).strip("_")
                self.card(child, slug, label, "%s/%s" % (slug, label),
                          {"kind": "card", "tts_id": c_id(child)}, side="both")
            elif kind == "Custom_Tile":
                label = re.sub(r"[^a-z0-9]+", "_", (nick or "tile").lower()).strip("_")
                self.tile(child, slug, label, "%s/%s" % (slug, label), {"kind": "tile"})


    # ------------------------------------------------------------ scena 3D

    def scene_objects(self, save):
        """Mesh OBJ + texture delle miniature, e standee piatti dei cacciatori."""
        model_idx = {os.path.splitext(f)[0]: os.path.join(MODELS, f) for f in os.listdir(MODELS)}
        done = set()

        def visit(objs):
            for o in objs:
                slug = SCENE_OBJECTS.get((o.get("Name"), o.get("Nickname", "")))
                if slug and slug not in done:
                    done.add(slug)
                    mesh = o.get("CustomMesh")
                    image = o.get("CustomImage")
                    entry = {"kind": "model" if mesh else "standee"}
                    if mesh:
                        src = model_idx.get(norm(mesh.get("MeshURL")))
                        if src:
                            os.makedirs(MODELS_OUT, exist_ok=True)
                            dst = os.path.join(MODELS_OUT, slug + ".obj")
                            shutil.copyfile(src, dst)
                            entry["mesh"] = "res://models/%s.obj" % slug
                        else:
                            self.manifest["missing"].append({"key": slug, "url": mesh.get("MeshURL")})
                        if mesh.get("DiffuseURL"):
                            tex = self.cut(mesh["DiffuseURL"], 1, 1, 0, "models", slug + "_diffuse",
                                           "model/%s/diffuse" % slug)
                            if tex:
                                entry["texture"] = tex["image"]
                    if image:
                        tex = self.cut(image.get("ImageURL"), 1, 1, 0, "models", slug + "_standee",
                                       "model/%s/standee" % slug)
                        if tex:
                            entry["texture"] = tex["image"]
                    self.manifest.setdefault("scene", {})[slug] = entry
                visit(o.get("ContainedObjects", []))

        visit(save["ObjectStates"])


def _deck_faces(deck):
    """Insieme delle immagini fronte del mazzo: la stessa carta fisica compare in
    piu' mazzi con CardID diversi, quindi va identificata dall'immagine."""
    faces = set()
    for card in deck["ContainedObjects"]:
        spec = card["CustomDeck"][str(card["CardID"] // 100)]
        faces.add(norm(spec["FaceURL"]))
    return faces


def _order_behavior_decks(decks):
    """Ordina i quattro mazzi behavior per livello di aggression."""
    faces = [_deck_faces(d) for d in decks]
    expected = {1: 6, 2: 3, 3: 0}
    for perm in itertools.permutations(range(len(decks))):
        if all(len(faces[perm[i]] & faces[perm[j]]) == expected[j - i]
               for i in range(len(perm)) for j in range(i + 1, len(perm))):
            # Il verso giusto e' quello che mette per primo il mazzo di sole carte base.
            first = decks[perm[0]]
            if not all(c["CardID"] // 100 < 10000 for c in first["ContainedObjects"]):
                perm = tuple(reversed(perm))
            return [decks[i] for i in perm]
    print("  ! struttura dei mazzi behavior inattesa: uso l'ordine del file")
    return decks


def c_id(obj):
    return (obj.get("CardID") or 0) // 100


def main():
    save = json.load(open(SAVE))
    ex = Extractor()
    print("Vyraxen...")
    ex.vyraxen(save)
    for h in ("Dareon", "Mirah", "Thoreg", "Karah", "Ljonar", "Heleren"):
        print("%s..." % h)
        ex.hunter(save, h)
    print("scena 3D...")
    ex.scene_objects(save)

    os.makedirs(DATA, exist_ok=True)
    with open(os.path.join(DATA, "tts_manifest.json"), "w") as f:
        json.dump(ex.manifest, f, indent=2, sort_keys=True)

    print("\n%d carte estratte, %d mancanti" % (len(ex.manifest["cards"]), len(ex.manifest["missing"])))
    for m in ex.manifest["missing"]:
        print("  MANCANTE:", m["key"])
    print("mazzi behavior:", json.dumps(ex.manifest["behavior_decks"]))


if __name__ == "__main__":
    main()
