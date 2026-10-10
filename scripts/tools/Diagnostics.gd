extends Node
## Strumento di misura: conta dal registro cosa succede davvero in partita, per
## capire se il limite ai livelli alti sia la stamina, i numeri o il motore.
## Avvio: godot --headless res://scenes/Diagnostics.tscn

const GAMES := 8


func _ready() -> void:
	print("%-8s %6s %6s %7s %8s %7s %6s %7s" % [
		"livello", "round", "carte", "scartate", "attacchi", "a vuoto", "ferite", "danno"])
	for level in 4:
		var t := {"rounds": 0, "played": 0, "paid": 0, "attacks": 0,
				  "wasted": 0, "wounds": 0, "damage": 0}
		for i in GAMES:
			var game := PrimalGame.new()
			game.auto_resolve = true
			await game.setup(["dareon", "mirah"], level, 500 + i, _loadouts_for(level))
			await _play(game)
			_tally(game.journal, t)
		var g := float(GAMES)
		print("%-8d %6.1f %6.1f %7.1f %8.1f %7.1f %6.1f %7.1f" % [
			level, t["rounds"] / g, t["played"] / g, t["paid"] / g,
			t["attacks"] / g, t["wasted"] / g, t["wounds"] / g, t["damage"] / g])
	get_tree().quit()


## Il registro e' gia' abbastanza esplicito da poter essere contato: niente sonde
## dentro il motore.
func _tally(journal: Array, t: Dictionary) -> void:
	for line in journal:
		var s := String(line)
		if s.begins_with("--- Round"):
			t["rounds"] += 1
		elif " gioca " in s:
			t["played"] += 1
		elif " scarta " in s and " per pagare " in s:
			t["paid"] += int(s.split(" scarta ")[1].split(" ")[0])
		elif " infligge " in s and " danni" in s:
			t["attacks"] += 1
			t["damage"] += int(s.split(" infligge ")[1].split(" ")[0])
		elif "non e' su un lato esposto" in s:
			t["wasted"] += 1
		elif "subisce una ferita" in s:
			t["wounds"] += 1


## Dotazione automatica: la weapon piu' pesante del livello, armor e helm con piu'
## salute, e il mazzo che rispetta la composizione della weapon. Serve a misurare
## i livelli alti nelle condizioni previste dal regolamento (p.66), cioe' con la
## forge, non col mazzo starter.
func _loadouts_for(level: int) -> Dictionary:
	if level == 0:
		return {}
	var out := {}
	for hunter in ["dareon", "mirah"]:
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
