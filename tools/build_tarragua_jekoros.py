#!/usr/bin/env python3
"""Scrive data/tarragua.json e data/jekoros.json.

Le carte sono state lette una per una dalle immagini estratte dal mod TTS
(art/monsters/<mostro>/). Qui sta la trascrizione, in forma di dati: rifare il
file e' rilanciare lo script.

Come sono stati ricavati i livelli: le carte identiche fra i quattro mazzi
behavior sono state riconosciute per immagine (differenza media dei pixel zero);
il glifo aggression in alto a sinistra di ogni carta (ordine ≢ ⊕ Ψ 8 M V, come
per gli altri mostri) dice a quali livelli appartiene, e la finestra scorrevole
di p.60 (L0 = A,B,C ... L3 = D,E,F) e' univoca per entrambi i mostri.

Reazione e refresh sono stampati sul **retro** di ogni behavior: icona al centro,
refresh in basso a sinistra.

    python3 tools/build_tarragua_jekoros.py
"""

import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent


def art(mon, name):
    return f"res://art/monsters/{mon}/{name}.jpg"


# ======================================================================
#  TARRAGUA
# ======================================================================

T = "tarragua"

# file di ciascuna carta distinta (indice usato nella trascrizione)
T_FILES = ["g2_00", "g2_01", "g2_02", "g2_03", "g2_04", "g2_05", "g2_06", "g2_07",
           "g3_00", "g3_03", "g3_04", "g3_05", "g3_07", "g5_04", "g5_06", "g5_07"]

FRONT_FLANK = "players_in_front_and_flank"

