extends Node
## Test mirati sulle regole: risoluzione (p.21, p.24, p.35) e livelli di
## aggression (p.60, glossario Infuriate e Burning).
## Avvio: godot --headless res://scenes/RulesTest.tscn

var _failures := 0
var _asked: Array[Dictionary] = []


func _ready() -> void:
	await _test_bonus_applies_to_its_own_attack()
	await _test_weapon_combo_applies_immediately()
	await _test_order_is_asked_when_simultaneous()
	await _test_priority_beats_player_choice()
	await _test_level3_setup()
	await _test_infuriate()
	await _test_burning()
	await _test_loadout()
	await _test_upgrade_cards()
	await _test_monster_states()
	await _test_kharja()
	await _test_kharja_objective()
	await _test_dygorax()
	await _test_toramat()
	await _test_thoreg()
	await _test_terrain()
	await _test_karah()
	await _test_ljonar()
	await _test_blow_signal()
	await _test_exposed_sides()
	await _test_out_of_turn_triggers()
	await _test_divert()
	await _test_heleren()
	await _test_unlocked_by_heleren()
	await _test_heleren_upgrades()
	await _test_notice_before_question()
	await _test_ljonar_upgrades()
	await _test_last_three()
	await _test_monster_boards()
	await _test_shield()

	if _failures == 0:
		print("\n=== tutti i test passati ===")
	else:
		print("\n=== %d test FALLITI ===" % _failures)
	get_tree().quit()


func _check(label: String, actual: Variant, expected: Variant) -> void:
	if actual == expected:
		print("  ok   %s (%s)" % [label, actual])
	else:
		_failures += 1
		print("  FAIL %s: atteso %s, ottenuto %s" % [label, expected, actual])


## Prepara una partita ferma in fase Azione, senza behavior in gioco, cosi' che
## nessuna reazione del mostro sporchi la misurazione.
func _arena() -> PrimalGame:
	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["dareon", "mirah"], 0, 7)
	g.behavior_slots = [-1, -1, -1]
	# Niente terreno: qui si misurano le carte, e il cyricae dello scenario
	# aggiungerebbe il suo bonus a ogni attacco.
	g.terrain = [[], [], [], []]
	g.phase = PrimalGame.Phase.ACTION
	var p := g.active_player()
	p.position = g.monster_facing        # settore front, lato esposto
	p.sequence.clear()
	p.hand.clear()
	p.stamina_token = 1
	return g


## Quanti danni ha incassato il mostro in totale.
func _damage_taken(g: PrimalGame, health_before: int, stance_before: int) -> int:
	return g.stance_damage - stance_before + (health_before - g.monster_health) * g.current_toughness()


## Counterstrike: ">A: aumenta di 3xWL i danni dell'attacco".
## Il bonus deve entrare nell'attacco che segue, non in quello dopo ancora.
func _test_bonus_applies_to_its_own_attack() -> void:
	print("Counterstrike + attacco")
	var g := await _arena()
	var p := g.active_player()
	p.hand.append(178105)   # Counterstrike (parry, costo 1)
	p.hand.append(178101)   # Battle Cry (attack, costo 0)
	var hp := g.monster_health
	var sd := g.stance_damage
	await g.play_card(178105)
	await g.play_card(178101)
	# weapon damage 2 + 3 x livello weapon (1) = 5
	_check("danni inflitti", _damage_taken(g, hp, sd), 5)


## Great Sword: "AA: aumenta di 2 i danni dell'attacco e rimuove 1 struggle".
func _test_weapon_combo_applies_immediately() -> void:
	print("Great Sword, due attacchi di fila")
	var g := await _arena()
	var p := g.active_player()
	p.hand.append(178101)   # Battle Cry  (attack, costo 0)
	p.hand.append(178121)   # Jumping Slice (attack, costo 1)
	g.struggle = 3
	var hp := g.monster_health
	var sd := g.stance_damage
	await g.play_card(178101)
	await g.play_card(178121)
	# 2 (primo attacco) + 2 + 2 (secondo attacco col bonus weapon) = 6
	_check("danni inflitti", _damage_taken(g, hp, sd), 6)
	_check("struggle rimosso dalla weapon", g.struggle, 2)


## Con due abilita' simultanee il motore deve chiedere l'ordine.
func _test_order_is_asked_when_simultaneous() -> void:
	print("Due abilita' simultanee")
	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["dareon", "mirah"], 0, 7)
	g.behavior_slots = [-1, -1, -1]
	# Niente terreno: qui si misurano le carte, e il cyricae dello scenario
	# aggiungerebbe il suo bonus a ogni attacco.
	g.terrain = [[], [], [], []]
	g.phase = PrimalGame.Phase.ACTION
	var p := g.active_player()
	p.position = g.monster_facing
	p.sequence.clear()
	p.hand.clear()
	p.stamina_token = 1

	# Registra le richieste senza sospendere il motore.
	_asked.clear()
	g.auto_resolve = false
	g.choice_required.connect(func(req): _asked.append(req); _answer_later(g, req))

	# Reactive Guard (">A: pesca 1") seguito da Dragon Strike ("P>: pesca 1"):
	# giocando l'attacco scattano insieme l'abilita' della parry gia' in sequenza
	# e quella della carta appena giocata.
	p.hand.append(178106)   # Reactive Guard (parry, costo 1)
	p.hand.append(178103)   # Dragon Strike  (attack, costo 1)
	p.hand.append(178114)   # Retreat: carburante, genera 2 stamina
	await g.play_card(178106)
	await g.play_card(178103)

	var orders := _asked.filter(func(r): return String(r.get("kind", "")) == "order")
	_check("richieste di ordine", orders.size() >= 1, true)
	if not orders.is_empty():
		var labels: Array = orders[0].get("options", [])
		_check("opzioni proposte", labels.size(), 2)


func _answer_later(g: PrimalGame, request: Dictionary) -> void:
	# Come fa la UI: la risposta arriva al frame successivo, quando `_ask`
	# e' effettivamente in attesa del segnale.
	var reply: Variant = g._auto_answer(request)
	g.answer.bind(reply).call_deferred()


## La priorita' (stance, peril, behavior, altre carte) viene prima della scelta.
func _test_priority_beats_player_choice() -> void:
	print("Priorita' fra categorie")
	var g := await _arena()
	var items := [
		{"priority": PrimalGame.PRIO_OTHER, "label": "carta", "kind": "effects",
		 "effects": [], "actor": g.active_player(), "ctx": {}},
		{"priority": PrimalGame.PRIO_PERIL, "label": "peril", "kind": "effects",
		 "effects": [], "actor": g.active_player(), "ctx": {}},
	]
	var before := g.journal.size()
	await g._resolve_simultaneous(items, g.active_player())
	var order: Array[String] = []
	for line in g.journal.slice(before):
		if line.begins_with("  -> "):
			order.append(line.substr(5).rstrip("."))
	_check("il peril si risolve per primo", order, ["peril", "carta"] as Array[String])


## Livello di aggression 3: stance piu' dure e apertura del round 1.
func _test_level3_setup() -> void:
	print("Vyraxen a livello 3")
	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["dareon", "mirah"], 3, 5)
	_check("salute iniziale", g.monster_health, 10)
	_check("toughness Stance I (18 per giocatore)", g.current_toughness(), 36)
	_check("valore damage", g.monster_damage(), 3)
	_check("fuoco piazzato nel settore front", "fire" in g.terrain[g.monster_facing], true)
	_check("struggle dall'apertura (1 per giocatore)", g.struggle, 2)


## Infuriate X/Y/Z: struggle extra in base alle carte aggro nelle mani.
func _test_infuriate() -> void:
	print("Infuriate 2/6/9")
	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["dareon", "mirah"], 3, 5)
	g.stance_index = 1              # Stance II -> peril Wall of Flames
	var aggro := [178100, 178103, 178107, 178118, 178121, 178123]
	g.players[0].hand.clear()
	for cid in aggro:
		g.players[0].hand.append(cid)
	g.players[1].hand.clear()
	g.struggle = 0
	await g._apply_infuriate()
	_check("6 carte aggro -> +2 struggle", g.struggle, 2)

	g.players[0].hand.resize(2)     # 2 carte aggro: soglia bassa raggiunta
	g.struggle = 0
	await g._apply_infuriate()
	_check("2 carte aggro -> +1 struggle", g.struggle, 1)

	g.players[0].hand.clear()
	g.struggle = 0
	await g._apply_infuriate()
	_check("nessuna carta aggro -> nessuno struggle", g.struggle, 0)


