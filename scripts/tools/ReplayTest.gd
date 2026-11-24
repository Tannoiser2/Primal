extends Node
## Collaudo del salvataggio: una partita giocata dal giocatore automatico viene
## registrata come fa l'interfaccia (comandi + risposte), passata per JSON come
## farebbe Firebase, e rigiocata su un motore nuovo con lo stesso seme. Le due
## partite devono essere identiche riga per riga del registro.
##
##     godot --headless --path . scenes/ReplayTest.tscn


## Motore che annota ogni comando e ogni risposta, come Main._record.
class Recorder extends PrimalGame:
	var acts: Array = []

	func _ask(request: Dictionary) -> Variant:
		var a: Variant = _auto_answer(request)
		acts.append({"k": "ans", "v": a})
		return a

	func play_card(card_id: int) -> bool:
		acts.append({"k": "play", "v": card_id})
		return await super(card_id)

	func move(to_position: int) -> bool:
		acts.append({"k": "move", "v": to_position})
		return await super(to_position)

	func end_action_phase() -> void:
		acts.append({"k": "endact", "v": 0})
		await super()

	func finish_consume_phase() -> void:
		acts.append({"k": "fcons", "v": 0})
		await super()

	func consume(player: PrimalPlayer, potion_index: int) -> bool:
		acts.append({"k": "cons", "v": [player.seat, potion_index]})
		return await super(player, potion_index)

	func assist(helper: PrimalPlayer, card_id: int) -> bool:
		acts.append({"k": "assist", "v": [helper.seat, card_id]})
		return await super(helper, card_id)


func _ready() -> void:
	var smoke: Node = load("res://scripts/tools/SmokeTest.gd").new()
	var failures := 0
	var games := 0
	for monster in ["vyraxen", "tarragua", "jekoros", "toramat"]:
		for level in [0, 2]:
			for seed_value in [11, 12]:
				print("%s liv.%d seme %d" % [monster, level, seed_value])
				var a := Recorder.new()
				a.monster_id = monster
				await a.setup(["dareon", "mirah"], level, seed_value, {})
				await smoke._play(a)
				# Come Firebase: JSON e numeri decimali.
				var acts: Array = _as_ints(JSON.parse_string(JSON.stringify(a.acts)))
				var b := PrimalGame.new()
				# Se il registro non bastasse, risponde l'euristica e la partita
				# diverge: lo dice il confronto dei registri, invece di restare appesa.
				b.auto_resolve = true
				b.monster_id = monster
				await b.setup(["dareon", "mirah"], level, seed_value, {})
				await _replay(b, acts)
				games += 1
				var same: bool = a.journal == b.journal and a.monster_health == b.monster_health \
					and a.round_no == b.round_no and a.finished == b.finished
				if not same:
					failures += 1
					var i := 0
					while i < mini(a.journal.size(), b.journal.size()) and a.journal[i] == b.journal[i]:
						i += 1
					print("DIVERSE %s liv.%d seme %d: prima differenza alla riga %d" % [monster, level, seed_value, i])
					if i < a.journal.size():
						print("  originale: ", a.journal[i])
					if i < b.journal.size():
						print("  rigiocata: ", b.journal[i])
	smoke.free()
	if failures == 0:
		print("=== %d partite rigiocate identiche ===" % games)
	else:
		print("=== %d partite su %d diverse ===" % [failures, games])
	get_tree().quit()


func _replay(game: PrimalGame, acts: Array) -> void:
	var i := 0
	while i < acts.size():
		var act: Dictionary = acts[i]
		i += 1
		var kind := String(act.get("k", ""))
		if kind == "ans":
			continue
		var answers: Array = []
		while i < acts.size() and String(acts[i].get("k", "")) == "ans":
			answers.append(acts[i].get("v"))
			i += 1
		game.replay_answers = answers
		var v: Variant = act.get("v")
		match kind:
			"play": await game.play_card(int(v))
			"move": await game.move(int(v))
			"endact": await game.end_action_phase()
			"fcons": await game.finish_consume_phase()
			"cons": await game.consume(game.players[int(v[0])], int(v[1]))
			"assist": await game.assist(game.players[int(v[0])], int(v[1]))
		game.replay_answers = []


func _as_ints(v: Variant) -> Variant:
	if v is float and v == floorf(v):
		return int(v)
	if v is Array:
		var out := []
		for x in v:
			out.append(_as_ints(x))
		return out
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _as_ints(v[k])
		return d
	return v
