#!/usr/bin/env python3
"""Estrae le carte di un mostro dal mod TTS, senza sapere in anticipo cosa sono.

Le carte dei mostri diversi da Vyraxen non hanno nickname nel salvataggio, quindi
non si puo' dedurre il ruolo di una carta dai dati: va letta l'immagine. Questo
script tira giu' tutto numerato per posizione e monta dei provini (contact sheet)
da leggere a colpo d'occhio, cosi' la trascrizione parte da immagini vere invece
che dall'ordine del file - che per Vyraxen si era gia' rivelato inaffidabile.

    python3 tools/extract_monster.py Kharja
"""
import sys, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from PIL import Image
import extract_assets as ea

OUT = pathlib.Path(__file__).parent.parent / "art" / "monsters"
SHEETS = pathlib.Path(__file__).parent.parent / "art" / "_provini"


def cards_of(deck):
    """Ogni carta di un mazzo, come (url foglio, larghezza, altezza, slot)."""
    out = []
    for c in deck.get("ContainedObjects", []):
        cd = list(c["CustomDeck"].values())[0]
        out.append((cd["FaceURL"], cd["NumWidth"], cd["NumHeight"],
                    ea.c_id(c) % 100, cd.get("BackURL")))
    return out


def grab(url, nw, nh, slot):
    sheet = ea.sheet(url)
    if nw * nh <= 1:
        # Kharja e i mostri successivi hanno un'immagine per carta, non un
        # foglio sprite come Vyraxen: qui lo slot non vuol dire niente.
        return sheet.convert("RGB")
    w, h = sheet.width // nw, sheet.height // nh
    x, y = (slot % nw) * w, (slot // nw) * h
    return sheet.crop((x, y, x + w, y + h)).convert("RGB")


def contact(images, path, cols=5):
    """Monta le carte in una griglia unica: una lettura invece di venti."""
    if not images:
        return
    tw = 460
    scaled = [im.resize((tw, int(im.height * tw / im.width))) for im in images]
    ch = max(im.height for im in scaled)
    rows = (len(scaled) + cols - 1) // cols
    out = Image.new("RGB", (cols * tw, rows * ch), (20, 20, 24))
    for i, im in enumerate(scaled):
        out.paste(im, ((i % cols) * tw, (i // cols) * ch))
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path, quality=88)
    print("  provino", path.name, "->", len(images), "carte")


def main():
    name = sys.argv[1] if len(sys.argv) > 1 else "Kharja"
    key = name.lower()
    import json
    save = json.load(open(ea.SAVE))
    bag = ea.find_bag(save["ObjectStates"], name)
    if not bag:
        sys.exit("bag %s non trovata" % name)

    dest = OUT / key
    dest.mkdir(parents=True, exist_ok=True)
    group = 0
    loose = 0
    tiles = []
    for obj in bag["ContainedObjects"]:
        if obj.get("Name") == "Deck":
            entries = cards_of(obj)
            group += 1
            fronts, backs = [], []
            # Il retro uguale su tutte le carte del mazzo e' il dorso comune: non
            # porta testo e non serve. Se invece ogni carta ha il suo, quel retro
            # e' la faccia B - la reazione delle behavior, la variante ad
            # aggression alta delle peril - e va tenuto. Un retro molto piu'
            # largo del fronte e' un foglio sprite, non una carta.
            common = len({e[4] for e in entries}) == 1 and len(entries) > 1
            for i, (url, nw, nh, slot, back) in enumerate(entries):
                im = grab(url, nw, nh, slot)
                im.save(dest / ("g%d_%02d_fronte.jpg" % (group, i)), quality=90)
                fronts.append(im)
                if back and not common:
                    bi = ea.sheet(back).convert("RGB")
                    if bi.width < im.width * 2:
                        bi.save(dest / ("g%d_%02d_retro.jpg" % (group, i)), quality=90)
                        backs.append(bi)
            contact(fronts, SHEETS / ("%s_gruppo%d_fronte.jpg" % (key, group)))
            contact(backs, SHEETS / ("%s_gruppo%d_retro.jpg" % (key, group)))
        elif obj.get("Name") == "Custom_Tile":
            # Nella borsa di un mostro le tessere sono piu' d'una: la plancia e
            # i segnalini (hardening, acceleration). Si tengono da parte tutte e
            # si sceglie dopo, perche' quale sia la plancia si vede dalla forma.
            tiles.append(obj.get("CustomImage") or {})
        elif obj.get("Name") in ("CardCustom", "Card"):
            cd = list(obj["CustomDeck"].values())[0]
            im = grab(cd["FaceURL"], cd["NumWidth"], cd["NumHeight"],
                      ea.c_id(obj) % 100)
            n = loose
            loose += 1
            im.save(dest / ("sciolta_%d.jpg" % n), quality=90)
            # Anche le carte sciolte sono stampate fronte-retro: Keep Your
            # Distance ha sul retro la versione ad aggression alta.
            back = cd.get("BackURL")
            if back:
                ea.sheet(back).convert("RGB").save(
                    dest / ("sciolta_%d_retro.jpg" % n), quality=90)
            # Le Stance II e III non sono carte a se': nel mod sono *States*
            # della carta Stance I, cioe' facce alternative dello stesso oggetto.
            for state in sorted(obj.get("States", {})):
                sd = list(obj["States"][state]["CustomDeck"].values())[0]
                si = grab(sd["FaceURL"], sd["NumWidth"], sd["NumHeight"],
                          ea.c_id(obj["States"][state]) % 100)
                si.save(dest / ("sciolta_%d_stato%s.jpg" % (n, state)), quality=90)
                # Anche gli States sono stampati fronte-retro, e il retro non e'
                # il dorso: e' la stessa stance all'aggression piu' alta. Senza
                # questo, di un mostro mancano tre carte su dodici.
                sback = sd.get("BackURL")
                if sback and sback != sd["FaceURL"]:
                    ea.sheet(sback).convert("RGB").save(
                        dest / ("sciolta_%d_stato%s_retro.jpg" % (n, state)), quality=90)
    # La plancia e' la tessera piu' grande e coricata: i segnalini sono quadrati
    # e piccoli. Sceglierla dalla forma evita di dover sapere in che ordine il
    # mod ha infilato le cose nella borsa.
    best, best_area = None, 0
    for img in tiles:
        url = img.get("ImageURL")
        if not url:
            continue
        im = ea.sheet(url).convert("RGB")
        if im.width < im.height * 1.2:
            continue
        if im.width * im.height > best_area:
            best, best_area = (im, img.get("ImageSecondaryURL")), im.width * im.height
    if best is not None:
        best[0].save(dest / "board.jpg", quality=90)
        print("  plancia %dx%d" % best[0].size)
        if best[1]:
            ea.sheet(best[1]).convert("RGB").save(dest / "board_retro.jpg", quality=90)
    else:
        print("  ! nessuna plancia fra le %d tessere" % len(tiles))

    loose_files = sorted(dest.glob("sciolta_*.jpg"))
    contact([Image.open(p) for p in loose_files], SHEETS / ("%s_sciolte.jpg" % key))
    print("fatto:", len(list(dest.glob('*.jpg'))), "immagini in", dest)


if __name__ == "__main__":
    main()