## Burning: si consuma quando il mazzo si esaurisce, in aggiunta al fatigue.
func _test_burning() -> void:
	print("Burning")
	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["dareon", "mirah"], 3, 5)
	var p := g.players[0]
	await g._inflict_burning(p)
	_check("segnalino burning preso", p.burning, true)
	p.damage = 0
	p.deck.clear()
	p.discard.clear()
	p.discard.append(178101)
	await g._draw_cards(p, 1)
	# fatigue (livello weapon 1) + burning (livello weapon 1)
	_check("danni da mazzo esaurito", p.damage, 2)
	_check("segnalino consumato", p.burning, false)


## Forge e deck-building: la dotazione scelta deve arrivare in partita.
func _test_loadout() -> void:
	print("Loadout di livello 2")
	var options := Db.loadout_options("dareon", 2)
	_check("weapon di livello 2 disponibili", options["weapons"].size(), 9)
	_check("potenziamenti sbloccati", options["upgrade_slots"], 4)
	_check("potenziamenti in catalogo", options["upgrades"].size(), 20)

	# Sceglie la weapon piu' pesante e costruisce il mazzo secondo la sua composizione.
	var weapon: Dictionary = options["weapons"][0]
	for w in options["weapons"]:
		if int(w.get("damage", 0)) > int(weapon.get("damage", 0)):
			weapon = w
	var comp: Dictionary = weapon["composition"]
	var deck: Array[int] = []
	var counts := {"attack": 0, "maneuver": 0, "parry": 0, "dodge": 0}
	for card in Db.hunter("dareon").get("deck", []):
		var t := String(card["type"])
		if counts[t] < int(comp.get(t, 0)):
			counts[t] += 1
			deck.append(int(card["id"]))

	var armor: Dictionary = options["armor"][0]
	var helm: Dictionary = options["helm"][0]
	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["dareon", "mirah"], 2, 11, {
		"dareon": {"weapon": weapon, "armor": armor, "helm": helm, "deck": deck},
	})
	var p: PrimalPlayer = g.players[0]
	_check("danno base della weapon scelta", p.base_weapon_damage(), int(weapon["damage"]))
	_check("livello weapon", p.weapon_level(), 2)
	_check("salute da armor + helm", p.max_health(),
		int(armor["health"]) + int(helm["health"]))
	_check("carte nel mazzo", p.deck.size() + p.hand.size(), deck.size())
	# Mirah non ha loadout: resta con la dotazione di partenza.
	_check("senza loadout resta il mazzo starter", g.players[1].base_weapon_damage(), 2)


## Le carte potenziamento devono avere effetto, non solo comparire nel mazzo.
func _test_upgrade_cards() -> void:
	print("Carte potenziamento")
	var catalogue := Db.upgrades_for("dareon")
	_check("potenziamenti di Dareon", catalogue.size(), 20)
	_check("id distinti fra cacciatori",
		Db.action(3212900).get("name", "?"), "Blade Surge")
	_check("stesso id TTS, cacciatore diverso",
		Db.action(4212900).get("name", "?"), "Double Shot")

	# Momentum Strike: +1xWL danni per ogni maneuver negli scarti.
	var g := await _arena()
	var p := g.active_player()
	for cid in [178100, 178111, 178117]:      # tre maneuver negli scarti
		p.discard.push_front(cid)
	p.hand.append(3214100)                    # Momentum Strike (attack, costo 1)
	var hp := g.monster_health
	var sd := g.stance_damage
	await g.play_card(3214100)
	# weapon damage 2 + 1 x livello weapon (1) x 3 maneuver = 5
	_check("Momentum Strike conta gli scarti", _damage_taken(g, hp, sd), 5)

	# Blind Rage: +1 al limite di sequenza per questo turno.
	var g2 := await _arena()
	var p2 := g2.active_player()
	var before := p2.sequence_limit()
	p2.hand.append(3213000)                   # Blind Rage (attack, costo 0)
	await g2.play_card(3213000)
	_check("Blind Rage alza il limite di sequenza", p2.sequence_limit(), before + 1)

	# Wrath of Blood: +5xWL solo se la salute e' critica.
	var g3 := await _arena()
	var p3 := g3.active_player()
	p3.hand.append(3214300)
	p3.hand.append(3214300)
	p3.hand.append(178114)                    # Retreat: carburante per il secondo attacco
	var hp3 := g3.monster_health
	var sd3 := g3.stance_damage
	await g3.play_card(3214300)               # salute piena: nessun bonus
	_check("Wrath of Blood senza salute critica", _damage_taken(g3, hp3, sd3), 2)
	p3.damage = p3.max_health() - 1           # ora la salute e' critica
	hp3 = g3.monster_health
	sd3 = g3.stance_damage
	await g3.play_card(3214300)
	# 2 (weapon) + 5 (bonus salute critica) + 2 (combo AA della Great Sword,
	# perche' anche la carta precedente era un attack) = 9
	_check("Wrath of Blood con salute critica", _damage_taken(g3, hp3, sd3), 9)


## Stun, blind e vulnerable colpiscono componenti diversi del tavolo.
func _test_monster_states() -> void:
	print("Stati del mostro")

	# Vulnerable raddoppia una singola fonte di danno, poi si consuma.
	var g := await _arena()
	g.monster_vulnerable = true
	var hp := g.monster_health
	var sd := g.stance_damage
	await g.deal_damage_to_monster(3)
	_check("vulnerable raddoppia", _damage_taken(g, hp, sd), 6)
	_check("il segnalino si consuma", g.monster_vulnerable, false)

	# Precise Strike lo infligge giocandolo. Nota: l'abilita' della carta si risolve
	# prima dell'effetto di colore (Regolamento p.21), quindi il segnalino e' gia'
	# sul tavolo quando l'attacco colpisce e puo' raddoppiare quello stesso attacco.
	var g2 := await _arena()
	var p2 := g2.active_player()
	p2.hand.append(178102)                    # Precise Strike (attack, costo 3)
	p2.hand.append(178114)                    # Retreat: carburante (genera 2)
	p2.stamina_token = 1
	var hp2 := g2.monster_health
	var sd2 := g2.stance_damage
	await g2.play_card(178102)
	_check("Precise Strike infligge vulnerable e lo spende", _damage_taken(g2, hp2, sd2), 4)

	# Blind rende blank la peril in gioco fino al turno di chi l'ha inflitto.
	var g3 := await _arena()
	var pid := int(g3.current_stance()["peril"])
	await g3._inflict_on_monster("blind", g3.active_player())
	_check("la peril e' accecata", g3.blinded_perils.has(pid), true)
	var before := g3.journal.size()
	await g3._trigger_perils("end_of_round")
	var fired := false
	for line in g3.journal.slice(before):
		if line.begins_with("Peril "):
			fired = true
	_check("la peril accecata non si attiva", fired, false)

	# Stun blocca una behavior per il round.
	var g4 := PrimalGame.new()
	g4.auto_resolve = true
	await g4.setup(["dareon", "mirah"], 0, 3)
	await g4._inflict_on_monster("stun", g4.active_player())
	_check("una behavior e' stordita", g4.stunned_behaviors.size(), 1)


