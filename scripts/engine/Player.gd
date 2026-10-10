class_name PrimalPlayer
extends RefCounted
## Stato di un cacciatore durante uno scenario.

var id: String                     ## "dareon" / "mirah"
var name: String
var seat: int                      ## indice nell'ordine di turno

## Posizione: indice 0..3 di una casella fissa della plancia.
var position: int = 0

var deck: Array[int] = []          ## id carte, [0] = cima
var hand: Array[int] = []
var discard: Array[int] = []       ## [0] = cima della pila degli scarti
var sequence: Array[int] = []      ## carte giocate questo turno, in ordine

var damage: int = 0                ## segnalini damage sulla plancia cacciatore
var stamina_token: int = 0
var threatened: bool = false
var burning: bool = false
var ko: bool = false
var ko_flipped: bool = false       ## segnalino KO girato sul lato bianco
var out_of_game: bool = false      ## armor e helm entrambi esauriti

var armor_depleted: bool = false
var helm_depleted: bool = false

var mastery_counters: int = 0
var mastery_focused: bool = false

## Bullet (Heleren): risorsa personale sul tracciato della sua plancia, che
## arriva a 3. Non e' stamina — si spende solo dove la carta lo dice.
var bullets: int = 0
## Quanti se ne sono spesi in questo turno: Replenishment li restituisce tutti.
var bullets_spent_this_turn: int = 0
## Segnalini defense (Glossario p.108): contano come carte difensive nella
## sequenza per il *prossimo* check di attrition, poi si scartano.
var defense_tokens: int = 0
var potions: Array[Dictionary] = []
var consumed_this_round: bool = false
var assisted_this_turn: bool = false
var revived_this_turn: bool = false

## Modificatori temporanei accumulati da carte giocate.
## Ognuno: {"type": "attack"/"any"/..., "n": -1, "duration": "turn"/"next_card"}
var cost_modifiers: Array[Dictionary] = []
var free_next: Array[Dictionary] = []   ## {"type"/"trait": ..., } gioca gratis la prossima carta
var pending_bonus_refill: int = 0
var next_card_keywords: Array[String] = []
var pending_on_next: Array[Dictionary] = []
var sequence_limit_bonus: int = 0
var maneuver_struggle_bonus: int = 0
var attrition_prevented: bool = false
var move_cost_override: int = -1

## Vincoli imposti dalle behavior di Kharja, tutti per il turno in corso.
var can_be_assisted: bool = true
var skip_movement: bool = false
var skip_turn: bool = false
## Se non e' vuoto, la stamina per il movimento si genera solo scartando una
## carta di questo tipo (Ember Dash: solo dodge).
var movement_payment_type: String = ""
## Pressure (Dygorax): {"kind": "defensive", "damage": N}. Se la carta
## successiva della sequenza non e' di quel tipo, il danno arriva.
var pending_next_card: Dictionary = {}
## Segnalini strain (Thoreg): al prossimo riempimento della mano si scartano
## tutti e si pesca una carta in meno per ognuno (Glossario p.113).
var strain: int = 0
## Bonus temporaneo al danno della weapon (Dragon Bane, Chase): dura il turno.
var weapon_damage_bonus: int = 0
## Maelstorm (Karah): la prossima battle dance del turno vale doppio.
var double_next_battle_dance: bool = false


## Equipaggiamento e mazzo scelti in fase di costruzione. Se vuoto si usa la
## dotazione di partenza del cacciatore (come al livello di aggression 0).
var loadout: Dictionary = {}


func data() -> Dictionary:
	return Db.hunter(id)


func weapon() -> Dictionary:
	return loadout.get("weapon", data().get("weapon", {}))


func mastery() -> Dictionary:
	return loadout.get("mastery", data().get("mastery", {}))


func weapon_level() -> int:
	return int(weapon().get("level", 1))


func base_weapon_damage() -> int:
	return int(weapon().get("damage", 0)) + weapon_damage_bonus


func max_health() -> int:
	var total := 0
	if not armor_depleted:
		total += int(loadout.get("armor", data().get("armor", {})).get("health", 0))
	if not helm_depleted:
		total += int(loadout.get("helm", data().get("helm", {})).get("health", 0))
	return total


func is_critical() -> bool:
	return max_health() > 0 and damage >= max_health() - 1


func hand_limit() -> int:
	return int(data().get("hand_limit", Db.rules().get("hand_limit", 5)))