T_CARDS = {
    0: dict(name="Metal Skin", reaction="turn_start_front", refresh=7,
            text="Tarragua's shield value is increased by 1 until the end of this turn.",
            it="Lo shield di Tarragua aumenta di 1 fino alla fine di questo turno.",
            effects=[{"op": "shield_bonus", "n": 1}]),
    12: dict(name="Arkeum Skin", reaction="turn_start_front", refresh=7,
             text="Tarragua's shield value is increased by 4 until the end of this turn.",
             it="Lo shield di Tarragua aumenta di 4 fino alla fine di questo turno.",
             effects=[{"op": "shield_bonus", "n": 4}]),
    1: dict(name="Spidery Grasp", reaction="turn_start_front", refresh=4,
            text="The active player becomes dazed and skips their movement phase this turn unless "
                 "another player in either the same sector or an adjacent one discards an offensive "
                 "card from their hand.",
            it="Il giocatore attivo diventa dazed e salta la fase movimento di questo turno, a meno "
               "che un altro giocatore nello stesso settore o in uno adiacente scarti una carta "
               "offensive dalla mano.",
            effects=[{"op": "skip_movement_unless_help", "who": "active", "kind": "offensive",
                      "dazed": True}],
            boost={"cost": 1,
                   "text": "The active player suffers DMG unless they reveal a number of dodges "
                           "from their hand equal to the current attrition level.",
                   "it": "Il giocatore attivo subisce DMG a meno che non riveli dalla mano tanti "
                         "dodge quanto il livello di attrition attuale.",
                   "effects": [{"op": "suffer_unless_reveal", "who": "active", "type": "dodge",
                                "n": "attrition_level"}]}),
    15: dict(name="Spidery Grasp", reaction="turn_start_front", refresh=4,
             text="The active player skips their movement phase this turn unless another player in "
                  "either the same sector or an adjacent one discards an offensive card from their hand.",
             it="Il giocatore attivo salta la fase movimento di questo turno, a meno che un altro "
                "giocatore nello stesso settore o in uno adiacente scarti una carta offensive dalla mano.",
             effects=[{"op": "skip_movement_unless_help", "who": "active", "kind": "offensive"}],
             boost={"cost": 1,
                    "text": "The active player suffers DMG unless they reveal a dodge from their hand.",
                    "it": "Il giocatore attivo subisce DMG a meno che non riveli un dodge dalla mano.",
                    "effects": [{"op": "suffer_unless_reveal", "who": "active", "type": "dodge"}]}),
    2: dict(name="Rumbling Stomp", reaction="dodge_played", refresh=1,
            text="Tarragua gains PP-1 struggle and gets DMG+1 until the end of the round.",
            it="Tarragua guadagna (giocatori-1) struggle e ottiene DMG+1 fino alla fine del round.",
            effects=[{"op": "monster_gain_struggle", "n": "players_minus_1"},
                     {"op": "monster_damage_bonus", "n": 1, "duration": "round"}]),
    10: dict(name="Rumbling Stomp", reaction="dodge_played", refresh=1,
             text="The active player becomes threatened. Tarragua gains 1 PP struggle and gets "
                  "DMG+3 until the end of the round.",
             it="Il giocatore attivo diventa threatened. Tarragua guadagna 1 struggle per "
                "giocatore e ottiene DMG+3 fino alla fine del round.",
             effects=[{"op": "become_threatened", "who": "active"},
                      {"op": "monster_gain_struggle", "n": 1, "scale": "per_player"},
                      {"op": "monster_damage_bonus", "n": 3, "duration": "round"}]),
    3: dict(name="Rampaging Horns", reaction="attack_played", refresh=5,
            text="Tarragua turns to the active player. That player may immediately move.",
            it="Tarragua si gira verso il giocatore attivo. Quel giocatore puo' muoversi subito.",
            effects=[{"op": "monster_turn_to", "criteria": "active"},
                     {"op": "offer_move", "who": "active"}]),
    11: dict(name="Rampaging Horns", reaction="attack_played", refresh=5,
             text="Tarragua turns to the active player. That player suffers DMG unless they "
                  "immediately move. The cost of this movement is increased by 1.",
             it="Tarragua si gira verso il giocatore attivo. Quel giocatore subisce DMG a meno che "
                "non si muova subito; quel movimento costa 1 stamina in piu'.",
             effects=[{"op": "monster_turn_to", "criteria": "active"},
                      {"op": "move_or_suffer", "who": "active", "extra_cost": 1}]),
    4: dict(name="Crushing Horns", reaction="turn_start_flank", refresh=5,
            text="If Tarragua suffered damage this turn, each player in the front and flank "
                 "sectors suffers DMG unless they reveal 2 dodges from their hand.",
            it="Se Tarragua ha subito danni in questo turno, ogni giocatore nei settori front e "
               "flank subisce DMG a meno che non riveli 2 dodge dalla mano.",
            effects=[{"op": "suffer_unless_reveal", "who": FRONT_FLANK, "type": "dodge", "n": 2,
                      "condition": "monster_damaged_this_turn"}]),
    9: dict(name="Crushing Horns", reaction="turn_start_flank", refresh=5,
            text="If Tarragua suffered damage this turn, each player suffers DMG unless they "
                 "reveal 2 dodges from their hand.",
            it="Se Tarragua ha subito danni in questo turno, ogni giocatore subisce DMG a meno "
               "che non riveli 2 dodge dalla mano.",
            effects=[{"op": "suffer_unless_reveal", "who": "all", "type": "dodge", "n": 2,
                      "condition": "monster_damaged_this_turn"}],
            boost={"cost": 1, "text": "Discard the top 3 cards of the attrition deck.",
                   "it": "Scarta le prime 3 carte del mazzo attrition.",
                   "effects": [{"op": "discard_attrition", "n": 3}]}),
    5: dict(name="Indomitable Charge", reaction="end_of_round", refresh=4,
            text="Each player in the front sector suffers DMGx2 unless they reveal 2 dodges from "
                 "their hand. If a player does reveal those cards, they must immediately move "
                 "without paying any stamina cost.",
            it="Ogni giocatore nel settore front subisce DMGx2 a meno che non riveli 2 dodge dalla "
               "mano. Chi li rivela deve muoversi subito, senza pagare stamina.",
            effects=[{"op": "suffer_unless_reveal", "who": "players_in_front", "type": "dodge",
                      "n": 2, "damage_multiplier": 2,
                      "on_reveal": [{"op": "free_move_now", "who": "self", "forced": True}]}]),
    14: dict(name="Indomitable Charge", reaction="end_of_round", refresh=4,
             text="Each player in the front sector suffers DMG unless they reveal 2 dodges from "
                  "their hand. If a player does reveal those cards, they must immediately move "
                  "without paying any stamina cost.",
             it="Ogni giocatore nel settore front subisce DMG a meno che non riveli 2 dodge dalla "
                "mano. Chi li rivela deve muoversi subito, senza pagare stamina.",
             effects=[{"op": "suffer_unless_reveal", "who": "players_in_front", "type": "dodge",
                       "n": 2,
                       "on_reveal": [{"op": "free_move_now", "who": "self", "forced": True}]}]),
    6: dict(name="Aggressive Posture", reaction="rampage", refresh=6, rampage=True,
            text="Tarragua gains 1 struggle for each player in the front sector.",
            it="Tarragua guadagna 1 struggle per ogni giocatore nel settore front.",
            effects=[{"op": "monster_gain_struggle", "n": 1, "per_target": "players_in_front"}]),
    13: dict(name="Aggressive Posture", reaction="rampage", refresh=6, rampage=True,
             text="Tarragua gains PP-1 struggle.",
             it="Tarragua guadagna (giocatori-1) struggle.",
             effects=[{"op": "monster_gain_struggle", "n": "players_minus_1"}]),
    7: dict(name="Hammer Tail", reaction="monster_turned", refresh=3,
            text="Each player in the rear sector suffers DMG unless they discard a dodge from "
                 "their hand. Each threatened player in the flank sectors suffers DMG unless they "
                 "reveal a dodge from their hand.",
            it="Ogni giocatore nel settore rear subisce DMG a meno che non scarti un dodge dalla "
               "mano. Ogni giocatore threatened nei settori flank subisce DMG a meno che non "
               "riveli un dodge dalla mano.",
            effects=[{"op": "suffer_unless_discard", "who": "players_in_rear", "discard_type": "dodge"},
                     {"op": "suffer_unless_reveal", "who": "threatened_in_flank", "type": "dodge"}]),
    8: dict(name="Hammer Tail", reaction="monster_turned", refresh=3,
            text="Threatened players in the flank and rear sectors suffer DMG+1. Threatened "
                 "players in the flank sectors suffer another DMG+1 unless they reveal a dodge "
                 "from their hand. Each other player in the flank and rear sectors suffers DMG "
                 "unless they discard a dodge from their hand.",
            it="I giocatori threatened nei settori flank e rear subiscono DMG+1. Quelli threatened "
               "nei flank subiscono un altro DMG+1 a meno che non rivelino un dodge dalla mano. "
               "Ogni altro giocatore nei settori flank e rear subisce DMG a meno che non scarti "
               "un dodge dalla mano.",
            effects=[{"op": "suffer", "who": "threatened_in_flank_rear", "damage_bonus": 1},
                     {"op": "suffer_unless_reveal", "who": "threatened_in_flank", "type": "dodge",
                      "damage_bonus": 1},
                     {"op": "suffer_unless_discard", "who": "unthreatened_in_flank_rear",
                      "discard_type": "dodge"}]),
}