## Kharja: quello che il mostro ha di suo e Vyraxen non aveva — segnalini sul
## mostro che scalano il danno, damage sui settori, stance che spostano il round.
func _test_kharja() -> void:
	print("Kharja")

	# I quattro mazzi: dieci carte, dieci nomi diversi, tutte con una reazione.
	Db.select_monster("kharja")
	for level in 4:
		var deck: Array = Db.monster_level(level)["behavior_deck"]
		var names := {}
		var without_reaction := 0
		for bid in deck:
			var card := Db.behavior(int(bid))
			names[card["name"]] = true
			if String(card.get("reaction", "")) == "":
				without_reaction += 1
		_check("livello %d: dieci behavior" % level, deck.size(), 10)
		_check("livello %d: dieci nomi diversi" % level, names.size(), 10)
		_check("livello %d: tutte con reazione" % level, without_reaction, 0)

	var g := await _kharja_arena(2)

	# Stance II piazza fuoco nei settori danneggiati: senza damage non piazza niente.
	g.stance_index = 1
	await g._apply_stance_on_reveal(false)
	_check("nessun settore danneggiato, nessun terreno", g.terrain[0].size() + g.terrain[1].size()
		+ g.terrain[2].size() + g.terrain[3].size(), 0)
	g.sector_damage[1] = 1
	g.monster_counters = 0
	await g._apply_stance_on_reveal(false)
	_check("il terreno fire va nel settore danneggiato", g.terrain[1], ["fire"])
	_check("Stance II al livello 2 lascia un segnalino sul mostro", g.monster_counters, 1)

	# Stance III sposta il segnalino round a 8; se ci e' gia', il mostro guadagna struggle.
	g.stance_index = 2
	g.round_no = 3
	await g._apply_stance_on_reveal(false)
	_check("il round balza a 8", g.round_no, 8)
	var struggle_before := g.struggle
	await g._apply_stance_on_reveal(false)
	_check("a round 8 arriva struggle invece", g.struggle > struggle_before, true)

	# Peril Burning Skin: ogni ferita lascia un segnalino, e il segnalino pesa
	# sull'attrition.
	var g2 := await _kharja_arena(0)
	g2.stance_index = 1                     # la peril di Stance II e' Burning Skin
	g2.monster_counters = 0
	await g2._wound_monster(1)
	_check("la ferita lascia un segnalino", g2.monster_counters, 1)
	_check("l'attrition pesa un danno in piu' per segnalino", g2._peril_attrition_bonus(), 1)

	# Le carte che chiedono di rivelare non tolgono niente dalla mano: o ce l'hai,
	# e non succede nulla, o incassi.
	var g3 := await _kharja_arena(0)
	var p: PrimalPlayer = g3.active_player()
	p.hand.clear()
	p.hand.append(178104)                   # Deflecting Blade (parry)
	var damage_before := p.damage
	await g3._run_effect({"op": "suffer_unless_reveal", "who": "active", "type": "parry"}, null, {})
	_check("con un parry in mano non subisce", p.damage, damage_before)
	_check("il parry resta in mano", p.hand.size(), 1)
	p.hand.clear()
	await g3._run_effect({"op": "suffer_unless_reveal", "who": "active", "type": "parry"}, null, {})
	_check("senza parry subisce DMG", p.damage > damage_before, true)

	# Fire Paw guarda la prima carta del mazzo behavior e colpisce solo se ha claw.
	var g4 := await _kharja_arena(0)
	var p4: PrimalPlayer = g4.active_player()
	g4.behavior_deck = [43009]              # Catlike Spring: ha claw
	var before4 := p4.damage
	await g4._run_effect({"op": "discard_top_behavior", "tag": "claw",
		"then": [{"op": "suffer", "who": "active"}]}, null, {})
	_check("la carta con claw fa danno", p4.damage > before4, true)
	g4.behavior_deck = [43003]              # Ember Dash: niente claw
	var before5 := p4.damage
	await g4._run_effect({"op": "discard_top_behavior", "tag": "claw",
		"then": [{"op": "suffer", "who": "active"}]}, null, {})
	_check("senza claw non succede niente", p4.damage, before5)

	# I segnalini sul mostro entrano nel danno delle behavior.
	var g5 := await _kharja_arena(0)
	var p5: PrimalPlayer = g5.active_player()
	g5.monster_counters = 3
	var before6 := p5.damage
	await g5._run_effect({"op": "suffer", "who": "active",
		"damage_bonus": "monster_counters"}, null, {})
	_check("DMG+X con X = segnalini", p5.damage - before6, g5.monster_damage() + 3)


## Come `_arena()`, ma contro Kharja e a un livello scelto.
func _kharja_arena(level: int) -> PrimalGame:
	var g := PrimalGame.new()
	g.auto_resolve = true
	g.monster_id = "kharja"
	await g.setup(["dareon", "mirah"], level, 11)
	g.behavior_slots = [-1, -1, -1]
	g.phase = PrimalGame.Phase.ACTION
	g.terrain = [[], [], [], []]
	g.sector_damage = [0, 0, 0, 0]
	g.monster_counters = 0
	var p := g.active_player()
	p.sequence.clear()
	p.hand.clear()
	return g


## Keep Your Distance: si attiva dopo un dodge, è facoltativo, ha un tetto di 3
## segnalini, chiude la fase azione e previene l'attrition. Al livello 3 entra la
## faccia B, che in più dà struggle al mostro.
func _test_kharja_objective() -> void:
	print("Kharja: Keep Your Distance")

	var g := await _kharja_arena(0)
	var oid := int(g.current_stance()["objective"])
	_check("l'objective di Stance I è Keep Your Distance",
		Db.objective(oid).get("name", ""), "Keep Your Distance")

	# Rispondendo "continua il turno" (indice 0) non succede niente: il giocatore
	# automatico del collaudo sceglie sempre la prima opzione, quindi le partite
	# headless non lo attivano mai.
	var p := g.active_player()
	p.hand.append(178110)                     # Evasive Step (dodge)
	p.stamina_token = 3
	await g.play_card(178110)
	_check("declinando non arrivano segnalini", int(g.objective_counters.get(oid, 0)), 0)
	_check("declinando la fase azione resta aperta", g.phase, PrimalGame.Phase.ACTION)

	# Rispondendo "metti un segnalino" (indice 1) l'objective si attiva.
	var g2 := await _kharja_arena(0)
	g2.auto_resolve = false
	var answer_taking := func(req):
		var reply: Variant = 1 if String(req.get("kind", "")) == "order" \
			else g2._auto_answer(req)
		g2.answer.bind(reply).call_deferred()
	g2.choice_required.connect(answer_taking)
	var p2 := g2.active_player()
	p2.hand.append(178110)
	p2.stamina_token = 3
	await g2.play_card(178110)
	_check("il segnalino va sull'objective", int(g2.objective_counters.get(oid, 0)), 1)
	_check("l'attrition è prevenuta", p2.attrition_prevented, true)
	_check("la fase azione è chiusa", g2.phase != PrimalGame.Phase.ACTION, true)
	g2.choice_required.disconnect(answer_taking)

	# Il tetto di 3 segnalini: a quota 3 la scelta non viene più offerta.
	var g3 := await _kharja_arena(0)
	g3.objective_counters[oid] = 3
	var p3 := g3.active_player()
	p3.hand.append(178110)
	p3.stamina_token = 3
	var before := g3.journal.size()
	await g3.play_card(178110)
	var offered := false
	for line in g3.journal.slice(before):
		if "Keep Your Distance" in line:
			offered = true
	_check("a segnalini pieni non viene offerto", offered, false)

	# Livello 3: peril e objective passano alla faccia B, che è più cattiva.
	var g4 := await _kharja_arena(3)
	_check("al livello 3 entra la faccia B dell'objective",
		int(g4.current_stance()["objective"]), 402010)
	g4.stance_index = 1
	_check("al livello 3 entra la faccia B della peril",
		int(g4.current_stance()["peril"]), 401020)
	g4.monster_counters = 0
	await g4._wound_monster(1)
	_check("Burning Skin V lascia 2 segnalini per ferita", g4.monster_counters, 2)


