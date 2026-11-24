#!/usr/bin/env python3
"""Aggiunge gli Item forgiabili a data/loadouts.json (slot Item, Regolamento p.66).

Gli Item stanno nel foglio *Cards* del `primal_database.xlsm` (Card = Equipment,
Card type = Item): 18 oggetti, ciascuno in tre livelli. Nel mod TTS non c'e'
un'immagine per carta, quindi come armor e helm della forge si mostrano col testo.

Ogni Item porta una chiave (`key`) con cui il motore riconosce l'effetto, e i
numeri che cambiano col livello sono in `values`: il testo resta quello del
database, la traduzione italiana sta in `it`.

    python3 tools/build_items.py [percorso/primal_database.xlsm]
"""

import json
import os
import pathlib
import sys

import openpyxl

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_XLSM = ROOT.parent / "primal_database.xlsm"

# chiave, valori per livello 1..3, traduzione per livello 1..3
ITEMS = {
    "Coral Trident": ("coral_trident", [0, 4, 7], [
        "Le tue carte azione contano un'icona stamina in piu' nei riding check.",
        "Quando infliggi danni al mostro con un riding check, aumentali di 4. Le tue carte "
        "azione contano un'icona stamina in piu' nei riding check.",
        "Quando infliggi danni al mostro con un riding check, aumentali di 7. Le tue carte "
        "azione contano un'icona stamina in piu' nei riding check."]),
    "Gauntlet of Shell Blade": ("shell_gauntlet", [3, 5, 7], [
        "Quando eviti il danno da attrition, prendi in mano la carta in cima ai tuoi scarti. "
        "Se e' un attack, infliggi 3 danni.",
        "Quando eviti il danno da attrition, prendi in mano la carta in cima ai tuoi scarti. "
        "Se e' un attack, infliggi 5 danni.",
        "Quando eviti il danno da attrition, prendi in mano la carta in cima ai tuoi scarti. "
        "Se e' offensive, infliggi 7 danni."]),
    "Crystal Spear": ("crystal_spear", [6, 9, 12], [
        "Inizio turno: se hai tre maneuver in mano, puoi scartarne uno per infliggere 6 danni.",
        "Inizio turno: se hai tre maneuver in mano, puoi scartarne uno per infliggere 9 danni. "
        "Se cosi' infliggi una ferita, infliggi vulnerable.",
        "Inizio turno: se hai tre maneuver in mano, puoi scartarne uno per infliggere 12 danni. "
        "Se cosi' infliggi una ferita, infliggi vulnerable."]),
    "Shimmering Boots": ("shimmering_boots", [1, 1, 2], [
        "Quando ti muovi puoi nominare un colore e scartare la prima carta del mazzo: se e' "
        "di quel colore, il movimento non costa nulla.",
        "Azione: muoviti (una volta per turno). Quando ti muovi puoi nominare un colore e "
        "scartare la prima carta del mazzo: se e' di quel colore, il movimento non costa nulla.",
        "Azione: muoviti (una volta per turno). Quando ti muovi puoi nominare un colore e "
        "scartare fino a 2 carte dalla cima del mazzo: se almeno una e' di quel colore, il "
        "movimento non costa nulla."]),
    "Feathered Coat": ("feathered_coat", [0, 0, 0], [
        "Quando ti muovi, se non sei il giocatore aggro, puoi rivelare un dodge dalla mano per "
        "non pagare il movimento.",
        "Quando ti muovi puoi rivelare un dodge dalla mano per non pagare il movimento.",
        "Quando ti muovi puoi rivelare un dodge dalla mano per non pagare il movimento. Quando "
        "innescheresti una behavior con la reazione del front, puoi rivelare due dodge: se lo "
        "fai, scarta quella behavior e rimpiazzala (al massimo una volta per round)."]),
    "Boomerang": ("boomerang", [1, 2, 3], [
        "A fine fase azione, se la prima e l'ultima carta della sequenza sono dodge, infliggi 1 "
        "danno per ogni carta della sequenza.",
        "A fine fase azione, se la prima e l'ultima carta della sequenza sono dodge, infliggi 2 "
        "danni per ogni carta della sequenza.",
        "A fine fase azione, se la prima e l'ultima carta della sequenza sono dodge, infliggi 3 "
        "danni per ogni carta della sequenza."]),
    "Woltyar Gauntlet": ("woltyar_gauntlet", [2, 4, 6], [
        "Su un attack: se l'hai pagato con una carta offensive, aumenta di 2 i danni dell'attacco.",
        "Su un attack: se l'hai pagato con una carta offensive, aumenta di 4 i danni dell'attacco.",
        "Su un attack: se l'hai pagato con una carta offensive, aumenta di 6 i danni dell'attacco."]),
    "Lava Buckler": ("lava_buckler", [1, 2, 3], [
        "Setup: 2 segnalini su questa carta. Quando subiresti danno da attrition, puoi togliere un "
        "segnalino e scartare la prima carta del mazzo: se e' defensive, il danno e' prevenuto.",
        "Setup: 2 segnalini su questa carta. Quando subiresti un danno, puoi togliere un "
        "segnalino e scartare la prima carta del mazzo: se e' defensive, il danno e' prevenuto.",
        "Setup: 2 segnalini su questa carta. Quando subiresti un danno, puoi togliere un "
        "segnalino e scartare una carta dalla mano o dalla cima del mazzo: se e' defensive, il "
        "danno e' prevenuto."]),
    "Skeletal Spear": ("skeletal_spear", [7, 15, 20], [
        "Quando si rivela una behavior, se sei nel settore front puoi esaurire questa carta: "
        "infliggi 7 danni e annulla gli effetti di quella behavior.",
        "Quando si rivela una behavior, se sei nel settore front puoi esaurire questa carta: "
        "infliggi 15 danni e annulla gli effetti di quella behavior.",
        "Quando si rivela una behavior, se sei nel settore front puoi esaurire questa carta: "
        "infliggi 20 danni e annulla gli effetti di quella behavior."]),
    "Big Jaws": ("big_jaws", [2, 4, 6], [
        "Quando il mostro si gira verso il tuo settore, puoi esaurire questa carta per infliggere "
        "2 danni per ogni carta aggro nei tuoi scarti.",
        "Quando il mostro si gira verso il tuo settore, puoi esaurire questa carta per infliggere "
        "4 danni per ogni carta aggro nei tuoi scarti.",
        "Quando il mostro si gira verso il tuo settore, puoi esaurire questa carta per infliggere "
        "6 danni per ogni carta aggro nei tuoi scarti."]),
    "Frozen boots": ("frozen_boots", [1, 2, 3], [
        "Ignora gli effetti dei terreni acqua e ghiaccio.",
        "Ignora gli effetti dei terreni acqua, ghiaccio e sabbia.",
        "Ignora gli effetti dei terreni acqua, ghiaccio, sabbia e palude."]),
    "Wristbow": ("wristbow", [1, 2, 3], [
        "Su una carta defensive: se l'hai pagata con un maneuver, infliggi 1 danno.",
        "Su una carta defensive: se l'hai pagata con un maneuver, infliggi 2 danni.",
        "Su una carta defensive: se l'hai pagata con un maneuver, infliggi 3 danni."]),
    "Iron Greaves": ("iron_greaves", [2, 4, 6], [
        "La tua salute aumenta di 2. Quando vai KO, esaurisci questa carta.",
        "La tua salute aumenta di 4. Quando vai KO, esaurisci questa carta.",
        "La tua salute aumenta di 6. Quando vai KO, esaurisci questa carta."]),
    "Explosive": ("explosive", [5, 10, 15], [
        "Inizio turno: puoi esaurire questa carta per infliggere 5 danni. Se cosi' infliggi una "
        "ferita, il mostro diventa confuse.",
        "Inizio turno: puoi esaurire questa carta per infliggere 10 danni. Se cosi' infliggi una "
        "ferita, stordisci il mostro e rendilo confuse.",
        "Inizio turno: puoi esaurire questa carta per infliggere 15 danni. Se cosi' infliggi una "
        "ferita, stordisci il mostro e rendilo confuse."]),
    "Electric Whip": ("electric_whip", [0, 3, 3], [
        "Quando si rivela una behavior, puoi scartare un maneuver dalla mano per aumentare di 1 "
        "il costo del suo boost.",
        "Quando si rivela una behavior, puoi scartare un maneuver dalla mano per aumentare di 1 "
        "il costo del suo boost. Se lo fai, infliggi 3 danni.",
        "Quando si rivela una behavior, puoi scartare un maneuver dalla mano per aumentare di 1 "
        "il costo del suo boost. Se lo fai, infliggi 3 danni per ogni maneuver nei tuoi scarti."]),
    "Electric Dagger": ("electric_dagger", [0, 4, 4], [
        "Quando eviti il danno da attrition, puoi scartare una behavior in gioco e rimpiazzarla "
        "con la prima del mazzo behavior.",
        "Quando eviti il danno da attrition, infliggi 4 danni. Poi puoi scartare una behavior in "
        "gioco e rimpiazzarla con la prima del mazzo behavior.",
        "Quando eviti il danno da attrition, infliggi 4 danni per ogni carta defensive nella tua "
        "sequenza. Poi puoi scartare una behavior in gioco e rimpiazzarla con la prima del mazzo "
        "behavior."]),
    "Bloodseeker": ("bloodseeker", [1, 2, 3], [
        "Quando eviti il danno da attrition, infliggi 1 danno per ogni attack nei tuoi scarti.",
        "Quando eviti il danno da attrition, infliggi 2 danni per ogni attack nei tuoi scarti.",
        "Quando eviti il danno da attrition, infliggi 3 danni per ogni attack nei tuoi scarti."]),
    "Blackspin": ("blackspin", [4, 5, 7], [
        "Quando esaurisci il mazzo, puoi rivelare un dodge dalla mano per infliggere 4 danni.",
        "Quando esaurisci il mazzo, infliggi 5 danni per ogni dodge in mano.",
        "Quando esaurisci il mazzo, infliggi 7 danni per ogni dodge in mano. Se cosi' infliggi "
        "una ferita, infliggi vulnerable."]),
}

