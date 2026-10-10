extends Node
## Partita automatica di collaudo: verifica che il motore giri per 10 round
## senza errori. Avvio: godot --headless res://scenes/SmokeTest.tscn
##
## Usa `auto_resolve`, cosi' le richieste di scelta vengono risolte da un'euristica
## invece di sospendere il motore in attesa della UI.

const GAMES := 15
const MONSTERS := ["vyraxen", "kharja", "dygorax", "toramat"]
## Il gruppo di collaudo: due cacciatori, cosi' le partite restano confrontabili.
const PARTY := ["dareon", "mirah"]


func _ready() -> void:
	for monster in MONSTERS:
		print("--- %s ---" % Db.monster(monster).get("name", monster))
		for level in 4:
			var wins := 0
			var health: Array[int] = []
			for i in GAMES:
				var game := PrimalGame.new()
				game.auto_resolve = true
				game.monster_id = monster
				await game.setup(PARTY, level, 1000 + i, _loadouts_for(level))
				await _play(game)
				if game.victory:
					wins += 1
				health.append(game.monster_health)
			var avg := 0.0
			for h in health:
				avg += float(h)
			avg /= float(maxi(health.size(), 1))
			var gear := "mazzo starter" if level == 0 else "forge + potenziamenti liv. %d" % level
			print("aggression %d (%s): %2d/%d vittorie | salute residua min %d max %d media %.1f"
				% [level, gear, wins, GAMES, health.min(), health.max(), avg])
	# I cacciatori fuori dal gruppo di misura non verrebbero mai giocati, e le
	# loro carte non verrebbero mai eseguite. Un giro a testa al livello 0 basta
	# a far passare il motore su tutte e 24.
	var extra := 0
	for hunter in ["thoreg", "karah", "ljonar", "heleren"]:
		if Db.hunter(hunter).get("deck", []).is_empty():
			continue
		# Meta' col mazzo starter e meta' con la forge: i potenziamenti si
		# giocano solo dal livello 1 in su, e senza questo giro non verrebbero
		# mai eseguiti nemmeno loro.
		var party := [hunter, "dareon"]
		for level in [0, 2]:
			var gear := _loadouts_for(level, party)
			if level > 0 and not gear.has(hunter):
				print("%s: niente forge, saltato il livello %d"
					% [Db.hunter(hunter).get("name", hunter), level])
				continue
			for i in GAMES:
				var game := PrimalGame.new()
				game.auto_resolve = true
				game.monster_id = "vyraxen"
				await game.setup(party, level, 5000 + i, gear)
				await _play(game)
				extra += 1
		print("%s: partite senza errori" % Db.hunter(hunter).get("name", hunter))

	print("=== nessun errore in %d partite ===" % (GAMES * 4 * MONSTERS.size() + extra))
	get_tree().quit()


## Dotazione automatica: la weapon piu' pesante del livello, armor e helm con piu'
## salute, e il mazzo che rispetta la composizione della weapon. Serve a misurare
## i livelli alti nelle condizioni previste dal regolamento (p.66), cioe' con la
## forge, non col mazzo starter.
func _loadouts_for(level: int, party: Array = PARTY) -> Dictionary:
	if level == 0:
		return {}
	var out := {}
	for hunter in party:
		var options := Db.loadout_options(hunter, level)
		if options["weapons"].is_empty():
			continue
		var weapon: Dictionary = options["weapons"][0]
		for w in options["weapons"]:
			if int(w.get("damage", 0)) > int(weapon.get("damage", 0)):
				weapon = w
		# Prende i potenziamenti concessi dal livello, saltando quelli il cui
		# effetto non e' ancora implementato, e li mette nel mazzo per primi.
		var picked: Array[int] = []
		for card in options["upgrades"]:
			if picked.size() >= int(options["upgrade_slots"]):
				break
			if not card.has("not_implemented"):
				picked.append(int(card["id"]))

		var comp: Dictionary = weapon["composition"]
		var counts := {"attack": 0, "maneuver": 0, "parry": 0, "dodge": 0}
		var deck: Array[int] = []
		for cid in picked:
			var ut := String(Db.action(cid).get("type", ""))
			if counts[ut] < int(comp.get(ut, 0)):
				counts[ut] += 1
				deck.append(cid)
		for card in Db.hunter(hunter).get("deck", []):
			var t := String(card["type"])
			if counts[t] < int(comp.get(t, 0)):
				counts[t] += 1
				deck.append(int(card["id"]))
		out[hunter] = {
			"weapon": weapon,
			"armor": _toughest(options["armor"]),
			"helm": _toughest(options["helm"]),
			"upgrades": picked,
			"deck": deck,
		}
	return out


func _toughest(items: Array) -> Dictionary:
	var best := {}
	for item in items:
		if item.has("health") and int(item["health"]) > int(best.get("health", -1)):
			best = item
	return best


## Giocatore automatico. Non e' un'IA seria: e' uno strumento di misura, serve a
## capire se un livello e' battibile giocando in modo ragionevole. Segue tre regole
## semplici: copri l'attrition, resta su un lato esposto, spendi il resto in danno
## privilegiando le combo.
const DEFENSIVE_TARGET := 2