# mazzi per livello, in indici di carta distinta (gruppi estratti 5, 2, 4, 3)
T_DECKS = {
    "0": [7, 7, 2, 3, 13, 4, 14, 15, 0],
    "1": [0, 1, 2, 3, 4, 5, 6, 7, 7],
    "2": [8, 8, 6, 4, 5, 3, 10, 0, 1],
    "3": [8, 8, 6, 9, 10, 11, 5, 12, 1],
}


def stance(n, tough, prog, dmg, exposed, art_name, shield, resistant, **extra):
    s = {"n": n, "toughness_per_player": tough, "damage": dmg, "exposed": exposed,
         "art": art_name}
    if prog is not None:
        s["progression"] = prog
    if shield:
        s["shield"] = shield
    if resistant:
        s["resistant"] = True
    s.update(extra)
    return s


ACC = [{"op": "acceleration", "n": 1}]
FR = ["flank", "rear"]
F = ["flank"]


def t_stances(lv):
    a = lambda n: art(T, n)
    p1, p3, ob = (46101, 46103, 46201) if lv < 3 else (461010, 461030, 462010)
    rows = {
        0: [(2, 6, 1, FR, "sciolta_1", 1, True), (3, 3, 1, FR, "sciolta_1_stato2", 1, True),
            (4, None, 2, FR, "sciolta_1_stato3", 2, False)],
        1: [(6, 6, 1, FR, "sciolta_2", 1, True), (7, 3, 1, F, "sciolta_2_stato2", 1, True),
            (8, None, 2, FR, "sciolta_2_stato3", 2, False)],
        2: [(10, 6, 2, FR, "sciolta_3", 2, True), (14, 3, 3, F, "sciolta_3_stato2", 2, True),
            (18, None, 4, FR, "sciolta_3_stato3", 3, False)],
        3: [(16, 6, 3, FR, "sciolta_3_retro", 3, True), (18, 3, 4, F, "sciolta_3_stato2_retro", 3, True),
            (22, None, 5, F, "sciolta_3_stato3_retro", 4, False)],
    }[lv]
    out = []
    for i, (tough, prog, dmg, exp, name, shield, res) in enumerate(rows):
        extra = {}
        texts = []
        if res:
            texts.append("Resistant.")
        texts.append("Shield %d." % shield)
        if i == 0:
            extra["peril"] = p1
            if lv == 3:
                extra["on_round_1"] = [{"op": "remove_attrition_card", "value": 0}]
                texts.append("At the start of round 1, search the attrition deck for a card with "
                             "attrition value of 0 and remove that card from the game. Then shuffle "
                             "the attrition deck.")
        if i == 1:
            extra["objective"] = ob
            extra["on_reveal"] = ACC
            texts.append("When revealed: Tarragua gains 1 acceleration.")
        if i == 2:
            extra["peril"] = p3
            if lv == 3:
                extra["on_reveal"] = ACC
                texts.append("When revealed: Tarragua gains 1 acceleration.")
        extra["text"] = " ".join(texts)
        out.append(stance(i + 1, tough, prog, dmg, exp, a(name), shield, res, **extra))
    return out