## Dygorax: hardening, dust e Resistant — le tre cose che gli altri due mostri
## non avevano.
func _test_dygorax() -> void:
	print("Dygorax")

	Db.select_monster("dygorax")
	for level in 4:
		var deck: Array = Db.monster_level(level)["behavior_deck"]
		var names := {}
		for bid in deck:
			names[Db.behavior(int(bid))["name"]] = true
		_check("livello %d: nove behavior" % level, deck.size(), 9)
		_check("livello %d: nove nomi diversi" % level, names.size(), 9)

	# Hardening: sale, e a 3 il mostro diventa hardened.
	var g := await _dygorax_arena(0)
	_check("si parte da hardening 0", g.hardening, 0)
	_check("e non hardened", g.hardened(), false)
	for i in 3:
		await g._run_effect({"op": "hardening", "n": 1}, null, {})
	_check("tre incrementi", g.hardening, 3)
	_check("ora e' hardened", g.hardened(), true)
	await g._run_effect({"op": "hardening", "n": 5}, null, {})
	_check("il tracciato si ferma a 3", g.hardening, 3)

	# Hardened: niente vulnerable, niente stun, e il damage in eccesso sparisce.
	await g._inflict_on_monster("vulnerable", g.active_player())
	_check("hardened blocca vulnerable", g.monster_vulnerable, false)
	await g._inflict_on_monster("stun", g.active_player())
	_check("hardened blocca stun", g.stunned_behaviors.size(), 0)
	g.stance_index = 0
	var hp := g.monster_health
	await g.deal_damage_to_monster(g.current_toughness() + 3)
	_check("la ferita arriva", g.monster_health, hp - 1)
	_check("hardened azzera il damage in eccesso", g.stance_damage, 0)

	# Resistant: l'eccesso non passa alla stance successiva.
	var g2 := await _dygorax_arena(0)
	g2.stance_index = 0
	g2.monster_health = int(g2.current_stance()["progression"]) + 1
	await g2.deal_damage_to_monster(g2.current_toughness() + 5)
	_check("Resistant: niente riporto sulla stance nuova", g2.stance_damage, 0)
	_check("ed e' avanzato di stance", g2.stance_index, 1)

	# Dust: massimo 2 per settore e disrupt sull'attrition.
	var g3 := await _dygorax_arena(0)
	var front := g3.monster_facing
	for i in 3:
		await g3._run_effect({"op": "place_dust", "where": "front"}, null, {})
	_check("massimo 2 dust per settore", g3.dust[front], 2)
	var p3: PrimalPlayer = g3.active_player()
	p3.position = front
	p3.sequence.clear()
	p3.sequence.append(178104)          # Deflecting Blade (parry)
	p3.sequence.append(178110)          # Evasive Step (dodge)
	_check("due difensive nella sequenza", p3.defensive_in_sequence(), 2)
	var before := g3.journal.size()
	await g3._attrition_check(p3)
	var disrupted := false
	for line in g3.journal.slice(before):
		if "disrupt" in line:
			disrupted = true
	_check("il dust mette disrupt sulle difensive", disrupted, true)

	# Dragon Scales (Stance III): mentre e' hardened resta esposto solo il rear.
	var g4 := await _dygorax_arena(0)
	g4.stance_index = 2
	_check("da non hardened i lati sono quelli della stance",
		g4._exposed_sides(), ["flank", "rear"])
	g4.hardening = 3
	_check("da hardened resta solo il rear", g4._exposed_sides(), ["rear"])

	# Pressure: o giochi una difensiva come carta dopo, o incassi.
	var g5 := await _dygorax_arena(0)
	var p5: PrimalPlayer = g5.active_player()
	p5.stamina_token = 3
	p5.hand.append(178110)              # dodge
	await g5._run_effect({"op": "suffer_unless_next_card", "who": "active",
		"kind": "defensive"}, null, {})
	var dmg5 := p5.damage
	await g5.play_card(178110)
	_check("con la difensiva non subisce", p5.damage, dmg5)

	var g6 := await _dygorax_arena(0)
	var p6: PrimalPlayer = g6.active_player()
	p6.stamina_token = 3
	p6.hand.append(178101)              # Battle Cry (attack)
	await g6._run_effect({"op": "suffer_unless_next_card", "who": "active",
		"kind": "defensive"}, null, {})
	var dmg6 := p6.damage
	await g6.play_card(178101)
	_check("con un attacco incassa", p6.damage > dmg6, true)

	# Hit the Tail: un attack dal settore rear abbassa l'hardening.
	var g7 := await _dygorax_arena(0)
	var p7: PrimalPlayer = g7.active_player()
	g7.hardening = 2
	p7.position = posmod(g7.monster_facing + 2, 4)   # rear
	p7.stamina_token = 3
	p7.hand.append(178101)
	await g7.play_card(178101)
	_check("attaccando dal rear l'hardening scende", g7.hardening, 1)


func _dygorax_arena(level: int) -> PrimalGame:
	var g := PrimalGame.new()
	g.auto_resolve = true
	g.monster_id = "dygorax"
	await g.setup(["dareon", "mirah"], level, 21)
	g.behavior_slots = [-1, -1, -1]
	g.phase = PrimalGame.Phase.ACTION
	g.terrain = [[], [], [], []]
	g.dust = [0, 0, 0, 0]
	g.hardening = 0
	var p := g.active_player()
	p.sequence.clear()
	p.hand.clear()
	return g


## Toramat: acceleration, carte attrition speciali e le due behavior che stanno
## fuori dal mazzo finche' qualcuno non le chiama.
func _test_toramat() -> void:
	print("Toramat")

	Db.select_monster("toramat")
	for level in 4:
		var deck: Array = Db.monster_level(level)["behavior_deck"]
		var names := {}
		for bid in deck:
			names[Db.behavior(int(bid))["name"]] = true
		_check("livello %d: nove behavior" % level, deck.size(), 9)
		_check("livello %d: nove nomi diversi" % level, names.size(), 9)

	# Acceleration: si ferma a 1 per giocatore e nell'upkeep vale struggle.
	var g := await _toramat_arena(0)
	_check("si parte da acceleration 0", g.acceleration, 0)
	for i in 5:
		await g._run_effect({"op": "acceleration", "n": 1}, null, {})
	_check("il tetto e' 1 per giocatore", g.acceleration, g.players.size())
	g.struggle = 0
	g.round_no = 2
	await g._monster_upkeep()
	_check("l'acceleration si somma allo struggle dell'upkeep",
		g.struggle >= g.players.size() + g.acceleration, true)

	# Escalation: rimescolando il mazzo, Rising Fury da' acceleration.
	var g2 := await _toramat_arena(0)
	g2.stance_index = 1                      # Stance II -> peril Rising Fury
	g2.acceleration = 0
	g2.behavior_deck.clear()
	g2.behavior_discard.append(45001)
	await g2._draw_behavior()
	_check("l'escalation porta acceleration", g2.acceleration, 1)

	# Carte attrition speciali: due nel mazzo, e chiedono un dodge preciso.
	var g3 := await _toramat_arena(0)
	var special := 0
	for card in g3.attrition_cards:
		if card.has("type"):
			special += 1
	_check("due carte attrition speciali nel mazzo", special, 2)
	var p3: PrimalPlayer = g3.active_player()
	p3.sequence.clear()
	p3.sequence.append(178104)               # parry: non basta, serve un dodge
	p3.damage = 0
	g3.attrition_deck.clear()
	for i in g3.attrition_cards.size():
		if g3.attrition_cards[i].has("type"):
			g3.attrition_deck.append(i)
	await g3._attrition_check(p3)
	_check("col parry la carta speciale colpisce lo stesso", p3.damage > 0, true)

	# Out of Control: la Stance III la mette in cima e si risolve appena entra.
	var g4 := await _toramat_arena(0)
	g4.behavior_slots = [-1, -1, -1]
	g4.stance_index = 2
	await g4._apply_stance_on_reveal(false)
	_check("Out of Control e' in cima al mazzo", g4.behavior_deck[0], 45019)
	var before := g4.journal.size()
	g4.behavior_slots[0] = await g4._draw_behavior()
	await g4._check_enter_play(0)
	var resolved := false
	for line in g4.journal.slice(before):
		if "Out of Control" in line:
			resolved = true
	_check("entrando in gioco si risolve subito", resolved, true)

	# Crash on the Rocks: rivelando 2 aggro arriva un segnalino; a quota
	# giocatori l'objective se ne va e mette Crashing Charge in cima.
	var g5 := await _toramat_arena(0)
	var oid := int(g5.current_stance()["objective"])
	_check("l'objective di Stance I e' Crash on the Rocks",
		Db.objective(oid).get("name", ""), "Crash on the Rocks")
	var p5: PrimalPlayer = g5.active_player()
	p5.hand.clear()
	for cid in [178100, 178103]:              # due carte aggro di Dareon
		p5.hand.append(cid)
	g5.objective_counters[oid] = g5.players.size() - 1
	await g5._offer_turn_start_objective(p5)
	_check("l'objective si completa", g5.objectives_completed.has(oid), true)
	_check("Crashing Charge finisce in cima al mazzo", g5.behavior_deck[0], 45020)


func _toramat_arena(level: int) -> PrimalGame:
	var g := PrimalGame.new()
	g.auto_resolve = true
	g.monster_id = "toramat"
	await g.setup(["dareon", "mirah"], level, 31)
	g.behavior_slots = [-1, -1, -1]
	g.phase = PrimalGame.Phase.ACTION
	g.terrain = [[], [], [], []]
	g.dust = [0, 0, 0, 0]
	g.hardening = 0
	g.acceleration = 0
	var p := g.active_player()
	p.sequence.clear()
	p.hand.clear()
	return g