ACCENTS = {"e'": "è", "puo'": "può", "piu'": "più", "cosi'": "così"}


def accent(text):
    for k, v in ACCENTS.items():
        text = text.replace(" " + k, " " + v).replace(k + " ", v + " ")
        if text.startswith(k):
            text = v + text[len(k):]
    return text.replace("e',", "è,").replace("e':", "è:").replace("e'.", "è.")


def main():
    xlsm = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_XLSM
    wb = openpyxl.load_workbook(xlsm, read_only=True, data_only=True)
    rows = list(wb["Cards"].iter_rows(values_only=True))
    header = [(h or "").split("\n")[0] for h in rows[1]]
    items = []
    for row in rows[2:]:
        r = dict(zip(header, row))
        if r.get("Card") != "Equipment" or r.get("Card type") != "Item":
            continue
        name = str(r["Card name"]).strip()
        level = int(r["Level"])
        key, values, it = ITEMS[name]
        items.append({
            "name": name, "level": level, "key": key, "value": values[level - 1],
            "element": r.get("Element") or "", "text": str(r["Card text"]).strip(),
            "it": accent(it[level - 1]),
        })
    path = ROOT / "data" / "loadouts.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    data["shared"]["item"] = items
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Item:", len(items))


if __name__ == "__main__":
    main()
