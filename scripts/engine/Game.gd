class_name PrimalGame
extends RefCounted
## Motore di gioco per uno scenario Expedition di Primal: The Awakening.
##
## Struttura del round (Regolamento p.17-18):
##   1 Consume  2 Upkeep del mostro  3 Turni dei giocatori  4 Fine del round
## Struttura del turno (p.19):
##   Movimento -> Azione -> Attrition -> Fine del turno

signal log_line(text: String)
signal state_changed()
signal choice_required(choice: Dictionary)
signal scenario_ended(victory: bool, reason: String)
## Una carta behavior si e' attivata e va girata a faccia in su.
signal behavior_revealed(behavior: Dictionary)
## Un colpo e' andato a segno: chi lo tira, chi lo incassa, quanto pesa.
## `state_changed` dice che qualcosa e' cambiato, non chi ha colpito chi: serve
## alla plancia per far scattare la miniatura giusta. Gli id sono quelli dei
## cacciatori, oppure "monster".
signal blow(attacker_id: String, target_id: String, amount: int)
## Il check di attrition si e' risolto: quali carte sono uscite, quante difensive
## c'erano in sequenza e com'e' finita. Al tavolo quelle carte si girano e si
## guardano; a schermo, senza questo, il danno arrivava dal nulla.
signal attrition_resolved(outcome: Dictionary)

enum Phase { SETUP, CONSUME, UPKEEP, MOVEMENT, ACTION, ATTRITION, TURN_END, ROUND_END, OVER }

const SECTORS := ["front", "flank", "rear", "flank"]

## Danno che non arriva dal mostro: mazzo esaurito, burning, terreni, carte
## proprie. Serve alla plancia per non far scattare avanti il mostro a vuoto.
const SELF_INFLICTED := ["fatigue", "burning", "synaerea", "wildmaw", "effetto carta"]

## Priorita' di risoluzione degli effetti simultanei (Regolamento p.35):
## stance, poi peril, poi behavior, poi tutte le altre carte.
const PRIO_STANCE := 0
const PRIO_PERIL := 1
const PRIO_BEHAVIOR := 2
const PRIO_OTHER := 3

var rng := RandomNumberGenerator.new()
var journal: Array[String] = []

# --- stato generale ---
var level: int = 0
var round_no: int = 0
var phase: int = Phase.SETUP
var players: Array[PrimalPlayer] = []
var active_index: int = 0
var first_player_index: int = 0
var aggro_index: int = 0
var finished: bool = false
var victory: bool = false

# --- mostro ---
var monster_health: int = 0
var stance_index: int = 0          ## 0..2
var stance_damage: int = 0         ## segnalini damage sulla stance corrente
var monster_counters: int = 0      ## segnalini sul mostro (Kharja: scalano il danno)
var monster_id: String = "vyraxen" ## quale mostro si sta affrontando
## Quale delle due expedition del mostro si gioca: cambia il terreno iniziale.
var expedition: String = "1"


## Il nome da mostrare nei log. Sta nei dati, non nel codice: e' cio' che
## permette di aggiungere un mostro senza toccare il motore.
func monster_name() -> String:
	return String(Db.monster(monster_id).get("name", "Il mostro"))

var struggle: int = 0
var monster_facing: int = 0        ## casella verso cui e' rivolto il fronte
var monster_damage_bonus: int = 0  ## bonus temporaneo al valore damage

## Stati del mostro (Glossario). Non sono status generici: ognuno colpisce un
## componente preciso del tavolo.
var monster_vulnerable: bool = false      ## raddoppia una singola fonte di danno
## Confuse (Thoreg): annulla il prossimo effetto boost del mostro e decade
## all'inizio del round successivo.
var monster_confused: bool = false
var stunned_behaviors: Array[int] = []    ## slot behavior che non si innescano questo round
var blinded_perils: Dictionary = {}       ## id peril -> posto del giocatore che la sbloccherà

# --- mazzi del mostro ---
var behavior_deck: Array[int] = []
var behavior_discard: Array[int] = []
var behavior_slots: Array[int] = [-1, -1, -1]
var behavior_triggered: Array[bool] = [false, false, false]

# --- attrition ---
var attrition_deck: Array[int] = []   ## indici in `attrition_cards`
## Le carte attrition di questa partita: quelle comuni, piu' le speciali del mostro.
var attrition_cards: Array = []
var attrition_discard: Array[int] = []

# --- tavolo ---
var terrain: Array[Array] = [[], [], [], []]   ## per casella, lista di tipi
## Segnalini damage sulle caselle: le stance di Kharja piazzano terreno fuoco
## "in ogni settore danneggiato". Massimo 1 per casella, come dice la carta.
var sector_damage: Array[int] = [0, 0, 0, 0]
## Segnalini dust (Dygorax): massimo 2 per casella. All'inizio della fase
## Attrition ognuno annulla una carta difensiva nella sequenza di chi e' li'.
var dust: Array[int] = [0, 0, 0, 0]
## Livello di hardening (Toramat, Dygorax). A 3 il mostro diventa *hardened*.
var hardening: int = 0
## Segnalini acceleration (Toramat): ognuno da' 1 struggle in piu' nell'upkeep.
var acceleration: int = 0
## Settore da cui e' stato appena rimosso un terreno, per le carte che dicono
## "in quel settore" dopo averlo tolto.
var _remembered_sector: int = -1
## Ultimo giocatore verso cui il mostro si e' girato: le carte lo chiamano "that player".
var _last_target: int = -1
## Chi sta subendo il danno in questo momento: serve alle carte che reagiscono
## al colpo di un compagno (Bulwark).
var _last_victim: int = -1
## Il valore della carta attrition peggiore appena rivelata: Judgement rimuove
## tanto struggle quanto quello.
var _last_attrition_level: int = 0
## Carte con un limite di una volta per turno (Not This Time!).
var _used_this_turn: Array[int] = []
var objective_counters: Dictionary = {}        ## id objective -> contatori
var objectives_completed: Array[int] = []

# --- interazione ---
## Quando il motore ha bisogno di una decisione emette `choice_required` e si
## sospende finche' la UI non chiama `answer()`. Con `auto_resolve` attivo
## (test headless) le scelte vengono risolte da un'euristica senza sospendersi.
signal choice_made(result: Variant)

var auto_resolve: bool = false
var pending_choice: Dictionary = {}
var _resolving_reactions: bool = false
## Keep Your Distance chiude la fase azione: si aspetta che la carta appena
## giocata abbia finito di risolversi.
var _end_action_after_card: bool = false
## Guardia contro la ricorsione di Resilience (pescare puo' far male).
var _offering_resilience: bool = false
## Tackle: sconto e stealth offerti da un altro giocatore sul pagamento in corso.
var _pending_payment_discount: int = 0
var _pending_stealth: bool = false
## Carte che questo turno non innescano le reazioni legate al tipo (stealth).
var _stealth_cards: Array[int] = []


## Chiede una decisione e restituisce la risposta.
##   kind "pay"     -> Array[int] di carte da scartare per generare `cost` stamina
##   kind "cards"   -> Array[int] di carte scelte fra `cards` (min..max)
##   kind "player"  -> int, il posto (seat) del giocatore scelto
##   kind "confirm" -> bool
##   kind "sector"  -> int, la casella scelta fra `options`
##   kind "order"   -> int, l'indice dell'effetto da risolvere per primo
func _ask(request: Dictionary) -> Variant:
	if auto_resolve:
		return _auto_answer(request)
	pending_choice = request
	choice_required.emit(request)
	var result: Variant = await choice_made
	pending_choice = {}
	return result


## Risposta della UI a `choice_required`.
func answer(result: Variant) -> void:
	choice_made.emit(result)


## Euristica usata nei test headless e come rete di sicurezza.
func _auto_answer(request: Dictionary) -> Variant:
	match String(request.get("kind", "")):
		"pay":
			# Scarta prima le carte che generano piu' stamina, per spenderne meno.
			var pool: Array = (request.get("cards", []) as Array).duplicate()
			pool.sort_custom(func(a, b):
				return int(Db.action(a).get("stamina", 0)) > int(Db.action(b).get("stamina", 0)))
			var chosen: Array[int] = []
			var got := int(request.get("tokens", 0))
			for cid in pool:
				if got >= int(request.get("cost", 0)):
					break
				chosen.append(int(cid))
				got += int(Db.action(cid).get("stamina", 0))
			return chosen
		"cards":
			var cards: Array = request.get("cards", [])
			var want := int(request.get("min", 0))
			var picked: Array[int] = []
			for i in mini(want, cards.size()):
				picked.append(int(cards[i]))
			return picked
		"player":
			var options: Array = request.get("options", [])
			return int(options[0]) if not options.is_empty() else -1
		"confirm":
			return bool(request.get("default", false))
		"sector":
			var sectors: Array = request.get("options", [])
			return int(sectors[0]) if not sectors.is_empty() else -1
		"order":
			return 0
		"notice":
			return null
	return null


# =====================================================================
#  SETUP
# =====================================================================

## `loadouts` (opzionale) associa l'id del cacciatore alla dotazione scelta in
## fase di costruzione: {"weapon":..., "armor":..., "helm":..., "mastery":...,
## "deck":[id...], "potions":[...]}.
func setup(hunter_ids: Array, aggression_level: int = 0, seed_value: int = 0,
		loadouts: Dictionary = {}) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	Db.select_monster(monster_id)
	level = aggression_level
	players.clear()
	for i in hunter_ids.size():
		var p := PrimalPlayer.new()
		p.id = String(hunter_ids[i])
		p.seat = i
		p.name = String(Db.hunter(p.id).get("name", p.id))
		p.position = 0            # tutti nel settore front (Regolamento p.15, punto 3)
		p.loadout = loadouts.get(p.id, {})
		if p.loadout.has("deck"):
			for cid in p.loadout["deck"]:
				p.deck.append(int(cid))
		else:
			for card in Db.hunter(p.id).get("deck", []):
				p.deck.append(int(card["id"]))
		_shuffle(p.deck)
		for potion in p.loadout.get("potions", Db.hunter(p.id).get("potions", [])):
			p.potions.append(potion)
		players.append(p)

	var lv := Db.monster_level(level)
	monster_health = int(lv.get("health", 10))
	stance_index = 0
	stance_damage = 0
	monster_counters = 0
	struggle = 0
	monster_facing = 0
	monster_damage_bonus = 0
	monster_vulnerable = false
	monster_confused = false
	stunned_behaviors.clear()
	blinded_perils.clear()

	behavior_deck.clear()
	for bid in lv.get("behavior_deck", []):
		behavior_deck.append(int(bid))
	_shuffle(behavior_deck)
	behavior_discard.clear()
	for i in 3:
		behavior_slots[i] = await _draw_behavior()
		behavior_triggered[i] = false

	# Il mazzo attrition e' condiviso, ma alcuni mostri ne sostituiscono una parte
	# con carte proprie (Toramat, Regolamento p.98).
	attrition_cards.clear()
	for card in Db.common.get("attrition_deck", []):
		attrition_cards.append(card)
	var special: Dictionary = Db.monster(monster_id).get("attrition", {})
	if not special.is_empty():
		var to_replace := int(special.get("count", 0))
		var value := int(special.get("replace_value", 1))
		for i in attrition_cards.size():
			if to_replace <= 0:
				break
			if int(attrition_cards[i].get("value", 0)) == value:
				attrition_cards[i] = special["card"]
				to_replace -= 1
		_log("Mazzo attrition: %d carte speciali di %s al posto di altrettante di valore %d."
			% [int(special.get("count", 0)), monster_name(), value])
	attrition_deck.clear()
	for i in attrition_cards.size():
		attrition_deck.append(i)
	_shuffle(attrition_deck)
	attrition_discard.clear()

	terrain = [[], [], [], []]
	# Terreno iniziale dello scenario (Regolamento, setup dell'Expedition): i
	# settori nei dati sono relativi al fronte, e al setup il fronte e' la
	# casella 0.
	var exp: Dictionary = Db.monster(monster_id).get("expeditions", {}).get(expedition, {})
	for piece in exp.get("terrain", []):
		terrain[int(piece.get("sector", 0)) % 4].append(String(piece.get("type", "rock")))
	if not exp.is_empty():
		_log("Terreno dello scenario: %s." % exp.get("name", expedition))
	sector_damage = [0, 0, 0, 0]
	dust = [0, 0, 0, 0]
	hardening = 0
	acceleration = 0
	_remembered_sector = -1
	_last_target = -1
	objective_counters.clear()
	objectives_completed.clear()

	aggro_index = 0
	first_player_index = 0
	round_no = 0
	finished = false
	victory = false

	for p in players:
		await _refill_hand(p)

	_log("Setup completato: %s contro %s (livello %d)." % [_player_names(), monster_name(), level])
	await _apply_stance_on_reveal(true)
	await begin_round()


func _player_names() -> String:
	var names: Array[String] = []
	for p in players:
		names.append(p.name)
	return ", ".join(names)


# =====================================================================
#  ROUND
# =====================================================================

func begin_round() -> void:
	if finished:
		return
	round_no += 1
	if round_no > int(Db.rules().get("rounds", 10)):
		_end_scenario(false, "Il round 10 e' terminato: i cacciatori non reggono piu' lo scontro.")
		return
	_log("--- Round %d ---" % round_no)
	monster_damage_bonus = 0
	if monster_confused:
		monster_confused = false
		_log("Il segnalino confuse di %s viene scartato." % monster_name())
	# Peril In the Clutches of Fire (Kharja, Stance I).
	await _trigger_perils("round_start")
	if finished:
		return
	if round_no == 1:
		var opening: Array = current_stance().get("on_round_1", [])
		if not opening.is_empty():
			await _run_effects(opening, null, {})
	for p in players:
		p.consumed_this_round = false
	phase = Phase.CONSUME
	_emit()


## Fase 1. La UI chiama await consume() per ogni pozione, poi await finish_consume_phase().
func consume(player: PrimalPlayer, potion_index: int) -> bool:
	if phase != Phase.CONSUME or player.consumed_this_round:
		return false
	if potion_index < 0 or potion_index >= player.potions.size():
		return false
	var potion: Dictionary = player.potions[potion_index]
	_log("%s consuma %s." % [player.name, potion.get("name", "pozione")])
	await _run_effects(potion.get("effects", []), player, {})
	player.potions.remove_at(potion_index)
	player.consumed_this_round = true
	_emit()
	return true


func finish_consume_phase() -> void:
	if phase != Phase.CONSUME:
		return
	phase = Phase.UPKEEP
	await _monster_upkeep()


## Fase 2 (Regolamento p.17).
func _monster_upkeep() -> void:
	if round_no > 1:
		var lowest := 99
		for slot in 3:
			var bid := behavior_slots[slot]
			if bid >= 0:
				lowest = mini(lowest, int(Db.behavior(bid).get("refresh", 99)))
		for slot in 3:
			var bid := behavior_slots[slot]
			if bid >= 0 and int(Db.behavior(bid).get("refresh", 99)) == lowest:
				_log("Upkeep: scartata %s (refresh %d)." % [Db.behavior(bid).get("name", "?"), lowest])
				behavior_discard.push_front(bid)
				behavior_slots[slot] = await _draw_behavior()
				behavior_triggered[slot] = false
				await _check_enter_play(slot)

	await _monster_gain_struggle(players.size(), "upkeep")
	if acceleration > 0:
		await _monster_gain_struggle(acceleration, "acceleration")
	await _apply_infuriate()
	if finished:
		return

	first_player_index = aggro_index
	active_index = first_player_index
	# Waiting Game (Mirah) si rivela adesso: l'ordine del round e' appena stato
	# deciso, e chi la ha puo' scegliere di giocare per ultimo.
	await _out_of_turn_offered("round_order_set", {})
	await _begin_turn()


## Infuriate X/Y/Z (Glossario): se la peril in gioco ha questa keyword, durante
## l'upkeep il mostro guadagna struggle extra in base alle carte aggro che i
## giocatori hanno complessivamente in mano.
func _apply_infuriate() -> void:
	var stance := current_stance()
	if not stance.has("peril"):
		return
	var thresholds: Array = Db.peril(int(stance["peril"])).get("infuriate", [])
	if thresholds.size() < 3:
		return
	var aggro_cards := 0
	for p in players:
		for cid in p.hand:
			if bool(Db.action(cid).get("aggro", false)):
				aggro_cards += 1
	var extra := 0
	if aggro_cards >= int(thresholds[2]):
		extra = 3
	elif aggro_cards >= int(thresholds[1]):
		extra = 2
	elif aggro_cards >= int(thresholds[0]):
		extra = 1
	if extra > 0:
		_log("Infuriate: %d carte aggro in mano ai cacciatori." % aggro_cards)
		await _monster_gain_struggle(extra, "infuriate")


# =====================================================================
#  TURNO DEL GIOCATORE
# =====================================================================

func active_player() -> PrimalPlayer:
	return players[active_index]


func _begin_turn() -> void:
	var p := active_player()
	if p.out_of_game:
		await _advance_turn()
		return
	if p.ko:
		if not p.ko_flipped:
			p.ko_flipped = true
			_log("%s e' KO: gira il segnalino e passa il turno." % p.name)
			await _advance_turn()
			return
		# Rise
		p.ko = false
		p.ko_flipped = false
		_log("%s si rialza e torna in battaglia." % p.name)
		await _refill_hand(p)
		await _advance_turn()
		return

	for pid in blinded_perils.keys():
		if int(blinded_perils[pid]) == p.seat:
			blinded_perils.erase(pid)
			_log("%s torna attiva: il blind e' scaduto." % Db.peril(int(pid)).get("name", "La peril"))
	p.clear_turn_modifiers()
	p.sequence.clear()
	_used_this_turn.clear()
	_log("Turno di %s (settore %s)." % [p.name, sector_of(p.position)])

	# Reazioni legate all'inizio del turno in un settore.
	var sector := sector_of(p.position)
	if sector == "front":
		_queue_reaction("turn_start_front")
	elif sector == "rear":
		_queue_reaction("turn_start_rear")
	else:
		_queue_reaction("turn_start_flank")
	# Varianti "se c'e' almeno un giocatore in quel settore" (Glossario p.93):
	# guardano il tavolo, non solo chi ha il turno.
	for other in players:
		if other.ko or other.out_of_game:
			continue
		var s2 := sector_of(other.position)
		if s2 == "rear" and not "any_turn_start_rear" in _reaction_queue:
			_queue_reaction("any_turn_start_rear")
		elif s2 == "flank" and not "any_turn_start_flank" in _reaction_queue:
			_queue_reaction("any_turn_start_flank")

	# Terreni che si fanno sentire a inizio turno (Regolamento p.89).
	if has_terrain(p.position, "baethanis"):
		_heal(p, p.weapon_level())
		_log("%s si cura di %d nel baethanis." % [p.name, p.weapon_level()])
	if has_terrain(p.position, "synaerea") and p.deck.size() + p.discard.size() > 0:
		var pay: bool = await _ask({
			"kind": "confirm",
			"prompt": "%s: subire %d danni per pescare 1 (synaerea)?" % [p.name, p.weapon_level()],
			"player": p.seat,
			"default": false,
		})
		if pay:
			await _suffer(p, p.weapon_level(), "synaerea")
			await _draw_cards(p, 1)

	# Taunt (Ljonar): un altro giocatore puo' prendersi addosso il mostro.
	await _taunt_offered()
	# Outflank: chi non ha il turno puo' scartarla per spostarsi adesso.
	await _out_of_turn_offered("other_turn_start", {"active": p.seat})
	# Reclaim: alcune condizioni si verificano proprio adesso (Unseen guarda se
	# inizi il turno nel settore di qualcun altro).
	await _reclaim_offered(p)

	# Objective che si offre a inizio turno (Crash on the Rocks di Toramat).
	await _offer_turn_start_objective(p)

	# Precision Draw: inizio turno, se e' la carta in cima agli scarti.
	if not p.discard.is_empty() and p.discard[0] == 178402:
		_log("Precision Draw: %s pesca 2." % p.name)
		await _draw_cards(p, 2)

	# Ultimate Shot focalizzata: Start: Volley 2.
	if p.mastery_focused and p.id == "mirah":
		await _volley(p, 2)

	phase = Phase.MOVEMENT
	# Line of Fire (Heleren) si rivela qui, se la mano e' abbastanza piena.
	await _out_of_turn_offered("movement_start", {"active": p.seat})
	await _resolve_reactions()
	if finished:
		return
	# Le behavior di inizio turno di Kharja possono togliere il turno o la fase
	# movimento al giocatore attivo.
	if p.skip_turn:
		_log("%s salta il turno." % p.name)
		await _end_turn()
		return
	if p.skip_movement:
		_log("%s salta la fase movimento." % p.name)
		phase = Phase.ACTION
	_emit()