## Thoreg: le tre parole che porta di suo — strain, confuse e la mastery che si
## focalizza stordendo.
func _test_thoreg() -> void:
	print("Thoreg")

	var deck: Array = Db.hunter("thoreg").get("deck", [])
	_check("ventiquattro carte", deck.size(), 24)
	var counts := {"attack": 0, "maneuver": 0, "parry": 0, "dodge": 0}
	for card in deck:
		counts[String(card["type"])] += 1
	_check("composizione 6/6/6/6 come la Hammer", counts,
		{"attack": 6, "maneuver": 6, "parry": 6, "dodge": 6})
	_check("venti potenziamenti", Db.upgrades_for("thoreg").size(), 20)

	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["thoreg", "dareon"], 0, 9)
	g.behavior_slots = [-1, -1, -1]
	g.phase = PrimalGame.Phase.ACTION
	var p: PrimalPlayer = g.active_player()
	p.position = g.monster_facing
	p.sequence.clear()
	p.hand.clear()
	p.stamina_token = 3

	# Strain: il segnalino si paga al riempimento della mano, non subito.
	await g._run_effect({"op": "strain", "n": 1}, p, {})
	_check("prende un segnalino strain", p.strain, 1)
	p.hand.clear()
	await g._refill_hand(p)
	# Tenacity non conta per il limite, quindi si guarda il conteggio "utile":
	# con Tenacity in mano le carte fisiche possono essere una in piu'.
	_check("con lo strain pesca una carta in meno",
		p.cards_against_hand_limit(), p.hand_limit() - 1)
	_check("e il segnalino si scarta", p.strain, 0)

	# Tenacity non conta per il limite di mano.
	p.hand.clear()
	p.hand.append(178304)
	_check("Tenacity non occupa posto in mano", p.cards_against_hand_limit(), 0)

	# Confuse: gira il mostro e annulla il prossimo boost, che pero' si paga.
	var g2 := PrimalGame.new()
	g2.auto_resolve = true
	await g2.setup(["thoreg", "dareon"], 0, 9)
	await g2._inflict_on_monster("confuse", g2.active_player())
	_check("il mostro e' confuse", g2.monster_confused, true)
	g2.round_no = 1
	await g2.begin_round()
	_check("a inizio round il confuse decade", g2.monster_confused, false)

	# Massive Blow si focalizza stordendo il mostro (focus 2).
	var g3 := PrimalGame.new()
	g3.auto_resolve = true
	await g3.setup(["thoreg", "dareon"], 0, 9)
	var t: PrimalPlayer = g3.players[0]
	t.mastery_counters = 0
	t.mastery_focused = false
	for i in 2:
		await g3._mastery_trigger(t, "stun")
	_check("due stun focalizzano Massive Blow", t.mastery_focused, true)

	# Sledgehammer si gioca solo dopo un maneuver.
	var g4 := PrimalGame.new()
	g4.auto_resolve = true
	await g4.setup(["thoreg", "dareon"], 0, 9)
	g4.behavior_slots = [-1, -1, -1]
	g4.phase = PrimalGame.Phase.ACTION
	var p4: PrimalPlayer = g4.active_player()
	p4.position = g4.monster_facing
	p4.sequence.clear()
	p4.hand.clear()
	p4.hand.append(178322)
	p4.stamina_token = 3
	_check("Sledgehammer da sola non si puo' giocare",
		g4.why_not_playable(p4, 178322) != "", true)
	p4.sequence.append(178317)                 # Charge (maneuver)
	_check("dopo un maneuver si puo'", g4.why_not_playable(p4, 178322), "")


## Terreni: adesso i segnalini dello scenario non sono solo scenografia.
func _test_terrain() -> void:
	print("Terreni")

	var g := await _arena()
	var p: PrimalPlayer = g.active_player()
	var pos := p.position

	# Cyricae: l'attacco vale il livello della propria weapon in piu'.
	g.terrain[pos] = ["cyricae"]
	p.hand.append(178101)                       # Battle Cry (attack, costo 0)
	var hp := g.monster_health
	var sd := g.stance_damage
	await g.play_card(178101)
	_check("il cyricae rinforza l'attacco", _damage_taken(g, hp, sd), 3)

	# Fuoco: finche' brucia non si gioca niente.
	g.terrain[pos] = ["fire"]
	p.hand.append(178105)
	_check("col fuoco nel settore non si gioca",
		g.why_not_playable(p, 178105) != "", true)

	# Il fuoco dura un round: rosso, poi giallo, poi via.
	await g._end_round()
	_check("dopo un round il fuoco e' quasi spento", g.terrain[pos], ["fire_spent"])
	await g._end_round()
	_check("dopo due round il fuoco sparisce", g.terrain[pos], [])

	# Piazzare fuoco sull'acqua la trasforma in nebbia, e brucia il brush.
	var g2 := await _arena()
	g2.terrain[g2.monster_facing] = ["water", "brush"]
	await g2._place_terrain("fire", "front")
	_check("il fuoco brucia il brush e asciuga l'acqua",
		g2.terrain[g2.monster_facing], ["fog", "fire"])

	# L'acqua non si accumula: si allarga ai settori adiacenti.
	var g3 := await _arena()
	var centre := g3.monster_facing
	g3.terrain[centre] = ["water"]
	await g3._place_terrain("water", "front")
	_check("l'acqua si allarga a sinistra", g3.terrain[posmod(centre - 1, 4)], ["water"])
	_check("e a destra", g3.terrain[posmod(centre + 1, 4)], ["water"])

	# Water: il limite di sequenza scende a 3.
	var g4 := await _arena()
	var p4: PrimalPlayer = g4.active_player()
	_check("limite di sequenza normale", g4.sequence_limit_of(p4), 5)
	g4.terrain[p4.position] = ["water"]
	_check("nell'acqua il limite scende", g4.sequence_limit_of(p4), 3)

	# Sand: uscirne costa una stamina in piu'.
	var g5 := await _arena()
	var p5: PrimalPlayer = g5.active_player()
	g5.phase = PrimalGame.Phase.MOVEMENT
	g5.terrain[p5.position] = ["sand"]
	p5.hand.clear()
	p5.stamina_token = 1                        # basterebbe per un movimento normale
	var before := p5.position
	await g5.move(posmod(before + 1, 4))
	_check("con la sabbia il movimento non si paga", p5.position, before)

	# Fog: entrarci rende threatened.
	var g6 := await _arena()
	var p6: PrimalPlayer = g6.active_player()
	g6.phase = PrimalGame.Phase.MOVEMENT
	p6.threatened = false
	p6.stamina_token = 2
	g6.terrain[posmod(p6.position + 1, 4)] = ["fog"]
	await g6.move(posmod(p6.position + 1, 4))
	_check("la nebbia rende threatened", p6.threatened, true)

	# Baethanis: a inizio turno cura quanto il livello della weapon.
	var g7 := await _arena()
	var p7: PrimalPlayer = g7.active_player()
	p7.damage = 3
	g7.terrain[p7.position] = ["baethanis"]
	await g7._begin_turn()
	_check("il baethanis cura", p7.damage, 3 - p7.weapon_level())

	# Wildmaw: chi chiude il turno threatened dentro le fauci paga.
	var g8 := await _arena()
	var p8: PrimalPlayer = g8.active_player()
	p8.damage = 0
	p8.threatened = true
	g8.terrain[p8.position] = ["wildmaw"]
	await g8._end_turn()
	_check("il wildmaw morde chi e' threatened", p8.damage, p8.weapon_level())

	# Rock: si consuma per evitare il danno da attrition.
	var g9 := await _arena()
	var p9: PrimalPlayer = g9.active_player()
	p9.damage = 0
	p9.sequence.clear()
	g9.terrain[p9.position] = ["rock"]
	await g9._attrition_check(p9)
	_check("la roccia para il colpo", p9.damage, 0)
	_check("e si consuma", g9.terrain[p9.position], [])


