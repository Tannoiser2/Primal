#!/usr/bin/env python3
"""Rilegge il diagramma di esposizione dalle carte stance e lo confronta col JSON.

Il diagramma e' il cerchio diviso da una X in quattro spicchi (Regolamento p.20):
rosso = lato esposto, nero = lato protetto. **E' orientato col front in basso**,
segnato dal trattino sotto il cerchio — non in alto. I dati di
`data/<mostro>.json` sono trascritti a mano da queste immagini, quindi qui non si
"ricalcola" niente: si rilegge la stessa fonte e si dice dove le due cose non
coincidono.

    python3 tools/check_exposure.py            # controlla tutti i mostri
    python3 tools/check_exposure.py toramat    # solo uno
    python3 tools/check_exposure.py --sheet    # tavole da guardare a occhio

La lettura automatica e' una **prima passata**, non un verdetto: su qualche carta
il cerchio non viene centrato e il risultato va scartato. Quando segnala una
differenza, la si conferma con `--sheet`, che ritaglia tutti i diagrammi e ci
scrive accanto il valore del JSON: e' li' che si decide.
"""

import json
import math
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MONSTERS = ["vyraxen", "kharja", "dygorax", "toramat"]

# Il cerchio, rimpicciolito a 300px di larghezza, ha un raggio in questo intorno.
SMALL_W = 300
R_MIN, R_MAX = 18, 52


def whitish(px):
    r, g, b = px[:3]
    return r > 150 and g > 150 and b > 150 and max(r, g, b) - min(r, g, b) < 60