## Fase Movimento. `to_position` = -1 per restare fermi.
func move(to_position: int) -> bool:
	if phase != Phase.MOVEMENT:
		return false
	var p := active_player()
	if to_position < 0:
		if not p.threatened:
			p.threatened = true
			_log("%s resta fermo e diventa threatened." % p.name)
			_queue_reaction("threatened")
		else:
			_log("%s resta fermo (gia' threatened)." % p.name)
			_queue_reaction("threatened")
		phase = Phase.ACTION
		await _resolve_reactions()
		_emit()
		return true

	if not _is_adjacent(p.position, to_position):
		return false
	var free := not p.free_next.is_empty() and p.free_next.any(func(f): return f.has("free_move"))
	var move_cost := p.move_cost_override if p.move_cost_override >= 0 \
		else int(Db.rules().get("move_cost", 1))
	# Sand: uscire dalla sabbia costa una stamina in piu'.
	if has_terrain(p.position, "sand"):
		move_cost += 1
	# Alcune carte modificano il costo di movimento mentre sono in cima agli scarti
	# (es. Lateral Move di Dareon).
	if not p.discard.is_empty():
		for ability in Db.action(p.discard[0]).get("abilities", []):
			if String(ability.get("trigger", "")) == "move_cost" \
					and String(ability.get("from", "")) == "discard_top":
				for effect in ability.get("effects", []):
					if String(effect.get("op", "")) == "set_move_cost":
						move_cost = int(effect.get("n", 0))
	if not free:
		# Ember Dash: in questo turno la stamina del movimento si genera solo
		# scartando una carta del tipo indicato.
		if p.movement_payment_type != "":
			if not (await _discard_of_type(p, p.movement_payment_type, "muoversi")):
				return false
		elif not (await _pay_stamina(p, move_cost)):
			return false
	p.position = to_position
	if p.threatened:
		p.threatened = false
		_log("%s si muove: rimuove threatened." % p.name)
	_log("%s si sposta nel settore %s." % [p.name, sector_of(p.position)])
	# Fog: si entra nella nebbia e si diventa threatened.
	if has_terrain(p.position, "fog"):
		p.threatened = true
		_log("%s entra nella nebbia e diventa threatened." % p.name)
		_queue_reaction("threatened")
	phase = Phase.ACTION
	_queue_reaction("player_moved")
	await _resolve_reactions()
	_emit()
	return true


## Fase Azione: gioca una carta dalla mano nella sequenza.
func play_card(card_id: int) -> bool:
	if phase != Phase.ACTION:
		return false
	var p := active_player()
	if not p.hand.has(card_id):
		return false
	if p.sequence.size() >= sequence_limit_of(p):
		return false
	var card := Db.action(card_id)
	var refusal := why_not_playable(p, card_id)
	if refusal != "":
		_log("Non puoi giocare %s: %s." % [card.get("name", "?"), refusal])
		return false

	var cost := 0 if p.is_free(card_id) or _chain_free(p, card_id) else cost_of(p, card_id)
	# Costo variabile X: e' il giocatore a decidere quanto spendere.
	_last_variable_payment = 0
	if bool(card.get("variable_cost", false)) and not p.is_free(card_id):
		var budget := p.available_stamina()
		var choices: Array[String] = []
		for x in range(0, mini(budget, 5) + 1):
			choices.append("Paga %d" % x)
		var picked: int = await _ask({
			"kind": "order",
			"prompt": "%s ha costo X: quanta stamina spendi?" % card.get("name", "?"),
			"player": p.seat,
			"options": choices,
		})
		_last_variable_payment = clampi(picked, 0, choices.size() - 1)
		cost = _last_variable_payment
	p.hand.erase(card_id)
	if cost > 0 and not (await _pay_stamina(p, cost, card_id)):
		p.hand.append(card_id)
		return false
	p.consume_next_card_modifiers()

	p.sequence.append(card_id)
	_log("%s gioca %s." % [p.name, card.get("name", "?")])
	# Pressure: la carta appena giocata soddisfa (o no) l'obbligo in sospeso.
	if not p.pending_next_card.is_empty():
		var duty := p.pending_next_card
		p.pending_next_card = {}
		var card_type := String(card.get("type", ""))
		var ok := Db.is_defensive(card_type) if String(duty["kind"]) == "defensive" \
			else card_type == String(duty["kind"])
		if ok:
			_log("%s soddisfa l'obbligo con %s." % [p.name, card.get("name", "?")])
		else:
			await _suffer(p, int(duty["damage"]), "behavior")

	if bool(card.get("aggro", false)):
		aggro_index = p.seat
		_log("%s prende il segnalino aggro." % p.name)
		_queue_reaction("aggro_played")

	# Tutte le abilita' innescate da questa carta sono simultanee: si risolvono
	# per priorita' e, a parita', nell'ordine scelto dal giocatore (p.24 e p.35).
	await _resolve_simultaneous(_collect_card_triggers(p, card), p)
	# Solo dopo si applica l'effetto legato al colore della carta, cosi' i bonus
	# ai danni raccolti dalle abilita' entrano nell'attacco (p.21).
	await _resolve_color_effect(p, card)

	var stealth := _stealth_cards.has(card_id)
	if stealth:
		_stealth_cards.erase(card_id)
		_log("  %s ha stealth: non innesca le reazioni di tipo." % card.get("name", "?"))
	match String(card.get("type", "")) if not stealth else "":
		"attack": _queue_reaction("attack_played")
		"maneuver": _queue_reaction("maneuver_played")
		"parry":
			_queue_reaction("parry_played")
			await _intuition_offered(p)
		"dodge": _queue_reaction("dodge_played")

	# Carte di altri giocatori che reagiscono alla combo appena completata.
	await _out_of_turn_offered("other_combo")

	# Reazioni "carta offensive" e "due carte offensive di fila" (Glossario p.93):
	# guardano il tipo, non il colore, e la seconda scatta dopo la seconda carta.
	if not stealth and Db.is_defensive(String(card.get("type", ""))):
		_queue_reaction("defensive_played")
	if not stealth and Db.is_offensive(String(card.get("type", ""))):
		_queue_reaction("offensive_played")
		if p.sequence.size() >= 2 \
				and Db.is_offensive(String(Db.action(p.sequence[-2]).get("type", ""))):
			_queue_reaction("two_offensive_played")
	# Combined Assault (Mirah) aspetta due **attack** di fila, di chiunque.
	if not stealth and String(card.get("type", "")) == "attack" and p.sequence.size() >= 2 \
			and String(Db.action(p.sequence[-2]).get("type", "")) == "attack":
		await _out_of_turn_offered("two_attacks_played", {"who": p.seat})

	await _resolve_reactions()
	await _reclaim_offered(p)
	if _end_action_after_card:
		_end_action_after_card = false
		if phase == Phase.ACTION:
			await end_action_phase()
	_emit()
	return true


## Un altro giocatore assiste il giocatore attivo scartando una carta con Assist.
func assist(helper: PrimalPlayer, card_id: int) -> bool:
	if helper == active_player() or helper.assisted_this_turn or helper.ko:
		return false
	if not active_player().can_be_assisted:
		return false
	if not helper.hand.has(card_id):
		return false
	if not "assist" in Db.action(card_id).get("keywords", []):
		return false
	await _discard_from_hand(helper, card_id)
	helper.assisted_this_turn = true
	_log("%s assiste %s." % [helper.name, active_player().name])
	await _draw_cards(active_player(), 1)
	_emit()
	return true


## Azione Revive (una volta per turno, stesso settore, 2 stamina).
func revive(target: PrimalPlayer) -> bool:
	if phase != Phase.ACTION:
		return false
	var p := active_player()
	if p.revived_this_turn or not target.ko or target.position != p.position:
		return false
	if not (await _pay_stamina(p, int(Db.rules().get("revive_cost", 2)))):
		return false
	p.revived_this_turn = true
	if not target.ko_flipped:
		target.ko_flipped = true
		_log("%s rianima %s (segnalino KO girato)." % [p.name, target.name])
	else:
		target.ko = false
		target.ko_flipped = false
		await _refill_hand(target)
		_log("%s rianima %s, che torna in battaglia." % [p.name, target.name])
	_emit()
	return true


func end_action_phase() -> void:
	if phase != Phase.ACTION:
		return
	var p := active_player()

	# Chi aveva un obbligo in sospeso e chiude la fase senza soddisfarlo, incassa.
	if not p.pending_next_card.is_empty():
		var duty := p.pending_next_card
		p.pending_next_card = {}
		await _suffer(p, int(duty["damage"]), "behavior")

	# Guardian Blade: alla fine della fase azione.
	if p.sequence.has(178107):
		var n := mini(p.aggro_icons_in_sequence(), 3)
		if n > 0:
			var other := _other_player(p)
			if other != null:
				_log("Guardian Blade: %s fa pescare %d a %s." % [p.name, n, other.name])
				await _draw_cards(other, n)

	if p.hand.size() >= 2 and p.stamina_token < int(Db.rules().get("stamina_token_max", 1)):
		p.stamina_token += 1
		_log("%s guadagna 1 segnalino stamina." % p.name)

	# Carte in sequenza che aspettano la fine della fase azione (Replenishment).
	for cid in p.sequence.duplicate():
		for ability in Db.action(cid).get("abilities", []):
			if String(ability.get("trigger", "")) == "end_of_action_phase":
				_log("  %s." % Db.action(cid).get("name", "?"))
				await _run_effects(ability.get("effects", []), p, {})

	phase = Phase.ATTRITION
	await _attrition_check(p)


## Fase Attrition (Regolamento p.27).
func _attrition_check(p: PrimalPlayer) -> void:
	var reveal := 2 if p.threatened else 1
	var worst := -1
	var required_type := ""
	var shown: Array[int] = []
	for i in reveal:
		var idx := _draw_attrition()
		if idx < 0:
			break
		# Deny (Karah): si puo' buttare la carta rivelata e pescarne un'altra.
		var deny := {}
		if await _out_of_turn_offered("attrition_revealed", deny):
			if deny.get("reroll_attrition", false):
				attrition_discard.push_front(idx)
				idx = _draw_attrition()
				if idx < 0:
					break
		var card: Dictionary = attrition_cards[idx]
		var value := int(card.get("value", 0))
		# Le carte speciali chiedono un colore preciso invece di una difensiva qualsiasi.
		if card.has("type"):
			required_type = String(card["type"])
		attrition_discard.push_front(idx)
		shown.append(idx)
		worst = maxi(worst, value)
	if worst < 0:
		worst = 0
	_last_attrition_level = worst
	var defensive := p.defensive_in_sequence()
	if required_type != "":
		defensive = 0
		for cid in p.sequence:
			if String(Db.action(cid).get("type", "")) == required_type:
				defensive += 1
		_log("Carta attrition speciale: contano solo le carte %s." % required_type)
	# Dust: ogni segnalino nel settore mette un disrupt su una carta difensiva
	# della sequenza, che per questo check non conta (Regolamento p.95).
	if dust[p.position] > 0:
		var disrupted := mini(dust[p.position], defensive)
		if disrupted > 0:
			_log("Dust: %d carte difensive di %s vengono disrupt." % [disrupted, p.name])
		defensive -= disrupted
	_log("Attrition: valore %d, carte difensive nella sequenza %d." % [worst, defensive])
	# Al tavolo le carte attrition si girano e si guardano: qui vanno raccontate,
	# altrimenti il danno arriva senza che si sia visto da dove.
	var outcome := {
		"player": p.seat, "threatened": p.threatened, "cards": shown,
		"worst": worst, "defensive": defensive, "required_type": required_type,
		"damage": 0, "prevented_by": "",
	}
	if defensive < worst:
		# Long Range in cima agli scarti previene il danno da attrition.
		if p.attrition_prevented:
			_log("Il danno da attrition e' prevenuto da un effetto in gioco.")
			outcome["prevented_by"] = "un effetto in gioco"
		elif not p.discard.is_empty() and bool(
				Db.action(p.discard[0]).get("prevents_attrition_on_top", false)):
			var shield_card := Db.action(p.discard[0])
			_log("%s previene il danno da attrition." % shield_card.get("name", "?"))
			outcome["prevented_by"] = String(shield_card.get("name", "?"))
		elif await _cover_fire_offered(p, worst):
			outcome["prevented_by"] = "Cover Fire"
		elif await _rock_offered(p):
			_log("La roccia si sbriciola e para il colpo.")
			outcome["prevented_by"] = "la roccia"
		else:
			outcome["damage"] = monster_damage() + _peril_attrition_bonus()
	# Prima si racconta, poi si incassa: il pannello deve essere in piedi quando
	# il danno arriva, non comparire dopo.
	# Glossario p.108: si dice che il giocatore attivo ha **evitato** il danno da
	# attrition se non lo subisce, sia perche' ha retto sia perche' qualcosa lo
	# ha prevenuto. Le carte che aspettano quel momento scattano qui.
	if int(outcome["damage"]) == 0:
		for cid in p.sequence.duplicate():
			for ability in Db.action(cid).get("abilities", []):
				if String(ability.get("trigger", "")) == "attrition_avoided":
					_log("  %s." % Db.action(cid).get("name", "?"))
					await _run_effects(ability.get("effects", []), p, {})
	if p.defense_tokens > 0:
		_log("%s scarta %d segnalino/i defense a fine check."
			% [p.name, p.defense_tokens])
		p.defense_tokens = 0
	attrition_resolved.emit(outcome)
	await _notice({"topic": "attrition", "outcome": outcome})
	if int(outcome["damage"]) > 0:
		await _suffer(p, int(outcome["damage"]), "attrition")
		# Hardening di Dygorax: la peril reagisce al danno da attrition.
		await _trigger_perils("attrition_damage")
	phase = Phase.TURN_END
	await _end_turn()


func _end_turn() -> void:
	var p := active_player()
	# Wildmaw: chi finisce il turno threatened dentro le fauci ci lascia qualcosa.
	if not p.ko and not p.out_of_game and p.threatened and has_terrain(p.position, "wildmaw"):
		_log("%s e' threatened nel wildmaw." % p.name)
		await _suffer(p, p.weapon_level(), "wildmaw")
	if not p.ko:
		# 1. scartare la sequenza (l'ultima giocata finisce in cima agli scarti)
		for cid in p.sequence:
			p.discard.push_front(cid)
		p.sequence.clear()
		# 2. ripristinare la mano
		await _refill_hand(p)
		# 3. il mostro si gira verso il giocatore aggro
		await _turn_monster_to(players[aggro_index].position, "rotazione di fine turno")
	await _advance_turn()


func _advance_turn() -> void:
	if finished:
		return
	var next := (active_index + 1) % players.size()
	if next == first_player_index:
		await _end_round()
	else:
		active_index = next
		await _begin_turn()


func _end_round() -> void:
	phase = Phase.ROUND_END
	_log("Fine del round %d." % round_no)
	_queue_reaction("end_of_round")
	# Peril Fire Breathing (Stance I)
	await _trigger_perils("end_of_round")
	await _resolve_reactions()
	if finished:
		return
	monster_damage_bonus = 0
	# Il fuoco dura un round: rosso -> giallo -> via (Regolamento p.90).
	for pos in 4:
		while terrain[pos].has("fire_spent"):
			terrain[pos].erase("fire_spent")
			_log("Il fuoco nel settore %s si spegne." % sector_of(pos))
		while terrain[pos].has("fire"):
			terrain[pos].erase("fire")
			terrain[pos].append("fire_spent")
	if dust != [0, 0, 0, 0]:
		dust = [0, 0, 0, 0]
		_log("Fine del round: i segnalini dust vengono rimossi.")
	if monster_vulnerable:
		monster_vulnerable = false
		_log("Il segnalino vulnerable viene rimosso a fine round.")
	stunned_behaviors.clear()
	await begin_round()


# =====================================================================
#  RISOLUZIONE CARTE AZIONE
# =====================================================================

func _requirements_met(p: PrimalPlayer, card: Dictionary) -> bool:
	var req: Dictionary = card.get("requires", {})
	if req.is_empty():
		return true
	if req.has("previous_in_sequence"):
		if p.sequence.is_empty():
			return false
		var prev := Db.action(p.sequence[-1])
		if String(prev.get("type", "")) != String(req["previous_in_sequence"]):
			return false
	if bool(req.get("not_aggro_player", false)) and aggro_index == p.seat:
		return false
	return true


## Motivo per cui una carta non e' giocabile adesso, "" se lo e'.
## Il controllo sta qui e non nell'interfaccia: e' una regola, non una comodita'.
func why_not_playable(p: PrimalPlayer, card_id: int) -> String:
	if phase != Phase.ACTION:
		return "non e' la fase Azione"
	if not p.hand.has(card_id):
		return "la carta non e' in mano"
	if p.sequence.size() >= sequence_limit_of(p):
		return "sequenza al limite (%d carte)" % sequence_limit_of(p)
	if has_terrain(p.position, "fire"):
		return "c'e' del fuoco nel tuo settore: non puoi giocare carte"
	var card := Db.action(card_id)
	# Regolamento p.21: le attack si giocano solo da un settore su un lato esposto.
	if String(card.get("type", "")) == "attack" \
			and not sector_of(p.position) in _exposed_sides():
		return "sei su un lato protetto: non puoi giocare attack"
	var req: Dictionary = card.get("requires", {})
	if req.has("previous_in_sequence"):
		var want := String(req["previous_in_sequence"])
		if p.sequence.is_empty():
			return "va giocata dopo una carta %s" % want
		if String(Db.action(p.sequence[-1]).get("type", "")) != want:
			return "la carta precedente deve essere %s" % want
	if bool(req.get("not_aggro_player", false)) and aggro_index == p.seat:
		return "non puoi giocarla mentre hai il segnalino aggro"
	if not p.is_free(card_id) and not _chain_free(p, card_id) \
			and p.available_stamina(String(card.get("type", ""))) < cost_of(p, card_id):
		return "stamina insufficiente"
	return ""


## Effetto legato al colore della carta giocata (Regolamento p.21).
func _resolve_color_effect(p: PrimalPlayer, card: Dictionary) -> void:
	match String(card.get("type", "")):
		"attack":
			# Cyricae: attaccare da qui vale il livello della propria weapon in piu'.
			if has_terrain(p.position, "cyricae"):
				_pending_bonus_damage += p.weapon_level()
				_log("Il cyricae rinforza l'attacco di %s (+%d)." % [p.name, p.weapon_level()])
			_perform_attack(p, card)
		"maneuver":
			await _remove_struggle(1 + p.maneuver_struggle_bonus,
				"%s gioca un maneuver" % p.name, p)
			await _battle_dance(p)


