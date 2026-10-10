#!/usr/bin/env python3
"""Traduce in italiano i testi delle carte equipaggiamento.

`loadouts.json` e' generato dal database, quindi le traduzioni non possono
stare li': verrebbero sovrascritte. Stanno invece in `data/equipment_it.json`,
indicizzato per **testo inglese** — cosi' sopravvive alle rigenerazioni e la
stessa frase tradotta una volta vale per tutte le carte che la usano.

La traduzione e' a regole: si applicano sostituzioni note e si emette il
risultato solo se copre l'intera frase. Quello che resta scoperto NON viene
tradotto a meta' — resta in inglese e finisce nel rapporto finale.
"""
import json, os, re, sys

PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

# Termini che il regolamento italiano lascia in inglese.
KEEP = r"attack|maneuver|dodge|parry|struggle|stamina|aggro|threatened|vulnerable|blind|stun|burning|slash|aim|weapon|armor|helm|potion|Assist|Berserker|Resilience|Finisher|Stealth|Consume|Recycle|Volley|Ignite|Opening"

RULES = [
    # frasi intere ricorrenti
    (r"^Increase your hand size limit by (\d+)\.?$", r"Aumenta di \1 il limite della tua mano."),
    (r"^Increase your sequence limit by (\d+)\.?$", r"Aumenta di \1 il limite della tua sequenza."),
    (r"^Heal (\d+)\.?$", r"Recupera \1."),
    (r"^Draw (\d+)\.?$", r"Pesca \1."),
    (r"^Deal (\d+) damage\.?$", r"Infliggi \1 danni."),
    (r"^Remove (\d+) struggle\.?$", r"Rimuovi \1 struggle."),
    (r"^Volley (\d+)\.?$", r"Volley \1."),
    # pezzi componibili
    (r"\bIncrease the damage (?:the|this) attack deals by (\d+)x?WL\b",
     r"aumenta di \1xWL i danni dell'attacco"),
    (r"\bIncrease the damage (?:the|this) attack deals by (\d+)\b",
     r"aumenta di \1 i danni dell'attacco"),
    (r"\bIncrease the struggle (?:the|this) maneuver removes by (\d+)\b",
     r"aumenta di \1 lo struggle rimosso dal maneuver"),
    (r"\bremove (\d+) struggle\b", r"rimuovi \1 struggle"),
    (r"\bRemove (\d+) struggle\b", r"Rimuovi \1 struggle"),
    (r"\bheal (\d+)x?WL\b", r"recupera \1xWL"),
    (r"\bHeal (\d+)x?WL\b", r"Recupera \1xWL"),
    (r"\bheal (\d+)\b", r"recupera \1"),
    (r"\bHeal (\d+)\b", r"Recupera \1"),
    (r"\bdraw (\d+)\b", r"pesca \1"),
    (r"\bDraw (\d+)\b", r"Pesca \1"),
    (r"\bdeal (\d+)x?WL damage\b", r"infliggi \1xWL danni"),
    (r"\bDeal (\d+)x?WL damage\b", r"Infliggi \1xWL danni"),
    (r"\bdeal (\d+) damage\b", r"infliggi \1 danni"),
    (r"\bDeal (\d+) damage\b", r"Infliggi \1 danni"),
    (r"\bthis attack inflicts\b", "questo attacco infligge"),
    (r"\bThis attack inflicts\b", "Questo attacco infligge"),
    (r"\bIf you are in the front sector\b", "Se sei nel settore front"),
    (r"\bif you are in the front sector\b", "se sei nel settore front"),
    (r"\bIf you are in the rear sector\b", "Se sei nel settore rear"),
    (r"\bin the front sector\b", "nel settore front"),
    (r"\bin the rear sector\b", "nel settore rear"),
    (r"\bin your sector\b", "nel tuo settore"),
    (r"\bin your sequence\b", "nella tua sequenza"),
    (r"\bin your hand\b", "in mano"),
    (r"\bfrom your hand\b", "dalla mano"),
    (r"\bin your discard pile\b", "nella tua pila degli scarti"),
    (r"\byour discard pile\b", "la tua pila degli scarti"),
    (r"\byour deck\b", "il tuo mazzo"),
    (r"\bat the end of your action phase\b", "alla fine della tua fase Azione"),
    (r"\bAt the end of your action phase\b", "Alla fine della tua fase Azione"),
    (r"\bAt the end of the round\b", "Alla fine del round"),
    (r"\bat the start of your turn\b", "all'inizio del tuo turno"),
    (r"\bAt the start of your turn\b", "All'inizio del tuo turno"),
    (r"\bWhen you\b", "Quando"),
    (r"\bwhen you\b", "quando"),
    (r"\byou may\b", "puoi"),
    (r"\bYou may\b", "Puoi"),
    (r"\band add it to your hand\b", "e aggiungila alla mano"),
    (r"\bChoose a player\b", "Scegli un giocatore"),
    (r"\bchoose a player\b", "scegli un giocatore"),
    (r"\bfor each\b", "per ogni"),
    (r"\bFor each\b", "Per ogni"),
    (r"\buntil the end of the turn\b", "fino alla fine del turno"),
    (r"\buntil the end of the round\b", "fino alla fine del round"),
    (r"\bthis turn\b", "in questo turno"),
    (r"\bcard with\b", "carta con"),
    (r"\bSearch\b", "Cerca"),
    (r"\bsearch\b", "cerca"),
]

# Una frase e' "coperta" se dopo le regole non restano parole inglesi note.
ENGLISH = re.compile(
    r"\b(the|this|that|your|you|and|or|of|to|by|with|for|in|a|an|is|are|may|"
    r"when|if|then|each|card|cards|damage|player|players|deal|draw|heal|remove|"
    r"increase|search|choose|add|hand|deck|discard|pile|sector|sequence|turn|"
    r"round|end|start|attack|attacks)\b", re.I)


def translate(text):
    out = text.strip()
    if not out:
        return None
    for pattern, repl in RULES:
        out = re.sub(pattern, repl, out)
    # toglie i termini che restano volutamente in inglese prima del controllo
    probe = re.sub(KEEP, "", out, flags=re.I)
    probe = re.sub(r"\bWL\b|\bDMG\b|\bMF\b|\bPP\b", "", probe)
    if ENGLISH.search(probe):
        return None
    return out


def main():
    data = json.load(open(os.path.join(PROJECT, "data", "loadouts.json")))
    texts = set()
    for group in list(data.get("shared", {}).values()):
        for item in group:
            texts.add(item.get("text", ""))
    for hunter in data.get("hunters", {}).values():
        for item in hunter.get("weapons", []):
            texts.add(item.get("text", ""))
    texts.discard("")

    out, skipped = {}, []
    for text in sorted(texts):
        it = translate(text)
        if it and it != text:
            out[text] = it
        else:
            skipped.append(text)

    path = os.path.join(PROJECT, "data", "equipment_it.json")
    json.dump({"_note": "Traduzioni indicizzate per testo inglese. Generato da "
                        "tools/translate_equipment.py, integrabile a mano.",
               "texts": out}, open(path, "w"), indent=2, ensure_ascii=False)
    print("%d frasi distinte, %d tradotte (%.0f%%), %d lasciate in inglese"
          % (len(texts), len(out), 100.0 * len(out) / max(len(texts), 1), len(skipped)))
    for s in skipped[:8]:
        print("   resta in inglese:", s[:90])
    return 0


if __name__ == "__main__":
    sys.exit(main())