func sequence_limit() -> int:
	return int(data().get("sequence_limit", Db.rules().get("sequence_limit", 5))) + sequence_limit_bonus


## Alcune carte non contano per il limite di mano (Tenacity di Thoreg).
func cards_against_hand_limit() -> int:
	var n := 0
	for cid in hand:
		if String(Db.action(cid).get("passive", "")) != "ignores_hand_limit":
			n += 1
	return n


func defensive_in_hand() -> int:
	var n := 0
	for cid in hand:
		if Db.is_defensive(String(Db.action(cid).get("type", ""))):
			n += 1
	return n


func defensive_in_sequence() -> int:
	var n := 0
	for cid in sequence:
		var card := Db.action(cid)
		if not Db.is_defensive(String(card.get("type", ""))):
			continue
		n += 1
		# Mettle vale due difensive, ma solo con la salute critica.
		var extra: Dictionary = card.get("counts_as_defensive", {})
		if not extra.is_empty() \
				and (String(extra.get("condition", "")) != "critical_health" or is_critical()):
			n += int(extra.get("n", 1)) - 1
	# Alcune carte, dalla cima degli scarti, contano come difensive nella
	# sequenza (Ranged Position di Ljonar, Ranged di Heleren). Il flag sta sulla
	# carta: sono due carte diverse con lo stesso mestiere, e cablare un id
	# lasciava fuori la seconda.
	if not discard.is_empty() \
			and bool(Db.action(discard[0]).get("counts_as_defensive_on_top", false)):
		n += 1
	n += defense_tokens
	return n


func aggro_icons_in_sequence() -> int:
	var n := 0
	for cid in sequence:
		if bool(Db.action(cid).get("aggro", false)):
			n += 1
	return n


## Stamina che questa carta genera se scartata. Alcune ne generano di piu' se
## servono a pagare un tipo preciso (Exertion di Heleren su un attack, Limitless
## Stamina di Thoreg, Stamina Surge di Ljonar).
func stamina_of(card_id: int, paying_for: String = "") -> int:
	var card := Db.action(card_id)
	var bonus: Dictionary = card.get("stamina_bonus", {})
	if bonus.is_empty() or String(bonus.get("type", "")) != paying_for:
		return int(card.get("stamina", 0))
	# Stamina Boost di Thoreg vale il doppio solo con la mastery focalizzata.
	if bonus.has("condition") \
			and not (String(bonus["condition"]) == "mastery_focused" and mastery_focused):
		return int(card.get("stamina", 0))
	return int(bonus.get("stamina", 0))


## Stamina totale generabile scartando tutte le carte in mano.
func available_stamina(paying_for: String = "") -> int:
	var total := stamina_token
	for cid in hand:
		total += stamina_of(cid, paying_for)
	return total


func bullet_max() -> int:
	return int(data().get("bullet_track", 0))


func cost_of(card_id: int) -> int:
	var card := Db.action(card_id)
	var cost := int(card.get("cost", 0))
	var type := String(card.get("type", ""))
	for m in cost_modifiers:
		var t := String(m.get("type", "any"))
		if t == "any" or t == type:
			cost += int(m.get("n", 0))
	return maxi(0, cost)


func is_free(card_id: int) -> bool:
	var card := Db.action(card_id)
	for f in free_next:
		if f.has("type") and String(f["type"]) == String(card.get("type", "")):
			return true
		if f.has("trait") and String(f["trait"]) in card.get("traits", []):
			return true
	return false


func clear_turn_modifiers() -> void:
	var kept: Array[Dictionary] = []
	for m in cost_modifiers:
		if String(m.get("duration", "turn")) == "permanent":
			kept.append(m)
	cost_modifiers = kept
	free_next.clear()
	next_card_keywords.clear()
	assisted_this_turn = false
	revived_this_turn = false
	pending_on_next.clear()
	sequence_limit_bonus = 0
	maneuver_struggle_bonus = 0
	attrition_prevented = false
	move_cost_override = -1
	can_be_assisted = true
	skip_movement = false
	skip_turn = false
	movement_payment_type = ""
	pending_next_card = {}
	weapon_damage_bonus = 0
	bullets_spent_this_turn = 0
	double_next_battle_dance = false


func consume_next_card_modifiers() -> void:
	var kept: Array[Dictionary] = []
	for m in cost_modifiers:
		if String(m.get("duration", "turn")) != "next_card":
			kept.append(m)
	cost_modifiers = kept
	free_next.clear()
	next_card_keywords.clear()