## Raccoglie tutte le abilita' che si attivano giocando `card`: quelle della carta
## stessa, quelle innescate da altre carte nella sequenza, weapon, mastery,
## obiettivo ed effetti in attesa (es. Sharp Shot).
func _collect_card_triggers(p: PrimalPlayer, card: Dictionary) -> Array:
	var items: Array = []

	# effetti in attesa dal turno (Sharp Shot, Targeted Shot)
	var type := String(card.get("type", ""))
	var kept: Array[Dictionary] = []
	for entry in p.pending_on_next:
		var want := String(entry.get("type", "any"))
		if want == "any" or want == type:
			items.append(_pending_effects(PRIO_OTHER, "effetto in attesa",
				entry.get("effects", []), p, {"card": card}))
		else:
			kept.append(entry)
	p.pending_on_next = kept

	# abilita' della carta appena giocata
	if not card.get("effects", []).is_empty():
		items.append(_pending_effects(PRIO_OTHER, String(card.get("name", "?")),
			card["effects"], p, {"card": card}))
	for ability in card.get("abilities", []):
		if ability.has("combo") or ability.has("trigger"):
			continue   # gestite altrove
		if _condition_met(p, ability):
			items.append(_pending_effects(PRIO_OTHER, String(card.get("name", "?")),
				ability.get("effects", []), p, {"card": card}))

	# carte gia' nella sequenza che aspettavano questa carta
	for i in p.sequence.size():
		var other := Db.action(p.sequence[i])
		for ability in other.get("abilities", []):
			if not ability.has("combo"):
				continue
			if _combo_matches(p, ability["combo"], i):
				items.append(_pending_effects(PRIO_OTHER, String(other.get("name", "?")),
					ability.get("effects", []), p, {"card": other}))

	# weapon
	var w := p.weapon()
	if w.has("combo") and _combo_matches_tail(p, w["combo"]) \
			and (not w.has("condition") or _condition_met(p, w)):
		items.append(_pending_effects(PRIO_OTHER, "%s (weapon)" % w.get("name", "?"),
			w.get("effects", []), p, {}, w))

	# mastery focalizzata con abilita' a combo (Massive Blow di Thoreg)
	var mf: Dictionary = p.mastery()
	if p.mastery_focused:
		for ability in mf.get("focused_abilities", []):
			if ability.has("combo") and _combo_matches_tail(p, ability["combo"]):
				items.append(_pending_effects(PRIO_OTHER,
					"%s (mastery)" % mf.get("name", "?"), ability.get("effects", []), p, {}, mf))

	# mastery: accumulo dei segnalini focus
	var m: Dictionary = p.mastery()
	if not p.mastery_focused and m.has("unfocused_combo") and _combo_matches_tail(p, m["unfocused_combo"]):
		items.append({
			"priority": PRIO_OTHER,
			"label": "%s (mastery)" % m.get("name", "?"),
			"kind": "mastery_focus",
			"actor": p,
		})

	# obiettivo attivo (es. Hit the Tail)
	var stance := current_stance()
	if stance.has("objective") and not objectives_completed.has(int(stance["objective"])):
		var oid := int(stance["objective"])
		var obj := Db.objective(oid)
		# Keep Your Distance vale finche' ha spazio: a segnalini pieni non c'e'
		# piu' niente da offrire.
		if obj.has("max_counters") \
				and int(objective_counters.get(oid, 0)) >= int(obj["max_counters"]):
			return items
		for ability in obj.get("abilities", []):
			if not ability.has("combo"):
				continue
			if _combo_matches_tail(p, ability["combo"]) and _condition_met(p, ability):
				items.append(_pending_effects(PRIO_OTHER, String(obj.get("name", "?")),
					ability.get("effects", []), p, {"objective_id": oid}, obj))

	return items


## `source` e' la carta (o weapon/mastery/obiettivo) da cui l'effetto arriva:
## serve solo a far vedere *cosa* si sta scegliendo quando due effetti sono
## simultanei. Il nome da solo non basta — nessuno ricorda a memoria cosa fa
## "Reactive Guard" mentre decide l'ordine.
func _pending_effects(priority: int, label: String, effects: Array,
		actor: PrimalPlayer, ctx: Dictionary, source: Dictionary = {}) -> Dictionary:
	if source.is_empty():
		source = ctx.get("card", {})
	return {
		"priority": priority, "label": label, "kind": "effects",
		"effects": effects, "actor": actor, "ctx": ctx,
		"art": _art_of(source), "text": Db.card_text(source),
	}


## Immagine di una carta. Le carte azione non portano il percorso nei dati: si
## ricava dall'id, ed e' il motivo per cui non basta leggere il campo "art".
func _damage_words(n: int) -> String:
	return "1 danno" if n == 1 else "%d danni" % n


func _art_of(card: Dictionary) -> String:
	if card.has("art"):
		return String(card["art"])
	if card.has("id"):
		return Db.card_art(int(card["id"]))
	return ""


## Risolve un gruppo di effetti simultanei (Regolamento p.35): prima per priorita'
## (stance, peril, behavior, altre carte); a parita' di priorita' l'ordine lo
## sceglie il giocatore, che puo' cosi' massimizzare le proprie combo.
func _resolve_simultaneous(items: Array, chooser: PrimalPlayer) -> void:
	var pool := items.duplicate()
	while not pool.is_empty() and not finished:
		var best := 99
		for it in pool:
			best = mini(best, int(it["priority"]))
		var tier: Array[int] = []
		for i in pool.size():
			if int(pool[i]["priority"]) == best:
				tier.append(i)

		var chosen := tier[0]
		if tier.size() > 1:
			var labels: Array[String] = []
			var arts: Array[String] = []
			var texts: Array[String] = []
			for i in tier:
				labels.append(String(pool[i]["label"]))
				arts.append(String(pool[i].get("art", "")))
				texts.append(String(pool[i].get("text", "")))
			var picked: int = await _ask({
				"kind": "order",
				"prompt": "Scegli quale effetto risolvere per primo",
				"player": chooser.seat if chooser else active_player().seat,
				"options": labels,
				"arts": arts,
				"texts": texts,
			})
			chosen = tier[clampi(picked, 0, tier.size() - 1)]

		var item: Dictionary = pool[chosen]
		pool.remove_at(chosen)
		await _resolve_pending(item)


func _resolve_pending(item: Dictionary) -> void:
	match String(item.get("kind", "effects")):
		"effects":
			_log("  -> %s." % item.get("label", "?"))
			await _run_effects(item.get("effects", []), item.get("actor"), item.get("ctx", {}))
		"mastery_focus":
			var p: PrimalPlayer = item["actor"]
			var m: Dictionary = p.mastery()
			p.mastery_counters += 1
			_log("  -> %s: %d/%d segnalini focus." % [
				m.get("name", "?"), p.mastery_counters, int(m.get("focus", 1))])
			if p.mastery_counters >= int(m.get("focus", 1)):
				p.mastery_focused = true
				p.mastery_counters = 0
				_log("  -> %s e' ora FOCUSED!" % m.get("name", "?"))
				await _run_effects(
					m.get("focused_effects", []).filter(func(e): return not e.has("trigger")), p, {})
		"behavior":
			await _resolve_behavior(int(item["slot"]))


func _condition_met(p: PrimalPlayer, ability: Dictionary) -> bool:
	var cond := String(ability.get("condition", ""))
	match cond:
		"": return true
		"mastery_focused": return p.mastery_focused
		"actor_in_rear": return sector_of(p.position) == "rear"
		"actor_in_front": return sector_of(p.position) == "front"
		"aggro_player_threatened": return players[aggro_index].threatened
		"monster_health_1": return monster_health == 1
		"struggle_per_player": return struggle >= players.size()
		"struggle_at_least_1": return struggle >= 1
		_:
			push_warning("Condizione non implementata: %s" % cond)
			return false
func _combo_matches(p: PrimalPlayer, combo: Array, this_index: int) -> bool:
	var offset := combo.find("this")
	if offset < 0:
		return false
	var start := this_index - offset
	if start < 0 or start + combo.size() > p.sequence.size():
		return false
	for k in combo.size():
		if String(combo[k]) == "this":
			continue
		if not _card_matches_token(p.sequence[start + k], String(combo[k])):
			return false
	# scatta solo quando l'ultima carta del pattern e' quella appena giocata
	return start + combo.size() == p.sequence.size()


## Pattern senza "this" (weapon/mastery): deve combaciare con la coda della sequenza.
func _combo_matches_tail(p: PrimalPlayer, combo: Array) -> bool:
	if p.sequence.size() < combo.size():
		return false
	var start := p.sequence.size() - combo.size()
	for k in combo.size():
		if not _card_matches_token(p.sequence[start + k], String(combo[k])):
			return false
	return true


func _card_matches_token(card_id: int, token: String) -> bool:
	var card := Db.action(card_id)
	var type := String(card.get("type", ""))
	match token:
		"offensive": return Db.is_offensive(type)
		"defensive": return Db.is_defensive(type)
		"aim", "slash": return token in card.get("traits", [])
		_: return type == token


# =====================================================================
#  ATTACCHI, DANNI E FERITE
# =====================================================================

var _pending_bonus_damage: int = 0
var _last_attack_dealt: bool = false


func _perform_attack(p: PrimalPlayer, card: Dictionary) -> void:
	if not sector_of(p.position) in _exposed_sides():
		# La carta era giocabile quando e' stata giocata: sono le abilita'
		# innescate prima della risoluzione che possono spostare il giocatore o
		# girare il mostro. Caso raro (2 volte su 60 partite) ma reale, quindi
		# va detto nel registro invece di sparire in un warning che il
		# giocatore non vede mai.
		_log("L'attacco di %s non va a segno: il settore %s non e' piu' esposto."
			% [p.name, sector_of(p.position)])
		_pending_bonus_damage = 0
		return
	var total := weapon_damage_of(p) + _pending_bonus_damage
	_pending_bonus_damage = 0
	_last_attack_dealt = total > 0
	_log("  %s infligge %d danni." % [p.name, total])
	if total > 0:
		blow.emit(p.id, "monster", total)
	var health_before := monster_health
	await deal_damage_to_monster(total)
	# «Se questo attacco infligge una ferita, ...»: si sa solo adesso.
	if monster_health < health_before:
		for effect in card.get("on_wound", []):
			await _run_effect(effect, p, {"card": card})


## Danno base della weapon, comprese le aure che vengono dalla cima degli scarti
## **degli altri** (Rapid Dash di Ljonar rinforza le armi dei compagni).
## `Player.base_weapon_damage` non puo' saperlo: vede solo se stesso.
func weapon_damage_of(p: PrimalPlayer) -> int:
	var total := p.base_weapon_damage()
	for q in players:
		if q == p or q.out_of_game or q.discard.is_empty():
			continue
		var aura: Dictionary = Db.action(q.discard[0]).get("aura", {})
		if aura.has("weapon_for_others"):
			var n := int(aura["weapon_for_others"])
			if String(aura.get("scale", "")) == "weapon_level":
				n *= q.weapon_level()
			total += n
	return total


## Costo di una carta, tenendo conto anche di quello che concedono le carte in
## cima agli scarti **degli altri** (Assistance di Ljonar sconta gli attack).
## `Player.cost_of` non puo' saperlo: vede solo se stesso.
func cost_of(p: PrimalPlayer, card_id: int) -> int:
	var cost := p.cost_of(card_id)
	var type := String(Db.action(card_id).get("type", ""))
	for q in players:
		if q == p or q.out_of_game or q.discard.is_empty():
			continue
		var aura: Dictionary = Db.action(q.discard[0]).get("aura", {})
		var discount: Dictionary = aura.get("cost_for_others", {})
		if not discount.is_empty() and String(discount.get("type", "any")) in [type, "any"]:
			cost += int(discount.get("n", 0))
	return maxi(cost, 0)


## Bonus ai danni che vengono da una carta in cima agli scarti di qualcuno
## (Attack Plan e Rapid Dash di Ljonar).
func _discard_top_aura(key: String) -> int:
	var total := 0
	for q in players:
		if q.out_of_game or q.discard.is_empty():
			continue
		var aura: Dictionary = Db.action(q.discard[0]).get("aura", {})
		if not aura.has(key):
			continue
		var n := int(aura[key])
		if String(aura.get("scale", "")) == "weapon_level":
			n *= q.weapon_level()
		total += n
	return total


func deal_damage_to_monster(amount: int) -> void:
	amount += _discard_top_aura("damage_to_monster")
	if amount <= 0 or finished:
		return
	# Vulnerable: si puo' scartare il segnalino per raddoppiare questa singola fonte.
	if monster_vulnerable:
		var double: bool = await _ask({
			"kind": "confirm",
			"prompt": "Scartare il segnalino vulnerable per raddoppiare questi %d danni?" % amount,
			"player": active_player().seat,
			"default": true,
		})
		if double:
			monster_vulnerable = false
			amount *= 2
			_log("  Vulnerable: il danno raddoppia a %d." % amount)
	# Shield X (Glossario p.110): la stance corrente toglie X a **ogni** fonte di
	# danno. Si applica per ultimo, dopo il raddoppio di vulnerable: e' l'armatura
	# del mostro, non una proprieta' del colpo.
	var shield := int(current_stance().get("shield", 0))
	if shield > 0:
		var stopped := mini(shield, amount)
		amount = maxi(0, amount - shield)
		_log("  Shield %d: %d danni fermati, ne passano %d." % [shield, stopped, amount])
	if amount <= 0:
		return
	stance_damage += amount
	# Ogni ferita va inflitta una alla volta: la toughness puo' cambiare.
	while true:
		var toughness := current_toughness()
		if toughness <= 0 or stance_damage < toughness:
			break
		stance_damage -= toughness
		# Hardened: il damage accumulato sparisce a ogni ferita, niente riporti.
		if hardened() and stance_damage > 0:
			_log("Hardened: il damage in eccesso (%d) viene rimosso." % stance_damage)
			stance_damage = 0
		await _wound_monster(1)
		if finished:
			return
	_emit()


func _wound_monster(n: int) -> void:
	for i in n:
		if finished:
			return
		monster_health -= 1
		_log("%s subisce una ferita (salute %d)." % [monster_name(), monster_health])
		if monster_health <= 0:
			_end_scenario(true, "%s e' stato abbattuto!" % monster_name())
			return
		# Peril Burning Skin (Kharja): ogni ferita lascia un segnalino.
		await _trigger_perils("monster_wound")
		var stance := current_stance()
		if monster_health <= int(stance.get("progression", 0)) and stance_index < 2:
			await _advance_stance()


func _advance_stance() -> void:
	# Resistant (Glossario p.111): completando la stance il damage in eccesso
	# non passa alla successiva.
	if bool(current_stance().get("resistant", false)) and stance_damage > 0:
		_log("Resistant: il damage in eccesso (%d) non passa alla stance seguente."
			% stance_damage)
		stance_damage = 0
	stance_index += 1
	_log("%s avanza alla Stance %s." % [monster_name(), ["I", "II", "III"][stance_index]])
	await _apply_stance_on_reveal(false)


func _apply_stance_on_reveal(initial: bool) -> void:
	var stance := current_stance()
	if stance.has("on_reveal") and not initial:
		await _run_effects(stance["on_reveal"], null, {})


func current_stance() -> Dictionary:
	var stances: Array = Db.monster_level(level).get("stances", [])
	if stance_index < stances.size():
		return stances[stance_index]
	return {}


func current_toughness() -> int:
	return int(current_stance().get("toughness_per_player", 0)) * players.size()


## Hardened (Glossario p.109): niente stun, niente confuse, niente vulnerable, e
## il damage in eccesso non viene mai riportato. Vale finche' il livello sta al
## massimo del tracciato.
func hardened() -> bool:
	var track: Dictionary = Db.monster(monster_id).get("hardening", {})
	if track.is_empty():
		return false
	return hardening >= int(track.get("hardened_at", 3))


func monster_damage() -> int:
	return int(current_stance().get("damage", 0)) + monster_damage_bonus


## Valore damage del mostro con i modificatori dell'effetto in corso
## (le carte ad aggression alta usano DMG+1, DMG+2, DMGx2).
## `damage_bonus` puo' essere un numero o un valore calcolato ("monster_counters"
## per Kharja). `ctx` porta i flag degli Enhancement, che moltiplicano il danno
## base senza cambiare il testo dell'effetto.
func _damage_from(e: Dictionary, ctx: Dictionary = {}) -> int:
	var dmg := monster_damage() + _amount(e.get("damage_bonus", 0), null)
	var multiplier := int(e.get("damage_multiplier", 1))
	if ctx.has("damage_multiplier"):
		multiplier = int(ctx["damage_multiplier"])
	return dmg * multiplier


func _exposed_sides() -> Array:
	var stance := current_stance()
	# Dragon Scales: mentre Dygorax e' hardened resta esposto solo il rear.
	if hardened() and stance.has("peril"):
		var peril := Db.peril(int(stance["peril"]))
		if peril.has("hardened_exposed") and not blinded_perils.has(int(stance["peril"])):
			return peril["hardened_exposed"]
	return stance.get("exposed", ["front", "rear"])


# =====================================================================
#  STRUGGLE
# =====================================================================

func _monster_gain_struggle(n: int, reason: String) -> void:
	if n <= 0:
		return
	# Sacrifice (Ljonar): si paga col proprio sangue perche' quello struggle
	# non arrivi mai.
	var stop := {"amount": n, "reason": reason}
	if await _out_of_turn_offered("monster_would_gain_struggle", stop) \
			and stop.get("prevented", false):
		_log("Lo struggle di %s viene impedito." % monster_name())
		return
	struggle += n
	_log("%s guadagna %d struggle (%s) -> %d." % [monster_name(), n, reason, struggle])
	var threshold := int(Db.rules().get("unleash_threshold_per_player", 3)) * players.size()
	if struggle >= threshold:
		await _unleash()


func _unleash() -> void:
	# Guardian Shield (Ljonar): chi sta nel front puo' pararlo per tutti.
	var stop := {}
	if await _out_of_turn_offered("would_unleash", stop) and stop.get("prevented", false):
		_log("UNLEASH fermato: nessuno subisce danno.")
		struggle = int(Db.rules().get("unleash_leftover_per_player", 1)) * players.size()
		return
	_log("UNLEASH! Tutti i giocatori subiscono %d danni." % monster_damage())
	for p in players:
		if not p.ko and not p.out_of_game:
			await _suffer(p, monster_damage(), "unleash")
	struggle = int(Db.rules().get("unleash_leftover_per_player", 1)) * players.size()
	_log("Lo struggle scende a %d." % struggle)


func _remove_struggle(n: int, reason: String, source: PrimalPlayer = null) -> void:
	if n <= 0:
		return
	# Thwart: un altro giocatore puo' scartare la carta dalla mano per raddoppiare.
	if source != null:
		for helper in players:
			if helper == source or helper.ko or helper.out_of_game:
				continue
			if not helper.hand.has(178117):
				continue
			var use: bool = await _ask({
				"kind": "confirm",
				"prompt": "%s: scartare Thwart per raddoppiare lo struggle rimosso (%d -> %d)?" % [helper.name, n, n * 2],
				"player": helper.seat,
				"default": false,
			})
			if use:
				await _discard_from_hand(helper, 178117)
				n *= 2
				_log("Thwart: %s raddoppia lo struggle rimosso." % helper.name)
				await _draw_cards(active_player(), 1)
				break
	var removed := mini(n, struggle)
	if removed <= 0:
		return
	struggle -= removed
	_log("Rimossi %d struggle (%s) -> %d." % [removed, reason, struggle])


# =====================================================================
#  CARTE BEHAVIOR
# =====================================================================

var _reaction_queue: Array[String] = []


func _queue_reaction(reaction: String) -> void:
	_reaction_queue.append(reaction)


## Rivela e risolve tutte le behavior innescate dalle reazioni in coda.
func _resolve_reactions() -> void:
	if _resolving_reactions:
		return
	_resolving_reactions = true
	while not _reaction_queue.is_empty() and not finished:
		var reaction: String = _reaction_queue.pop_front()
		# Piu' behavior possono attivarsi sullo stesso evento: si rivelano e si
		# risolvono una alla volta, nell'ordine scelto dai giocatori (p.33).
		var items: Array = []
		for slot in 3:
			var bid := behavior_slots[slot]
			if bid < 0:
				continue
			if stunned_behaviors.has(slot):
				continue      # stordita: non si innesca in questo round
			if String(Db.behavior(bid).get("reaction", "")) == reaction:
				behavior_triggered[slot] = true
				items.append({
					"priority": PRIO_BEHAVIOR,
					"label": String(Db.behavior(bid).get("name", "?")),
					"kind": "behavior",
					"slot": slot,
				})
		if not items.is_empty():
			await _resolve_simultaneous(items, active_player())
	_resolving_reactions = false