def tarragua():
    behaviors = {}
    for idx, c in T_CARDS.items():
        rec = dict(c)
        rec["art"] = art(T, T_FILES[idx] + "_fronte")
        rec["back"] = art(T, T_FILES[idx] + "_retro")
        behaviors[str(46001 + idx)] = rec
    levels = {}
    for lv in range(4):
        levels[str(lv)] = {
            "health": 10,
            "behavior_deck": [46001 + i for i in T_DECKS[str(lv)]],
            "stances": t_stances(lv),
        }
    perils = {
        "46101": {"n": 1, "stance": 1, "name": "Wailing Roar", "permanent": True,
                  "art": art(T, "g1_01_fronte"),
                  "text": "Permanent. When the attrition deck is emptied, Tarragua gains 1 PP struggle.",
                  "it": "Permanente. Quando il mazzo attrition si esaurisce, Tarragua guadagna 1 "
                        "struggle per giocatore.",
                  "abilities": [{"trigger": "attrition_deck_emptied", "effects": [
                      {"op": "monster_gain_struggle", "n": 1, "scale": "per_player"}]}]},
        "461010": {"n": 1, "stance": 1, "name": "Wailing Roar", "permanent": True,
                   "art": art(T, "g1_01_retro"),
                   "text": "Permanent. When the attrition deck is emptied, Tarragua gains 1 PP "
                           "struggle and is unstoppable until the end of the round.",
                   "it": "Permanente. Quando il mazzo attrition si esaurisce, Tarragua guadagna 1 "
                         "struggle per giocatore ed e' unstoppable fino alla fine del round.",
                   "abilities": [{"trigger": "attrition_deck_emptied", "effects": [
                       {"op": "monster_gain_struggle", "n": 1, "scale": "per_player"},
                       {"op": "unstoppable", "duration": "round"}]}]},
        "46103": {"n": 3, "stance": 3, "name": "Unscratchable",
                  "art": art(T, "g1_00_fronte"),
                  "text": "While Tarragua has 1 PP or more struggle, all weapon cards are "
                          "considered to be blank (ignore the ability text on those cards).",
                  "it": "Finche' Tarragua ha almeno 1 struggle per giocatore, tutte le carte "
                        "weapon sono blank (se ne ignora il testo).",
                  "weapons_blank_at_struggle_per_player": 1},
        "461030": {"n": 3, "stance": 3, "name": "Unscratchable",
                   "art": art(T, "g1_00_retro"),
                   "text": "While Tarragua has 1 PP or more struggle, its shield value is "
                           "increased to 6 and all weapon cards are considered to be blank.",
                   "it": "Finche' Tarragua ha almeno 1 struggle per giocatore, il suo shield sale "
                         "a 6 e tutte le carte weapon sono blank.",
                   "weapons_blank_at_struggle_per_player": 1, "shield_at_struggle": 6},
    }
    objectives = {
        "46201": {"name": "Slash to the Throat", "stance": 2, "permanent": True,
                  "art": art(T, "sciolta_0"),
                  "text": "Permanent. When a behavior card with the front sector reaction is "
                          "revealed, the active player may discard an attack from their hand. "
                          "If they do, cancel the effects of that behavior card and inflict vulnerable.",
                  "it": "Permanente. Quando viene rivelata una behavior con la reazione del "
                        "settore front, il giocatore attivo puo' scartare un attack dalla mano: "
                        "se lo fa, annulla gli effetti di quella behavior e infliggi vulnerable.",
                  "abilities": [{"trigger": "behavior_revealed", "reaction": "turn_start_front",
                                 "discard_type": "attack",
                                 "effects": [{"op": "cancel_behavior"},
                                             {"op": "inflict", "status": "vulnerable"}]}]},
        "462010": {"name": "Slash to the Throat", "stance": 2, "permanent": True,
                   "art": art(T, "sciolta_0_retro"),
                   "text": "Permanent. When a behavior card with the front sector reaction is "
                           "revealed, the active player may discard an attack from their hand. "
                           "If they do, cancel the effects of that behavior card.",
                   "it": "Permanente. Quando viene rivelata una behavior con la reazione del "
                         "settore front, il giocatore attivo puo' scartare un attack dalla mano: "
                         "se lo fa, annulla gli effetti di quella behavior.",
                   "abilities": [{"trigger": "behavior_revealed", "reaction": "turn_start_front",
                                  "discard_type": "attack",
                                  "effects": [{"op": "cancel_behavior"}]}]},
    }
    return {
        "_note": "Tarragua. Trascritto dalle immagini con tools/build_tarragua_jekoros.py: vedi "
                 "docs/tarragua_struttura.md. Terreno delle Expedition dal Regolamento (p.69-70): "
                 "i pezzi sono quelli del libro, le caselle sono provvisorie.",
        "id": T, "name": "Tarragua", "element": "earth",
        "acceleration": {"max_per_player": 1},
        "art": {"behavior_back": art(T, "g2_00_retro"), "model": "res://models/tarragua.glb",
                "model_yaw": 180, "board": art(T, "board"),
                "portrait": {"art": art(T, "sciolta_1"), "region": [0.3, 0.0, 0.32, 0.45]}},
        "expeditions": {
            "_note": "Pezzi dal Regolamento; posizioni provvisorie, da confrontare col diagramma.",
            "1": {"name": "Expedition 1", "terrain": [
                {"type": "plateau", "sector": 2}, {"type": "rock", "sector": 1},
                {"type": "rock", "sector": 3}, {"type": "baethanis", "sector": 0}]},
            "2": {"name": "Expedition 2", "terrain": [
                {"type": "plateau", "sector": 2}, {"type": "rock", "sector": 1},
                {"type": "rock", "sector": 3}, {"type": "fog", "sector": 0},
                {"type": "fog", "sector": 2}]},
        },
        "levels": levels, "behaviors": behaviors, "perils": perils, "objectives": objectives,
    }