## Karah: chain, overrun e battle dance.
func _test_karah() -> void:
	print("Karah")

	var deck: Array = Db.hunter("karah").get("deck", [])
	_check("ventiquattro carte", deck.size(), 24)
	_check("venti potenziamenti", Db.upgrades_for("karah").size(), 20)

	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["karah", "dareon"], 0, 13)
	g.behavior_slots = [-1, -1, -1]
	g.terrain = [[], [], [], []]
	g.phase = PrimalGame.Phase.ACTION
	var p: PrimalPlayer = g.active_player()
	p.position = g.monster_facing
	p.sequence.clear()
	p.hand.clear()
	p.stamina_token = 0

	# Chain: Twist (dodge, costo 1) e' gratis se segue un attack.
	p.hand.append(210100)
	_check("senza attack prima non c'e' chain", g._chain_free(p, 210100), false)
	p.sequence.append(207300)                  # Airblade (attack)
	_check("dopo un attack la chain scatta", g._chain_free(p, 210100), true)

	# Overrun: si finisce nel settore opposto.
	var before := p.position
	await g._overrun(p)
	_check("l'overrun porta nel settore opposto", p.position, posmod(before + 2, 4))

	# Battle dance: due maneuver di fila fanno 3 danni per livello weapon,
	# piu' 1 dalla Dual Blade.
	var g2 := PrimalGame.new()
	g2.auto_resolve = true
	await g2.setup(["karah", "dareon"], 0, 13)
	g2.behavior_slots = [-1, -1, -1]
	g2.terrain = [[], [], [], []]
	g2.phase = PrimalGame.Phase.ACTION
	var p2: PrimalPlayer = g2.active_player()
	p2.sequence.clear()
	p2.hand.clear()
	p2.stamina_token = 3
	p2.hand.append(209900)                     # Slice (maneuver)
	p2.hand.append(210000)                     # Swing (dodge) - non conta
	var hp := g2.monster_health
	var sd := g2.stance_damage
	await g2.play_card(209900)
	_check("un solo maneuver non balla ancora", _damage_taken(g2, hp, sd), 0)
	p2.hand.append(208300)                     # Cut Through (maneuver)
	await g2.play_card(208300)
	# 3 x livello weapon (1) + 1 della Dual Blade
	_check("due maneuver di fila: battle dance", _damage_taken(g2, hp, sd), 4)


## Ljonar: taunt e resilience, le due keyword che non sono solo sue.
func _test_ljonar() -> void:
	print("Ljonar")

	var deck: Array = Db.hunter("ljonar").get("deck", [])
	_check("ventiquattro carte", deck.size(), 24)
	_check("venti potenziamenti", Db.upgrades_for("ljonar").size(), 20)

	# Taunt: chi la scarta prende l'aggro e si gira il mostro addosso.
	var g := PrimalGame.new()
	g.auto_resolve = false
	await g.setup(["dareon", "ljonar"], 0, 17)
	g.behavior_slots = [-1, -1, -1]
	g.terrain = [[], [], [], []]
	var lj: PrimalPlayer = g.players[1]
	lj.hand.clear()
	lj.hand.append(178220)                     # Drawn to Danger (taunt)
	lj.position = posmod(g.monster_facing + 1, 4)
	g.aggro_index = 0
	var answer_yes := func(req):
		g.answer.bind(true if String(req.get("kind", "")) == "confirm"
			else g._auto_answer(req)).call_deferred()
	g.choice_required.connect(answer_yes)
	await g._taunt_offered()
	g.choice_required.disconnect(answer_yes)
	_check("il taunt sposta l'aggro", g.aggro_index, 1)
	_check("e gira il mostro verso chi provoca", g.monster_facing, lj.position)
	_check("la carta e' stata scartata", lj.hand.has(178220), false)

	# Resilience: si rivela (resta in mano) e si pesca 1.
	var g2 := await _arena()
	var p2: PrimalPlayer = g2.active_player()
	p2.hand.clear()
	p2.hand.append(178206)                     # Last Breath (resilience)
	p2.damage = 0
	var before := p2.hand.size()
	await g2._suffer(p2, 1, "prova")
	_check("la carta resta in mano", p2.hand.has(178206), true)
	_check("e fa pescare", p2.hand.size() > before, true)


## `blow` racconta chi ha colpito chi: e' quello che la plancia usa per far
## scattare la miniatura giusta, e `state_changed` non lo dice.
func _test_blow_signal() -> void:
	print("Segnale blow")
	var g := await _arena()
	var p := g.active_player()
	var blows: Array = []
	g.blow.connect(func(a, t, n): blows.append([a, t, n]))

	p.hand.append(178101)                      # Battle Cry (attack, costo 0)
	await g.play_card(178101)
	_check("l'attacco emette un colpo", blows.size(), 1)
	_check("dal cacciatore al mostro", [blows[0][0], blows[0][1]], [p.id, "monster"])
	_check("del valore inflitto", blows[0][2], 2)

	# Danno da attrition: e' il mostro a colpire.
	blows.clear()
	await g._suffer(p, 3, "attrition")
	_check("l'attrition viene dal mostro", blows[0][0], "monster")
	_check("e arriva al cacciatore", blows[0][1], p.id)

	# Mazzo esaurito: il mostro non c'entra, il colpo parte e arriva a chi lo subisce.
	blows.clear()
	await g._suffer(p, 1, "fatigue")
	_check("la fatigue non viene dal mostro", blows[0][0], p.id)


## Lati esposti: il diagramma sulla carta stance ha il **front in basso**, come
## dice il Regolamento p.20. Letto al contrario scambia front e rear, e l'errore
## si nota solo quando provi ad attaccare e la carta viene rifiutata. Qui sono
## fissati i casi in cui i quattro lati non sono simmetrici, quelli in cui uno
## scambio si vedrebbe. I valori vengono da `tools/check_exposure.py`.
func _test_exposed_sides() -> void:
	print("Lati esposti")
	var expected := {
		"vyraxen": {0: [["front", "rear"], ["flank", "rear"], ["front", "flank", "rear"]]},
		"kharja": {
			0: [["flank", "rear"], ["flank", "rear"], ["flank"]],
			2: [["front", "flank"], ["flank", "rear"], ["flank"]],
			3: [["front", "flank"], ["flank", "rear"], ["flank"]],
		},
		"toramat": {
			0: [["flank", "rear"], ["flank", "rear"], ["flank", "rear"]],
			3: [["flank", "rear"], ["flank"], ["flank"]],
		},
	}
	for monster in expected:
		Db.select_monster(String(monster))
		for level in expected[monster]:
			var stances: Array = Db.monster_level(int(level))["stances"]
			for i in 3:
				var want: Array = expected[monster][level][i]
				var got: Array = stances[i].get("exposed", [])
				_check("%s liv %d stance %d" % [monster, level, i + 1], got, want)
	Db.select_monster("vyraxen")

	# E la regola che ci sta sopra: dal lato protetto l'attack non si gioca.
	var g := await _arena()
	var p := g.active_player()
	p.hand.append(178101)                                  # Battle Cry (attack)
	p.position = posmod(g.monster_facing + 1, 4)           # flank
	_check("Vyraxen Stance I: dal flank niente attack",
		g.why_not_playable(p, 178101), "sei su un lato protetto: non puoi giocare attack")
	p.position = g.monster_facing                          # front, esposto
	_check("dal front si puo'", g.why_not_playable(p, 178101), "")


## Ogni `out_of_turn` scritto nei dati deve avere qualcuno che lo innesca. Tre
## carte erano morte in silenzio — Anticipate, Bulwark e Disengage nominavano
## trigger che il motore non emetteva — e non se ne accorgeva nessuno: una carta
## che non viene mai offerta non fa rumore, semplicemente non succede.
func _test_out_of_turn_triggers() -> void:
	print("Trigger fuori turno")
	var source := FileAccess.get_file_as_string("res://scripts/engine/Game.gd")
	var wanted := {}
	for file in ["res://data/hunters.json", "res://data/upgrades.json"]:
		var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		var decks: Array = []
		if raw is Dictionary and raw.has("cards"):
			decks.append(raw["cards"])
		elif raw is Dictionary:
			for key in raw:
				if raw[key] is Dictionary and raw[key].has("deck"):
					decks.append(raw[key]["deck"])
		for deck in decks:
			for card in deck:
				var duty: Dictionary = card.get("out_of_turn", {})
				if not duty.is_empty():
					wanted[String(duty.get("trigger", ""))] = String(card.get("name", "?"))

	var orphans: Array[String] = []
	for trigger in wanted:
		if not source.contains('_out_of_turn_offered("%s"' % trigger):
			orphans.append("%s (%s)" % [trigger, wanted[trigger]])
	_check("trigger senza innesco", orphans, [] as Array[String])
	_check("trigger dichiarati dai dati", wanted.size() >= 8, true)