func _resolve_behavior(slot: int) -> void:
	var bid := behavior_slots[slot]
	if bid < 0:
		return
	var b := Db.behavior(bid)
	behavior_triggered[slot] = false
	_log("Behavior rivelata: %s." % b.get("name", "?"))
	behavior_revealed.emit(b)
	# Il motore si ferma finche' la carta non e' stata guardata. Serve anche a
	# mettere in fila le cose: la domanda «la scarti?» arriva **dopo**, e si
	# capisce che e' una risposta a questa reazione e non un'altra cosa.
	await _notice({"topic": "behavior", "behavior": b})

	# Carte che si scartano dalla mano quando una behavior viene rivelata.
	var reaction_ctx := {}
	await _out_of_turn_offered("behavior_revealed", reaction_ctx)

	# Peril: reazione alla rivelazione (es. firestorm).
	await _trigger_perils("behavior_revealed", b)

	# 1. Reazione: effetto base + boost
	var removed := false
	var ctx := {"behavior": b, "slot": slot}
	if reaction_ctx.get("cancelled", false):
		ctx["cancelled"] = true
	var boost: Dictionary = b.get("boost", {})
	# Alcuni boost si risolvono solo in certe stance (Fiery Mane ad aggression 2+).
	if boost.has("condition") and not _effect_condition_met(boost, null):
		boost = {}
	var cost := int(boost.get("cost", 0))
	var boosted := not boost.is_empty() and struggle >= cost

	# Alcuni boost (le "Enhancement" delle carte ad aggression alta) non aggiungono
	# un effetto: modificano quello base. Vanno quindi pagati e applicati prima.
	if boosted and bool(boost.get("modifies_base", false)):
		await _remove_struggle(cost, "boost di %s" % b.get("name", "?"))
		_log("  Enhancement: %s" % boost.get("text", ""))
		for key in boost.get("flags", {}):
			ctx[key] = boost["flags"][key]

	if not ctx.get("cancelled", false):
		await _run_effects(b.get("effects", []), null, ctx)
	if ctx.get("removed_from_game", false):
		removed = true

	if ctx.get("cancelled", false):
		boost = {}
	if not boost.is_empty() and not bool(boost.get("modifies_base", false)):
		if boosted:
			await _remove_struggle(cost, "boost di %s" % b.get("name", "?"))
			if monster_confused:
				monster_confused = false
				_log("  Confuse: il boost viene annullato (il costo e' pagato lo stesso).")
			else:
				_log("  Boost: %s" % Db.card_text(boost))
				await _run_effects(boost.get("effects", []), null, ctx)
		else:
			_log("  Struggle insufficiente per il boost (%d/%d)." % [struggle, cost])

	# 2. Rampage: se ne scattano piu' di una, l'ordine lo scelgono i giocatori.
	var rampage: Array = []
	for s in 3:
		var rid := behavior_slots[s]
		if s != slot and rid >= 0 and bool(Db.behavior(rid).get("rampage", false)):
			rampage.append({
				"priority": PRIO_BEHAVIOR,
				"label": "Rampage: %s" % Db.behavior(rid).get("name", "?"),
				"kind": "behavior",
				"slot": s,
			})
	if not rampage.is_empty():
		_log("  Rampage innescato.")
		await _resolve_simultaneous(rampage, active_player())

	# 3. Scarta e ripristina
	if behavior_slots[slot] == bid:
		if not removed:
			behavior_discard.push_front(bid)
		behavior_slots[slot] = await _draw_behavior()
		behavior_triggered[slot] = false
		await _check_enter_play(slot)
	_emit()


## Alcune behavior si innescano appena entrano in uno spazio (Glossario p.93) e
## si risolvono prima di ogni altra: Out of Control e Crashing Charge di Toramat.
func _check_enter_play(slot: int) -> void:
	var bid := behavior_slots[slot]
	if bid < 0:
		return
	if String(Db.behavior(bid).get("reaction", "")) != "on_enter_play":
		return
	behavior_triggered[slot] = true
	await _resolve_behavior(slot)


func _draw_behavior() -> int:
	if behavior_deck.is_empty():
		if behavior_discard.is_empty():
			return -1
		behavior_deck = behavior_discard.duplicate()
		behavior_discard.clear()
		_shuffle(behavior_deck)
		_log("Escalation: il mazzo behavior viene rimescolato.")
		await _trigger_perils("escalation")
		await _monster_gain_struggle(int(Db.rules().get("escalation_struggle", 1)), "escalation")
	return behavior_deck.pop_front()


func _trigger_perils(trigger: String, behavior: Dictionary = {}) -> void:
	var stance := current_stance()
	if not stance.has("peril"):
		return
	if blinded_perils.has(int(stance["peril"])):
		return      # blind: la peril e' considerata blank
	var peril := Db.peril(int(stance["peril"]))
	for ability in peril.get("abilities", []):
		if String(ability.get("trigger", "")) != trigger:
			continue
		if ability.has("tag") and not String(ability["tag"]) in behavior.get("tags", []):
			continue
		if ability.has("condition") and not _condition_met(players[aggro_index], ability):
			continue
		_log("Peril %s si attiva." % peril.get("name", "?"))
		await _run_effects(ability.get("effects", []), null, {})


## Crash on the Rocks: a inizio turno puoi rivelare due carte aggro per mettere
## un segnalino sull'objective. Rivelare non costa nulla, ma lo si chiede lo
## stesso: mostrare la mano e' un'informazione che si da' agli altri.
func _offer_turn_start_objective(p: PrimalPlayer) -> void:
	var stance := current_stance()
	if not stance.has("objective"):
		return
	var oid := int(stance["objective"])
	if objectives_completed.has(oid):
		return
	for ability in Db.objective(oid).get("abilities", []):
		if String(ability.get("trigger", "")) != "turn_start":
			continue
		var req: Dictionary = ability.get("reveal", {})
		var need := int(req.get("n", 1))
		var have := _aggro_in_hand(p) if String(req.get("kind", "")) == "aggro" \
			else _cards_of_kind_in_hand(p, String(req.get("type", "")), String(req.get("kind", "")))
		if have < need:
			continue
		var yes: bool = await _ask({
			"kind": "confirm",
			"prompt": "%s: riveli %d carte %s per %s?"
				% [p.name, need, req.get("kind", req.get("type", "")),
				   Db.objective(oid).get("name", "l'objective")],
			"player": p.seat,
			"default": true,
		})
		if yes:
			_log("%s rivela %d carte aggro." % [p.name, need])
			await _run_effects(ability.get("effects", []), p, {"objective_id": oid})


# =====================================================================
#  BULLET (Heleren)
# =====================================================================

## Reload X: si recuperano X bullet, fino al tetto del tracciato. La mastery
## Precision Reload reagisce proprio a questo, focalizzata e non.
func _reload(p: PrimalPlayer, n: int) -> void:
	if p == null or n <= 0:
		return
	var before := p.bullets
	p.bullets = mini(p.bullets + n, p.bullet_max())
	if p.bullets == before:
		_log("%s ha gia' il tracciato bullet pieno." % p.name)
	else:
		_log("%s fa reload: %d bullet." % [p.name, p.bullets])
	# Arbitraggio: Precision Reload dice «quando fai reload», e l'istruzione c'e'
	# stata anche se il tracciato era pieno e non hai recuperato niente. Letta
	# nell'altro modo, un tracciato pieno bloccherebbe di nascosto una mastery
	# che parla solo di reload.
	_mastery_trigger(p, "reload")
	await _mastery_focused_trigger(p, "reload")
	_emit()


## Spendere bullet. Restituisce quanti se ne sono spesi davvero: le carte dicono
## «puoi spendere», quindi zero e' una risposta valida e non un errore.
func _spend_bullets(p: PrimalPlayer, n: int) -> bool:
	if p == null or n <= 0 or p.bullets < n:
		return false
	p.bullets -= n
	p.bullets_spent_this_turn += n
	_log("%s spende %d bullet (restano %d)." % [p.name, n, p.bullets])
	await _ignite(p)
	_emit()
	return true


## Ignite: scatta quando si spendono bullet, **una volta sola** per spesa anche
## se se ne spende piu' d'uno (Player Reference di Heleren).
func _ignite(p: PrimalPlayer) -> void:
	await _run_effects(p.weapon().get("on_ignite", []), p, {})
	for cid in p.sequence:
		for ability in Db.action(cid).get("abilities", []):
			if String(ability.get("trigger", "")) == "ignite":
				_log("  Ignite: %s." % Db.action(cid).get("name", "?"))
				await _run_effects(ability.get("effects", []), p, {})


## Reclaim (Player Reference di Karah): mentre la carta e' negli scarti, se la
## condizione e' soddisfatta la si puo' rimettere in mano. Il momento in cui
## controllare non e' scritto sulla carta — «in qualunque momento» — quindi lo
## si offre dove la condizione puo' essere appena diventata vera: dopo una carta
## giocata e all'inizio del turno.
func _reclaim_offered(p: PrimalPlayer) -> void:
	for cid in p.discard.duplicate():
		var card := Db.action(cid)
		var rule: Dictionary = card.get("reclaim", {})
		if rule.is_empty():
			continue
		if rule.has("combo") and not _combo_matches_tail(p, rule["combo"]):
			continue
		if String(rule.get("condition", "")) == "sharing_sector" \
				and not _shares_sector(p):
			continue
		var take: bool = await _ask({
			"kind": "confirm",
			"prompt": "%s: riprendere in mano %s? (Reclaim)" % [
				p.name, card.get("name", "?")],
			"player": p.seat,
			"default": true,
			"art": _art_of(card),
			"text": Db.card_text(card),
		})
		if take:
			p.discard.erase(cid)
			p.hand.append(cid)
			_log("%s recupera %s (Reclaim)." % [p.name, card.get("name", "?")])


func _shares_sector(p: PrimalPlayer) -> bool:
	for q in players:
		if q != p and not q.out_of_game and q.position == p.position:
			return true
	return false


## Chain [colore] (Karah): la carta non costa stamina se segue una carta di quel
## colore nella sequenza. Stessa strada per "Wall of Blades", che si sconta da
## sola quando la sequenza e' gia' lunga.
func _chain_free(p: PrimalPlayer, card_id: int) -> bool:
	var card := Db.action(card_id)
	if card.has("chain") and not p.sequence.is_empty():
		if String(Db.action(p.sequence[-1]).get("type", "")) == String(card["chain"]):
			return true
	var free_if: Dictionary = card.get("free_if", {})
	if bool(free_if.get("mastery_focused", false)) and p.mastery_focused:
		return true
	if free_if.has("sequence_at_least") \
			and p.sequence.size() >= int(free_if["sequence_at_least"]):
		return true
	return false


## Overrun (Karah): la miniatura passa attraverso il mostro e finisce nel settore
## opposto. Conta come movimento: toglie threatened e sveglia le reazioni.
func _overrun(p: PrimalPlayer) -> void:
	p.position = posmod(p.position + 2, 4)
	p.threatened = false
	_log("%s attraversa %s e sbuca nel settore %s."
		% [p.name, monster_name(), sector_of(p.position)])
	if has_terrain(p.position, "fog"):
		p.threatened = true
		_log("%s entra nella nebbia e diventa threatened." % p.name)
	_mastery_trigger(p, "overrun")
	await _mastery_focused_trigger(p, "overrun")
	await _out_of_turn_offered("overrun", {"who": p.seat})
	_queue_reaction("player_moved")
	_emit()


## Mastery gia' focalizzate che reagiscono a un evento (Piercing Dash di Karah).
func _mastery_focused_trigger(p: PrimalPlayer, trigger: String) -> void:
	if p == null or not p.mastery_focused:
		return
	var m: Dictionary = p.mastery()
	if String(m.get("focused_trigger", "")) != trigger:
		return
	_log("%s (mastery)." % m.get("name", "?"))
	await _run_effects(m.get("focused_effects", []), p, {})


## Battle Dance (Karah): i maneuver consecutivi fanno danno da soli, alle soglie
## stampate sulla sua plancia cacciatore.
func _battle_dance(p: PrimalPlayer) -> void:
	var dance: Dictionary = Db.hunter(p.id).get("battle_dance", {})
	if dance.is_empty():
		return
	# Quante carte valgono come maneuver di fila. Non e' sempre "una a testa":
	# Dancing Shield e' una parry che conta come maneuver, Double Strike e' un
	# attack che ne vale due. Il campo sta sulla carta, non qui.
	var run := 0
	for i in range(p.sequence.size() - 1, -1, -1):
		var card := Db.action(p.sequence[i])
		var worth := int(card.get("counts_as_maneuver", 0))
		if worth <= 0:
			if String(card.get("type", "")) != "maneuver":
				break
			worth = 1
		run += worth
	var thresholds: Dictionary = dance.get("thresholds", {})
	if not thresholds.has(str(run)):
		return
	var damage := int(thresholds[str(run)])
	if String(dance.get("scale", "")) == "weapon_level":
		damage *= p.weapon_level()
	# Maelstorm raddoppia la prossima battle dance del turno, una volta sola.
	if p.double_next_battle_dance:
		p.double_next_battle_dance = false
		damage *= 2
		_log("Maelstorm: la battle dance raddoppia.")
	_log("Battle dance: %d maneuver di fila, %d danni." % [run, damage])
	await deal_damage_to_monster(damage)
	await _run_effects(p.weapon().get("on_battle_dance", []), p, {})


## Taunt (Glossario): durante il turno di un altro giocatore puoi scartare una
## carta con Taunt: il giocatore attivo pesca 1, tu prendi l'aggro e il mostro si
## gira verso di te.
func _taunt_offered() -> void:
	for holder in players:
		if holder == active_player() or holder.ko or holder.out_of_game:
			continue
		for cid in holder.hand.duplicate():
			if not "taunt" in Db.action(cid).get("keywords", []):
				continue
			var use: bool = await _ask({
				"kind": "confirm",
				"prompt": "%s: provocare il mostro scartando %s?"
					% [holder.name, Db.action(cid).get("name", "?")],
				"player": holder.seat,
				"default": false,
			})
			if not use:
				continue
			await _discard_from_hand(holder, cid)
			await _draw_cards(active_player(), 1)
			aggro_index = holder.seat
			_log("%s provoca %s e prende il segnalino aggro." % [holder.name, monster_name()])
			await _turn_monster_to(holder.position, "taunt")
			await _resolve_reactions()
			return


## Resilience (Glossario): dopo aver subito danno si puo' RIVELARE una carta con
## questa keyword per pescare 1. Rivelare non la toglie dalla mano.
func _resilience_offered(p: PrimalPlayer) -> void:
	# Pescando si puo' esaurire il mazzo, e il fatigue e' altro danno: senza
	# questa guardia Resilience si richiamerebbe all'infinito.
	if _offering_resilience:
		return
	_offering_resilience = true
	await _resilience_body(p)
	_offering_resilience = false


func _resilience_body(p: PrimalPlayer) -> void:
	for cid in p.hand:
		if not "resilience" in Db.action(cid).get("keywords", []):
			continue
		var use: bool = await _ask({
			"kind": "confirm",
			"prompt": "%s: rivelare %s (Resilience) per pescare 1?"
				% [p.name, Db.action(cid).get("name", "?")],
			"player": p.seat,
			"default": true,
			"art": Db.card_art(cid),
			"text": Db.card_text(Db.action(cid)),
		})
		if use:
			_log("%s rivela %s: Resilience." % [p.name, Db.action(cid).get("name", "?")])
			await _draw_cards(p, 1)
		return


## Rock: si puo' togliere il segnalino dal gioco per evitare il danno da attrition.
func _rock_offered(p: PrimalPlayer) -> bool:
	if not terrain[p.position].has("rock"):
		return false
	var use: bool = await _ask({
		"kind": "confirm",
		"prompt": "%s: consumare la roccia del settore per evitare il danno da attrition?" % p.name,
		"player": p.seat,
		"default": true,
	})
	if not use:
		return false
	terrain[p.position].erase("rock")
	_emit()
	return true


## Danno da attrition in piu' dovuto alla peril in gioco (Kharja: 1 per ogni
## segnalino sul mostro). Zero se la peril e' blind o non ne ha.
func _peril_attrition_bonus() -> int:
	var stance := current_stance()
	if not stance.has("peril") or blinded_perils.has(int(stance["peril"])):
		return 0
	var bonus := 0
	for ability in Db.peril(int(stance["peril"])).get("abilities", []):
		if String(ability.get("trigger", "")) == "attrition_damage":
			bonus += int(ability.get("per_counter", 0)) * monster_counters
	return bonus


# =====================================================================
#  EFFETTI
# =====================================================================

func _run_effects(effects: Array, actor: PrimalPlayer, ctx: Dictionary) -> void:
	for e in effects:
		if finished:
			return
		await _run_effect(e, actor, ctx)