def find_circle(img):
    """Cerchio bianco del diagramma: piccola trasformata di Hough sul ridotto."""
    scale = SMALL_W / img.width
    small = img.convert("RGB").resize((SMALL_W, round(img.height * scale)))
    w, h = small.size
    px = small.load()

    ring = [[whitish(px[x, y]) for y in range(h)] for x in range(w)]
    ray = [(math.cos(math.tau * k / 48), math.sin(math.tau * k / 48)) for k in range(48)]

    def patch(x, y):
        total = [0, 0, 0]
        n = 0
        for k in range(-1, 2):
            for j in range(-1, 2):
                if 0 <= x + k < w and 0 <= y + j < h:
                    p = px[x + k, y + j]
                    total = [total[i] + p[i] for i in range(3)]
                    n += 1
        return [c / max(n, 1) for c in total]

    def classifiable(colour):
        """Uno spicchio vero e' o rosso o quasi nero, mai un grigio qualunque."""
        r, g, b = colour
        return is_exposed(colour) or max(r, g, b) < 115

    def score(cx, cy, r):
        if cx - r < 0 or cy - r < 0 or cx + r >= w or cy + r >= h:
            return -1
        # L'interno del diagramma e' colorato, non bianco: senza questo controllo
        # una zona bianca dell'illustrazione fa 48 su 48 e vince sempre.
        inside = sum(1 for dx, dy in ray
                     if ring[int(cx + dx * r * 0.6)][int(cy + dy * r * 0.6)])
        if inside > len(ray) * 0.35:
            return -1
        # E i quattro spicchi devono essere spicchi: almeno uno rosso, e nessuno
        # di un colore che sul diagramma non esiste.
        wedges = [patch(int(cx + dx * r * 0.5), int(cy + dy * r * 0.5))
                  for dx, dy in [(0, 1), (0, -1), (-1, 0), (1, 0)]]
        if not all(classifiable(c) for c in wedges):
            return -1
        if not any(is_exposed(c) for c in wedges):
            return -1
        return sum(1 for dx, dy in ray if ring[int(cx + dx * r)][int(cy + dy * r)])

    # A parita' di bordo bianco vince il cerchio piu' grande: sulla carta c'e'
    # anche lo schizzo rosso della toughness, che e' un disco rosso su fondo
    # scuro e supera tutti i controlli di forma — e' solo molto piu' piccolo.
    def search(xs, ys, rs):
        best = (0, 0, None)
        for cx in xs:
            for cy in ys:
                for r in rs:
                    hits = score(cx, cy, r)
                    if hits < 0:
                        continue
                    rank = hits * r
                    if rank > best[0]:
                        best = (rank, hits, (cx, cy, r))
        return (best[1], best[2])

    # Prima a passo grosso sulla meta' destra/bassa, poi si rifinisce intorno
    # al candidato: a passo 1 su tutta la carta ci vorrebbero minuti, e a passo
    # 3 soltanto meta' dei cerchi viene centrata.
    coarse = search(range(w // 2, w - R_MIN, 3),
                    range(h // 3, h - R_MIN, 3),
                    range(R_MIN, R_MAX, 3))
    if coarse[1] is None:
        return None
    cx0, cy0, r0 = coarse[1]
    best = search(range(cx0 - 4, cx0 + 5), range(cy0 - 4, cy0 + 5),
                  range(max(R_MIN, r0 - 4), r0 + 5))
    if best[1] is None or best[0] < 26:
        return None
    cx, cy, r = best[1]
    return (cx / scale, cy / scale, r / scale, best[0])


def wedge_colour(img, cx, cy, r, dx, dy):
    """Colore medio al centro di uno spicchio."""
    px = img.convert("RGB").load()
    total = [0, 0, 0]
    n = 0
    for k in range(-4, 5):
        for j in range(-4, 5):
            x = int(cx + dx * r * 0.5) + k
            y = int(cy + dy * r * 0.5) + j
            if 0 <= x < img.width and 0 <= y < img.height:
                p = px[x, y]
                total = [total[i] + p[i] for i in range(3)]
                n += 1
    return [c / max(n, 1) for c in total]


def is_exposed(colour):
    """Rosso = esposto, nero = protetto.

    Il rosso stampato sta intorno a (180,115,110): il rosso va staccato di
    almeno 40 da entrambi gli altri canali. Con una soglia piu' larga passano
    anche i grigi caldi dell'illustrazione, e il diagramma viene "trovato"
    dove non c'e'.
    """
    r, g, b = colour
    return r > 120 and r - g > 40 and r - b > 40


def read_diagram(path):
    img = Image.open(path)
    found = find_circle(img)
    if found is None:
        return None
    cx, cy, r, _hits = found
    # Front in basso, rear in alto, flank ai lati (Regolamento p.20).
    sides = {
        "front": wedge_colour(img, cx, cy, r, 0, 1),
        "rear": wedge_colour(img, cx, cy, r, 0, -1),
        "flank_left": wedge_colour(img, cx, cy, r, -1, 0),
        "flank_right": wedge_colour(img, cx, cy, r, 1, 0),
    }
    exposed = []
    if is_exposed(sides["front"]):
        exposed.append("front")
    if is_exposed(sides["flank_left"]) or is_exposed(sides["flank_right"]):
        exposed.append("flank")
    if is_exposed(sides["rear"]):
        exposed.append("rear")
    return exposed, sides


def art_path(res_path):
    return ROOT / res_path.replace("res://", "")


## Ritaglia tutti i diagrammi di un mostro in una tavola unica, con accanto il
## valore scritto nel JSON. E' il controllo che decide: la lettura automatica
## sbaglia il cerchio su qualche carta, l'occhio no.
def contact_sheet(name, data):
    from PIL import ImageDraw

    tiles = []
    for level in sorted(data["levels"]):
        for i, stance in enumerate(data["levels"][level].get("stances", [])):
            path = art_path(str(stance.get("art", "")))
            if not path.exists():
                continue
            img = Image.open(path)
            w, h = img.size
            crop = img.crop((int(w * 0.59), int(h * 0.53), int(w * 0.88), int(h * 0.95)))
            tiles.append(("L%s S%d  json=%s" % (level, i + 1,
                ",".join(stance.get("exposed", []))), crop.resize((190, 190))))

    cols = 3
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 200, rows * 212), (25, 25, 28))
    draw = ImageDraw.Draw(sheet)
    for k, (label, img) in enumerate(tiles):
        x = (k % cols) * 200 + 5
        y = (k // cols) * 212 + 18
        sheet.paste(img, (x, y))
        draw.text((x, y - 14), label, fill=(230, 220, 210))
    out = ROOT / "build" / ("exposure_%s.png" % name)
    out.parent.mkdir(exist_ok=True)
    sheet.save(out)
    return out


def main():
    args = sys.argv[1:]
    sheet = "--sheet" in args
    wanted = [a for a in args if not a.startswith("--")] or MONSTERS
    if sheet:
        for name in wanted:
            data = json.loads((ROOT / "data" / f"{name}.json").read_text())
            print("tavola:", contact_sheet(name, data))
        return 0
    problems = 0
    for name in wanted:
        data = json.loads((ROOT / "data" / f"{name}.json").read_text())
        print(f"=== {name}")
        for level in sorted(data["levels"]):
            for i, stance in enumerate(data["levels"][level].get("stances", [])):
                path = art_path(str(stance.get("art", "")))
                if not path.exists():
                    print(f"  liv {level} stance {i + 1}: immagine mancante {path}")
                    problems += 1
                    continue
                result = read_diagram(path)
                if result is None:
                    print(f"  liv {level} stance {i + 1}: diagramma non trovato")
                    problems += 1
                    continue
                found, sides = result
                declared = list(stance.get("exposed", []))
                mark = "ok  " if found == declared else "DIVERSO"
                if found != declared:
                    problems += 1
                print(f"  liv {level} stance {i + 1}: {mark} carta={found} json={declared}")
                if found != declared:
                    for side, colour in sides.items():
                        print("        %-12s rgb(%3d,%3d,%3d)" % (
                            side, colour[0], colour[1], colour[2]))
    if problems:
        print(f"\n{problems} da confermare a occhio: python3 tools/check_exposure.py --sheet")
    else:
        print("\ntutto coerente")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