## Divert (Karah): quando si rivela una behavior, la si scarta per fare overrun.
func _test_divert() -> void:
	print("Divert sulla behavior rivelata")
	var g := PrimalGame.new()
	g.auto_resolve = false
	await g.setup(["karah", "dareon"], 0, 23)
	g.terrain = [[], [], [], []]
	var k: PrimalPlayer = g.players[0]
	k.hand.clear()
	k.hand.append(208700)                      # Divert
	k.position = g.monster_facing
	var before := k.position
	var yes := func(req):
		g.answer.bind(true if String(req.get("kind", "")) == "confirm"
			else g._auto_answer(req)).call_deferred()
	g.choice_required.connect(yes)
	await g._resolve_behavior(0)
	g.choice_required.disconnect(yes)
	_check("la carta e' stata scartata", k.hand.has(208700), false)
	_check("e Karah e' passata dall'altra parte", k.position, posmod(before + 2, 4))


## Heleren: bullet, Reload, Ignite, defense token e la stamina che cambia valore
## a seconda di cosa paga. Sono i tre pezzi che mancavano al motore, e senza di
## essi diciannove delle sue ventiquattro carte non facevano niente.
func _test_heleren() -> void:
	print("Heleren")
	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["heleren", "dareon"], 0, 31)
	g.behavior_slots = [-1, -1, -1]
	g.terrain = [[], [], [], []]
	g.phase = PrimalGame.Phase.ACTION
	var h: PrimalPlayer = g.players[0]
	g.active_index = 0
	h.position = g.monster_facing
	h.sequence.clear()
	h.hand.clear()

	_check("ventiquattro carte", Db.hunter("heleren").get("deck", []).size(), 24)
	_check("il tracciato bullet arriva a 3", h.bullet_max(), 3)
	_check("si parte a zero bullet", h.bullets, 0)

	# Reload 3 non sfonda il tetto, e fa avanzare la mastery.
	await g._reload(h, 3)
	_check("reload 3", h.bullets, 3)
	await g._reload(h, 2)
	_check("il tetto non si supera", h.bullets, 3)
	_check("Precision Reload accumula", h.mastery_focused, true)

	# Ignite: la Gunbow infligge 1 danno ogni volta che si spendono bullet, una
	# volta sola anche spendendone piu' d'uno.
	var hp := g.monster_health
	var sd := g.stance_damage
	await g._spend_bullets(h, 2)
	_check("spesi due bullet", h.bullets, 1)
	_check("Ignite scatta una volta sola", _damage_taken(g, hp, sd), 1)

	# Exertion genera 2 stamina se paga un attack, 1 altrimenti.
	_check("Exertion per un attack", h.stamina_of(213800, "attack"), 2)
	_check("Exertion per un parry", h.stamina_of(213800, "parry"), 1)
	_check("una carta normale non cambia", h.stamina_of(214600, "attack"), 1)

	# Defense token: conta come difensiva nella sequenza e si scarta a fine check.
	var before := h.defensive_in_sequence()
	h.defense_tokens = 1
	_check("il segnalino defense conta come difensiva",
		h.defensive_in_sequence(), before + 1)

	# Ranged, dalla cima degli scarti, conta come difensiva: e' il flag sulla
	# carta, non un id cablato, quindi vale anche per quella di Ljonar.
	h.defense_tokens = 0
	h.discard.push_front(214800)
	_check("Ranged dalla cima degli scarti", h.defensive_in_sequence(), before + 1)
	h.discard.pop_front()
	h.discard.push_front(178416)
	_check("e Ranged Position di Ljonar allo stesso modo",
		h.defensive_in_sequence(), before + 1)


## Le tre carte che aspettavano proprio i pezzi arrivati con Heleren.
func _test_unlocked_by_heleren() -> void:
	print("Carte sbloccate")
	var g := await _arena()
	var p := g.active_player()
	# Stamina Boost di Thoreg: 4 stamina per un attack, ma solo da focalizzata.
	p.mastery_focused = false
	_check("Stamina Boost senza focus", p.stamina_of(178310, "attack"), 2)
	p.mastery_focused = true
	_check("Stamina Boost focalizzata", p.stamina_of(178310, "attack"), 4)
	_check("e solo per un attack", p.stamina_of(178310, "dodge"), 2)
	# Stamina Surge di Ljonar: nessuna condizione.
	_check("Stamina Surge per un attack", p.stamina_of(178210, "attack"), 2)

	# Le 24 carte azione di ogni cacciatore hanno tutte un effetto: se una torna
	# a essere senza, e' perche' qualcuno l'ha aggiunta e non l'ha finita.
	var without: Array[String] = []
	for hunter in ["dareon", "mirah", "thoreg", "karah", "ljonar", "heleren"]:
		for card in Db.hunter(hunter).get("deck", []):
			if card.has("not_implemented"):
				without.append("%s: %s" % [hunter, card.get("name", "?")])
	_check("nessuna carta azione senza effetto", without, [] as Array[String])


## I potenziamenti di Heleren: quelli che parlano di bullet, e i due conteggi
## nuovi (bullet spesi nel turno, un altro parry in sequenza).
func _test_heleren_upgrades() -> void:
	print("Potenziamenti di Heleren")
	var cards := Db.upgrades_for("heleren")
	_check("venti potenziamenti", cards.size(), 20)
	# Le 120 carte potenziamento hanno tutte un effetto: se una torna a essere
	# senza, e' perche' e' stata aggiunta e lasciata a meta'.
	var without: Array[String] = []
	for hunter in ["dareon", "mirah", "thoreg", "karah", "ljonar", "heleren"]:
		for card in Db.upgrades_for(hunter):
			if card.has("not_implemented"):
				without.append("%s: %s" % [hunter, card.get("name", "?")])
	_check("nessun potenziamento senza effetto", without, [] as Array[String])

	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["heleren", "dareon"], 0, 41)
	g.behavior_slots = [-1, -1, -1]
	g.terrain = [[], [], [], []]
	g.phase = PrimalGame.Phase.ACTION
	var h: PrimalPlayer = g.players[0]
	g.active_index = 0
	h.position = g.monster_facing
	h.sequence.clear()
	h.hand.clear()

	# Replenishment restituisce i bullet spesi nel turno.
	await g._reload(h, 3)
	await g._spend_bullets(h, 2)
	_check("due bullet spesi nel turno", h.bullets_spent_this_turn, 2)
	await g._run_effects([{"op": "reload", "n": 0, "per_count": true,
		"count": "bullets_spent"}], h, {})
	_check("Replenishment li rimette", h.bullets, 3)

	# Swift Reload guarda se in sequenza c'e' *un altro* parry, non se stessa.
	h.sequence = [214600, 217400]              # Prompt Reflexes (parry) + questa
	_check("un altro parry in sequenza", g._other_in_sequence(h, "parry"), 1)
	h.sequence = [217400]
	_check("da sola non conta", g._other_in_sequence(h, "parry"), 0)

	# Infallible Aim: +5 col tracciato pieno, +3 altrimenti.
	h.weapon_damage_bonus = 0
	await g._run_effects([
		{"op": "weapon_damage_bonus", "n": 5, "condition": "bullets_full"},
		{"op": "weapon_damage_bonus", "n": 3, "condition": "bullets_not_full"}], h, {})
	_check("Infallible Aim col tracciato pieno", h.weapon_damage_bonus, 5)
	h.weapon_damage_bonus = 0
	await g._spend_bullets(h, 1)
	await g._run_effects([
		{"op": "weapon_damage_bonus", "n": 5, "condition": "bullets_full"},
		{"op": "weapon_damage_bonus", "n": 3, "condition": "bullets_not_full"}], h, {})
	_check("e col tracciato non pieno", h.weapon_damage_bonus, 3)