func _run_effect(e: Dictionary, actor: PrimalPlayer, ctx: Dictionary) -> void:
	if e.has("condition") and not _effect_condition_met(e, actor):
		return
	var op := String(e.get("op", ""))
	match op:
		"draw":
			var n := _amount(e.get("n", 1), actor)
			if bool(e.get("per_count", false)):
				n = await _count_for(e, actor)
			if e.has("max"):
				n = mini(n, int(e["max"]))
			for t in await _targets(e.get("target", "self"), actor):
				await _draw_cards(t, n)

		"remove_struggle":
			await _remove_struggle(int(e.get("n", 1)), "effetto carta", actor)

		"remove_struggle_per":
			await _remove_struggle(await _count_for(e, actor), "effetto carta", actor)

		"bonus_damage_per":
			var per := int(e.get("n", 0)) * await _count_for(e, actor)
			if e.has("max"):
				per = mini(per, int(e["max"]))
			if String(e.get("scale", "")) == "weapon_level" and actor != null:
				per *= actor.weapon_level()
			_pending_bonus_damage += per

		"heal":
			var amount := int(e.get("n", 0))
			if String(e.get("scale", "")) == "weapon_level" and actor != null:
				amount *= actor.weapon_level()
			_heal(actor, amount)

		"sequence_limit":
			actor.sequence_limit_bonus += int(e.get("n", 1))

		"maneuver_struggle_bonus":
			var bonus := int(e.get("n", 1))
			if bool(e.get("per_count", false)):
				bonus *= await _count_for(e, actor)
			if str(e.get("n", "")) == "variable_payment":
				bonus = mini(_last_variable_payment, int(e.get("max", 99)))
			actor.maneuver_struggle_bonus += bonus

		"if_paid_at_least":
			if _last_variable_payment >= int(e.get("n", 0)):
				await _run_effects(e.get("then", []), actor, ctx)

		"mill_and_damage_per":
			# Hail of Arrows: scarta X carte e colpisce per ogni carta del tipo voluto.
			var milled := await _mill(actor, _last_variable_payment)
			var hits := 0
			for cid in milled:
				var t := String(Db.action(cid).get("type", ""))
				var want := String(e.get("kind", "offensive"))
				if (want == "offensive" and Db.is_offensive(t)) \
						or (want == "defensive" and Db.is_defensive(t)) or want == t:
					hits += 1
			if hits > 0:
				await deal_damage_to_monster(weapon_damage_of(actor) * hits)

		"prevent_attrition":
			actor.attrition_prevented = true

		"set_move_cost":
			actor.move_cost_override = int(e.get("n", 0))

		"free_if":
			if _effect_condition_met({"condition": e.get("condition", "")}, actor):
				pass   # il costo e' gia' stato pagato: nessun effetto retroattivo

		"draw_to_limit":
			var limit := actor.hand_limit() + int(e.get("extra", 0))
			await _draw_cards(actor, maxi(0, limit - actor.hand.size()))

		"discard_any":
			var picked: Array = await _ask({
				"kind": "cards",
				"prompt": "Quali carte scarti dalla mano?",
				"player": actor.seat,
				"cards": actor.hand.duplicate(),
				"min": 0, "max": actor.hand.size(),
				"allow_none": true, "none_label": "Nessuna",
			})
			for cid in picked:
				if actor.hand.has(cid):
					await _discard_from_hand(actor, int(cid))

		"reveal_and_draw":
			var eligible: Array[int] = []
			for cid in actor.hand:
				var card_r := Db.action(cid)
				if e.has("keyword"):
					if String(e["keyword"]) in card_r.get("keywords", []):
						eligible.append(cid)
				elif String(card_r.get("type", "")) == String(e.get("type", "")):
					eligible.append(cid)
			if not eligible.is_empty():
				# Di solito si pesca quanto si rivela; Vanguard rivela una carta
				# e ne fa pescare due, quindi il quanto puo' essere fisso.
				var cap := mini(int(e.get("max", eligible.size())), eligible.size())
				var each := int(e.get("n", 0))
				var shown: Array = await _ask({
					"kind": "cards",
					"prompt": "Rivela fino a %d carte %s" % [cap, e.get("type", "")],
					"player": actor.seat,
					"cards": eligible,
					"min": 0, "max": cap,
					"allow_none": true, "none_label": "Nessuna",
				})
				var how_many := shown.size() * each if each > 0 else shown.size()
				for t in await _targets(String(e.get("target", "self")), actor):
					await _draw_cards(t, how_many)

		"return_from_sequence":
			var candidates: Array[int] = []
			for cid in actor.sequence:
				if e.has("trait") and not String(e["trait"]) in Db.action(cid).get("traits", []):
					continue
				candidates.append(cid)
			if not candidates.is_empty():
				var back: Array = await _ask({
					"kind": "cards",
					"prompt": "Riprendi in mano una carta dalla sequenza",
					"player": actor.seat,
					"cards": candidates,
					"min": 0, "max": 1,
					"allow_none": true, "none_label": "Nessuna",
				})
				if not back.is_empty():
					actor.sequence.erase(int(back[0]))
					actor.hand.append(int(back[0]))

		"play_from_discard":
			var playable: Array[int] = []
			# `from: "top"` guarda solo la carta in cima, non tutta la pila.
			var pile_source: Array = [actor.discard[0]] if String(e.get("from", "")) == "top" \
				and not actor.discard.is_empty() else actor.discard
			for cid in pile_source:
				if String(Db.action(cid).get("type", "")) == String(e.get("type", "")):
					playable.append(cid)
			if not playable.is_empty():
				var pick: Array = await _ask({
					"kind": "cards",
					"prompt": "Gioca una carta %s dagli scarti" % e.get("type", ""),
					"player": actor.seat,
					"cards": playable,
					"min": 0, "max": 1,
					"allow_none": true, "none_label": "Nessuna",
				})
				if not pick.is_empty():
					actor.discard.erase(int(pick[0]))
					actor.hand.append(int(pick[0]))
					actor.free_next.append({"type": String(e.get("type", ""))})

		"mill_then_play":
			var milled := await _mill(actor, int(e.get("n", 1)))
			for cid in milled:
				if String(Db.action(cid).get("type", "")) == String(e.get("type", "")):
					actor.discard.erase(cid)
					actor.hand.append(cid)
					actor.free_next.append({"type": String(e.get("type", ""))})
					break

		"shuffle_discard_into_deck":
			var everything := bool(e.get("all_if_mastery_focused", false)) and actor.mastery_focused
			var moved := 0
			var cap_moved := int(e.get("max", 99))
			for cid in actor.discard.duplicate():
				if moved >= cap_moved:
					break
				if everything or String(Db.action(cid).get("type", "")) == String(e.get("type", "")):
					actor.discard.erase(cid)
					actor.deck.append(cid)
					moved += 1
			_shuffle(actor.deck)
			_log("%s rimescola %d carte nel mazzo." % [actor.name, moved])

		"choose_one":
			var options: Array = e.get("options", [])
			var labels: Array[String] = []
			for o in options:
				labels.append(String(o.get("label", "?")))
			var index: int = await _ask({
				"kind": "order",
				"prompt": "Scegli un effetto",
				"player": actor.seat,
				"options": labels,
			})
			await _run_effects(options[clampi(index, 0, options.size() - 1)].get("effects", []), actor, ctx)

		"monster_gain_struggle":
			var n2 := _amount(e.get("n", 1), actor)
			if String(e.get("scale", "")) == "per_player":
				n2 *= players.size()
			if e.has("per_target"):
				n2 *= (await _targets(String(e["per_target"]), actor)).size()
			await _monster_gain_struggle(n2, "effetto carta")

		"monster_add_counter":
			var n3 := _amount(e.get("n", 1), actor)
			monster_counters += n3
			_log("%s riceve %d segnalino/i (totale %d)." % [monster_name(), n3, monster_counters])

		"monster_damage_bonus":
			monster_damage_bonus += int(e.get("n", 0))
			_log("Il valore damage di %s sale a %d per questo round." % [monster_name(), monster_damage()])

		"bonus_damage":
			var bonus := int(e.get("n", 0))
			if String(e.get("scale", "")) == "weapon_level" and actor != null:
				bonus *= actor.weapon_level()
			if e.has("if_paid_with") and not _paid_with(actor, String(e["if_paid_with"])):
				return
			_pending_bonus_damage += bonus

		"deal_damage_per":
			# Snare: il danno della weapon per ogni difensiva in sequenza.
			var each_dmg := weapon_damage_of(actor) \
				if str(e.get("n", "")) == "base_weapon" else int(e.get("n", 0))
			var times := await _count_for(e, actor)
			if each_dmg > 0 and times > 0:
				await deal_damage_to_monster(each_dmg * times)

		"deal_damage":
			var dmg := 0
			if str(e.get("n", "")) == "base_weapon":
				dmg = weapon_damage_of(actor)
			else:
				dmg = int(e.get("n", 0))
				if String(e.get("scale", "")) == "weapon_level" and actor != null:
					dmg *= actor.weapon_level()
			await deal_damage_to_monster(dmg)

		"reload":
			var many := int(e.get("n", 1))
			if bool(e.get("per_count", false)):
				many = await _count_for(e, actor)
			await _reload(actor, many)

		"gain_defense_token":
			if actor != null:
				actor.defense_tokens += 1
				_log("%s prende un segnalino defense." % actor.name)

		"spend_bullets":
			# «Puoi spendere N bullet: se lo fai, ...». Con `amount: "any"` e'
			# il giocatore a dire quanti (Barrage of Bullets).
			var want := 1
			if String(e.get("amount", "")) == "any":
				var most := actor.bullets
				if most <= 0:
					return
				var picks: Array[String] = []
				for k in range(0, most + 1):
					picks.append("Spendi %d" % k)
				want = clampi(await _ask({
					"kind": "order",
					"prompt": "%s: quanti bullet spendi?" % e.get("label", "Bullet"),
					"player": actor.seat,
					"options": picks,
				}), 0, most)
				if want == 0:
					return
			else:
				want = int(e.get("n", 1))
				if actor.bullets < want:
					return
				if bool(e.get("optional", true)):
					var go: bool = await _ask({
						"kind": "confirm",
						"prompt": "%s: spendere %d bullet? (%s)" % [
							actor.name, want, e.get("label", "effetto")],
						"player": actor.seat,
						"default": true,
					})
					if not go:
						return
			if await _spend_bullets(actor, want):
				_last_variable_payment = want
				await _run_effects(e.get("then", []), actor, ctx)

		"ask_discard_of_type":
			# Strategic Support: chiedi, e l'effetto arriva solo se accetta.
			var asked := await _targets(String(e.get("who", "choose_other")), actor)
			for t in asked:
				var kind := String(e.get("type", "maneuver"))
				if await _discard_of_type(t, kind, "aiutare %s" % actor.name):
					await _run_effects(e.get("then", []), actor, ctx)

		"optional_suffer":
			# «Puoi subire danno: se lo fai, ...». Il danno e' il proprio livello
			# weapon, o quello del mostro se la carta lo dice.
			var hurt := actor.weapon_level() * int(e.get("n", 1))
			if String(e.get("amount", "")) == "monster_damage":
				hurt = monster_damage()
			var take: bool = await _ask({
				"kind": "confirm",
				"prompt": "%s: subire %s? (%s)" % [
					actor.name, _damage_words(hurt), e.get("label", "effetto")],
				"player": actor.seat,
				"default": false,
			})
			if take:
				await _suffer(actor, hurt, "effetto carta")
				await _run_effects(e.get("then", []), actor, ctx)

		"reveal_and_damage":
			# Golden Opportunity: un altro rivela fino a N attack e per ognuna
			# infligge il **suo** danno weapon.
			for t in await _targets(String(e.get("who", "choose_any")), actor):
				var ready: Array[int] = []
				for cid in t.hand:
					if String(Db.action(cid).get("type", "")) == String(e.get("type", "attack")):
						ready.append(cid)
				if ready.is_empty():
					continue
				var cap_r := int(e.get("max", 2))
				var shown_r: Array = await _ask({
					"kind": "cards",
					"prompt": "%s: rivela fino a %d carte %s — ognuna infligge il tuo weapon damage"
						% [t.name, cap_r, e.get("type", "attack")],
					"player": t.seat,
					"cards": ready,
					"min": 0, "max": mini(cap_r, ready.size()),
					"allow_none": true, "none_label": "Nessuna",
				})
				if not shown_r.is_empty():
					await deal_damage_to_monster(weapon_damage_of(t) * shown_r.size())

		"draw_and_check":
			# Dance Step: pesca 1, e se quella carta e' del colore giusto ne pesca
			# un'altra. Serve sapere *cosa* e' arrivato, non solo quante.
			var before_hand := actor.hand.size()
			await _draw_cards(actor, int(e.get("n", 1)))
			var got := false
			for i in range(before_hand, actor.hand.size()):
				if String(Db.action(actor.hand[i]).get("type", "")) == String(e.get("type", "")):
					got = true
			if got:
				await _run_effects(e.get("then", []), actor, ctx)

		"draw_up_to":
			# «Pesca fino ad averne N»: se ne hai gia' di piu', non peschi.
			var want_hand := int(e.get("n", 3))
			await _draw_cards(actor, maxi(0, want_hand - actor.hand.size()))

		"volley":
			await _volley(actor, int(e.get("n", 1)))

		"recycle":
			for t in await _targets(String(e.get("target", "self")), actor):
				await _recycle(t, int(e.get("n", 1)))

		"cost_modifier":
			actor.cost_modifiers.append({
				"type": String(e.get("type", "any")),
				"n": int(e.get("n", 0)),
				"duration": String(e.get("duration", "turn")),
			})

		"free_next":
			var f := {}
			if e.has("type"):
				f["type"] = String(e["type"])
			if e.has("trait"):
				f["trait"] = String(e["trait"])
			if e.has("if_sector") and sector_of(actor.position) != String(e["if_sector"]):
				return
			actor.free_next.append(f)

		"free_move":
			actor.free_next.append({"free_move": true})

		"grant_keyword":
			actor.next_card_keywords.append(String(e.get("keyword", "")))

		"bonus_refill":
			actor.pending_bonus_refill += int(e.get("n", 1))

		"search_deck":
			await _search(actor, actor.deck, e, true)

		"search_discard":
			await _search(actor, actor.discard, e, false)

		"inflict":
			await _inflict_on_monster(String(e.get("status", "")), actor)

		"place_terrain":
			await _place_terrain(String(e.get("terrain", "fire")), String(e.get("where", "front")),
				int(e.get("count", 1)))

		"become_threatened":
			for t in await _targets(String(e.get("who", "active")), actor):
				if not t.threatened:
					t.threatened = true
					_log("%s diventa threatened." % t.name)
					_queue_reaction("threatened")
				else:
					_queue_reaction("threatened")

		"cancel_behavior":
			# Rapid Blow: si salta la fase Reazione della carta behavior; rampage,
			# scarto e ripristino restano (Glossario "Confuse"/annullamento).
			ctx["cancelled"] = true
			_log("  Gli effetti della behavior vengono annullati.")

		"overrun":
			# Karah: si passa attraverso il mostro e si finisce nel settore opposto.
			for t in await _targets(String(e.get("who", "self")), actor):
				var go := true
				if bool(e.get("optional", false)):
					go = await _ask({
						"kind": "confirm",
						"prompt": "%s: fare overrun sul mostro?" % t.name,
						"player": t.seat,
						"default": true,
					})
				if go:
					await _overrun(t)
					await _run_effects(e.get("then", []), t, ctx)

		"grant_stealth_turn":
			# Shadowstrike: tutte le carte di questo turno passano inosservate.
			if actor != null:
				for cid in actor.hand:
					if not _stealth_cards.has(cid):
						_stealth_cards.append(cid)
				_log("Le carte di %s guadagnano stealth per questo turno." % actor.name)

		"reroll_attrition":
			ctx["reroll_attrition"] = true

		"free_move_now":
			# Sharp Reflexes: ci si sposta subito, senza pagare.
			var movers := await _targets(String(e.get("who", "self")), actor)
			var mover := movers[0] if not movers.is_empty() else active_player()
			var dests: Array[int] = [posmod(mover.position - 1, 4), posmod(mover.position + 1, 4)]
			var dest2: int = await _ask({
				"kind": "sector",
				"prompt": "%s: dove ti sposti?" % mover.name,
				"player": mover.seat,
				"options": dests,
				"allow_none": true,
				"none_label": "Resta",
			})
			if dest2 >= 0:
				mover.position = dest2
				mover.threatened = false
				_log("%s si sposta nel settore %s." % [mover.name, sector_of(dest2)])
				_queue_reaction("player_moved")

		"discount_payment":
			_pending_payment_discount += int(e.get("n", 1))

		"grant_stealth":
			_pending_stealth = true

		"discard_strain":
			if actor != null and actor.strain > 0:
				actor.strain = maxi(0, actor.strain - int(e.get("n", 1)))
				_log("%s scarta un segnalino strain (restano %d)." % [actor.name, actor.strain])

		"weapon_damage_bonus":
			var wb := int(e.get("n", 0))
			if String(e.get("scale", "")) == "weapon_level" and actor != null:
				wb *= actor.weapon_level()
			actor.weapon_damage_bonus += wb
			_log("%s: la weapon ottiene +%d danni fino a fine turno." % [actor.name, wb])

		"prevent_damage":
			ctx["prevented"] = true

		"halve_damage":
			ctx["halved"] = true

		"double_next_battle_dance":
			actor.double_next_battle_dance = true

		"become_last_player":
			# Waiting Game: chi la rivela gioca per ultimo in questo round. Il
			# giro parte da `first_player_index`, quindi «ultimo» vuol dire
			# «subito prima di chi apre».
			first_player_index = posmod(actor.seat + 1, players.size())
			active_index = first_player_index
			_log("%s passa in fondo all'ordine di turno." % actor.name)

		"recycle_any":
			var most := actor.hand.size()
			if most > 0:
				await _recycle(actor, most)

		"suffer_self":
			var self_dmg := int(e.get("n", 1))
			if String(e.get("scale", "")) == "weapon_level" and actor != null:
				self_dmg *= actor.weapon_level()
			await _suffer(actor if actor != null else active_player(), self_dmg, "effetto carta")

		"strain":
			for t in await _targets(String(e.get("who", "self")), actor):
				t.strain += int(e.get("n", 1))
				_log("%s prende %d segnalino strain (totale %d)."
					% [t.name, int(e.get("n", 1)), t.strain])

		"acceleration":
			var acc_max := int(Db.monster(monster_id).get("acceleration", {})
				.get("max_per_player", 1)) * players.size()
			var delta := int(e.get("n", 1))
			if String(e.get("scale", "")) == "per_player":
				delta *= players.size()
			acceleration = clampi(acceleration + delta, 0, acc_max)
			_log("Acceleration: %d (max %d)." % [acceleration, acc_max])

		"discard_behaviors_with_reaction":
			var want := String(e.get("reaction", ""))
			for slot in 3:
				var bid2 := behavior_slots[slot]
				if bid2 < 0:
					continue
				if String(Db.behavior(bid2).get("reaction", "")) != want:
					continue
				if ctx.get("slot", -1) == slot:
					continue      # non se stessa
				_log("  %s viene scartata." % Db.behavior(bid2).get("name", "?"))
				behavior_discard.push_front(bid2)
				behavior_slots[slot] = await _draw_behavior()
				behavior_triggered[slot] = false

		"place_behavior_on_top":
			var top_bid := int(e.get("id", 0))
			behavior_deck.push_front(top_bid)
			_log("%s va in cima al mazzo behavior." % Db.behavior(top_bid).get("name", "?"))

		"remove_terrain":
			var spots2: Array[int] = []
			match String(e.get("where", "front")):
				"front": spots2.append(monster_facing)
				"rear": spots2.append(posmod(monster_facing + 2, 4))
				"any":
					for pos2 in 4:
						spots2.append(pos2)
				_: spots2.append(monster_facing)
			var wanted := String(e.get("terrain", "rock"))
			var removed := false
			for spot in spots2:
				if wanted in terrain[spot]:
					terrain[spot].erase(wanted)
					_log("Terreno %s rimosso dal settore %s." % [wanted, sector_of(spot)])
					if bool(e.get("remember", false)):
						_remembered_sector = spot
					removed = true
					break
			if not removed:
				_log("Nessun terreno %s da rimuovere." % wanted)
				if bool(e.get("remember", false)):
					_remembered_sector = monster_facing

		"remove_terrain_or_suffer":
			var spot3 := monster_facing
			var wanted3 := String(e.get("terrain", "rock"))
			var can_remove := wanted3 in terrain[spot3]
			var do_remove := false
			if can_remove:
				do_remove = await _ask({
					"kind": "confirm",
					"prompt": "%s: rimuovi un terreno %s dal settore front per evitare il danno?"
						% [active_player().name, wanted3],
					"player": active_player().seat,
					"default": true,
				})
			if do_remove:
				terrain[spot3].erase(wanted3)
				_log("Terreno %s rimosso dal settore front." % wanted3)
				await _run_effects(e.get("on_removed", []), actor, ctx)
			else:
				for t in await _targets(String(e.get("who", "players_in_front")), actor):
					await _suffer(t, _damage_from(e, ctx), "behavior")

		"hardening":
			var track: Dictionary = Db.monster(monster_id).get("hardening", {})
			var was := hardened()
			if e.has("unless_discard"):
				var duty: Dictionary = e["unless_discard"]
				var payers := await _targets(String(duty.get("who", "aggro")), actor)
				var all_paid := not payers.is_empty()
				for q in payers:
					if not await _discard_of_type(q, String(duty.get("type", "maneuver")),
							"evitare l'hardening"):
						all_paid = false
				if all_paid:
					_log("L'hardening viene evitato.")
					return
			if e.has("set"):
				hardening = clampi(int(e["set"]), 0, int(track.get("max", 3)))
			else:
				hardening = clampi(hardening + int(e.get("n", 1)), 0, int(track.get("max", 3)))
			_log("Livello di hardening: %d." % hardening)
			if hardened() and not was:
				_log("%s diventa HARDENED." % monster_name())
			elif was and not hardened():
				_log("%s non e' piu' hardened." % monster_name())

		"place_dust":
			var spots: Array[int] = []
			match String(e.get("where", "front")):
				"front": spots.append(monster_facing)
				"rear": spots.append(posmod(monster_facing + 2, 4))
				"each_flank":
					spots.append(posmod(monster_facing + 1, 4))
					spots.append(posmod(monster_facing + 3, 4))
				"aggro_sector": spots.append(players[aggro_index].position)
				"targeted_sectors":
					for p in players:
						if not p.ko and not p.out_of_game and not spots.has(p.position) \
								and sector_of(p.position) in ["rear", "flank"]:
							spots.append(p.position)
				_: spots.append(monster_facing)
			for spot in spots:
				if dust[spot] >= 2:
					_log("Il settore %s ha gia' 2 segnalini dust." % sector_of(spot))
				else:
					dust[spot] += 1
					_log("Segnalino dust nel settore %s (%d)." % [sector_of(spot), dust[spot]])

		"suffer_unless_next_card":
			# L'esito dipende dalla carta successiva: si segna e si verifica al
			# momento (o a fine fase azione, se la carta non arriva).
			for t in await _targets(String(e.get("who", "active")), actor):
				t.pending_next_card = {
					"kind": String(e.get("kind", "defensive")),
					"damage": _damage_from(e, ctx),
				}
				_log("%s dovra' giocare una carta %s o subire %d danni."
					% [t.name, t.pending_next_card["kind"], t.pending_next_card["damage"]])

		"suffer_halved_on_discard":
			for t in await _targets(String(e.get("who", "active")), actor):
				var full := _damage_from(e, ctx)
				var halved := int(ceil(float(full) / 2.0))
				var discard_type := String(e.get("discard_type", "dodge"))
				var can := _cards_of_kind_in_hand(t, discard_type, "") > 0
				var pay := false
				if can:
					pay = await _ask({
						"kind": "confirm",
						"prompt": "%s: scarti un %s per dimezzare il danno (%d -> %d)?"
							% [t.name, discard_type, full, halved],
						"player": t.seat,
						"default": true,
					})
				if pay and await _discard_of_type(t, discard_type, "dimezzare il danno"):
					await _suffer(t, halved, "behavior")
				else:
					await _suffer(t, full, "behavior")

		"suffer":
			var flat := int(e.get("flat", -1))
			for t in await _targets(String(e.get("who", "active")), actor):
				await _suffer(t, flat if flat >= 0 else _damage_from(e, ctx), "behavior")

		"suffer_unless_reveal":
			# Rivelare non costa nulla: chi ha la carta la mostra sempre, quindi
			# qui non si chiede niente, si guarda la mano (Glossario "reveal").
			var reveal_kind := String(e.get("kind", ""))
			var reveal_type := String(e.get("type", ""))
			var need := int(e.get("n", 1))
			var only := String(ctx.get("reveal_who", ""))
			if ctx.has("reveal_n"):
				need = int(ctx["reveal_n"])
			for t in await _targets(String(e.get("who", "active")), actor):
				# Enhancement di Onslaught: la richiesta piu' dura vale solo per
				# il giocatore aggro, gli altri restano a una carta.
				var required := need
				if only != "":
					required = need if t.seat == aggro_index else 1
				if _cards_of_kind_in_hand(t, reveal_type, reveal_kind) >= required:
					_log("%s rivela %d %s." % [t.name, required,
						reveal_type if reveal_type != "" else reveal_kind])
					if e.has("on_reveal"):
						await _run_effects(e["on_reveal"], t, ctx)
				else:
					await _suffer(t, _damage_from(e, ctx), "behavior")

		"force_discard":
			for t in await _targets(String(e.get("who", "active")), actor):
				if e.has("n"):
					# Senza un tipo richiesto si scarta a scelta (Barrel Roll).
					for i in int(e["n"]):
						await _discard_any_one(t)
				elif String(e.get("kind", "")) == "defensive":
					await _discard_defensive(t)
				else:
					await _discard_of_type(t, String(e.get("type", "dodge")), "effetto behavior")

		"discard_all_of_type":
			for t in await _targets(String(e.get("who", "active")), actor):
				var type_all := String(e.get("type", "attack"))
				var doomed: Array[int] = []
				for cid in t.hand:
					if String(Db.action(cid).get("type", "")) == type_all:
						doomed.append(cid)
				for cid in doomed:
					await _discard_from_hand(t, cid)
				if not doomed.is_empty():
					_log("%s scarta %d carte %s." % [t.name, doomed.size(), type_all])

		"no_assist":
			for t in await _targets(String(e.get("who", "active")), actor):
				t.can_be_assisted = false
				_log("%s non puo' essere assistito in questo turno." % t.name)

		"skip_movement":
			for t in await _targets(String(e.get("who", "active")), actor):
				if e.has("unless_reveal") \
						and _cards_of_kind_in_hand(t, String(e["unless_reveal"]), "") > 0:
					_log("%s rivela un %s e conserva il movimento."
						% [t.name, e["unless_reveal"]])
					continue
				t.skip_movement = true

		"skip_turn":
			await _skip_turn(e, actor)

		"movement_payment_type":
			for t in await _targets(String(e.get("who", "active")), actor):
				t.movement_payment_type = String(e.get("type", "dodge"))

		"place_sector_damage":
			var pos := monster_facing if String(e.get("where", "front")) == "front" \
				else active_player().position
			if sector_damage[pos] > 0:
				_log("Il settore %s ha gia' un segnalino damage." % sector_of(pos))
			else:
				sector_damage[pos] = 1
				_log("Segnalino damage nel settore %s." % sector_of(pos))

		"clear_sector_damage":
			sector_damage = [0, 0, 0, 0]
			_log("Il damage viene rimosso da tutti i settori.")

		"exhaust_potion":
			for t in await _targets(String(e.get("who", "all")), actor):
				await _exhaust_potion(t)

		"exhaust_potion_or_discard":
			for t in await _targets(String(e.get("who", "all")), actor):
				if t.potions.is_empty():
					await _discard_one_card(t)
				elif t.hand.is_empty():
					await _exhaust_potion(t)
				else:
					var pick: int = await _ask({
						"kind": "order",
						"prompt": "%s: esaurisci una pozione o scarta una carta?" % t.name,
						"player": t.seat,
						"options": ["Esaurisci una pozione", "Scarta una carta"],
					})
					if pick == 0:
						await _exhaust_potion(t)
					else:
						await _discard_one_card(t)

		"discard_top_behavior":
			var top_id := await _draw_behavior()
			if top_id < 0:
				_log("Il mazzo behavior e' vuoto: niente da scartare.")
			else:
				var top_card := Db.behavior(top_id)
				behavior_discard.push_front(top_id)
				var tag := String(e.get("tag", "claw"))
				var has_tag: bool = tag in top_card.get("tags", [])
				_log("Scartata %s dal mazzo behavior (%s %s)."
					% [top_card.get("name", "?"), "ha" if has_tag else "non ha", tag])
				if has_tag:
					await _run_effects(e.get("then", []), actor, ctx)

		"advance_round_marker":
			var target := int(e.get("to", 8))
			if round_no < target:
				_log("Il segnalino round avanza da %d a %d." % [round_no, target])
				round_no = target
			else:
				await _run_effects(e.get("else", []), actor, ctx)

		"unleash":
			await _unleash()

		"end_action_phase":
			# Non si chiude la fase in mezzo alla risoluzione di una carta: si
			# segna, e `play_card` chiude appena ha finito (Regolamento p.24, le
			# abilita' innescate si risolvono tutte prima del passo successivo).
			_end_action_after_card = true

		"suffer_unless_discard":
			var who_discard := String(e.get("who", "active"))
			if ctx.get("retarget", "") != "":
				who_discard = String(ctx["retarget"])
			for t in await _targets(who_discard, actor):
				if e.has("discard_kind"):
					if _cards_of_kind_in_hand(t, "", String(e["discard_kind"])) > 0 \
							and await _discard_defensive(t):
						continue
					await _suffer(t, _damage_from(e, ctx), "behavior")
				else:
					await _suffer_unless_discard(t, String(e.get("discard_type", "dodge")),
						_damage_from(e, ctx))

		"suffer_unless_in_sequence":
			for t in await _targets(String(e.get("who", "active")), actor):
				var found := false
				for cid in t.sequence:
					if String(Db.action(cid).get("type", "")) == String(e.get("type", "dodge")):
						found = true
						break
				if not found:
					await _suffer(t, _damage_from(e, ctx), "behavior")

		"mill":
			for t in await _targets(String(e.get("who", "active")), actor):
				await _mill(t, int(e.get("n", 1)))

		"inflict_burning":
			for t in await _targets(String(e.get("who", "active")), actor):
				await _inflict_burning(t)

		"mill_then_suffer":
			var who_mill := String(e.get("who", "active"))
			if ctx.get("retarget", "") != "":
				who_mill = String(ctx["retarget"])
			var kind := String(e.get("unless_type", e.get("unless_kind", "defensive")))
			for t in await _targets(who_mill, actor):
				await _mill_then_suffer(t, int(e.get("n", 3)), kind, _damage_from(e, ctx))
				# Le versioni ad aggression alta colpiscono due volte chi e' threatened.
				if bool(e.get("repeat_if_threatened", false)) and t.threatened:
					await _mill_then_suffer(t, int(e.get("n", 3)), kind, _damage_from(e, ctx))

		"move_or_suffer":
			for t in await _targets(String(e.get("who", "players_in_front")), actor):
				var dests: Array[int] = [posmod(t.position - 1, 4), posmod(t.position + 1, 4)]
				var payment := String(e.get("payment_type", ctx.get("move_payment_type", "")))
				var can_pay := t.available_stamina() >= int(Db.rules().get("move_cost", 1))
				if payment != "":
					can_pay = false
					for cid in t.hand:
						if String(Db.action(cid).get("type", "")) == payment:
							can_pay = true
							break
				var dest := -1
				if can_pay:
					dest = await _ask({
						"kind": "sector",
						"prompt": "%s: muoviti (1 stamina) o subisci %d danni" % [t.name, monster_damage()],
						"player": t.seat,
						"options": dests,
						"allow_none": true,
						"none_label": "Subisci %d danni" % monster_damage(),
					})
				var moved := false
				if dest >= 0:
					if payment == "":
						moved = await _pay_stamina(t, int(Db.rules().get("move_cost", 1)), -1, "movimento forzato")
					else:
						moved = await _discard_of_type(t, payment, "muoversi")
				if moved:
					t.position = dest
					t.threatened = false
					_log("%s e' costretto a muoversi nel settore %s." % [t.name, sector_of(dest)])
					_queue_reaction("player_moved")
				else:
					await _suffer(t, _damage_from(e, ctx), "behavior")

		"monster_turn_to":
			var criteria := String(e.get("criteria", "active"))
			if criteria == "actor" and actor != null:
				_last_target = actor.seat
				await _turn_monster_to(actor.position, "Taunt")
			elif criteria == "active":
				_last_target = active_player().seat
				await _turn_monster_to(active_player().position, "Wrath of the Dragon")
			elif criteria == "most_aggro_in_hand":
				var loudest: PrimalPlayer = null
				for p in players:
					if p.ko or p.out_of_game:
						continue
					if loudest == null or _aggro_in_hand(p) > _aggro_in_hand(loudest):
						loudest = p
				if loudest != null:
					_last_target = loudest.seat
					await _turn_monster_to(loudest.position, "Raging Havoc")
			elif criteria == "fewest_defensive_in_hand":
				var best: PrimalPlayer = null
				for p in players:
					if p.out_of_game:
						continue
					if best == null or p.defensive_in_hand() < best.defensive_in_hand():
						best = p
				if best != null:
					await _turn_monster_to(best.position, "Aggression")

		"monster_suffer_wounds":
			await _wound_monster(int(e.get("n", 1)))

		"add_counter":
			var oid := int(ctx.get("objective_id", 2320))
			var counters := int(objective_counters.get(oid, 0)) + int(e.get("n", 1))
			if e.has("max"):
				counters = mini(counters, int(e["max"]))
			objective_counters[oid] = counters
			_log("Obiettivo: %d segnalini." % objective_counters[oid])
			await _check_objective(oid)

		"complete_objective":
			var oid2 := int(ctx.get("objective_id", 2320))
			if not objectives_completed.has(oid2):
				objectives_completed.append(oid2)
			_log("Obiettivo completato!")

		"if_objective_completed":
			if objectives_completed.has(int(e.get("objective", 0))):
				await _run_effects(e.get("then", []), actor, ctx)
				ctx["removed_from_game"] = true
			else:
				await _run_effects(e.get("else", []), actor, ctx)

		"remove_from_game":
			ctx["removed_from_game"] = true
			_log("  La carta viene rimossa dal gioco.")

		"repeat_base":
			var b: Dictionary = ctx.get("behavior", {})
			await _run_effects(b.get("effects", []), actor, {})

		"heal_choose":
			var heal := int(e.get("n", 0))
			if _attrition_level() <= 1:
				heal = int(e.get("n_if_low_attrition", heal))
			var seats: Array[int] = []
			for q in players:
				if not q.out_of_game and q.position == actor.position:
					seats.append(q.seat)
			if seats.size() <= 1:
				_heal(actor, heal)
			else:
				var seat: int = await _ask({
					"kind": "player",
					"prompt": "Chi curi di %d?" % heal,
					"player": actor.seat,
					"options": seats,
				})
				_heal(players[seat] if seat >= 0 else actor, heal)

		"optional_pay":
			var extra := int(e.get("stamina", 0))
			if actor != null and actor.available_stamina() >= extra:
				var pay: bool = await _ask({
					"kind": "confirm",
					"prompt": "Pagare %d stamina extra? (%s)" % [extra, e.get("label", "effetto opzionale")],
					"player": actor.seat,
					"default": actor.available_stamina() >= extra + 1,
				})
				if pay and await _pay_stamina(actor, extra, -1, "costo opzionale"):
					_log("  %s paga %d stamina extra." % [actor.name, extra])
					await _run_effects(e.get("then", []), actor, ctx)

		"on_next":
			actor.pending_on_next.append({
				"type": String(e.get("type", "any")),
				"effects": e.get("then", []),
			})

		"recycle_self":
			var self_card: Dictionary = ctx.get("card", {})
			if actor != null and self_card.has("id"):
				var cid2 := int(self_card["id"])
				if actor.hand.has(cid2):
					actor.hand.erase(cid2)
					actor.deck.append(cid2)
					await _draw_cards(actor, 1)
					_log("  %s ricicla %s." % [actor.name, self_card.get("name", "?")])

		"count_as_defensive", "double_struggle_removed":
			# Gestiti in modo contestuale nei rispettivi controlli (attrition, struggle).
			pass

		_:
			push_warning("Effetto non implementato: %s" % op)


