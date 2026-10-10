extends Node
## Carica e indicizza i dati statici del gioco (autoload "Db").

var common: Dictionary = {}
var hunters: Dictionary = {}
var vyraxen: Dictionary = {}
var monsters: Dictionary = {}
## Il mostro dello scontro in corso: behavior, peril, objective e stance si
## cercano qui. Lo imposta `PrimalGame.setup()`.
var selected: String = "vyraxen"
var loadouts: Dictionary = {}
var upgrades: Dictionary = {}   ## id globale -> carta potenziamento
## Traduzioni dell'equipaggiamento, indicizzate per testo inglese: `loadouts.json`
## e' generato dal database, quindi le traduzioni devono vivere fuori da li'.
var equipment_it: Dictionary = {}

## id carta azione -> definizione (con "hunter" iniettato)
var action_by_id: Dictionary = {}


func _ready() -> void:
	common = _load("res://data/common.json")
	hunters = _load("res://data/hunters.json")
	vyraxen = _load("res://data/vyraxen.json")
	# Il registro dei mostri: la chiave e' l'id usato dal motore e dalla
	# schermata iniziale. `vyraxen` resta per compatibilita' con la UI.
	monsters = {
		"vyraxen": vyraxen,
		"kharja": _load("res://data/kharja.json"),
		"dygorax": _load("res://data/dygorax.json"),
		"toramat": _load("res://data/toramat.json"),
	}
	loadouts = _load("res://data/loadouts.json")
	equipment_it = _load("res://data/equipment_it.json").get("texts", {})
	for key in hunters:
		if key.begins_with("_"):
			continue
		for card in hunters[key].get("deck", []):
			card["hunter"] = key
			action_by_id[int(card["id"])] = card
	# Le carte potenziamento entrano nello stesso indice: una volta scelte in fase
	# di costruzione del mazzo sono carte azione a tutti gli effetti.
	# Nota: gli id TTS si ripetono fra cacciatori (212900 e' sia Blade Surge di
	# Dareon che Double Shot di Mirah), percio' `upgrades.json` porta un id globale.
	var upgrade_data: Dictionary = _load("res://data/upgrades.json")
	for card in upgrade_data.get("cards", []):
		card["upgrade"] = true
		upgrades[int(card["id"])] = card
		action_by_id[int(card["id"])] = card


func _load(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("Db: impossibile leggere %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Db: JSON non valido in %s" % path)
		return {}
	return parsed


func rules() -> Dictionary:
	return common.get("rules", {})


## I dati di un mostro. Il motore passa sempre da qui: aggiungerne uno e' un
## file in piu' piu' una riga nel registro.
func monster(id: String) -> Dictionary:
	return monsters.get(id, {})


## Sceglie il mostro dello scontro. Da chiamare prima di leggere stance,
## behavior, peril o objective.
func select_monster(id: String) -> void:
	if monsters.has(id):
		selected = id
	else:
		push_error("Db: mostro sconosciuto %s" % id)


func current() -> Dictionary:
	return monsters.get(selected, {})


func hunter(id: String) -> Dictionary:
	return hunters.get(id, {})


func action(id: int) -> Dictionary:
	return action_by_id.get(id, {})


func monster_level(level: int) -> Dictionary:
	return current().get("levels", {}).get(str(level), {})


## Alcune carte behavior compaiono nel mod TTS con piu' CardID ma sono la stessa
## carta fisica (stessa immagine): gli alias riportano al record canonico.
func behavior(id: int) -> Dictionary:
	var key := str(id)
	var aliases: Dictionary = current().get("behavior_aliases", {})
	if aliases.has(key):
		key = str(int(aliases[key]))
	return current().get("behaviors", {}).get(key, {})


func peril(id: int) -> Dictionary:
	return current().get("perils", {}).get(str(id), {})


func objective(id: int) -> Dictionary:
	return current().get("objectives", {}).get(str(id), {})


## Percorso dell'illustrazione di una carta azione.
## Gli asset sono in JPEG dove non serve trasparenza, in PNG altrove.
func card_art(card_id: int) -> String:
	var card := action(card_id)
	if card.has("art"):
		return String(card["art"])
	var hunter_id := String(card.get("hunter", "dareon"))
	for ext in [".jpg", ".png"]:
		var path := "res://art/%s/action_%d%s" % [hunter_id, card_id, ext]
		if ResourceLoader.exists(path):
			return path
	return ""


## Equipaggiamento e potenziamenti disponibili per un cacciatore a un dato livello
## di aggression (in Expedition il livello della forge combacia con quello del
## mostro, Regolamento p.66).
func loadout_options(hunter_id: String, level: int) -> Dictionary:
	var h: Dictionary = loadouts.get("hunters", {}).get(hunter_id, {})
	var shared: Dictionary = loadouts.get("shared", {})
	var forge_level := maxi(level, 1)
	return {
		"weapons": _by_level(h.get("weapons", []), forge_level),
		"armor": _by_level(shared.get("armor", []), forge_level),
		"helm": _by_level(shared.get("helm", []), forge_level),
		"potions": _by_level(shared.get("potion", []), forge_level),
		"masteries": h.get("masteries", []),
		"upgrades": upgrades_for(hunter_id),
		"upgrade_slots": int(loadouts.get("upgrades_per_level", {}).get(str(level), 0)),
	}


## I potenziamenti di un cacciatore, in ordine di track.
func upgrades_for(hunter_id: String) -> Array:
	var out: Array = []
	for id in upgrades:
		if String(upgrades[id].get("hunter", "")) == hunter_id:
			out.append(upgrades[id])
	out.sort_custom(func(a, b): return String(a["track"]) + a["name"] < String(b["track"]) + b["name"])
	return out


func _by_level(items: Array, level: int) -> Array:
	var out: Array = []
	for item in items:
		if int(item.get("level", 1)) == level:
			out.append(item)
	return out


## Testo di una carta in italiano dove la traduzione c'e', altrimenti l'originale
## inglese stampato sulla carta. I termini di gioco (struggle, stamina, aggro,
## threatened, Assist, Volley e i tipi di carta) restano in inglese come nel
## regolamento italiano.
func card_text(card: Dictionary, key: String = "it") -> String:
	if card.has(key):
		return String(card[key])
	# Equipaggiamento: la traduzione si cerca per testo inglese.
	var original := String(card.get("text", ""))
	if equipment_it.has(original):
		return String(equipment_it[original])
	# Ripiego: per le mastery il testo originale sta su una chiave diversa.
	for fallback in ["text", key.replace("it_", "") + "_text"]:
		if card.has(fallback):
			return String(card[fallback])
	return ""


## "attack"/"maneuver" -> offensive, "dodge"/"parry" -> defensive
static func is_defensive(card_type: String) -> bool:
	return card_type == "dodge" or card_type == "parry"


static func is_offensive(card_type: String) -> bool:
	return card_type == "attack" or card_type == "maneuver"