## L'ordine dei riquadri: prima si guarda la behavior rivelata, poi arriva la
## domanda sulla carta da scartare. Sovrapposti non si capiva a cosa si stesse
## rispondendo.
func _test_notice_before_question() -> void:
	print("Ordine dei riquadri")
	var g := PrimalGame.new()
	g.auto_resolve = false
	await g.setup(["karah", "dareon"], 0, 23)
	g.terrain = [[], [], [], []]
	var k: PrimalPlayer = g.players[0]
	k.hand.clear()
	k.hand.append(208700)                      # Divert: si scarta sulla behavior
	k.position = g.monster_facing

	var seen: Array[String] = []
	var answer := func(req):
		seen.append(String(req.get("kind", "")))
		g.answer.bind(g._auto_answer(req)).call_deferred()
	g.choice_required.connect(answer)
	await g._resolve_behavior(0)
	g.choice_required.disconnect(answer)

	_check("il primo riquadro e' la behavior", seen[0] if not seen.is_empty() else "-", "notice")
	var confirm_at := seen.find("confirm")
	_check("la domanda arriva dopo", confirm_at > 0, true)


## I potenziamenti di Ljonar: erano tutti e venti in catalogo senza effetto.
## Qui i quattro impianti nuovi, che sono quelli su cui si puo' sbagliare.
func _test_ljonar_upgrades() -> void:
	print("Potenziamenti di Ljonar")
	var cards := Db.upgrades_for("ljonar")
	var without := 0
	for card in cards:
		if card.has("not_implemented"):
			without += 1
	_check("venti potenziamenti", cards.size(), 20)
	_check("tutti con effetto", without, 0)

	var g := PrimalGame.new()
	g.auto_resolve = true
	await g.setup(["ljonar", "dareon"], 0, 53)
	g.behavior_slots = [-1, -1, -1]
	g.terrain = [[], [], [], []]
	var lj: PrimalPlayer = g.players[0]
	var other: PrimalPlayer = g.players[1]

	# Mettle vale due difensive, ma solo con la salute critica.
	lj.sequence = [7213300]                    # Mettle (dodge)
	lj.damage = 0
	_check("Mettle in salute conta una", lj.defensive_in_sequence(), 1)
	lj.damage = lj.max_health() - 1
	_check("Mettle critico ne conta due", lj.defensive_in_sequence(), 2)
	lj.damage = 0
	lj.sequence.clear()

	# Assistance sconta gli attack **degli altri**, non i propri.
	var attack_id := 0
	for card in Db.hunter("dareon").get("deck", []):
		if String(card["type"]) == "attack" and int(card["cost"]) > 0:
			attack_id = int(card["id"])
			break
	var full := other.cost_of(attack_id)
	lj.discard.push_front(7212700)             # Assistance in cima ai suoi scarti
	_check("l'attack dell'altro costa 1 in meno", g.cost_of(other, attack_id), full - 1)
	_check("e a Ljonar non cambia niente", g.cost_of(lj, attack_id), lj.cost_of(attack_id))
	lj.discard.pop_front()

	# Sacrifice impedisce allo struggle di arrivare.
	lj.hand.clear()
	lj.hand.append(7214000)                    # Sacrifice
	g.struggle = 0
	var yes := func(req):
		g.answer.bind(true if String(req.get("kind", "")) == "confirm"
			else g._auto_answer(req)).call_deferred()
	g.auto_resolve = false
	g.choice_required.connect(yes)
	await g._monster_gain_struggle(2, "prova")
	g.choice_required.disconnect(yes)
	g.auto_resolve = true
	_check("lo struggle non arriva", g.struggle, 0)
	_check("e Sacrifice e' stata scartata", lj.hand.has(7214000), false)

	# Shield Wall: dalla cima degli scarti incassa al posto del compagno.
	lj.discard.push_front(7214300)             # Shield Wall
	lj.position = other.position
	lj.damage = 0
	other.damage = 0
	g.auto_resolve = false
	var yes2 := func(req):
		g.answer.bind(true if String(req.get("kind", "")) == "confirm"
			else g._auto_answer(req)).call_deferred()
	g.choice_required.connect(yes2)
	await g._suffer(other, 2, "prova")
	g.choice_required.disconnect(yes2)
	_check("il colpo lo prende Ljonar", lj.damage, 2)
	_check("e il compagno resta illeso", other.damage, 0)


## Gli ultimi tre impianti: Reclaim, la battle dance riscritta e il danno
## dimezzato. Sono quelli che sbloccano piu' di una carta a testa, quindi
## sbagliarli si paga tre volte.
func _test_last_three() -> void:
	print("Reclaim, battle dance, danno dimezzato")
	var g := await _arena()
	var p := g.active_player()

	# --- Reclaim: la carta torna in mano quando la condizione e' vera.
	var k := PrimalGame.new()
	k.auto_resolve = false
	await k.setup(["karah", "dareon"], 0, 61)
	k.terrain = [[], [], [], []]
	k.phase = PrimalGame.Phase.ACTION
	var ka: PrimalPlayer = k.players[0]
	k.active_index = 0
	ka.discard.push_front(6206800)             # Returning Blade, negli scarti
	ka.sequence = [208000, 208000, 208000]     # tre carte in sequenza
	var yes := func(req):
		k.answer.bind(true if String(req.get("kind", "")) == "confirm"
			else k._auto_answer(req)).call_deferred()
	k.choice_required.connect(yes)
	await k._reclaim_offered(ka)
	k.choice_required.disconnect(yes)
	var offensive := Db.is_offensive(String(Db.action(208000).get("type", "")))
	if offensive:
		_check("Returning Blade torna in mano", ka.hand.has(6206800), true)
		_check("e non e' piu' negli scarti", ka.discard.has(6206800), false)

	# --- Battle dance: Double Strike vale due maneuver, Dancing Shield uno.
	_check("Double Strike vale due maneuver",
		int(Db.action(6205700).get("counts_as_maneuver", 0)), 2)
	_check("Dancing Shield ne vale uno",
		int(Db.action(6205600).get("counts_as_maneuver", 0)), 1)
	var karah_dance: Dictionary = Db.hunter("karah").get("battle_dance", {})
	_check("la soglia dei due maneuver esiste",
		karah_dance.get("thresholds", {}).has("2"), true)

	# --- Danno dimezzato: per eccesso, come le altre riduzioni del motore.
	p.damage = 0
	var shield := {"victim": p.seat, "halved": true}
	await g._run_effects([{"op": "halve_damage"}], p, shield)
	_check("halve_damage marca il colpo", shield.get("halved", false), true)
	p.hand.clear()
	p.hand.append(6206200)                     # Iron Hedge in mano
	p.damage = 0
	g.auto_resolve = false
	var yes2 := func(req):
		g.answer.bind(true if String(req.get("kind", "")) == "confirm"
			else g._auto_answer(req)).call_deferred()
	g.choice_required.connect(yes2)
	await g._suffer(p, 5, "prova")
	g.choice_required.disconnect(yes2)
	_check("Iron Hedge dimezza 5 in 3", p.damage, 3)


## Ogni mostro deve avere la sua plancia estratta: e' quella su cui si leggono
## salute, hardening e acceleration. Per tre mostri su quattro non c'era, perche'
## l'estrattore guardava mazzi e carte sciolte ma non le tessere.
func _test_monster_boards() -> void:
	print("Plance mostro")
	var missing: Array[String] = []
	for id in ["vyraxen", "kharja", "dygorax", "toramat"]:
		var art := String(Db.monster(id).get("art", {}).get("board", ""))
		if art == "" or not ResourceLoader.exists(art):
			missing.append(id)
	_check("tutte estratte", missing, [] as Array[String])


## Shield X (Glossario p.110): la stance toglie X a ogni fonte di danno, e si
## applica dopo il raddoppio di vulnerable — e' l'armatura del mostro, non una
## proprieta' del colpo.
func _test_shield() -> void:
	print("Shield X")
	var g := await _arena()
	var p := g.active_player()
	var stance := g.current_stance()
	stance["shield"] = 2
	var hp := g.monster_health
	var sd := g.stance_damage
	await g.deal_damage_to_monster(5)
	_check("5 danni contro Shield 2", _damage_taken(g, hp, sd), 3)

	hp = g.monster_health
	sd = g.stance_damage
	await g.deal_damage_to_monster(1)
	_check("un colpo piu' piccolo dello shield non passa", _damage_taken(g, hp, sd), 0)

	# Con vulnerable: prima raddoppia, poi lo shield toglie la sua parte.
	g.monster_vulnerable = true
	hp = g.monster_health
	sd = g.stance_damage
	await g.deal_damage_to_monster(3)
	_check("vulnerable raddoppia e poi lo shield toglie", _damage_taken(g, hp, sd), 4)
	stance.erase("shield")