## Condizioni che valgono per un singolo effetto.
func _effect_condition_met(e: Dictionary, actor: PrimalPlayer) -> bool:
	match String(e["condition"]):
		"critical_health": return actor != null and actor.is_critical()
		"mastery_focused": return actor != null and actor.mastery_focused
		"mastery_not_focused": return actor != null and not actor.mastery_focused
		"has_strain": return actor != null and actor.strain > 0
		"is_aggro": return actor != null and aggro_index == actor.seat
		"not_aggro": return actor != null and aggro_index != actor.seat
		"monster_no_struggle": return struggle == 0
		"monster_has_struggle": return struggle > 0
		"not_critical_health": return actor != null and not actor.is_critical()
		"paid_at_least_6": return _last_variable_payment >= 6
		"actor_in_front": return actor != null and sector_of(actor.position) == "front"
		"actor_not_in_front": return actor != null and sector_of(actor.position) != "front"
		"paid_with_maneuver": return _paid_with(actor, "maneuver")
		"paid_with_attack": return _paid_with(actor, "attack")
		"not_paid_with_maneuver": return not _paid_with(actor, "maneuver")
		"opening": return actor != null and actor.sequence.size() <= 1
		"defensive_on_discard_top":
			return actor != null and not actor.discard.is_empty() \
				and Db.is_defensive(String(Db.action(actor.discard[0]).get("type", "")))
		# Le behavior di Kharja hanno righe che valgono solo in certe stance.
		"stance_1": return stance_index == 0
		"stance_2": return stance_index == 1
		"stance_3": return stance_index == 2
		"stance_2_or_3": return stance_index >= 1
		"monster_health_1": return monster_health == 1
		"monster_hardened": return hardened()
		"has_bullets": return actor != null and actor.bullets > 0
		"hand_at_least_7": return actor != null and actor.hand.size() >= 7
		"bullets_full": return actor != null and actor.bullets >= actor.bullet_max()
		"bullets_not_full": return actor == null or actor.bullets < actor.bullet_max()
		"another_parry_in_sequence": return _other_in_sequence(actor, "parry") > 0
		"no_other_parry_in_sequence": return _other_in_sequence(actor, "parry") == 0
		"no_bullets": return actor == null or actor.bullets == 0
		# Diversion: l'alternativa scatta solo se il bullet non e' stato speso.
		"no_bullet_spent": return _last_variable_payment == 0
		_:
			push_warning("Condizione di effetto non implementata: %s" % e["condition"])
			return false


## Quante volte contare un bonus "per ogni ...".
## Alcuni conteggi chiedono qualcosa al giocatore, quindi la funzione attende.
func _count_for(e: Dictionary, actor: PrimalPlayer) -> int:
	if actor == null:
		return 0
	var n := 0
	match String(e.get("count", "")):
		"variable_payment":
			n = _last_variable_payment
		"bullet_track":
			n = actor.bullets
		"stance_number":
			n = stance_index + 1
		"attrition_level":
			n = int(_last_attrition_level)
		"own_damage":
			n = actor.damage
		"defensive_in_sequence":
			n = actor.defensive_in_sequence()
		"type_in_other_discard":
			# Concentrated Attack conta negli scarti di **un altro**, scelto.
			var chosen := await _targets("choose_other", actor)
			if not chosen.is_empty():
				for cid in chosen[0].discard:
					if String(Db.action(cid).get("type", "")) == String(e.get("type", "")):
						n += 1
		"bullets_spent":
			n = actor.bullets_spent_this_turn
		"defensive_in_hand":
			n = actor.defensive_in_hand()
		"occupied_sectors":
			var seen: Array[int] = []
			for q in players:
				if not q.ko and not q.out_of_game and not seen.has(q.position):
					seen.append(q.position)
			n = seen.size()
		"aggro_in_discard":
			for cid in actor.discard:
				if bool(Db.action(cid).get("aggro", false)):
					n += 1
		"type_in_sequence":
			for cid in actor.sequence:
				if String(Db.action(cid).get("type", "")) == String(e.get("type", "")):
					n += 1
		"other_cards_with_trait_in_sequence":
			var trait_name := String(e.get("trait", ""))
			for i in actor.sequence.size():
				if i == actor.sequence.size() - 1:
					continue      # la carta appena giocata non conta se stessa
				if trait_name in Db.action(actor.sequence[i]).get("traits", []):
					n += 1
		"type_in_discard":
			for cid in actor.discard:
				if String(Db.action(cid).get("type", "")) == String(e.get("type", "")):
					n += 1
		"trait_in_discard":
			for cid in actor.discard:
				if String(e.get("trait", "")) in Db.action(cid).get("traits", []):
					n += 1
		_:
			push_warning("Conteggio non implementato: %s" % e.get("count", ""))
	return n


func _amount(value: Variant, actor: PrimalPlayer) -> int:
	if typeof(value) == TYPE_STRING:
		match String(value):
			"players_minus_1": return maxi(0, players.size() - 1)
			"players": return players.size()
			"aggro_icons_in_sequence": return actor.aggro_icons_in_sequence() if actor else 0
			"monster_counters": return monster_counters
			"monster_struggle": return struggle
			"own_damage": return actor.damage if actor != null else 0
			"variable_payment": return _last_variable_payment
			_: return 0
	return int(value)


func _targets(who: String, actor: PrimalPlayer) -> Array[PrimalPlayer]:
	var out: Array[PrimalPlayer] = []
	match who:
		"self":
			if actor != null:
				out.append(actor)
		"active":
			out.append(active_player())
		"players_in_front", "players_in_rear", "threatened_players_in_front":
			var want := "front" if who != "players_in_rear" else "rear"
			for p in players:
				if sector_of(p.position) != want or p.ko or p.out_of_game:
					continue
				if who == "threatened_players_in_front" and not p.threatened:
					continue
				out.append(p)
		"players_in_active_sector":
			for p in players:
				if p.position == active_player().position and not p.ko and not p.out_of_game:
					out.append(p)
		"players_in_front_and_flank":
			for p in players:
				if p.ko or p.out_of_game:
					continue
				if sector_of(p.position) in ["front", "flank"]:
					out.append(p)
		"threatened_players":
			for p in players:
				if p.threatened and not p.ko and not p.out_of_game:
					out.append(p)
		"target":
			out.append(players[_last_target] if _last_target >= 0 else active_player())
		"victim":
			# Chi sta subendo il danno adesso (Bulwark fa pescare anche lui).
			out.append(players[_last_victim] if _last_victim >= 0 else active_player())
		"players_in_rear_or_flank":
			for p in players:
				if p.ko or p.out_of_game:
					continue
				if sector_of(p.position) == "rear":
					out.append(p)
			if out.is_empty():
				for p in players:
					if not p.ko and not p.out_of_game and sector_of(p.position) == "flank":
						out.append(p)
		"players_in_remembered":
			var centre2 := _remembered_sector if _remembered_sector >= 0 else monster_facing
			for p in players:
				if p.position == centre2 and not p.ko and not p.out_of_game:
					out.append(p)
		"players_in_dust_sectors":
			for p in players:
				if p.ko or p.out_of_game:
					continue
				if dust[p.position] > 0:
					out.append(p)
		"players_in_flank":
			for p in players:
				if p.ko or p.out_of_game:
					continue
				if sector_of(p.position) == "flank":
					out.append(p)
		"players_in_aggro_sector":
			for p in players:
				if p.position == players[aggro_index].position and not p.ko and not p.out_of_game:
					out.append(p)
		"players_in_damaged_sectors":
			for p in players:
				if p.ko or p.out_of_game:
					continue
				if sector_damage[p.position] > 0:
					out.append(p)
		"aggro":
			out.append(players[aggro_index])
		"players_in_threatened_sectors":
			var sectors: Array[int] = []
			for p in players:
				if p.threatened and not sectors.has(p.position):
					sectors.append(p.position)
			for p in players:
				if p.position in sectors and not p.ko and not p.out_of_game:
					out.append(p)
		"all":
			for p in players:
				if not p.ko and not p.out_of_game:
					out.append(p)
		"choose_other", "choose_any":
			var chooser: PrimalPlayer = actor if actor else active_player()
			var seats: Array[int] = []
			for q in players:
				if q.ko or q.out_of_game:
					continue
				if who == "choose_other" and q == chooser:
					continue
				seats.append(q.seat)
			if seats.size() == 1:
				out.append(players[seats[0]])
			elif seats.size() > 1:
				var seat: int = await _ask({
					"kind": "player",
					"prompt": "Scegli un giocatore",
					"player": chooser.seat,
					"options": seats,
				})
				if seat >= 0:
					out.append(players[seat])
		_:
			if actor != null:
				out.append(actor)
	return out