func _play(game: PrimalGame) -> void:
	var guard := 0
	while not game.finished and guard < 4000:
		guard += 1
		match game.phase:
			PrimalGame.Phase.CONSUME:
				await _consume_phase(game)
			PrimalGame.Phase.MOVEMENT:
				await _choose_move(game)
			PrimalGame.Phase.ACTION:
				if not await _act(game):
					await _assist_phase(game)
					await game.end_action_phase()
			_:
				pass
	if guard >= 4000:
		push_error("Loop di sicurezza: la partita non termina.")


## Beve una pozione quando la salute e' scesa sotto meta'.
func _consume_phase(game: PrimalGame) -> void:
	for p in game.players:
		if p.ko or p.out_of_game or p.potions.is_empty():
			continue
		if p.damage * 3 >= p.max_health():
			await game.consume(p, 0)
	await game.finish_consume_phase()


## Gli altri giocatori assistono: costa una carta e fa pescare al giocatore attivo.
func _assist_phase(game: PrimalGame) -> void:
	for helper in game.players:
		if helper == game.active_player() or helper.ko or helper.assisted_this_turn:
			continue
		for cid in helper.hand.duplicate():
			if "assist" in Db.action(cid).get("keywords", []):
				if await game.assist(helper, cid):
					break


## Restare fermi rende threatened, e da threatened l'attrition pesca due carte e
## prende la peggiore: conviene quasi sempre muoversi, se la stamina lo consente.
## Fra le destinazioni si preferisce un lato esposto, per poter attaccare.
func _choose_move(game: PrimalGame) -> void:
	var p := game.active_player()
	var exposed: Array = game.current_stance().get("exposed", [])
	var cost := int(Db.rules().get("move_cost", 1))
	# Con poca stamina muoversi costa piu' di quanto rende: meglio tenerla per le carte.
	if p.available_stamina() < cost + 2:
		await game.move(-1)
		return

	var options: Array[int] = [posmod(p.position - 1, 4), posmod(p.position + 1, 4)]
	var best := -1
	for dest in options:
		if game.sector_of(dest) in exposed:
			best = dest
			break
	if best < 0 and p.threatened:
		best = options[0]      # togliersi threatened vale piu' del lato esposto
	if best < 0 or not await game.move(best):
		await game.move(-1)


## Gioca la carta piu' utile; false quando conviene chiudere la fase.
func _act(game: PrimalGame) -> bool:
	var p := game.active_player()
	if p.sequence.size() >= p.sequence_limit():
		return false
	var best := -1
	var best_score := 0.0
	for cid in p.hand:
		var score := _value(game, p, cid)
		if score > best_score:
			best_score = score
			best = cid
	if best < 0:
		return false
	return await game.play_card(best)


## Quanto vale giocare questa carta adesso.
func _value(game: PrimalGame, p: PrimalPlayer, card_id: int) -> float:
	var card := Db.action(card_id)
	var type := String(card.get("type", ""))
	var cost := 0 if p.is_free(card_id) else p.cost_of(card_id)
	# Va lasciata stamina per le carte successive: non svuotiamo la mano.
	if not p.is_free(card_id) and p.available_stamina() < cost + 1:
		return 0.0

	var exposed: bool = game.sector_of(p.position) in game.current_stance().get("exposed", [])
	var defensive := p.defensive_in_sequence()
	var previous := ""
	if not p.sequence.is_empty():
		previous = String(Db.action(p.sequence[-1]).get("type", ""))

	match type:
		"attack":
			if not exposed:
				return 0.0
			# Con la salute critica un attacco in piu' non vale il rischio di restare
			# senza difensive per l'attrition.
			if p.is_critical() and defensive < DEFENSIVE_TARGET:
				return 0.0
			if "finisher" in card.get("keywords", []) and previous != "attack":
				return 0.0     # i Finisher valgono solo dopo un attacco
			var damage := float(p.base_weapon_damage())
			if previous == "attack":
				damage += 2.0  # combo AA della weapon
			damage += _declared_bonus(card) * float(p.weapon_level())
			return damage + 1.0
		"parry", "dodge":
			# Le prime difensive coprono l'attrition. Quando la salute stringe ne
			# servono di piu': un KO costa il turno, la mano e un pezzo di armatura.
			var target := DEFENSIVE_TARGET
			if p.damage * 2 >= p.max_health():
				target += 1
			return 7.0 if defensive < target else 1.5
		"maneuver":
			var threshold := int(Db.rules().get("unleash_threshold_per_player", 3)) * game.players.size()
			return 5.0 if game.struggle >= threshold - 2 else 2.0
	return 1.0


## Bonus ai danni dichiarato dal testo della carta, per pesare gli attacchi.
func _declared_bonus(card: Dictionary) -> float:
	var bonus := 0.0
	for e in card.get("effects", []):
		if String(e.get("op", "")) == "bonus_damage" and not e.has("condition"):
			bonus += float(e.get("n", 0))
	return bonus