# ======================================================================
#  JEKOROS
# ======================================================================

J = "jekoros"

J_FILES = ["g1_00", "g1_01", "g1_02", "g1_03", "g1_04", "g1_05", "g1_06", "g1_07", "g1_08",
           "g2_01", "g2_06", "g3_02", "g3_04", "g3_06", "g3_08", "g4_00", "g4_03", "g4_05"]

DEF_OR_THR = "defensive_played|threatened"

J_CARDS = {
    0: dict(name="Unfathomable Shadows", reaction="turn_start_front", refresh=5,
            text="The active player discards 2 random cards from their hand and then draws 2.",
            it="Il giocatore attivo scarta 2 carte a caso dalla mano, poi ne pesca 2.",
            effects=[{"op": "discard_random", "who": "active", "n": 2},
                     {"op": "draw", "target": "active", "n": 2}]),
    15: dict(name="Creeping Shadows", reaction="turn_start_front", refresh=5,
             text="The active player must recycle all offensive cards in their hand.",
             it="Il giocatore attivo deve riciclare tutte le carte offensive che ha in mano.",
             effects=[{"op": "recycle_all_of_kind", "who": "active", "kind": "offensive"}]),
    1: dict(name="Haunting Echoes", reaction=DEF_OR_THR, refresh=3,
            text="The active player reveals a random card from their hand. If that card is an "
                 "offensive card, they discard it. Otherwise, Jekoros gains PP-1 struggle.",
            it="Il giocatore attivo rivela una carta a caso dalla mano: se e' offensive la scarta, "
               "altrimenti Jekoros guadagna (giocatori-1) struggle.",
            effects=[{"op": "reveal_random", "who": "active", "kind": "offensive",
                      "match": [{"op": "discard_revealed"}],
                      "else": [{"op": "monster_gain_struggle", "n": "players_minus_1"}]}]),
    9: dict(name="Haunting Echoes", reaction=DEF_OR_THR, refresh=3,
            text="The active player reveals a random card from their hand. If that card is an "
                 "attack, they discard it. Otherwise, Jekoros gains PP-1 struggle.",
            it="Il giocatore attivo rivela una carta a caso dalla mano: se e' un attack la scarta, "
               "altrimenti Jekoros guadagna (giocatori-1) struggle.",
            effects=[{"op": "reveal_random", "who": "active", "type": "attack",
                      "match": [{"op": "discard_revealed"}],
                      "else": [{"op": "monster_gain_struggle", "n": "players_minus_1"}]}]),
    2: dict(name="Electric Spark", reaction="threatened", refresh=2,
            text="The active player reveals a random card from their hand. If that card is a "
                 "defensive card, they discard it.",
            it="Il giocatore attivo rivela una carta a caso dalla mano: se e' defensive la scarta.",
            effects=[{"op": "reveal_random", "who": "active", "kind": "defensive",
                      "match": [{"op": "discard_revealed"}]}]),
    11: dict(name="Electric Spark", reaction="threatened", refresh=2,
             text="The active player discards a defensive card from their hand.",
             it="Il giocatore attivo scarta una carta defensive dalla mano.",
             effects=[{"op": "force_discard", "who": "active", "kind": "defensive"}]),
    3: dict(name="Sting", reaction="rampage", refresh=4, rampage=True,
            text="Each player in the flank and rear sectors suffers DMG unless they reveal 2 "
                 "dodges from their hand.",
            it="Ogni giocatore nei settori flank e rear subisce DMG a meno che non riveli 2 dodge "
               "dalla mano.",
            effects=[{"op": "suffer_unless_reveal", "who": "players_in_flank_and_rear",
                      "type": "dodge", "n": 2}]),
    16: dict(name="Sting", reaction="rampage", refresh=4, rampage=True,
             text="Each player in the rear and flank sectors suffers DMG+1 unless they reveal 2 "
                  "dodges from their hand.",
             it="Ogni giocatore nei settori rear e flank subisce DMG+1 a meno che non riveli 2 "
                "dodge dalla mano.",
             effects=[{"op": "suffer_unless_reveal", "who": "players_in_flank_and_rear",
                       "type": "dodge", "n": 2, "damage_bonus": 1}]),
    4: dict(name="Retaliation", reaction="turn_start_flank", refresh=4,
            text="If Jekoros suffered a wound this turn, the active player suffers DMG. "
                 "Otherwise, Jekoros gains PP-1 struggle.",
            it="Se Jekoros ha subito una ferita in questo turno, il giocatore attivo subisce DMG; "
               "altrimenti Jekoros guadagna (giocatori-1) struggle.",
            effects=[{"op": "if", "test": "monster_wounded_this_turn",
                      "then": [{"op": "suffer", "who": "active"}],
                      "else": [{"op": "monster_gain_struggle", "n": "players_minus_1"}]}]),
    12: dict(name="Retaliation", reaction="turn_start_flank", refresh=4,
             text="If Jekoros suffered a wound this turn, the active player suffers DMG. "
                  "Otherwise, Jekoros gains 1 PP struggle.",
             it="Se Jekoros ha subito una ferita in questo turno, il giocatore attivo subisce DMG; "
                "altrimenti Jekoros guadagna 1 struggle per giocatore.",
             effects=[{"op": "if", "test": "monster_wounded_this_turn",
                       "then": [{"op": "suffer", "who": "active"}],
                       "else": [{"op": "monster_gain_struggle", "n": 1, "scale": "per_player"}]}]),
    5: dict(name="Electrocution", reaction="empty_hand", refresh=2,
            text="If the active player is in a sector with a water terrain, they suffer DMG "
                 "unless they discard a random card from their hand.",
            it="Se il giocatore attivo e' in un settore con acqua, subisce DMG a meno che non "
               "scarti una carta a caso dalla mano.",
            effects=[{"op": "suffer_unless_discard_random", "who": "active_in_water"}]),
    17: dict(name="Electrocution", reaction="empty_hand", refresh=2,
             text="Each player in a sector with a water terrain suffers DMG unless they discard "
                  "a random card from their hand.",
             it="Ogni giocatore in un settore con acqua subisce DMG a meno che non scarti una "
                "carta a caso dalla mano.",
             effects=[{"op": "suffer_unless_discard_random", "who": "players_in_water"}]),
    6: dict(name="Heart Seeker", reaction="aggro_played", refresh=3,
            text="Jekoros immediately turns to the active player unless another player discards "
                 "a maneuver from their hand.",
            it="Jekoros si gira subito verso il giocatore attivo, a meno che un altro giocatore "
               "scarti un maneuver dalla mano.",
            effects=[{"op": "turn_unless_other_discards", "type": "maneuver"}]),
    14: dict(name="Heart Seeker", reaction="aggro_played", refresh=3,
             text="Jekoros immediately turns to the active player. That player becomes threatened.",
             it="Jekoros si gira subito verso il giocatore attivo, che diventa threatened.",
             effects=[{"op": "monster_turn_to", "criteria": "active"},
                      {"op": "become_threatened", "who": "active"}]),
    7: dict(name="Killer Tail", reaction="end_of_round", refresh=5,
            text="Each player in the rear sector suffers DMG+1 unless they reveal a dodge from "
                 "their hand. If there are no players in the rear sector, players in the flank "
                 "sectors are targeted instead.",
            it="Ogni giocatore nel settore rear subisce DMG+1 a meno che non riveli un dodge dalla "
               "mano. Se nel rear non c'e' nessuno, i bersagli sono i giocatori nei flank.",
            effects=[{"op": "suffer_unless_reveal", "who": "players_in_rear_or_flank",
                      "type": "dodge", "damage_bonus": 1}]),
    13: dict(name="Killer Tail", reaction="end_of_round", refresh=5,
             text="Each player in the rear sector suffers DMG+1 unless they reveal 2 dodges from "
                  "their hand. If there are no players in the rear sector, players in the flank "
                  "sectors are targeted instead.",
             it="Ogni giocatore nel settore rear subisce DMG+1 a meno che non riveli 2 dodge dalla "
                "mano. Se nel rear non c'e' nessuno, i bersagli sono i giocatori nei flank.",
             effects=[{"op": "suffer_unless_reveal", "who": "players_in_rear_or_flank",
                       "type": "dodge", "n": 2, "damage_bonus": 1}]),
    8: dict(name="Insane Buzz", reaction="end_of_round", refresh=5,
            text="If the charge level is 2 or higher, all players become dazed. If a player is "
                 "already dazed, they discard a card from their hand.",
            it="Se il livello di charge e' 2 o piu', tutti i giocatori diventano dazed; chi lo e' "
               "gia' scarta una carta dalla mano.",
            effects=[{"op": "daze_all", "min_charge": 2, "random": False}]),
    10: dict(name="Insane Buzz", reaction="end_of_round", refresh=5,
             text="If the charge level is 2 or higher, all players become dazed. If a player is "
                  "already dazed, they discard a random card from their hand.",
             it="Se il livello di charge e' 2 o piu', tutti i giocatori diventano dazed; chi lo e' "
                "gia' scarta una carta a caso dalla mano.",
             effects=[{"op": "daze_all", "min_charge": 2, "random": True}]),
}