func _other_player(p: PrimalPlayer) -> PrimalPlayer:
	for q in players:
		if q != p and not q.ko and not q.out_of_game:
			return q
	return null


## Quante carte di quel colore ci sono in sequenza oltre all'ultima giocata.
## Swift Reload chiede «un ALTRO parry», quindi la carta stessa non conta.
func _other_in_sequence(p: PrimalPlayer, type: String) -> int:
	if p == null:
		return 0
	var n := 0
	for i in p.sequence.size() - 1:
		if String(Db.action(p.sequence[i]).get("type", "")) == type:
			n += 1
	return n


func _paid_with(p: PrimalPlayer, type: String) -> bool:
	return _last_payment_types.has(type)


# =====================================================================
#  RISORSE DEL GIOCATORE
# =====================================================================

var _last_payment_types: Array[String] = []
var _last_variable_payment: int = 0   ## quanto e' stato speso per l'ultimo costo X


## Genera stamina scartando carte dalla mano: e' il giocatore a scegliere quali.
## Il segnalino stamina, se presente, viene speso per primo.
func _pay_stamina(p: PrimalPlayer, cost: int, exclude: int = -1, reason: String = "") -> bool:
	_last_payment_types.clear()
	if cost <= 0:
		return true
	# Tackle: un altro giocatore puo' scartare la carta per scontare il costo.
	if players.size() > 1:
		_pending_payment_discount = 0
		_pending_stealth = false
		if await _out_of_turn_offered("other_pays_stamina"):
			if _pending_payment_discount > 0:
				cost = maxi(0, cost - _pending_payment_discount)
				_log("Il costo scende a %d." % cost)
			if _pending_stealth and exclude >= 0:
				_stealth_cards.append(exclude)
				_log("La carta guadagna stealth.")
			_pending_payment_discount = 0
			_pending_stealth = false
		if cost <= 0:
			return true
	# Alcune carte generano di piu' se pagano un colore preciso: il loro valore
	# si sa solo qui, dove si sa per cosa si sta pagando.
	var paying_for := String(Db.action(exclude).get("type", "")) if exclude >= 0 else ""
	_paying_for = paying_for if paying_for != "" else "any"
	if p.available_stamina(paying_for) < cost:
		_paying_for = ""
		return false

	var paid := 0
	var candidates := p.hand.duplicate()
	candidates.erase(exclude)

	var chosen: Array = await _ask({
		"kind": "pay",
		"prompt": "Paga %d stamina%s" % [cost, (" — " + reason) if reason != "" else ""],
		"player": p.seat,
		"cost": cost,
		"cards": candidates,
		"tokens": p.stamina_token,
		"playing": exclude,
	})

	for cid in chosen:
		if not p.hand.has(cid) or cid == exclude:
			continue
		_last_payment_types.append(String(Db.action(cid).get("type", "")))
		paid += p.stamina_of(int(cid), paying_for)
		await _discard_from_hand(p, int(cid))

	# Il segnalino stamina copre solo quel che manca: chi vuole conservarlo
	# scarta abbastanza carte da pagare tutto.
	if paid < cost and p.stamina_token > 0:
		p.stamina_token -= 1
		paid += 1
		_log("  %s spende il segnalino stamina." % p.name)

	if not _last_payment_types.is_empty():
		_log("  %s scarta %d carte per pagare %d stamina." % [p.name, _last_payment_types.size(), cost])

	# Rete di sicurezza: se la scelta non copre il costo, completiamo noi.
	if paid < cost:
		var rest := p.hand.duplicate()
		rest.erase(exclude)
		rest.sort_custom(func(a, b):
			return p.stamina_of(a, paying_for) > p.stamina_of(b, paying_for))
		for cid in rest:
			if paid >= cost:
				break
			_last_payment_types.append(String(Db.action(cid).get("type", "")))
			paid += p.stamina_of(int(cid), paying_for)
			await _discard_from_hand(p, int(cid))
	_paying_for = ""
	return paid >= cost


## Cosa si stava pagando mentre la carta veniva scartata: le carte che reagiscono
## allo scarto per stamina spesso guardano il colore (Cycle of Bullets: attack).
var _paying_for: String = ""


func _discard_from_hand(p: PrimalPlayer, card_id: int) -> void:
	# Alcune carte fanno qualcosa proprio quando vengono scartate dalla mano.
	var discarded := Db.action(card_id)
	if discarded.has("on_discard"):
		await _run_effects(discarded["on_discard"], p, {})
	p.hand.erase(card_id)
	p.discard.push_front(card_id)
	var card := Db.action(card_id)
	for ability in card.get("abilities", []):
		var when := String(ability.get("trigger", ""))
		if when == "discarded_from_hand":
			_log("  %s: effetto allo scarto." % card.get("name", "?"))
			await _run_effects(ability.get("effects", []), p, {"card": card})
		elif when == "discarded_for_stamina" and _paying_for != "":
			# Alcune chiedono anche *per cosa* stavi pagando.
			if not ability.has("for_type") or String(ability["for_type"]) == _paying_for:
				_log("  %s: effetto allo scarto per stamina." % card.get("name", "?"))
				await _run_effects(ability.get("effects", []), p, {"card": card})


func _draw_cards(p: PrimalPlayer, n: int) -> void:
	var drawn := 0
	for i in n:
		if p.deck.is_empty():
			await _deck_emptied(p)
			if p.deck.is_empty():
				break
		p.hand.append(p.deck.pop_front())
		drawn += 1
	# Le pescate vanno dette: senza, le carte compaiono in mano e non si capisce
	# da dove. Il ripristino di fine turno si annuncia da se' in `_refill_hand`.
	if drawn > 0:
		_log("  %s pesca %d (mano %d)." % [p.name, drawn, p.hand.size()])


func _deck_emptied(p: PrimalPlayer) -> void:
	# Fatigue damage: quando il mazzo si esaurisce si subisce danno pari al livello weapon.
	_log("%s ha esaurito il mazzo: fatigue damage." % p.name)
	var m: Dictionary = p.mastery()
	if not p.mastery_focused and String(m.get("unfocused_trigger", "")) == "deck_emptied":
		p.mastery_counters += 1
		if p.mastery_counters >= int(m.get("focus", 1)):
			p.mastery_focused = true
			p.mastery_counters = 0
			_log("  -> %s e' ora FOCUSED!" % m.get("name", "?"))
	elif p.mastery_focused and p.id == "mirah":
		await deal_damage_to_monster(5 * p.weapon_level())
	await _suffer(p, p.weapon_level(), "fatigue")
	if p.burning:
		p.burning = false
		_log("  Il burning di %s si consuma." % p.name)
		await _suffer(p, p.weapon_level(), "burning")
	p.deck = p.discard.duplicate()
	p.discard.clear()
	_shuffle(p.deck)


func _refill_hand(p: PrimalPlayer) -> void:
	var limit := p.hand_limit() + p.pending_bonus_refill
	p.pending_bonus_refill = 0
	# Strain: si scartano tutti i segnalini e si pesca una carta in meno per ognuno.
	if p.strain > 0:
		limit -= p.strain
		_log("%s scarta %d segnalini strain: pesca %d carte in meno."
			% [p.name, p.strain, p.strain])
		p.strain = 0
	while p.cards_against_hand_limit() > limit:
		for cid in p.hand:
			if String(Db.action(cid).get("passive", "")) != "ignores_hand_limit":
				await _discard_from_hand(p, cid)
				break
	var drawn := 0
	while p.cards_against_hand_limit() < limit:
		if p.deck.is_empty():
			await _deck_emptied(p)
			if p.deck.is_empty():
				break
		p.hand.append(p.deck.pop_front())
		drawn += 1
	# E' qui che si pesca, alla fine del proprio turno: dirlo toglie il dubbio
	# piu' comune di chi impara il gioco a schermo.
	if drawn > 0:
		_log("%s ripristina la mano: pesca %d (%d carte)." % [p.name, drawn, p.hand.size()])


func _suffer(p: PrimalPlayer, amount: int, reason: String) -> void:
	if amount <= 0 or p.ko or p.out_of_game:
		return
	# Carte che possono annullare il colpo. Sono tre offerte diverse perche' le
	# carte distinguono: Anticipate para solo le behavior, Bulwark para il colpo
	# di un compagno. Un trigger solo le lasciava tutte e due senza innesco.
	_last_victim = p.seat
	# Shield Wall (Ljonar): non si scarta dalla mano, sta gia' in cima ai propri
	# scarti e chi la ha si prende il colpo di un compagno del suo settore.
	for helper in players:
		if helper == p or helper.ko or helper.out_of_game or helper.discard.is_empty():
			continue
		var top := Db.action(helper.discard[0])
		var swap: Dictionary = top.get("take_damage_instead", {})
		if swap.is_empty() or helper.position != p.position:
			continue
		var accept: bool = await _ask({
			"kind": "confirm",
			"prompt": "%s: incassare tu %s al posto di %s? (%s)" % [
				helper.name, _damage_words(amount), p.name, top.get("name", "?")],
			"player": helper.seat,
			"default": false,
			"art": _art_of(top),
			"text": Db.card_text(top),
		})
		if accept:
			_log("%s incassa al posto di %s." % [helper.name, p.name])
			await _suffer(helper, amount, reason)
			return

	var shield := {"victim": p.seat, "reason": reason}
	if await _out_of_turn_offered("would_suffer", shield):
		if shield.get("prevented", false):
			_log("Il danno a %s viene prevenuto." % p.name)
			return
		if shield.get("halved", false):
			# Per eccesso, come tutte le riduzioni a meta' gia' nel motore.
			amount = int(ceil(float(amount) / 2.0))
			_log("Il danno a %s scende a %d." % [p.name, amount])
	if reason == "behavior" \
			and await _out_of_turn_offered("would_suffer_behavior", shield) \
			and shield.get("prevented", false):
		_log("Il danno a %s viene prevenuto." % p.name)
		return
	if await _out_of_turn_offered("other_would_suffer", shield) \
			and shield.get("prevented", false):
		_log("Il danno a %s viene prevenuto." % p.name)
		return
	p.damage += amount
	_log("%s subisce %d danni (%s) -> %d/%d." % [p.name, amount, reason, p.damage, p.max_health()])
	blow.emit(p.id if reason in SELF_INFLICTED else "monster", p.id, amount)
	if not _offering_resilience:
		await _resilience_offered(p)
		await _out_of_turn_offered("suffered_damage", {"victim": p.seat})
	if p.damage >= p.max_health():
		await _knock_out(p)


func _heal(p: PrimalPlayer, amount: int) -> void:
	if amount <= 0:
		return
	p.damage = maxi(0, p.damage - amount)
	_log("%s recupera %d (danni %d)." % [p.name, amount, p.damage])


func _knock_out(p: PrimalPlayer) -> void:
	_log("%s e' messo KO!" % p.name)
	var was_active := p == active_player()
	p.damage = 0
	p.stamina_token = 0
	p.threatened = false
	if aggro_index == p.seat:
		var other := _other_player(p)
		if other != null:
			aggro_index = other.seat
	for cid in p.hand.duplicate():
		p.discard.push_front(cid)
	p.hand.clear()
	for cid in p.sequence:
		p.discard.push_front(cid)
	p.sequence.clear()
	# Carta Wound nel mazzo degli scarti, poi rimescolo.
	p.discard.push_front(-1)
	p.deck.append_array(p.discard)
	p.discard.clear()
	_shuffle(p.deck)
	if not p.armor_depleted:
		p.armor_depleted = true
	elif not p.helm_depleted:
		p.helm_depleted = true
	if p.armor_depleted and p.helm_depleted:
		p.out_of_game = true
		_log("%s e' fuori dallo scenario: equipaggiamento esaurito." % p.name)
	p.ko = true
	p.ko_flipped = false
	await _turn_monster_to(players[aggro_index].position, "KO")

	var standing := 0
	for q in players:
		if not q.ko and not q.out_of_game:
			standing += 1
	if standing == 0:
		_end_scenario(false, "Tutti i cacciatori sono KO.")
		return
	if was_active:
		phase = Phase.TURN_END
		await _advance_turn()


## Il giocatore sceglie se spendere una carta del tipo richiesto o incassare.
func _suffer_unless_discard(p: PrimalPlayer, type: String, damage: int = -1) -> void:
	var dmg := damage if damage >= 0 else monster_damage()
	var eligible: Array[int] = []
	for cid in p.hand:
		if String(Db.action(cid).get("type", "")) == type:
			eligible.append(cid)
	if not eligible.is_empty():
		var picked: Array = await _ask({
			"kind": "cards",
			"prompt": "Scarta una carta %s per evitare %d danni" % [type, dmg],
			"player": p.seat,
			"cards": eligible,
			"min": 0, "max": 1,
			"allow_none": true,
			"none_label": "Subisci %d danni" % dmg,
		})
		if not picked.is_empty():
			var cid := int(picked[0])
			_log("%s scarta %s per evitare il danno." % [p.name, Db.action(cid).get("name", "?")])
			await _discard_from_hand(p, cid)
			return
	await _suffer(p, dmg, "behavior")


## Scarta le prime `n` carte del mazzo; se fra queste non c'e' una carta del tipo
## richiesto (`defensive` oppure un colore preciso), il giocatore subisce danno.
func _mill_then_suffer(p: PrimalPlayer, n: int, kind: String, damage: int = -1) -> void:
	var dmg := damage if damage >= 0 else monster_damage()
	var found := false
	for cid in await _mill(p, n):
		var type := String(Db.action(cid).get("type", ""))
		if kind == "defensive" and Db.is_defensive(type):
			found = true
		elif kind == type:
			found = true
	if not found:
		await _suffer(p, dmg, "behavior")
	else:
		_log("%s scarta una carta %s ed evita il danno." % [p.name, kind])


## Scarta le prime `n` carte del mazzo e restituisce gli id scartati.
func _mill(p: PrimalPlayer, n: int) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		if p.deck.is_empty():
			await _deck_emptied(p)
			if p.deck.is_empty():
				break
		var cid: int = p.deck.pop_front()
		p.discard.push_front(cid)
		out.append(cid)
	if not out.is_empty():
		_log("%s scarta %d carte dal mazzo." % [p.name, out.size()])
	return out


## Applica al mostro uno stato del glossario.
func _inflict_on_monster(status: String, actor: PrimalPlayer) -> void:
	if hardened() and status in ["vulnerable", "stun", "confuse"]:
		_log("  %s e' hardened: %s non ha effetto." % [monster_name(), status])
		return
	match status:
		"vulnerable":
			if monster_vulnerable:
				_log("  %s e' gia' vulnerable." % monster_name())
			else:
				monster_vulnerable = true
				_log("  %s diventa vulnerable." % monster_name())

		"blind":
			# Blind rende blank una peril fino all'inizio del turno di chi l'ha inflitto.
			var stance := current_stance()
			if not stance.has("peril"):
				_log("  Nessuna peril in gioco da accecare.")
				return
			var pid := int(stance["peril"])
			if blinded_perils.has(pid):
				_log("  La peril e' gia' blind.")
				return
			blinded_perils[pid] = actor.seat if actor else active_player().seat
			_log("  %s diventa blank (blind)." % Db.peril(pid).get("name", "La peril"))

		"stun":
			await _stun_monster(actor)

		"confuse":
			# Glossario p.107: il mostro si gira dove vuole chi lo confonde, e il
			# prossimo boost viene annullato (il costo si paga lo stesso).
			if monster_confused:
				_log("  %s e' gia' confuse." % monster_name())
			else:
				monster_confused = true
				_log("  %s diventa confuse." % monster_name())
			var who := actor if actor != null else active_player()
			var dest: int = await _ask({
				"kind": "sector",
				"prompt": "Confuse: verso quale settore giri %s?" % monster_name(),
				"player": who.seat,
				"options": [0, 1, 2, 3],
			})
			if dest >= 0:
				await _turn_monster_to(dest, "confuse")

		_:
			push_warning("Stato del mostro non implementato: %s" % status)


## Stun: il segnalino va su una carta behavior, che non potra' innescarsi in questo
## round; poi un giocatore puo' rivelare fino a due attack dalla mano e infliggere
## il proprio weapon damage per ognuna.
## Massive Blow: la mastery di Thoreg si focalizza stordendo il mostro.
func _mastery_trigger(p: PrimalPlayer, trigger: String) -> void:
	if p == null or p.mastery_focused:
		return
	var m: Dictionary = p.mastery()
	if String(m.get("unfocused_trigger", "")) != trigger:
		return
	p.mastery_counters += 1
	_log("%s: %d/%d segnalini." % [m.get("name", "?"), p.mastery_counters,
		int(m.get("focus", 1))])
	if p.mastery_counters >= int(m.get("focus", 1)):
		p.mastery_focused = true
		p.mastery_counters = 0
		_log("%s e' ora focalizzata." % m.get("name", "?"))


func _stun_monster(actor: PrimalPlayer) -> void:
	_mastery_trigger(actor, "stun")
	var slots: Array[int] = []
	var labels: Array[String] = []
	for slot in 3:
		var bid := behavior_slots[slot]
		if bid >= 0 and not stunned_behaviors.has(slot):
			slots.append(slot)
			labels.append(String(Db.behavior(bid).get("name", "?")))
	if slots.is_empty():
		_log("  Nessuna behavior da stordire.")
		return

	var chooser: PrimalPlayer = actor if actor else active_player()
	var pick := 0
	if slots.size() > 1:
		pick = await _ask({
			"kind": "order",
			"prompt": "Stun: quale behavior blocchi per questo round?",
			"player": chooser.seat,
			"options": labels,
		})
	pick = clampi(pick, 0, slots.size() - 1)
	stunned_behaviors.append(slots[pick])
	_log("  Stun su %s: non si inneschera' in questo round." % labels[pick])

	# Poi si sceglie un giocatore che rivela fino a due attack.
	var seats: Array[int] = []
	for q in players:
		if not q.ko and not q.out_of_game:
			seats.append(q.seat)
	if seats.is_empty():
		return
	var seat: int = chooser.seat
	if seats.size() > 1:
		seat = await _ask({
			"kind": "player",
			"prompt": "Chi rivela le carte attack per lo stun?",
			"player": chooser.seat,
			"options": seats,
		})
	var revealer: PrimalPlayer = players[clampi(seat, 0, players.size() - 1)]

	var eligible: Array[int] = []
	for cid in revealer.hand:
		var card := Db.action(cid)
		if String(card.get("type", "")) == "attack" \
				or bool(card.get("stun_counts_as_two_attacks", false)):
			eligible.append(cid)
	if eligible.is_empty():
		return
	var shown: Array = await _ask({
		"kind": "cards",
		"prompt": "Rivela fino a 2 carte attack: ognuna infligge il tuo weapon damage",
		"player": revealer.seat,
		"cards": eligible,
		"min": 0, "max": 2,
		"allow_none": true, "none_label": "Nessuna",
	})
	var hits := 0
	for cid in shown:
		# Open Target vale come due attack durante la risoluzione di uno stun.
		hits += 2 if bool(Db.action(int(cid)).get("stun_counts_as_two_attacks", false)) else 1
	if hits > 0:
		_log("  %s rivela %d carte: %d colpi." % [revealer.name, shown.size(), hits])
		await deal_damage_to_monster(weapon_damage_of(revealer) * hits)