# mazzi per livello (gruppi estratti 1, 2, 3, 4). Nel gruppo 2 il mod ha una
# carta in meno: e' Electric Spark della versione D, presente nei gruppi 3 e 4.
J_DECKS = {
    "0": [0, 1, 2, 3, 4, 5, 6, 7, 8],
    "1": [0, 9, 3, 4, 5, 7, 10, 6, 11],
    "2": [0, 9, 11, 3, 12, 5, 13, 10, 14],
    "3": [15, 9, 11, 16, 12, 17, 10, 13, 14],
}


def j_stances(lv):
    a = lambda n: art(J, n)
    ALL = ["front", "flank", "rear"]
    FF = ["front", "flank"]
    p_echo, p_horn, p_tension, ob = (47101, 47102, 47103, 47201) if lv < 3 \
        else (471010, 471020, 471030, 472010)
    rows = {
        0: [(2, "sciolta_2"), (4, "sciolta_2_stato2"), (5, "sciolta_2_stato3"), 1],
        1: [(7, "sciolta_1"), (8, "sciolta_1_stato2"), (12, "sciolta_1_stato3"), 1],
        2: [(12, "sciolta_4"), (17, "sciolta_4_stato2"), (22, "sciolta_4_stato3"), 2],
        3: [(20, "sciolta_3"), (25, "sciolta_3_stato2"), (30, "sciolta_3_stato3"), 3],
    }[lv]
    dmg = rows[3]
    next_text = "When the charge level reaches 3, reset it to 0 and advance to Stance %s."
    out = []
    s1 = stance(1, rows[0][0], None, dmg, ALL, a(rows[0][1]), 0, False,
                peril=p_echo, perils=[p_echo, p_horn],
                on_charge_full=[{"op": "charge", "set": 0}, {"op": "advance_stance"}],
                text=next_text % "II")
    if lv >= 2:
        s1["on_round_1"] = [{"op": "charge", "n": 1}]
        s1["text"] = "At the start of round 1, increase the charge level by 1. " + s1["text"]
    out.append(s1)
    out.append(stance(2, rows[1][0], None, dmg, FF, a(rows[1][1]), 0, False, objective=ob,
                      on_charge_full=[{"op": "charge", "set": 0}, {"op": "advance_stance"}],
                      text=next_text % "III"))
    out.append(stance(3, rows[2][0], None, dmg, FF, a(rows[2][1]), 0, False, peril=p_tension,
                      on_charge_full=[{"op": "all_players_ko"}],
                      text="When the charge level reaches 3, all players are KO'd."))
    return out


def jekoros():
    behaviors = {}
    for idx, c in J_CARDS.items():
        rec = dict(c)
        rec["art"] = art(J, J_FILES[idx] + "_fronte")
        rec["back"] = art(J, J_FILES[idx] + "_retro")
        behaviors[str(47001 + idx)] = rec
    levels = {}
    for lv in range(4):
        levels[str(lv)] = {
            "health": 10,
            "behavior_deck": [47001 + i for i in J_DECKS[str(lv)]],
            "stances": j_stances(lv),
        }
    echo = {"n": 1, "stance": 1, "name": "Incessant Echo", "permanent": True,
            "text": "Permanent. Jekoros is unstoppable.",
            "it": "Permanente. Jekoros e' unstoppable.", "unstoppable": True}
    horn_text = ("Permanent. Immune to blind. When Jekoros suffers a wound, it gains %s struggle. "
                 "Unleash: Increase the charge level by 1. A player in a sector with a rock terrain "
                 "may remove that terrain from the game to prevent unleash damage in that sector.")
    horn_it = ("Permanente. Immune a blind. Quando Jekoros subisce una ferita guadagna %s struggle. "
               "Unleash: il livello di charge aumenta di 1. Un giocatore in un settore con una roccia "
               "puo' rimuoverla dal gioco per evitare il danno dell'unleash in quel settore.")
    perils = {
        "47101": dict(echo, art=art(J, "g5_01_fronte")),
        "471010": dict(echo, art=art(J, "g5_01_retro")),
        "47102": {"n": 1, "stance": 1, "name": "Thunder Horn", "permanent": True,
                  "immune_blind": True, "art": art(J, "g5_02_retro"),
                  "text": horn_text % "1 PP", "it": horn_it % "1 per giocatore",
                  "rock_stops_unleash": True,
                  "abilities": [
                      {"trigger": "monster_wound", "effects": [
                          {"op": "monster_gain_struggle", "n": 1, "scale": "per_player"}]},
                      {"trigger": "unleash", "effects": [{"op": "charge", "n": 1}]}]},
        "471020": {"n": 1, "stance": 1, "name": "Thunder Horn", "permanent": True,
                   "immune_blind": True, "art": art(J, "g5_02_fronte"),
                   "text": horn_text % "PP-1", "it": horn_it % "(giocatori-1)",
                   "rock_stops_unleash": True,
                   "abilities": [
                       {"trigger": "monster_wound", "effects": [
                           {"op": "monster_gain_struggle", "n": "players_minus_1"}]},
                       {"trigger": "unleash", "effects": [{"op": "charge", "n": 1}]}]},
        "47103": {"n": 3, "stance": 3, "name": "High Tension", "art": art(J, "g5_00_fronte"),
                  "text": "When a player suffers attrition damage, if the charge level is 2 or "
                          "more, that player suffers DMGx2 instead of DMG.",
                  "it": "Quando un giocatore subisce danno da attrition, se il livello di charge "
                        "e' 2 o piu' subisce DMGx2 invece di DMG.",
                  "attrition_double_at_charge": 2},
        "471030": {"n": 3, "stance": 3, "name": "High Tension", "art": art(J, "g5_00_retro"),
                   "text": "When a player suffers attrition damage, if the charge level is 1 or "
                           "more, that player suffers DMGx2 instead of DMG.",
                   "it": "Quando un giocatore subisce danno da attrition, se il livello di charge "
                         "e' 1 o piu' subisce DMGx2 invece di DMG.",
                   "attrition_double_at_charge": 1},
    }
    strike = ("Permanent. At the start of each player's turn, a player in the front sector may "
              "discard %s from their hand to either inflict vulnerable or reduce the charge level by 1.")
    strike_it = ("Permanente. All'inizio del turno di ogni giocatore, un giocatore nel settore front "
                 "puo' scartare %s dalla mano per infliggere vulnerable oppure ridurre di 1 il "
                 "livello di charge.")
    objectives = {
        "47201": {"name": "Strike to the Heart", "stance": 2, "permanent": True,
                  "art": art(J, "sciolta_0"), "text": strike % "an offensive card",
                  "it": strike_it % "una carta offensive",
                  "abilities": [{"trigger": "turn_start_front_discard", "kind": "offensive"}]},
        "472010": {"name": "Strike to the Heart", "stance": 2, "permanent": True,
                   "art": art(J, "sciolta_0_retro"), "text": strike % "an attack",
                   "it": strike_it % "un attack",
                   "abilities": [{"trigger": "turn_start_front_discard", "type": "attack"}]},
    }
    return {
        "_note": "Jekoros. Trascritto dalle immagini con tools/build_tarragua_jekoros.py: vedi "
                 "docs/jekoros_struttura.md. Le stance avanzano solo col tracciato charge, non con "
                 "la salute. Terreno delle Expedition: pezzi dal Regolamento, caselle provvisorie.",
        "id": J, "name": "Jekoros", "element": "lightning",
        "charge": {"max": 3},
        "attrition": {"_note": "Le cinque carte attrition di Jekoros prendono il posto delle "
                               "cinque di valore 1 del mazzo comune.",
                      "replace_value": 1, "count": 5,
                      "card": {"value": 1, "art": art(J, "g6_00_fronte"),
                               "text": "When revealed: If the active player is in the front "
                                       "sector, Jekoros gains 1 struggle.",
                               "on_reveal": [{"op": "monster_gain_struggle", "n": 1,
                                              "condition": "active_in_front"}]}},
        "art": {"behavior_back": art(J, "g1_00_retro"), "model": "res://models/jekoros.glb",
                "model_yaw": 180, "board": art(J, "board"),
                "portrait": {"art": art(J, "sciolta_2"), "region": [0.2, 0.0, 0.32, 0.45]}},
        "expeditions": {
            "_note": "Pezzi dal Regolamento; posizioni provvisorie, da confrontare col diagramma.",
            "1": {"name": "Expedition 1", "terrain": [
                {"type": "rock", "sector": 1}, {"type": "rock", "sector": 3},
                {"type": "baethanis", "sector": 2}, {"type": "water", "sector": 0},
                {"type": "water", "sector": 2}]},
            "2": {"name": "Expedition 2", "terrain": [
                {"type": "rock", "sector": 1}, {"type": "rock", "sector": 3},
                {"type": "cyricae", "sector": 0}, {"type": "cyricae", "sector": 2},
                {"type": "water", "sector": 1}, {"type": "water", "sector": 3}]},
        },
        "levels": levels, "behaviors": behaviors, "perils": perils, "objectives": objectives,
    }


def main():
    for name, data in (("tarragua", tarragua()), ("jekoros", jekoros())):
        path = ROOT / "data" / f"{name}.json"
        path.write_text(json.dumps(data, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        print("scritto", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