## Chiede di scartare una carta del tipo indicato; restituisce false se il
## giocatore rinuncia o non ne ha.
func _discard_of_type(p: PrimalPlayer, type: String, reason: String) -> bool:
	var eligible: Array[int] = []
	for cid in p.hand:
		if String(Db.action(cid).get("type", "")) == type:
			eligible.append(cid)
	if eligible.is_empty():
		return false
	var picked: Array = await _ask({
		"kind": "cards",
		"prompt": "Scarta una carta %s per %s" % [type, reason],
		"player": p.seat,
		"cards": eligible,
		"min": 0, "max": 1,
		"allow_none": true,
		"none_label": "Rinuncia",
	})
	if picked.is_empty():
		return false
	await _discard_from_hand(p, int(picked[0]))
	return true


## Scarta una carta qualsiasi dalla mano, a scelta del giocatore.
func _discard_one_card(p: PrimalPlayer) -> bool:
	if p.hand.is_empty():
		return false
	var picked: Array = await _ask({
		"kind": "cards",
		"prompt": "%s: scarta una carta dalla mano" % p.name,
		"player": p.seat,
		"cards": p.hand.duplicate(),
		"min": 1, "max": 1,
	})
	if picked.is_empty():
		return false
	await _discard_from_hand(p, int(picked[0]))
	return true


## Scarta una carta difensiva (dodge o parry) a scelta, se ce n'e' una.
## Una carta a scelta dalla mano, di qualunque colore (Barrel Roll).
func _discard_any_one(p: PrimalPlayer) -> void:
	if p.hand.is_empty():
		return
	var picked: Array = await _ask({
		"kind": "cards",
		"prompt": "%s: scarta una carta dalla mano" % p.name,
		"player": p.seat,
		"cards": p.hand.duplicate(),
		"min": 1, "max": 1,
	})
	if not picked.is_empty():
		await _discard_from_hand(p, int(picked[0]))


func _discard_defensive(p: PrimalPlayer) -> bool:
	var eligible: Array[int] = []
	for cid in p.hand:
		if Db.is_defensive(String(Db.action(cid).get("type", ""))):
			eligible.append(cid)
	if eligible.is_empty():
		_log("%s non ha carte difensive da scartare." % p.name)
		return false
	var picked: Array = await _ask({
		"kind": "cards",
		"prompt": "Scarta una carta difensiva",
		"player": p.seat,
		"cards": eligible,
		"min": 1, "max": 1,
	})
	if picked.is_empty():
		return false
	await _discard_from_hand(p, int(picked[0]))
	return true


## Quante carte aggro ha in mano: Raging Havoc sceglie chi ne ha di piu'.
func _aggro_in_hand(p: PrimalPlayer) -> int:
	var n := 0
	for cid in p.hand:
		if bool(Db.action(cid).get("aggro", false)):
			n += 1
	return n


## Quante carte di un tipo ("parry") o di una categoria ("defensive") ha in mano.
func _cards_of_kind_in_hand(p: PrimalPlayer, type: String, kind: String = "") -> int:
	var n := 0
	for cid in p.hand:
		var card_type := String(Db.action(cid).get("type", ""))
		if type != "" and card_type == type:
			n += 1
		elif kind == "defensive" and Db.is_defensive(card_type):
			n += 1
		elif kind == "offensive" and Db.is_offensive(card_type):
			n += 1
	return n


## Esaurire una pozione: la carta esce dal gioco senza essere bevuta.
func _exhaust_potion(p: PrimalPlayer) -> void:
	if p.potions.is_empty():
		_log("%s non ha pozioni da esaurire." % p.name)
		return
	var index := 0
	if p.potions.size() > 1:
		var labels: Array[String] = []
		for potion in p.potions:
			labels.append(String(potion.get("name", "pozione")))
		index = clampi(await _ask({
			"kind": "order",
			"prompt": "%s: quale pozione esaurisci?" % p.name,
			"player": p.seat,
			"options": labels,
		}), 0, p.potions.size() - 1)
	_log("%s esaurisce %s." % [p.name, p.potions[index].get("name", "una pozione")])
	p.potions.remove_at(index)


## Il giocatore attivo salta il turno se nessuno paga il pedaggio.
## Terrifying Gaze: normalmente lo paga un altro giocatore; se e' rimasto solo,
## lo paga lui. La versione ad aggression alta non chiede niente quando e' solo.
func _skip_turn(e: Dictionary, actor: PrimalPlayer) -> void:
	var kind_needed := String(e.get("unless_discard_kind", "offensive"))
	for t in await _targets(String(e.get("who", "active")), actor):
		var standing: Array[PrimalPlayer] = []
		for q in players:
			if not q.ko and not q.out_of_game:
				standing.append(q)
		var alone := standing.size() <= 1
		if alone and bool(e.get("only_if_multiple", false)):
			continue
		var payers: Array[PrimalPlayer] = []
		if alone:
			payers.append(t)
		else:
			for q in standing:
				if q != t:
					payers.append(q)
		var paid := false
		for q in payers:
			if _cards_of_kind_in_hand(q, "", kind_needed) == 0:
				continue
			var yes: bool = await _ask({
				"kind": "confirm",
				"prompt": "%s: scarti una carta %s per evitare che %s salti il turno?"
					% [q.name, kind_needed, t.name],
				"player": q.seat,
				"default": true,
			})
			if not yes:
				continue
			var eligible: Array[int] = []
			for cid in q.hand:
				var card_type := String(Db.action(cid).get("type", ""))
				var ok := Db.is_offensive(card_type) if kind_needed == "offensive" \
					else Db.is_defensive(card_type)
				if ok:
					eligible.append(cid)
			var picked: Array = await _ask({
				"kind": "cards",
				"prompt": "Scarta una carta %s" % kind_needed,
				"player": q.seat,
				"cards": eligible,
				"min": 1, "max": 1,
			})
			if picked.is_empty():
				continue
			await _discard_from_hand(q, int(picked[0]))
			paid = true
			break
		if not paid:
			t.skip_turn = true
			_log("%s saltera' il turno." % t.name)


## Burning (Glossario): si prende il segnalino; alla prossima volta che il mazzo
## si esaurisce lo si scarta subendo danno pari al livello della propria weapon.
## Chi ha gia' il segnalino scarta invece le prime 5 carte del mazzo.
func _inflict_burning(p: PrimalPlayer) -> void:
	if p.burning:
		_log("%s e' gia' burning: scarta 5 carte." % p.name)
		await _mill(p, 5)
	else:
		p.burning = true
		_log("%s subisce burning." % p.name)


func _volley(p: PrimalPlayer, n: int) -> void:
	## Volley X: infliggi X x livello weapon danni, indipendentemente dal lato esposto.
	if p == null:
		return
	var dmg := n * p.weapon_level()
	_log("Volley %d: %s infligge %d danni." % [n, p.name, dmg])
	await deal_damage_to_monster(dmg)


func _recycle(p: PrimalPlayer, n: int) -> void:
	## Recycle X: metti fino a X carte dalla mano in fondo al mazzo, poi pesca altrettante.
	if p == null:
		return
	if p.hand.is_empty():
		return
	var picked: Array = await _ask({
		"kind": "cards",
		"prompt": "Recycle %d: quali carte rimetti in fondo al mazzo?" % n,
		"player": p.seat,
		"cards": p.hand.duplicate(),
		"min": 0, "max": mini(n, p.hand.size()),
		"allow_none": true,
		"none_label": "Nessuna",
	})
	var moved := 0
	for cid in picked:
		if p.hand.has(cid):
			p.hand.erase(cid)
			p.deck.append(int(cid))
			moved += 1
	await _draw_cards(p, moved)
	if moved > 0:
		_log("%s ricicla %d carte." % [p.name, moved])


## Cerca nel mazzo o negli scarti: e' il giocatore a scegliere quale carta prendere.
func _search(p: PrimalPlayer, pile: Array, e: Dictionary, reshuffle: bool) -> void:
	var wanted_type := String(e.get("type", ""))
	var wanted_trait := String(e.get("trait", ""))
	var wanted_keyword := String(e.get("keyword", ""))
	var eligible: Array[int] = []
	for cid in pile:
		var card := Db.action(cid)
		if wanted_type != "" and String(card.get("type", "")) != wanted_type:
			continue
		if wanted_trait != "" and not wanted_trait in card.get("traits", []):
			continue
		if wanted_keyword != "" and not wanted_keyword in card.get("keywords", []):
			continue
		eligible.append(int(cid))

	if not eligible.is_empty():
		var what := wanted_trait if wanted_trait != "" else (
			wanted_keyword if wanted_keyword != "" else wanted_type)
		var where := "da mettere in cima al mazzo" \
			if String(e.get("to", "hand")) == "deck_top" else "da aggiungere alla mano"
		var how_many := mini(int(e.get("max", 1)), eligible.size())
		var picked: Array = await _ask({
			"kind": "cards",
			"prompt": "Cerca %s %s %s" % [
				"fino a %d carte" % how_many if how_many > 1 else "una carta",
				what, where],
			"player": p.seat,
			"cards": eligible,
			"min": 0, "max": how_many,
			"allow_none": true,
			"none_label": "Nessuna",
		})
		for chosen_id in picked:
			var cid := int(chosen_id)
			pile.erase(cid)
			# Rapid Ignition non la mette in mano: la mette in cima al mazzo.
			if String(e.get("to", "hand")) == "deck_top":
				p.deck.push_front(cid)
				_log("%s mette %s in cima al mazzo."
					% [p.name, Db.action(cid).get("name", "?")])
			else:
				p.hand.append(cid)
				_log("%s cerca e prende %s." % [p.name, Db.action(cid).get("name", "?")])
	if reshuffle:
		_shuffle(p.deck)


func _check_objective(oid: int) -> void:
	var obj := Db.objective(oid)
	for ability in obj.get("abilities", []):
		if String(ability.get("trigger", "")) != "counters_reached":
			continue
		var threshold := int(ability.get("threshold", 1))
		if String(ability.get("scale", "")) == "per_player":
			threshold *= players.size()
		if int(objective_counters.get(oid, 0)) >= threshold:
			await _run_effects(ability.get("effects", []), null, {"objective_id": oid})
func sector_of(position: int) -> String:
	return SECTORS[posmod(position - monster_facing, 4)]


func _is_adjacent(a: int, b: int) -> bool:
	return posmod(a - b, 4) == 1 or posmod(b - a, 4) == 1


func _turn_monster_to(position: int, reason: String) -> void:
	if monster_facing == position:
		return
	monster_facing = position
	_log("%s si gira verso il settore di %s (%s)." % [monster_name(), _who_at(position), reason])
	# Alcune behavior di Toramat reagiscono al cambio di orientamento.
	_queue_reaction("monster_turned")
	# E anche una carta in mano: Disengage di Karah ripesca la mano piena.
	await _out_of_turn_offered("monster_turned", {})
	_emit()


func _who_at(position: int) -> String:
	for p in players:
		if p.position == position:
			return p.name
	return "settore %d" % position


## C'e' un terreno di questo tipo nel settore? Il fuoco spento ("fire_spent")
## conta come fuoco per tutto tranne che per la rimozione di fine round.
func has_terrain(pos: int, type: String) -> bool:
	if type == "fire":
		return terrain[pos].has("fire") or terrain[pos].has("fire_spent")
	return terrain[pos].has(type)


## Limite di sequenza del giocatore, con il terreno Water che lo abbassa a 3.
func sequence_limit_of(p: PrimalPlayer) -> int:
	if has_terrain(p.position, "water"):
		return 3 + p.sequence_limit_bonus
	return p.sequence_limit()


func _place_terrain(type: String, where: String, count: int = 1) -> void:
	var targets: Array[int] = []
	match where:
		"front":
			targets.append(monster_facing)
		"each_threatened_sector":
			for p in players:
				if p.threatened and not targets.has(p.position):
					targets.append(p.position)
		"aggro_sector":
			targets.append(players[aggro_index].position)
		"each_damaged_sector":
			for pos in 4:
				if sector_damage[pos] > 0:
					targets.append(pos)
		"each_sector":
			for pos in 4:
				targets.append(pos)
		"remembered":
			targets.append(_remembered_sector if _remembered_sector >= 0 else monster_facing)
		"adjacent_to_remembered":
			var centre := _remembered_sector if _remembered_sector >= 0 else monster_facing
			targets.append(posmod(centre - 1, 4))
			targets.append(posmod(centre + 1, 4))
		_:
			targets.append(monster_facing)
	for pos in targets:
		for i in count:
			await _place_one_terrain(type, pos)
	_emit()


## Un singolo segnalino, con le interazioni del Regolamento (p.89-90).
func _place_one_terrain(type: String, pos: int) -> void:
	if type == "fire":
		# Fuoco su fuoco: si rigira sul lato rosso e chi e' li' brucia.
		if has_terrain(pos, "fire"):
			terrain[pos].erase("fire_spent")
			if not terrain[pos].has("fire"):
				terrain[pos].append("fire")
			_log("Il fuoco nel settore %s torna acceso." % sector_of(pos))
			for p in players:
				if p.position == pos and not p.ko and not p.out_of_game:
					await _inflict_burning(p)
			return
		# Il fuoco brucia il brush e trasforma l'acqua in nebbia.
		while terrain[pos].has("brush"):
			terrain[pos].erase("brush")
			_log("Il brush nel settore %s brucia." % sector_of(pos))
		while terrain[pos].has("water"):
			terrain[pos].erase("water")
			terrain[pos].append("fog")
			_log("L'acqua nel settore %s diventa nebbia." % sector_of(pos))
	elif type == "water" and terrain[pos].has("water"):
		# Diffusione: l'acqua non si accumula, si allarga ai settori vicini.
		_log("L'acqua si allarga dai settori adiacenti a %s." % sector_of(pos))
		for near in [posmod(pos - 1, 4), posmod(pos + 1, 4)]:
			if not terrain[near].has("water"):
				terrain[near].append("water")
				_log("Terreno water piazzato nel settore %s." % sector_of(near))
		return
	terrain[pos].append(type)
	_log("Terreno %s piazzato nel settore %s." % [type, sector_of(pos)])


func _attrition_level() -> int:
	if attrition_discard.is_empty():
		return 99
	return int(attrition_cards[attrition_discard[0]].get("value", 0))


func _draw_attrition() -> int:
	if attrition_deck.is_empty():
		if attrition_discard.is_empty():
			return -1
		attrition_deck = attrition_discard.duplicate()
		attrition_discard.clear()
		_shuffle(attrition_deck)
	return attrition_deck.pop_front()


# =====================================================================
#  UTILITA'
# =====================================================================

func _shuffle(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func _end_scenario(won: bool, reason: String) -> void:
	if finished:
		return
	finished = true
	victory = won
	phase = Phase.OVER
	_log(("VITTORIA! " if won else "SCONFITTA. ") + reason)
	scenario_ended.emit(won, reason)
	_emit()


## Una cosa da guardare, non da decidere: il motore si sospende finche' chi
## gioca non chiude il riquadro. E' una richiesta come le altre proprio perche'
## cosi' gli effetti restano in fila — niente riquadri sovrapposti.
func _notice(info: Dictionary) -> void:
	var request := info.duplicate()
	request["kind"] = "notice"
	request["player"] = active_player().seat
	await _ask(request)


func _log(text: String) -> void:
	journal.append(text)
	log_line.emit(text)


func _emit() -> void:
	state_changed.emit()


# =====================================================================
#  REAZIONI FUORI TURNO
# =====================================================================

## Cover Fire: un altro giocatore scarta la carta per prevenire il danno da
## attrition del giocatore attivo. Sono due carte diverse con lo stesso mestiere
## — Mirah e Heleren — quindi la reazione e' dichiarata nei dati come tutte le
## altre invece di essere cablata su un id.
func _cover_fire_offered(victim: PrimalPlayer, level: int = 0) -> bool:
	var shield := {"victim": victim.seat, "reason": "attrition", "attrition_level": level}
	if await _out_of_turn_offered("other_would_suffer_attrition", shield):
		return bool(shield.get("prevented", false))
	return false


## Intuition (Mirah): quando giochi una parry puoi riciclare questa carta dalla mano.
## Reazioni fuori turno dichiarate nei dati: una carta in mano con `out_of_turn`
## si puo' scartare quando succede il fatto indicato. Thoreg ne ha quattro.
## Restituisce true se qualcuno l'ha usata.
func _out_of_turn_offered(trigger: String, ctx: Dictionary = {}) -> bool:
	var used := false
	for holder in players:
		if holder.ko or holder.out_of_game:
			continue
		for cid in holder.hand.duplicate():
			var card := Db.action(cid)
			var duty: Dictionary = card.get("out_of_turn", {})
			if duty.is_empty() or String(duty.get("trigger", "")) != trigger:
				continue
			if duty.has("combo"):
				# "quando un ALTRO giocatore gioca ..." — chi la scarta non e' l'attivo.
				if holder == active_player():
					continue
				if not _combo_matches_tail(active_player(), duty["combo"]):
					continue
			if String(duty.get("who", "")) == "other" and holder == active_player():
				continue
			# I trigger che cominciano per "other_" parlano di quello che capita a
			# qualcun altro: chi tiene la carta non puo' essere il bersaglio.
			if trigger.begins_with("other_") and ctx.has("victim") \
					and holder.seat == int(ctx["victim"]):
				continue
			# Alcune carte valgono solo da una certa posizione (Bulwark: front).
			if duty.has("condition") and not _effect_condition_met(duty, holder):
				continue
			# Prompt Jump para il colpo proprio, non quello degli altri.
			if bool(duty.get("only_victim", false)) \
					and (not ctx.has("victim") or holder.seat != int(ctx["victim"])):
				continue
			# Not This Time!: una volta per turno.
			if bool(duty.get("once_per_turn", false)) and _used_this_turn.has(cid):
				continue
			# Qualcuna si **rivela** invece di scartarsi: resta in mano.
			var reveal := bool(duty.get("reveal", false))
			var verb := "rivelare" if reveal else "scartare"
			var use: bool = await _ask({
				"kind": "confirm",
				"prompt": "%s: %s %s dalla mano?" % [
					holder.name, verb, card.get("name", "?")],
				"player": holder.seat,
				"default": false,
				# Senza la carta sotto gli occhi la domanda e' senza risposta:
				# nessuno ricorda a memoria cosa fa una carta che ha in mano.
				"art": _art_of(card),
				"text": Db.card_text(card),
			})
			if not use:
				continue
			if reveal:
				_log("%s rivela %s." % [holder.name, card.get("name", "?")])
			else:
				await _discard_from_hand(holder, cid)
				_log("%s scarta %s." % [holder.name, card.get("name", "?")])
			if bool(duty.get("once_per_turn", false)):
				_used_this_turn.append(cid)
			await _run_effects(duty.get("effects", []), holder, ctx)
			used = true
	return used


func _intuition_offered(p: PrimalPlayer) -> void:
	if not p.hand.has(178404):
		return
	var use: bool = await _ask({
		"kind": "confirm",
		"prompt": "Riciclare Intuition dalla mano?",
		"player": p.seat,
		"default": false,
		"art": Db.card_art(178404),
		"text": Db.card_text(Db.action(178404)),
	})
	if use:
		p.hand.erase(178404)
		p.deck.append(178404)
		await _draw_cards(p, 1)
		_log("%s ricicla Intuition." % p.name)
