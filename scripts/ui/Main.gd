extends Node
## Scena principale: costruisce plancia 3D + interfaccia e collega il motore.
##
## Il motore e' asincrono: quando serve una decisione emette `choice_required`
## e resta sospeso finche' `game.answer()` non riceve la risposta. Qui quella
## richiesta diventa un pannello modale.
##
## Nota: in GDScript non si puo' usare `await` dentro una lambda, quindi i
## pulsanti non chiamano direttamente i metodi del motore ma li avviano con
## `call_deferred`.

const CARD_W := 132
const CARD_H := 185
# La mano occupa una striscia bassa: le carte si leggono passandoci sopra.
const HAND_W := 152
const HAND_H := 214
const HAND_LIFT := 16

# Palette: notte, brace, pergamena. Il gioco ha un'estetica forte e l'interfaccia
# deve starle dietro senza rubarle la scena.
const INK := Color(0.06, 0.055, 0.065)
const PANEL := Color(0.11, 0.10, 0.11)
const EMBER := Color(0.78, 0.46, 0.24)
const PARCHMENT := Color(0.88, 0.85, 0.79)
const MUTED := Color(0.62, 0.59, 0.55)

var game: PrimalGame
var board: Board3D

var _root_ui: Control
var _status: RichTextLabel
var _monster_panel: HBoxContainer
var _behavior_row: HBoxContainer
var _hand_layer: Control
var _actions_box: PanelContainer
## Carta in attesa di pagamento: si sceglie dalla mano cosa scartare.
var _pending_play: int = -1
var _pay_request: Dictionary = {}
var _pay_selection: Array[int] = []
var _pay_banner: PanelContainer
var _pay_banner_row: HBoxContainer
var _actions_row: HBoxContainer
var _track_row: HBoxContainer
var _sequence_window: Window
var _sequence_row: BoxContainer
var _sequence_closed_by_hand := false
var _party_row: HBoxContainer
var _monster_chip: HBoxContainer
var _prompt: RichTextLabel
var _log_lines: Array[String] = []
var _log_view: RichTextLabel
var _log_panel: PanelContainer
var _log_toggle: Button
var _monster_box: BoxContainer
var _theme: Theme
var _windows: Dictionary = {}
var _hunter_board: PanelContainer
var _hunter_box: BoxContainer
## Scheda cacciatore mostrata: segue chi deve agire, ma si puo' cambiare a mano.
var _shown_hunter := ""
var _last_active := -1
var _card_zoom: TextureRect

# --- pannello di scelta ---
var _choice_panel: PanelContainer
var _choice_prompt: RichTextLabel
var _choice_options: HBoxContainer
var _choice_scroll: ScrollContainer
var _choice_footer: HBoxContainer
var _choice_confirm: Button
var _choice_hint: Label
var _choice_notice: VBoxContainer
var _choice_request: Dictionary = {}
var _choice_selection: Array[int] = []

var _level: int = 0
var _loadout_screen: LoadoutScreen
var _loadouts: Dictionary = {}
var _party: Array = ["dareon", "mirah"]
var _monster: String = "vyraxen"
var _expedition: String = "1"


## Le prove da riga di comando saltano la schermata iniziale.
func _dev_run(args: PackedStringArray) -> bool:
	for a in args:
		if a == "--shot-splash":
			return false
		if a.begins_with("--shot") or a == "--test-pay" or a == "--test-pay-token":
			return true
	return false


## Mostra la schermata iniziale e aspetta la scelta del gruppo.
func _ask_party() -> void:
	var splash: Control = preload("res://scripts/ui/SplashScreen.gd").new()
	# Dentro il layer della UI, altrimenti resta sotto al tavolo e alle finestre.
	_root_ui.add_child(splash)
	splash.mouse_filter = Control.MOUSE_FILTER_STOP
	# Mentre si sceglie, i pannelli della partita non c'entrano niente.
	for title in _windows:
		(_windows[title] as Window).hide()
	# Foto della schermata iniziale, per guardarla senza doverla usare a mano.
	if "--shot-splash" in OS.get_cmdline_user_args():
		for i in 30:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		image.save_png(ProjectSettings.globalize_path("res://screenshot.png"))
		print("screenshot salvato")
		get_tree().quit()
		return
	var picked: Array = await splash.start_requested
	_party = picked[0]
	_monster = String(picked[1])
	_level = picked[2]
	if picked.size() > 3:
		_expedition = String(picked[3])
	splash.queue_free()
	for title in _windows:
		(_windows[title] as Window).show()

var _tex_cache: Dictionary = {}


func _ready() -> void:
	board = Board3D.new()
	add_child(board)
	board.sector_clicked.connect(_on_sector_clicked)

	_build_ui()

	game = PrimalGame.new()
	game.log_line.connect(_on_log)
	game.state_changed.connect(_refresh)
	game.scenario_ended.connect(_on_end)
	game.choice_required.connect(_on_choice_required)
	game.blow.connect(board.strike)

	var args := OS.get_cmdline_user_args()
	# Le prove automatiche partono dalla partita gia' pronta: la schermata
	# iniziale aspetterebbe un clic che nessuno dara' mai.
	if not _dev_run(args):
		await _ask_party()
	else:
		# Le prove saltano la schermata iniziale: il mostro si sceglie da riga
		# di comando (`-- --shot --monster=kharja`).
		for a in args:
			if a.begins_with("--monster="):
				_monster = a.substr(10)
			elif a.begins_with("--party="):
				_party = a.substr(8).split(",", false)
			elif a.begins_with("--level="):
				_level = int(a.substr(8))

	game.monster_id = _monster
	game.expedition = _expedition
	board.spawn_monster(_monster)
	for h in _party:
		board.spawn_hunter(h)

	await game.setup(_party, _level, 0, _loadouts)
	_refresh()

	if "--test-pay-token" in args:
		await _test_pay_with_token()
	elif "--shot" in args:
		_capture_and_quit()
	elif "--shot-choice" in args:
		_demo_choice()
	elif "--shot-order" in args:
		_demo_order()
	elif "--shot-loadout" in args:
		_demo_loadout()
	elif "--shot-confirm" in args:
		_demo_confirm()
	elif "--shot-terrain" in args:
		_demo_terrain()
	elif "--shot-blow" in args:
		_demo_blow()
	elif "--shot-turn" in args:
		_demo_turn()
	elif "--shot-reaction" in args:
		_demo_reaction()
	elif "--shot-attrition" in args:
		_demo_attrition()
	elif "--shot-hunter" in args:
		_demo_hunter()
	elif "--shot-facing" in args:
		_demo_facing()
	elif "--test-pay" in args:
		_test_payment()


## Collaudo del pagamento nella mano: simula i clic e verifica che la carta
## arrivi davvero sul tavolo.
func _test_payment() -> void:
	call_deferred("_do_finish_consume")
	for i in 30:
		await get_tree().process_frame
	print("fase dopo Consume: ", _phase_name())
	call_deferred("_do_move", -1)
	for i in 30:
		await get_tree().process_frame
	print("fase dopo Movimento: ", _phase_name())

	var p := game.active_player()
	var target := -1
	for cid in p.hand:
		if p.cost_of(cid) > 0 and p.available_stamina() > p.cost_of(cid):
			target = cid
			break
	if target < 0:
		print("NESSUNA carta a pagamento in mano")
		get_tree().quit()
		return
	print("clicco: ", Db.action(target).get("name", "?"), " costo ", p.cost_of(target))

	_on_hand_card(target)
	for i in 20:
		await get_tree().process_frame
	print("modalita' pagamento attiva: ", _pending_play >= 0,
		" | costo richiesto: ", _pay_request.get("cost", "-"))

	# Sceglie le carte da scartare finche' il costo non e' coperto.
	var guard := 0
	while _pending_play >= 0 and guard < 8:
		guard += 1
		var picked := false
		for cid in p.hand:
			if cid == target or _pay_selection.has(cid):
				continue
			if int(Db.action(cid).get("stamina", 0)) > 0:
				_on_hand_card(cid)
				picked = true
				break
		if not picked:
			break
		for i in 10:
			await get_tree().process_frame
	for i in 40:
		await get_tree().process_frame
	print("RISULTATO -> carte sul tavolo: ", p.sequence.size(),
		" | la carta giocata e' in sequenza: ", p.sequence.has(target))
	get_tree().quit()


## Utilita' di sviluppo: gioca una carta e fotografa il tavolo.
func _demo_confirm() -> void:
	call_deferred("_do_finish_consume")
	await _advance_until("")
	call_deferred("_do_move", -1)
	await _advance_until("")
	var p := game.active_player()
	var target: int = p.hand[0]
	for cid in p.hand:
		if p.cost_of(cid) == 0:
			target = cid
			break
	call_deferred("_do_play", target)
	for i in 20:
		await get_tree().process_frame
	print("giocata: ", Db.action(target).get("name", "?"),
		" | carte sul tavolo: ", p.sequence.size())
	_capture_and_quit()


## Utilita' di sviluppo: apre la costruzione del mazzo a livello 2 e la fotografa.
func _demo_loadout() -> void:
	_level = 2
	_open_loadout()
	for i in 10:
		await get_tree().process_frame
	_capture_and_quit()


## Utilita' di sviluppo: costruisce una sequenza con due abilita' simultanee
## (Reactive Guard seguito da Dragon Strike) e fotografa la scelta dell'ordine.
func _demo_order() -> void:
	call_deferred("_do_finish_consume")
	await _advance_until("")
	var p := game.active_player()
	p.position = game.monster_facing
	call_deferred("_do_move", -1)
	await _advance_until("")
	game.behavior_slots = [-1, -1, -1]
	p.hand.clear()
	p.hand.append(178106)   # Reactive Guard
	p.hand.append(178103)   # Dragon Strike
	p.hand.append(178114)   # Retreat, come carburante
	p.stamina_token = 1
	_refresh()
	call_deferred("_do_play", 178106)
	await _advance_until("")
	call_deferred("_do_play", 178103)
	await _advance_until("order")
	print("richiesta mostrata: ", _choice_request.get("kind", "-"),
		" opzioni: ", _choice_request.get("options", []))
	_capture_and_quit()


## Prova del caso segnalato: si gioca l'ultima carta in mano e il costo puo'
## essere coperto solo dal segnalino stamina. Prima il pagamento restava
## appeso, perche' l'unico modo di confermarlo era cliccare una carta in mano.
func _test_pay_with_token() -> void:
	call_deferred("_do_finish_consume")
	await _advance_until("")
	call_deferred("_do_move", -1)
	await _advance_until("")

	var p := game.active_player()
	var target := -1
	for cid in p.hand:
		if p.cost_of(cid) == 1 and game.why_not_playable(p, cid) == "":
			target = cid
			break
	if target < 0:
		push_error("nessuna carta da 1 stamina in mano")
		get_tree().quit()
		return
	# Mano ridotta alla sola carta da giocare, e un segnalino stamina.
	p.hand.clear()
	p.hand.append(target)
	p.stamina_token = 1

	call_deferred("_do_play", target)
	for step in 60:
		await get_tree().process_frame
		if _pending_play >= 0:
			break
	if _pending_play < 0:
		push_error("il pagamento non e' stato chiesto")
		get_tree().quit()
		return

	var button: Button = null
	for c in _pay_banner_row.get_children():
		if c is Button:
			button = c
	if button == null:
		push_error("FALLITO: nessun pulsante per pagare col segnalino")
	else:
		print("pulsante offerto: ", button.text)
		button.pressed.emit()
		for step in 60:
			await get_tree().process_frame
			if _pending_play < 0 and p.sequence.has(target):
				break
		if p.sequence.has(target) and p.stamina_token == 0:
			print("=== ok: la carta e' stata giocata pagando col segnalino ===")
		else:
			push_error("FALLITO: sequenza %s, segnalini %d" % [p.sequence, p.stamina_token])
	get_tree().quit()


## Utilita' di sviluppo: avanza fino alla prima richiesta di pagamento.
func _demo_choice() -> void:
	call_deferred("_do_finish_consume")
	await _advance_until("")
	call_deferred("_do_move", -1)
	await _advance_until("")
	var p := game.active_player()
	for cid in p.hand:
		if p.cost_of(cid) > 0:
			call_deferred("_do_play", cid)
			break
	await _advance_until("pay")
	_capture_and_quit()


## Fa avanzare la partita rispondendo da sola ai pannelli, finche' non compare
## quello di tipo `target` (stringa vuota = finche' non ne resta nessuno aperto).
func _advance_until(target: String) -> void:
	for step in 200:
		await get_tree().process_frame
		# Il pagamento della stamina non apre il pannello di scelta: si fa nella
		# mano. Le prove devono saperlo, altrimenti restano appese sulla prima
		# carta che costa qualcosa.
		if _pending_play >= 0:
			if target == "pay":
				return
			_settle_payment()
			continue
		if not _choice_panel.visible:
			continue
		var kind := String(_choice_request.get("kind", ""))
		if kind == target:
			return
		_respond(game._auto_answer(_choice_request))
	if target != "":
		push_error("il pannello '%s' non e' comparso" % target)


## Paga scartando le prime carte utili: serve solo alle prove automatiche.
func _settle_payment() -> void:
	var cost := int(_pay_request.get("cost", 0))
	for cid in game.active_player().hand:
		if _generated() >= cost:
			break
		if cid == _pending_play or int(Db.action(cid).get("stamina", 0)) <= 0:
			continue
		_pay_selection.append(cid)
	_finish_payment()


## Utilita' di sviluppo: porta la partita dentro il turno del primo cacciatore,
## con due carte gia' in sequenza. Serve per guardare la traccia del round
## mentre e' accesa su un turno, non sulla fase Consume.
func _demo_turn() -> void:
	call_deferred("_do_finish_consume")
	await _advance_until("")
	call_deferred("_do_move", -1)
	await _advance_until("")
	for i in 2:
		var p := game.active_player()
		for cid in p.hand:
			if game.why_not_playable(p, cid) == "":
				call_deferred("_do_play", cid)
				break
		await _advance_until("")
	_refresh()
	_capture_and_quit()


## Utilita' di sviluppo: arriva alla fase Attrition restando fermo — chi resta
## fermo diventa threatened, quindi si rivelano due carte invece di una.
func _demo_attrition() -> void:
	call_deferred("_do_finish_consume")
	await _advance_until("")
	call_deferred("_do_move", -1)
	await _advance_until("")
	call_deferred("_do_end_action")
	# L'esito dell'attrition ora e' un riquadro che aspetta: si fotografa quello.
	for i in 60:
		await get_tree().process_frame
		if String(_choice_request.get("topic", "")) == "attrition" and _choice_panel.visible:
			break
	await _capture_and_quit(4)


## Utilita' di sviluppo: gira il mostro verso il settore 2, quello davanti alla
## camera. Serve a controllare che il modello guardi dove il motore crede: ogni
## GLB e' scolpito rivolto da una parte diversa, e l'angolo di correzione sta nei
## dati del mostro (`art.model_yaw`).
func _demo_facing() -> void:
	var want := 2
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--facing="):
			want = int(a.substr(9))
	game.monster_facing = want
	_refresh()
	await _capture_and_quit(40)


## Utilita' di sviluppo: apre la scheda del cacciatore, che in partita si apre
## cliccando il suo ritratto.
func _demo_hunter() -> void:
	(_windows["Mostro"] as Window).hide()
	(_windows["Cacciatore"] as Window).show()
	_refresh()
	_capture_and_quit(10)


## Utilita' di sviluppo: mostra la carta reazione del mostro dove compare in
## partita. Prima finiva fuori dal tavolo, ed e' il genere di cosa che si vede
## solo guardandola.
func _demo_reaction() -> void:
	call_deferred("_do_finish_consume")
	await _advance_until("")
	# La behavior si attiva quando capita: qui la si risolve a comando, cosi' lo
	# scatto e' sempre lo stesso.
	for slot in 3:
		if game.behavior_slots[slot] >= 0:
			game._resolve_behavior.call_deferred(slot)
			break
	for i in 60:
		await get_tree().process_frame
		if String(_choice_request.get("topic", "")) == "behavior" and _choice_panel.visible:
			break
	await _capture_and_quit(4)


## Utilita' di sviluppo: mette in tavola i quattro terreni che non hanno una
## miniatura — fuoco (acceso e quasi spento), acqua, sabbia e dust — per
## guardarli tutti insieme senza aspettare la partita che li produce.
func _demo_terrain() -> void:
	game.terrain[0].append("fire")
	game.terrain[1].append("water")
	game.terrain[2].append("sand")
	game.terrain[3].append("fire_spent")
	game.dust[2] = 2
	_refresh()
	_capture_and_quit()


## Utilita' di sviluppo: fotografa un colpo a meta' strada. Serve per guardare
## lo scatto e il tremito, che in una posa ferma non si vedrebbero.
func _demo_blow() -> void:
	if "--no-windows" in OS.get_cmdline_user_args():
		for title in _windows:
			(_windows[title] as Window).hide()
	for i in 20:
		await get_tree().process_frame
	board.strike(_party[0], "monster", 6)
	# Lo scatto dura 0.13s: dodici fotogrammi dentro, la miniatura e' in volo.
	await _capture_and_quit(12)


## Utilita' di sviluppo: salva uno screenshot e chiude (avvio con `-- --shot`).
func _capture_and_quit(frames: int = 30) -> void:
	# `--no-windows` chiude i pannelli flottanti: serve a fotografare la plancia.
	if "--no-windows" in OS.get_cmdline_user_args():
		for title in _windows:
			(_windows[title] as Window).hide()
	for i in frames:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://screenshot.png")
	image.save_png(path)
	print("screenshot salvato in ", path)
	get_tree().quit()


# =====================================================================
#  COSTRUZIONE UI
# =====================================================================

## Tema dei pulsanti: compatti, angoli stondati, stati visibili al passaggio e
## alla pressione.
func _button_theme() -> Theme:
	var theme := Theme.new()
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.17, 0.16, 0.17)
	normal.border_color = Color(0.32, 0.29, 0.28)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7

	var hover := normal.duplicate()
	hover.bg_color = Color(0.26, 0.21, 0.16)
	hover.border_color = EMBER
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.42, 0.26, 0.14)
	pressed.border_color = EMBER
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.13, 0.13, 0.14)
	disabled.border_color = Color(0.2, 0.19, 0.19)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	theme.set_color("font_color", "Button", PARCHMENT)
	theme.set_color("font_hover_color", "Button", Color.WHITE)
	theme.set_color("font_disabled_color", "Button", Color(0.45, 0.43, 0.42))
	theme.set_font_size("font_size", "Button", 14)
	return theme


## Finestra vera: spostabile e ridimensionabile, si chiude e si riapre.
func _make_window(title: String, at: Vector2, size: Vector2,
		horizontal := false) -> BoxContainer:
	var win := Window.new()
	win.title = title
	win.position = at
	win.size = size
	win.unresizable = false
	win.transient = true
	win.exclusive = false
	win.theme = _theme
	win.close_requested.connect(func(): win.hide())
	_root_ui.add_child(win)
	_windows[title] = win

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	win.add_child(margin)

	var scroll := ScrollContainer.new()
	if horizontal:
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	else:
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var box: BoxContainer = HBoxContainer.new() if horizontal else VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	return box


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_root_ui = Control.new()
	_root_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_theme = _button_theme()
	_root_ui.theme = _theme
	# Ridimensionando la finestra il ventaglio va ricalcolato, altrimenti resta
	# dov'era e sembra fluttuare a mezz'aria.
	_root_ui.resized.connect(func():
		if game != null:
			_refresh_hand())
	layer.add_child(_root_ui)

	_build_top_bar()
	_build_monster_panel()
	# Non veniva costruita da nessuno: la costruzione del mazzo era irraggiungibile.
	_build_loadout_screen()
	_build_log_panel()
	_build_bottom()
	_build_choice_panel()

	# Striscia del pagamento: compare sopra la mano, cosi' e' chiaro che le carte
	# che stai cliccando servono a pagare e non finiscono in sequenza.
	_pay_banner = _panel(10, true)
	_pay_banner.visible = false
	_root_ui.add_child(_pay_banner)
	_pay_banner_row = HBoxContainer.new()
	_pay_banner_row.add_theme_constant_override("separation", 8)
	_pay_banner.add_child(_pay_banner_row)

	# Zoom della carta sotto il puntatore: segue il mouse, non copre un angolo fisso.
	_card_zoom = TextureRect.new()
	_card_zoom.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_zoom.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_card_zoom.custom_minimum_size = Vector2(300, 420)
	_card_zoom.size = Vector2(300, 420)
	_card_zoom.visible = false
	_card_zoom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_ui.add_child(_card_zoom)


## Barra superiore su due righe: sopra lo stato (mostro e cacciatori, a icone),
## sotto tutto cio' che riguarda l'azione — pulsanti, scelte, stamina da pagare.
func _build_top_bar() -> void:
	var bar := _panel(8)
	# Il preset TOP_WIDE lascia l'altezza a zero e lo sfondo non copre la seconda
	# riga: ancore e offset vanno messi a mano.
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0
	bar.anchor_bottom = 0.0
	bar.offset_left = 0.0
	bar.offset_right = 0.0
	bar.offset_top = 0.0
	bar.offset_bottom = 156.0
	_root_ui.add_child(bar)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	bar.add_child(rows)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	rows.add_child(top)

	# Il mostro viene prima dei cacciatori: e' lui a dettare il ritmo.
	_monster_chip = HBoxContainer.new()
	_monster_chip.add_theme_constant_override("separation", 4)
	top.add_child(_monster_chip)

	_party_row = HBoxContainer.new()
	_party_row.add_theme_constant_override("separation", 8)
	top.add_child(_party_row)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)

	var seq_toggle := Button.new()
	seq_toggle.text = "Sequenza"
	seq_toggle.pressed.connect(func():
		_sequence_closed_by_hand = _sequence_window.visible
		_sequence_window.visible = not _sequence_window.visible)
	top.add_child(seq_toggle)

	_log_toggle = Button.new()
	_log_toggle.text = "Registro"
	_log_toggle.toggle_mode = true
	_log_toggle.button_pressed = true
	_log_toggle.toggled.connect(func(on): _log_panel.visible = on)
	top.add_child(_log_toggle)

	# Seconda riga: la traccia del round, cioe' l'ordine in cui si gioca.
	_track_row = HBoxContainer.new()
	_track_row.add_theme_constant_override("separation", 2)
	rows.add_child(_track_row)

	# Terza riga: la richiesta del momento e i comandi.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	rows.add_child(bottom)

	_status = RichTextLabel.new()
	_status.bbcode_enabled = true
	_status.fit_content = true
	_status.custom_minimum_size = Vector2(110, 30)
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	bottom.add_child(_status)

	_prompt = RichTextLabel.new()
	_prompt.bbcode_enabled = true
	_prompt.fit_content = true
	_prompt.custom_minimum_size = Vector2(560, 30)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
	_prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(_prompt)

	_actions_row = HBoxContainer.new()
	_actions_row.add_theme_constant_override("separation", 4)
	bottom.add_child(_actions_row)


## Mostro e cacciatore vivono in due finestre indipendenti: si spostano, si
## ridimensionano e si chiudono come qualunque finestra.
## Le due schede stanno nella stessa colonna a sinistra, stretta e verticale: al
## centro ci va il tavolo, a destra il registro. Prima erano due strisce larghe
## 940 appoggiate sopra la plancia, e il tavolo non si vedeva.
## Le carte del mostro, tutte alla stessa misura nella colonna di sinistra.
const MONSTER_CARD_W := 264

const SIDE_X := 8.0
const SIDE_Y := 168.0
const SIDE_SIZE := Vector2(316, 508)


func _build_monster_panel() -> void:
	# Il livello di aggression non si cambia in corsa: si decide nella schermata
	# iniziale, con la partita ancora da montare.
	_monster_box = _make_window("Mostro", Vector2(SIDE_X, SIDE_Y), SIDE_SIZE)
	# Stessa casella della scheda mostro: si guarda o l'una o l'altra, e aprire
	# una chiude l'altra. Restano finestre, quindi chi vuole le stacca.
	_hunter_box = _make_window("Cacciatore", Vector2(SIDE_X, SIDE_Y), SIDE_SIZE)
	var inventory: Window = _windows["Cacciatore"]
	inventory.hide()


func _build_log_panel() -> void:
	_log_panel = _panel(10)
	_log_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_log_panel.position = Vector2(-306, SIDE_Y)
	_log_panel.custom_minimum_size = Vector2(292, 430)
	_root_ui.add_child(_log_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_log_panel.add_child(box)
	box.add_child(_heading("Registro"))
	_log_view = RichTextLabel.new()
	_log_view.bbcode_enabled = true
	_log_view.scroll_following = false
	_log_view.custom_minimum_size = Vector2(272, 400)
	_log_view.add_theme_font_size_override("normal_font_size", 12)
	_log_view.add_theme_color_override("default_color", MUTED)
	box.add_child(_log_view)


## Niente piu' finestra inferiore: la mano sta direttamente sullo schermo, a
## ventaglio, come se la tenessi tu; i pulsanti compaiono solo quando servono.
func _build_bottom() -> void:
	_hand_layer = Control.new()
	_hand_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hand_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_ui.add_child(_hand_layer)

	# Le carte giocate stanno sul tavolo, ma quando il cacciatore e' sul lato
	# lontano finiscono piccole e di taglio. Qui sono leggibili, ed e' una
	# finestra vera: si sposta dove non da' fastidio e si chiude.
	_sequence_row = _make_window("Sequenza", Vector2(SIDE_X, 672), Vector2(600, 212), true)
	_sequence_window = _windows["Sequenza"]
	_sequence_window.hide()
	# Chi la chiude a mano non se la ritrova aperta alla carta dopo; il turno
	# seguente riparte pulito.
	_sequence_window.close_requested.connect(func(): _sequence_closed_by_hand = true)




func _build_choice_panel() -> void:
	# Velo che blocca il resto dell'interfaccia mentre serve una decisione.
	_choice_panel = PanelContainer.new()
	_choice_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_choice_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_choice_panel.visible = false
	var veil := StyleBoxFlat.new()
	veil.bg_color = Color(0.02, 0.02, 0.04, 0.82)
	_choice_panel.add_theme_stylebox_override("panel", veil)
	_root_ui.add_child(_choice_panel)

	# La finestra di scelta e' centrata piu' in basso, non a meta' esatta: la
	# fascia in alto e' dove compaiono la behavior rivelata e l'esito
	# dell'attrition, e sono proprio le cose che servono per rispondere.
	var below := MarginContainer.new()
	below.set_anchors_preset(Control.PRESET_FULL_RECT)
	below.add_theme_constant_override("margin_top", 200)
	_choice_panel.add_child(below)
	var center := CenterContainer.new()
	below.add_child(center)

	var card := PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.10, 0.10, 0.12)
	frame.border_color = Color(0.85, 0.65, 0.35)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(6)
	frame.set_content_margin_all(22)
	card.add_theme_stylebox_override("panel", frame)
	center.add_child(card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)

	_choice_prompt = RichTextLabel.new()
	_choice_prompt.bbcode_enabled = true
	_choice_prompt.fit_content = true
	_choice_prompt.custom_minimum_size = Vector2(680, 0)
	_choice_prompt.add_theme_font_size_override("normal_font_size", 17)
	box.add_child(_choice_prompt)

	# Le cose da guardare (behavior rivelata, esito dell'attrition) vanno qui:
	# hanno una forma loro e non stanno nella striscia delle carte.
	_choice_notice = VBoxContainer.new()
	_choice_notice.add_theme_constant_override("separation", 8)
	_choice_notice.visible = false
	box.add_child(_choice_notice)

	_choice_scroll = ScrollContainer.new()
	var options_scroll := _choice_scroll
	options_scroll.custom_minimum_size = Vector2(680, CARD_H + 24)
	options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(options_scroll)
	_choice_options = HBoxContainer.new()
	_choice_options.add_theme_constant_override("separation", 8)
	options_scroll.add_child(_choice_options)

	_choice_hint = Label.new()
	_choice_hint.add_theme_color_override("font_color", Color(0.75, 0.72, 0.68))
	box.add_child(_choice_hint)

	_choice_footer = HBoxContainer.new()
	_choice_footer.add_theme_constant_override("separation", 10)
	box.add_child(_choice_footer)

	_choice_confirm = Button.new()
	_choice_confirm.text = "Conferma"
	_choice_confirm.pressed.connect(_on_choice_confirm)
	_choice_footer.add_child(_choice_confirm)


func _build_loadout_screen() -> void:
	_loadout_screen = LoadoutScreen.new()
	_loadout_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loadout_screen.visible = false
	_loadout_screen.confirmed.connect(_on_loadout_confirmed)
	_root_ui.add_child(_loadout_screen)


func _on_loadout_confirmed(choices: Dictionary) -> void:
	_loadouts = choices
	_loadout_screen.visible = false
	_show_game_ui(true)
	call_deferred("_do_restart")


## Intestazione che apre e chiude il pannello sottostante, come fa il registro.
func _collapse_toggle(title: String, on_toggle: Callable) -> Button:
	var b := Button.new()
	b.text = "▾  " + title.to_upper()
	b.toggle_mode = true
	b.button_pressed = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 11)
	b.add_theme_color_override("font_color", EMBER)
	b.toggled.connect(func(on):
		b.text = ("▾  " if on else "▸  ") + title.to_upper()
		on_toggle.call(on))
	return b


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", EMBER)
	return l


## Riquadro scuro con bordo brace, usato per tutti i pannelli.
func _panel(margin: int = 12, accent: bool = false) -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_corner_radius_all(5)
	style.set_content_margin_all(margin)
	if accent:
		style.border_color = EMBER
		style.set_border_width_all(1)
	box.add_theme_stylebox_override("panel", style)
	return box


## Segnalino vero, con il numero sopra quando serve contarli.
func _token(kind: String, count: int = -1, size: int = 30) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.clip_contents = true
	var tex := _tex("res://art/tokens/%s.png" % kind)
	if tex != null:
		var art := TextureRect.new()
		art.texture = tex
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		holder.add_child(art)
	if count >= 0:
		var label := Label.new()
		label.text = str(count)
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 5)
		holder.add_child(label)
	holder.tooltip_text = kind
	return holder


# =====================================================================
#  PANNELLO DI SCELTA
# =====================================================================

func _on_choice_required(request: Dictionary) -> void:
	# Il pagamento della stamina si fa nella mano, non in una finestra: si clicca
	# la carta da giocare e poi quelle da scartare.
	if String(request.get("kind", "")) == "pay":
		_pay_request = request
		_pay_selection.clear()
		_pending_play = int(request.get("playing", -1))
		if _pending_play < 0:
			_pending_play = 0      # marca comunque lo stato "sto pagando"
		_refresh_hand()
		_refresh_actions()
		return
	_choice_request = request
	_choice_selection.clear()
	_choice_panel.visible = true
	_choice_confirm.visible = false
	_choice_hint.text = ""

	for c in _choice_notice.get_children():
		c.queue_free()
	_choice_notice.visible = false
	for c in _choice_options.get_children():
		c.queue_free()
	for c in _choice_footer.get_children():
		if c != _choice_confirm:
			c.queue_free()
	# L'area delle carte serve solo alle scelte che ne propongono.
	_choice_scroll.visible = String(request.get("kind", "")) in ["pay", "cards"]

	var who := ""
	if request.has("player"):
		var seat := int(request["player"])
		if seat >= 0 and seat < game.players.size():
			who = "[color=#e0b070]%s[/color] — " % game.players[seat].name
	_choice_prompt.text = who + String(request.get("prompt", "Scegli"))

	# Se la richiesta parla di una carta precisa, quella carta si vede: decidere
	# se scartarla leggendone solo il nome non e' una decisione, e' un indovinello.
	if String(request.get("art", "")) != "":
		_choice_options.add_child(_choice_card(String(request["art"]),
			String(request.get("text", ""))))
		_choice_scroll.visible = true

	match String(request.get("kind", "")):
		"pay": _fill_pay()
		"cards": _fill_cards()
		"player": _fill_players()
		"sector": _fill_sectors()
		"confirm": _fill_confirm()
		"order": _fill_order()
		"notice": _fill_notice()
		_: _respond(null)


## Selezione di carte dalla mano fino a coprire un costo in stamina.
func _fill_pay() -> void:
	var cost := int(_choice_request.get("cost", 0))
	var tokens := int(_choice_request.get("tokens", 0))
	if tokens > 0:
		_choice_hint.text = "Hai 1 segnalino stamina: copre quel che manca, ma se paghi tutto con le carte lo conservi."
	for cid in _choice_request.get("cards", []):
		_choice_options.add_child(_selectable_card(int(cid)))
	_choice_confirm.visible = true
	_update_pay_state()


func _update_pay_state() -> void:
	var cost := int(_choice_request.get("cost", 0))
	var tokens := int(_choice_request.get("tokens", 0))
	var from_cards := 0
	for cid in _choice_selection:
		from_cards += int(Db.action(cid).get("stamina", 0))
	var total := from_cards + (tokens if from_cards < cost else 0)
	_choice_confirm.disabled = total < cost
	if from_cards < cost and tokens > 0 and total >= cost:
		_choice_confirm.text = "Paga  (%d/%d, +1 dal segnalino)" % [from_cards, cost]
	else:
		_choice_confirm.text = "Paga  (%d/%d stamina)" % [from_cards, cost]
	_refresh_card_selection()


## Selezione di 0..max carte da un elenco.
func _fill_cards() -> void:
	var wanted_min := int(_choice_request.get("min", 0))
	var wanted_max := int(_choice_request.get("max", 1))
	_choice_hint.text = "Seleziona da %d a %d carte." % [wanted_min, wanted_max]
	for cid in _choice_request.get("cards", []):
		_choice_options.add_child(_selectable_card(int(cid)))
	_choice_confirm.visible = true
	if bool(_choice_request.get("allow_none", false)):
		_add_footer_button(String(_choice_request.get("none_label", "Nessuna")), func():
			_choice_selection.clear()
			_respond([]))
	_update_cards_state()


func _update_cards_state() -> void:
	var wanted_min := int(_choice_request.get("min", 0))
	var wanted_max := int(_choice_request.get("max", 1))
	_choice_confirm.disabled = _choice_selection.size() < wanted_min \
		or _choice_selection.size() > wanted_max
	_choice_confirm.text = "Conferma  (%d selezionate)" % _choice_selection.size()
	_refresh_card_selection()


func _fill_players() -> void:
	for seat in _choice_request.get("options", []):
		var s := int(seat)
		var p: PrimalPlayer = game.players[s]
		_add_footer_button("%s  (settore %s, danni %d/%d)" % [
			p.name, game.sector_of(p.position), p.damage, p.max_health()],
			func(): _respond(s))


func _fill_sectors() -> void:
	for pos in _choice_request.get("options", []):
		var s := int(pos)
		_add_footer_button("Vai nel settore %s" % game.sector_of(s), func(): _respond(s))
	if bool(_choice_request.get("allow_none", false)):
		_add_footer_button(String(_choice_request.get("none_label", "Rinuncia")), func(): _respond(-1))


func _fill_confirm() -> void:
	_add_footer_button("Sì", func(): _respond(true))
	_add_footer_button("No", func(): _respond(false))


## Carta mostrata dentro il pannello di scelta, col suo testo sotto.
func _choice_card(art: String, text: String, width := 190) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var art_node := TextureRect.new()
	art_node.texture = _tex(art)
	art_node.custom_minimum_size = Vector2(width, width * 1.4)
	art_node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_node.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	col.add_child(art_node)
	if text != "":
		var body := Label.new()
		body.text = text
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size.x = width
		body.add_theme_font_size_override("font_size", 11)
		body.add_theme_color_override("font_color", PARCHMENT)
		col.add_child(body)
	return col


## Effetti simultanei: il giocatore sceglie quale risolvere per primo. Le opzioni
## sono carte, non nomi: al tavolo le hai davanti, qui devono esserci anche.
func _fill_order() -> void:
	var labels: Array = _choice_request.get("options", [])
	var arts: Array = _choice_request.get("arts", [])
	var texts: Array = _choice_request.get("texts", [])
	_choice_hint.text = "Gli altri effetti si risolveranno subito dopo, sempre a tua scelta."
	var with_cards := false
	for i in labels.size():
		var idx := i
		var art := String(arts[i]) if i < arts.size() else ""
		if art != "":
			with_cards = true
			var col := _choice_card(art, String(texts[i]) if i < texts.size() else "", 170)
			var pick := Button.new()
			pick.text = String(labels[i])
			pick.pressed.connect(func(): _respond(idx))
			col.add_child(pick)
			_choice_options.add_child(col)
		else:
			_add_footer_button(String(labels[i]), func(): _respond(idx))
	_choice_scroll.visible = _choice_scroll.visible or with_cards


func _add_footer_button(text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	_choice_footer.add_child(b)


func _selectable_card(card_id: int) -> Control:
	var btn := TextureButton.new()
	btn.texture_normal = _card_texture(card_id)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
	btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
	btn.set_meta("card_id", card_id)
	var card := Db.action(card_id)
	btn.tooltip_text = "%s  (%s, genera %d stamina)\n%s" % [
		card.get("name", "?"), card.get("type", "?"),
		int(card.get("stamina", 0)), card.get("text", "")]
	btn.pressed.connect(func(): _toggle_card(card_id))
	return btn


func _toggle_card(card_id: int) -> void:
	if _choice_selection.has(card_id):
		_choice_selection.erase(card_id)
	else:
		_choice_selection.append(card_id)
	if String(_choice_request.get("kind", "")) == "pay":
		_update_pay_state()
	else:
		_update_cards_state()


func _refresh_card_selection() -> void:
	for c in _choice_options.get_children():
		if not c.has_meta("card_id"):
			continue
		var selected: bool = _choice_selection.has(int(c.get_meta("card_id")))
		c.modulate = Color(1, 1, 1) if selected else Color(0.55, 0.55, 0.6)


func _on_choice_confirm() -> void:
	_respond(_choice_selection.duplicate())


func _respond(result: Variant) -> void:
	_choice_panel.visible = false
	_choice_request = {}
	_choice_selection.clear()
	# Il motore e' sospeso dentro `_ask`: lo riprendiamo al frame successivo,
	# cosi' non ripartiamo dall'interno del gestore del pulsante.
	call_deferred("_deliver_answer", result)


func _deliver_answer(result: Variant) -> void:
	game.answer(result)


# =====================================================================
#  AGGIORNAMENTO
# =====================================================================

func _refresh() -> void:
	if game == null:
		return
	_refresh_status()
	_refresh_track()
	_refresh_board()
	_refresh_behaviors()
	_refresh_sequence()
	_refresh_actions()
	_refresh_party()
	_refresh_hand()


func _refresh_status() -> void:
	var p := game.active_player()
	# La fase non si ripete qui: la dice la traccia, riga per riga.
	_status.text = "[b][color=#c8763c]Round %d/%d[/color][/b]" % [
		game.round_no, int(Db.rules().get("rounds", 10))]

	# Box del mostro: ritratto e icone, tutto dentro il suo riquadro.
	for c in _monster_chip.get_children():
		c.queue_free()
	var box := _entity_box("%s  %s" % [game.monster_name().to_upper(),
			["I", "II", "III"][game.stance_index]],
		_portrait(Db.monster(game.monster_id).get("art", {})),
		Color(0.88, 0.42, 0.38))
	var icons: HBoxContainer = box.get_meta("icons")
	icons.add_child(_labelled(_token("counter", game.monster_health, 30), "salute"))
	if game.stance_damage > 0:
		icons.add_child(_labelled(_token("damage", game.stance_damage, 30),
			"ferite in arrivo: a %d danni scatta la ferita" % game.current_toughness()))
	var threshold := int(Db.rules().get("unleash_threshold_per_player", 3)) * game.players.size()
	icons.add_child(_labelled(_token("struggle", game.struggle, 30),
		"unleash a %d struggle" % threshold))
	if game.monster_vulnerable:
		icons.add_child(_labelled(_token("vulnerable", -1, 30), "vulnerable"))
	var face: TextureRect = box.get_meta("face")
	face.mouse_filter = Control.MOUSE_FILTER_STOP
	face.tooltip_text = "Clicca per aprire o chiudere la scheda del mostro"
	face.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			var w: Window = _windows.get("Mostro")
			if w != null:
				w.visible = not w.visible
				if w.visible:
					(_windows["Cacciatore"] as Window).hide())
	_monster_chip.add_child(box)

	var dmg := Label.new()
	dmg.text = "DMG %d" % game.monster_damage()
	dmg.add_theme_font_size_override("font_size", 12)
	dmg.add_theme_color_override("font_color", MUTED)
	dmg.tooltip_text = "danno che infligge ai cacciatori"
	icons.add_child(dmg)


## Traccia del round: la sequenza vera del regolamento, con la casella accesa
## dove siamo adesso. E' la risposta a «adesso a chi tocca»: Consume, poi il
## mostro, poi un turno per cacciatore in ordine di gioco, poi la fine del round.
## L'ordine parte dal giocatore aggro (p.17), non dal primo posto in tavola.
func _refresh_track() -> void:
	for c in _track_row.get_children():
		c.queue_free()
	if game.phase == PrimalGame.Phase.OVER:
		return

	var order := _turn_order()
	var here := _track_position()
	var steps: Array = [{"label": "Consume", "tip": "Ogni cacciatore può bere una pozione."},
		{"label": "%s: upkeep" % game.monster_name(),
		 "tip": "Il mostro rinnova le carte reazione e guadagna struggle."}]
	for i in order.size():
		var q: PrimalPlayer = order[i]
		var label: String = q.name
		var tip := "Turno di %s." % q.name
		if here == 2 + i:
			label += ": " + _sub_phase_name()
			tip = "Movimento, poi Azione, poi Attrition."
		if q.ko:
			label += " (KO)"
		steps.append({"label": label, "tip": tip})
	steps.append({"label": "Fine round", "tip": "Il fuoco si spegne, i dust si tolgono."})

	for i in steps.size():
		if i > 0:
			var arrow := Label.new()
			arrow.text = "›"
			arrow.add_theme_font_size_override("font_size", 12)
			arrow.add_theme_color_override("font_color", Color(0.34, 0.32, 0.31))
			_track_row.add_child(arrow)
		_track_row.add_child(_track_chip(String(steps[i]["label"]),
			String(steps[i]["tip"]), i - here))


## L'ordine di turno del round in corso: parte dal primo giocatore e gira.
## Prima dell'upkeep il primo giocatore e' ancora quello del round scorso: li'
## mostriamo l'ordine che ci sara', cioe' quello che parte dal giocatore aggro
## (Regolamento p.17), perche' e' quello che serve sapere per decidere adesso.
func _turn_order() -> Array:
	var start := game.first_player_index
	if game.phase == PrimalGame.Phase.CONSUME or game.phase == PrimalGame.Phase.UPKEEP:
		start = game.aggro_index
	var order: Array = []
	for i in game.players.size():
		order.append(game.players[(start + i) % game.players.size()])
	return order


## A che punto della traccia siamo: 0 Consume, 1 upkeep, 2+i il turno dell'i-esimo
## giocatore dell'ordine, in fondo la fine del round.
func _track_position() -> int:
	match game.phase:
		PrimalGame.Phase.CONSUME: return 0
		PrimalGame.Phase.UPKEEP: return 1
		PrimalGame.Phase.ROUND_END: return 2 + game.players.size()
	var order := _turn_order()
	for i in order.size():
		if order[i] == game.active_player():
			return 2 + i
	return 1


func _sub_phase_name() -> String:
	match game.phase:
		PrimalGame.Phase.MOVEMENT: return "movimento"
		PrimalGame.Phase.ACTION: return "azione"
		PrimalGame.Phase.ATTRITION: return "attrition"
		PrimalGame.Phase.TURN_END: return "fine turno"
	return "turno"


## `offset` < 0 e' gia' passato, 0 e' adesso, > 0 deve ancora venire.
func _track_chip(text: String, tip: String, offset: int) -> Control:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 11)
	if offset == 0:
		style.bg_color = Color(0.42, 0.22, 0.10)
		style.border_color = EMBER
		style.set_border_width_all(1)
		label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.68))
	elif offset < 0:
		style.bg_color = Color(0.10, 0.10, 0.11)
		label.add_theme_color_override("font_color", Color(0.40, 0.38, 0.36))
	else:
		style.bg_color = Color(0.14, 0.135, 0.14)
		label.add_theme_color_override("font_color", MUTED)
	chip.add_theme_stylebox_override("panel", style)
	chip.tooltip_text = tip
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	chip.add_child(label)
	return chip


## Ritratto: un ritaglio dell'illustrazione, non l'immagine intera. Le plance
## dei personaggi e le carte stance sono larghe e il soggetto sta da una parte;
## ridotte a 46 pixel non si capisce cosa siano. La finestra e' misurata a mano
## e sta nei dati (`art.portrait`), come tutto quello che si legge dalle immagini.
func _portrait(art: Dictionary) -> Texture2D:
	var portrait: Dictionary = art.get("portrait", {})
	var tex := _tex(String(portrait.get("art", art.get("board", ""))))
	if tex == null:
		return null
	var region: Array = portrait.get("region", [])
	if region.size() != 4:
		return tex
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = Rect2(
		float(region[0]) * tex.get_width(), float(region[1]) * tex.get_height(),
		float(region[2]) * tex.get_width(), float(region[3]) * tex.get_height())
	return atlas


## Riquadro di un'entita': ritratto quadrato, nome e la riga delle icone.
## La riga di icone si recupera con get_meta("icons").
func _entity_box(title: String, portrait: Texture2D, tint: Color) -> PanelContainer:
	var box := _panel(6, true)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)

	var face := TextureRect.new()
	face.texture = portrait
	face.custom_minimum_size = Vector2(60, 60)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	face.clip_contents = true
	row.add_child(face)
	box.set_meta("face", face)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var name := Label.new()
	name.text = title
	name.add_theme_font_size_override("font_size", 12)
	name.add_theme_color_override("font_color", tint)
	col.add_child(name)
	var icons := HBoxContainer.new()
	icons.add_theme_constant_override("separation", 3)
	col.add_child(icons)
	box.set_meta("icons", icons)
	return box


func _labelled(node: Control, tip: String) -> Control:
	node.tooltip_text = tip
	node.mouse_filter = Control.MOUSE_FILTER_STOP
	return node


## Riquadro di un cacciatore: salute, stamina e i suoi segnalini di stato.
func _hunter_card(p: PrimalPlayer) -> Control:
	var box := _panel(6, p == game.active_player())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	box.add_child(col)

	var name := Label.new()
	name.text = p.name
	name.add_theme_font_size_override("font_size", 12)
	name.add_theme_color_override("font_color",
		EMBER if p == game.active_player() else PARCHMENT)
	col.add_child(name)

	var stats := Label.new()
	stats.text = "%d/%d  mano %d  %s" % [
		maxi(p.max_health() - p.damage, 0), p.max_health(), p.hand.size(),
		game.sector_of(p.position)]
	stats.add_theme_font_size_override("font_size", 10)
	stats.add_theme_color_override("font_color", MUTED)
	col.add_child(stats)

	# Le carte del cacciatore: arma ed equipaggiamento, a vista.
	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 3)
	var w := p.weapon()
	cards.add_child(_mini_card(String(w.get("art", "")),
		"%s — liv. %d, %d danni\n%s" % [w.get("name", "?"), int(w.get("level", 1)),
			int(w.get("damage", 0)), Db.card_text(w)]))
	var am: Dictionary = p.loadout.get("armor", p.data().get("armor", {}))
	var hm: Dictionary = p.loadout.get("helm", p.data().get("helm", {}))
	cards.add_child(_mini_card(String(am.get("art", "")),
		"%s — %d salute" % [am.get("name", "?"), int(am.get("health", 0))]))
	cards.add_child(_mini_card(String(hm.get("art", "")),
		"%s — %d salute" % [hm.get("name", "?"), int(hm.get("health", 0))]))
	var ma := p.mastery()
	cards.add_child(_mini_card(String(ma.get("art_focused" if p.mastery_focused else "art", "")),
		"%s — %s" % [ma.get("name", "?"),
			"focalizzata" if p.mastery_focused else "%d/%d segnalini" % [
				p.mastery_counters, int(ma.get("focus", 1))]]))
	for potion in p.potions:
		cards.add_child(_mini_card(String(potion.get("art", "")),
			"%s\n%s" % [potion.get("name", "?"), Db.card_text(potion)]))
	col.add_child(cards)

	var tokens := HBoxContainer.new()
	tokens.add_theme_constant_override("separation", 3)
	if p.damage > 0:
		tokens.add_child(_labelled(_token("damage", p.damage, 22), "danni subiti"))
	if p.stamina_token > 0:
		tokens.add_child(_labelled(_token("stamina", -1, 22), "segnalino stamina"))
	if p.threatened:
		tokens.add_child(_labelled(_token("threatened", -1, 22), "threatened"))
	if p.burning:
		tokens.add_child(_labelled(_token("burning", -1, 22), "burning"))
	if p.ko:
		tokens.add_child(_labelled(_token("ko", -1, 22), "KO"))
	if p.armor_depleted or p.helm_depleted:
		tokens.add_child(_labelled(_token("depleted", -1, 22), "equipaggiamento esaurito"))
	if game.aggro_index == p.seat:
		tokens.add_child(_labelled(_aggro_badge(), "ha il segnalino aggro"))
	col.add_child(tokens)
	return box


## Nel mod TTS non esiste un'immagine per il segnalino aggro: lo disegniamo.
## Miniatura di una carta equipaggiamento, con i dati nel tooltip.
func _mini_card(art_path: String, tip: String) -> Control:
	var art := TextureRect.new()
	art.texture = _tex(art_path)
	art.custom_minimum_size = Vector2(34, 24)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.tooltip_text = tip
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	return art


func _aggro_badge() -> Control:
	var badge := Label.new()
	badge.text = "AGGRO"
	badge.custom_minimum_size = Vector2(50, 22)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_theme_font_size_override("font_size", 10)
	badge.add_theme_color_override("font_color", Color.WHITE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.72, 0.20, 0.18)
	style.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("normal", style)
	return badge


func _phase_name() -> String:
	match game.phase:
		PrimalGame.Phase.CONSUME: return "Consume"
		PrimalGame.Phase.UPKEEP: return "Upkeep del mostro"
		PrimalGame.Phase.MOVEMENT: return "Movimento"
		PrimalGame.Phase.ACTION: return "Azione"
		PrimalGame.Phase.ATTRITION: return "Attrition"
		PrimalGame.Phase.ROUND_END: return "Fine round"
		PrimalGame.Phase.OVER: return "Partita conclusa"
	return "-"


func _refresh_board() -> void:
	board.set_monster_facing(game.monster_facing)
	# Quanti cacciatori condividono ogni casella, per non sovrapporre le miniature.
	var per_sector := {}
	for p in game.players:
		per_sector[p.position] = int(per_sector.get(p.position, 0)) + 1
	var placed := {}
	var active := game.active_player()
	for p in game.players:
		var slot := int(placed.get(p.position, 0))
		placed[p.position] = slot + 1
		board.set_hunter_position(p.id, p.position, p.ko, slot,
			int(per_sector[p.position]), p == active)
	var reachable: Array = []
	if game.phase == PrimalGame.Phase.MOVEMENT:
		var pos := active.position
		reachable = [posmod(pos + 1, 4), posmod(pos - 1, 4)]
	board.highlight_sectors(reachable, game.current_stance().get("exposed", []), game.monster_facing)
	board.set_terrain(game.terrain, game.dust)


## Scheda del mostro: la stance corrente con i suoi peril e objective, e le tre
## carte reazione in gioco — coperte, come sul tavolo, con l'icona di reazione a
## vista e il valore di refresh.
## Le quattro plance mostro hanno lo stesso stampo: la traccia salute in alto,
## dieci caselle, e per Dygorax e Toramat una seconda traccia da tre a destra
## (hardening e acceleration). Le posizioni sono frazioni misurate una volta
## sull'immagine — valgono per tutte e quattro.
const TRACK_X := 0.418
const TRACK_DX := 0.0588
const TRACK_Y := 0.068
const TRACK2_X := 0.831
const TRACK2_Y := 0.200
## I tre riquadri stampati in mezzo alla plancia, dove sul tavolo si appoggiano
## le carte reazione. Anche questi misurati una volta: lo stampo e' lo stesso.
const SLOT_X := 0.065
const SLOT_STEP := 0.325
const SLOT_W := 0.235
const SLOT_Y := 0.355
const SLOT_H := 0.520


## Segnalino tondo sulla plancia, alla casella `step` della traccia. Sta su
## ancore, non su pixel: cosi' resta al suo posto qualunque misura prenda la
## plancia quando la finestra viene ridimensionata.
func _board_marker(x0: float, y: float, step: int, colour: Color) -> Control:
	var ring := Panel.new()
	var side := 11.0
	var fx := x0 + float(step - 1) * TRACK_DX
	ring.anchor_left = fx
	ring.anchor_right = fx
	ring.anchor_top = y
	ring.anchor_bottom = y
	ring.offset_left = -side * 0.5
	ring.offset_right = side * 0.5
	ring.offset_top = -side * 0.5
	ring.offset_bottom = side * 0.5
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(colour.r, colour.g, colour.b, 0.45)
	style.border_color = colour
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(side * 0.5))
	ring.add_theme_stylebox_override("panel", style)
	return ring


## La plancia del mostro con i segnalini dove sono adesso: salute sempre,
## hardening o acceleration dove quella traccia esiste.
func _monster_board_view() -> Control:
	var art := String(Db.monster(game.monster_id).get("art", {}).get("board", ""))
	var tex := _tex(art)
	if tex == null:
		return null
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(MONSTER_CARD_W,
		MONSTER_CARD_W * float(tex.get_height()) / float(tex.get_width()))
	# Il riquadro non si allarga oltre la plancia: i segnalini stanno su ancore
	# relative a lui, e se restasse dello spazio vuoto ai lati finirebbero fuori.
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var board := TextureRect.new()
	board.texture = tex
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	board.stretch_mode = TextureRect.STRETCH_SCALE
	board.tooltip_text = "%s — salute %d/10" % [game.monster_name(), game.monster_health]
	board.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(board)

	# Le tre carte reazione vanno nei loro riquadri, come sul tavolo: erano una
	# fila in fondo al pannello, e i riquadri restavano vuoti a fare da disegno.
	for slot in 3:
		var bid: int = game.behavior_slots[slot]
		if bid < 0:
			continue
		var b := Db.behavior(bid)
		var card := TextureRect.new()
		card.texture = _tex(String(b.get("back", "")))
		card.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card.stretch_mode = TextureRect.STRETCH_SCALE
		card.anchor_left = SLOT_X + float(slot) * SLOT_STEP
		card.anchor_right = card.anchor_left + SLOT_W
		card.anchor_top = SLOT_Y
		card.anchor_bottom = SLOT_Y + SLOT_H
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		var stunned: bool = game.stunned_behaviors.has(slot)
		if stunned:
			card.modulate = Color(0.5, 0.5, 0.58)
		card.tooltip_text = "Reazione: %s\nRefresh %d%s" % [
			Db.common.get("reactions", {}).get(String(b.get("reaction", "")), "?"),
			int(b.get("refresh", 0)), "\n\nStordita: non si innesca in questo round." \
				if stunned else ""]
		holder.add_child(card)

	holder.add_child(_board_marker(TRACK_X, TRACK_Y,
		clampi(game.monster_health, 1, 10), Color(0.92, 0.25, 0.22)))
	# La seconda traccia esiste solo su chi ce l'ha stampata.
	if game.hardening > 0:
		holder.add_child(_board_marker(TRACK2_X, TRACK2_Y,
			clampi(game.hardening, 1, 3), Color(0.55, 0.75, 1.0)))
	elif game.acceleration > 0:
		holder.add_child(_board_marker(TRACK2_X, TRACK2_Y,
			clampi(game.acceleration, 1, 3), Color(1.0, 0.78, 0.3)))
	return holder


func _refresh_behaviors() -> void:
	for c in _monster_box.get_children():
		c.queue_free()

	# La plancia sta sopra le carte, come sul tavolo: e' il pezzo su cui si
	# appoggiano gli altri, e porta la traccia della salute.
	var board := _monster_board_view()
	if board != null:
		_monster_box.add_child(_heading(game.monster_name()))
		_monster_box.add_child(board)

	# Niente statistiche qui: sono gia' nella barra in alto. Le tre carte del
	# mostro in colonna e **della stessa misura** — stance, peril e obiettivo
	# contano allo stesso modo, e rimpicciolirne due le faceva sembrare note a
	# margine. In fondo le reazioni, che invece sono coperte.
	var stance := game.current_stance()
	_monster_box.add_child(_card_slot("Stance %s" % ["I", "II", "III"][game.stance_index],
		String(stance.get("art", "")), MONSTER_CARD_W))
	if stance.has("peril"):
		var peril := Db.peril(int(stance["peril"]))
		_monster_box.add_child(_card_slot("Peril", String(peril.get("art", "")),
			MONSTER_CARD_W, "%s\n%s" % [peril.get("name", ""), Db.card_text(peril)]))
	if stance.has("objective"):
		var obj := Db.objective(int(stance["objective"]))
		var counters := int(game.objective_counters.get(int(stance["objective"]), 0))
		_monster_box.add_child(_card_slot(
			"Obiettivo" + ("  (%d)" % counters if counters > 0 else ""),
			String(obj.get("art", "")), MONSTER_CARD_W,
			"%s\n%s" % [obj.get("name", ""), Db.card_text(obj)]))



## Proporzione altezza/larghezza di un'immagine.
func _aspect(art_path: String, fallback: float) -> float:
	var tex := _tex(art_path)
	if tex == null or tex.get_width() <= 0:
		return fallback
	return float(tex.get_height()) / float(tex.get_width())


## Come `_card_slot`, ma e' l'altezza a comandare: serve a far tornare armor e
## helm esattamente a meta' dell'arma, qualunque sia la forma delle immagini.
func _card_slot_h(title: String, art_path: String, height: float, tip := "") -> Control:
	var tex := _tex(art_path)
	var ratio := 1.4
	if tex != null and tex.get_height() > 0:
		ratio = float(tex.get_width()) / float(tex.get_height())
	return _card_slot(title, art_path, roundi(height * ratio), tip)


## Fila di carte dentro una colonna stretta.
func _card_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	return row


## Una carta con la sua etichetta sopra, distanziata dalle altre.
func _card_slot(title: String, art_path: String, width: int, tip := "") -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	# Senza titolo non si mette una riga vuota: le carte si toccano e la colonna
	# resta compatta.
	if title != "":
		var label := Label.new()
		label.text = title
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", EMBER)
		col.add_child(label)
	var art := TextureRect.new()
	var tex := _tex(art_path)
	art.texture = tex
	# In un contenitore orizzontale l'altezza non si deduce da sola: la ricaviamo
	# dalle proporzioni dell'immagine, altrimenti la carta resta alta zero.
	var ratio := 1.4
	if tex != null and tex.get_width() > 0:
		ratio = float(tex.get_height()) / float(tex.get_width())
	art.custom_minimum_size = Vector2(width, float(width) * ratio)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	art.tooltip_text = tip
	# Senza tooltip la carta non deve nemmeno prendersi il puntatore.
	art.mouse_filter = Control.MOUSE_FILTER_STOP if tip != "" \
		else Control.MOUSE_FILTER_IGNORE
	col.add_child(art)
	return col


## Immagine ingrandibile al passaggio del mouse.
func _inspectable(path: String, w: int, h: int, tip: String = "") -> Control:
	var art := TextureRect.new()
	art.texture = _tex(path)
	art.custom_minimum_size = Vector2(w, h)
	art.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	art.tooltip_text = tip
	art.mouse_entered.connect(func(): _show_zoom(path))
	art.mouse_exited.connect(_hide_zoom)
	return art


func _refresh_sequence() -> void:
	var p := game.active_player()
	board.show_sequence(p.sequence, p.position)

	for c in _sequence_row.get_children():
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.queue_free()
	# La finestra compare da sola alla prima carta giocata e si richiude a fine
	# turno; chi la chiude a mano se la riapre dal pulsante nella barra.
	if p.sequence.is_empty():
		_sequence_window.hide()
		_sequence_closed_by_hand = false
		return
	if not _sequence_window.visible and not _sequence_closed_by_hand:
		_sequence_window.show()
	_sequence_window.title = "Sequenza di %s — %d/%d" % [
		p.name, p.sequence.size(), game.sequence_limit_of(p)]
	for cid in p.sequence:
		var card := Db.action(cid)
		_sequence_row.add_child(_inspectable(_card_art_path(cid), 130, 182,
			"%s  (%s)\n%s" % [card.get("name", "?"), card.get("type", "?"),
				Db.card_text(card)]))


## Scheda del cacciatore: schede per scegliere chi guardare, statistiche, le sue
## carte equipaggiamento alla stessa dimensione di quelle del mostro, e i pulsanti
## di scelta del momento.
## In alto: una targhetta per cacciatore con statistiche e segnalini. Cliccandola
## si apre il suo inventario nella finestra Cacciatore.
func _refresh_party() -> void:
	for c in _party_row.get_children():
		c.queue_free()
	var active := game.active_player()
	if game.active_index != _last_active or _shown_hunter == "":
		_last_active = game.active_index
		_shown_hunter = active.id

	for q in game.players:
		var tint: Color = EMBER if q == active else PARCHMENT
		var box := _entity_box(q.name + ("  •" if q == active else ""),
			_portrait(Db.hunter(q.id).get("art", {})), tint)
		var icons: HBoxContainer = box.get_meta("icons")
		icons.add_child(_labelled(
			_token("counter", maxi(q.max_health() - q.damage, 0), 28), "salute"))
		if q.damage > 0:
			icons.add_child(_labelled(_token("damage", q.damage, 28), "ferite subite"))
		if q.stamina_token > 0:
			icons.add_child(_labelled(_token("stamina", -1, 28), "segnalino stamina"))
		if q.threatened:
			icons.add_child(_labelled(_token("threatened", -1, 28), "threatened"))
		if q.burning:
			icons.add_child(_labelled(_token("burning", -1, 28), "burning"))
		if q.ko:
			icons.add_child(_labelled(_token("ko", -1, 28), "KO"))
		if q.armor_depleted or q.helm_depleted:
			icons.add_child(_labelled(_token("depleted", -1, 28), "equipaggiamento esaurito"))
		if game.aggro_index == q.seat:
			icons.add_child(_labelled(_aggro_badge(), "ha il segnalino aggro"))

		# Il ritratto apre l'inventario del personaggio.
		var face: TextureRect = box.get_meta("face")
		face.mouse_filter = Control.MOUSE_FILTER_STOP
		face.tooltip_text = "Clicca per aprire o chiudere l'inventario di %s" % q.name
		var hid := q.id
		face.gui_input.connect(func(event):
			if not (event is InputEventMouseButton and event.pressed):
				return
			var w: Window = _windows.get("Cacciatore")
			if w == null:
				return
			# Stesso ritratto due volte: chiude. Ritratto diverso: cambia personaggio.
			if w.visible and _shown_hunter == hid:
				w.hide()
			else:
				_shown_hunter = hid
				w.show()
				(_windows["Mostro"] as Window).hide()
			_refresh_party())
		_party_row.add_child(box)

	_refresh_inventory()


## Inventario disposto come sulla plancia del cacciatore (Regolamento p.8):
## la mastery sta a parte, non fra l'equipaggiamento; poi weapon, armor, helm e
## le pozioni, ciascuna nel suo spazio.
func _refresh_inventory() -> void:
	for c in _hunter_box.get_children():
		c.queue_free()
	var shown: PrimalPlayer = game.active_player()
	for q in game.players:
		if q.id == _shown_hunter:
			shown = q

	# Come sulla plancia del cacciatore: l'arma grande a sinistra con sotto la
	# mastery, e tutto l'equipaggiamento impilato a destra — armor, helm e
	# pozioni, ciascuno **alto la meta'** dell'arma.
	#
	# Niente tooltip su queste carte: quello che direbbero (nome, livello, danno,
	# testo dell'abilita') e' gia' stampato sulla carta che si sta guardando.
	# Restano solo le etichette che dicono qualcosa che la carta **non** dice:
	# i segnalini della mastery e l'equipaggiamento esaurito.
	var w := shown.weapon()
	var am: Dictionary = shown.loadout.get("armor", shown.data().get("armor", {}))
	var hm: Dictionary = shown.loadout.get("helm", shown.data().get("helm", {}))
	# La larghezza dell'arma non e' fissa: si ricava all'indietro dallo spazio
	# che c'e'. L'equipaggiamento e' alto meta' dell'arma ma sono carte
	# *coricate*, quindi larghe il doppio in proporzione, e a misura fissa
	# uscivano dalla colonna. Qui si risolve `arma + equipaggiamento = spazio`.
	var room := SIDE_SIZE.x - 52.0
	var w_ratio := _aspect(String(w.get("art", "")), 1.4)          # altezza/larghezza
	var gear_ratio := 1.0 / _aspect(String(am.get("art", "")), 0.65)   # larghezza/altezza
	var weapon_w := clampf(room / (1.0 + w_ratio * gear_ratio * 0.5), 110.0, 210.0)
	var weapon_h := weapon_w * w_ratio

	var top := _card_row()
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.add_child(_card_slot("", String(w.get("art", "")), roundi(weapon_w)))

	# La mastery sta sotto l'arma, e finche' non e' focalizzata resta spenta.
	var ma := shown.mastery()
	var mastery_slot := _card_slot(
		"Mastery — %s" % ("focalizzata" if shown.mastery_focused
			else "%d/%d" % [shown.mastery_counters, int(ma.get("focus", 1))]),
		String(ma.get("art_focused" if shown.mastery_focused else "art", "")),
		roundi(weapon_w))
	if not shown.mastery_focused:
		mastery_slot.modulate = Color(0.55, 0.55, 0.58)
	left.add_child(mastery_slot)
	top.add_child(left)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	stack.add_child(_card_slot_h("esaurita" if shown.armor_depleted else "",
		String(am.get("art", "")), weapon_h * 0.5))
	stack.add_child(_card_slot_h("esaurito" if shown.helm_depleted else "",
		String(hm.get("art", "")), weapon_h * 0.5))
	for potion in shown.potions:
		stack.add_child(_card_slot_h("", String(potion.get("art", "")), weapon_h * 0.5))
	top.add_child(stack)
	_hunter_box.add_child(top)


## Carta equipaggiamento nella scheda, grande come quelle del mostro.
func _gear_card(art_path: String, tip: String, scale := 1.0) -> Control:
	var art := TextureRect.new()
	art.texture = _tex(art_path)
	art.custom_minimum_size = Vector2(124, 88) * scale
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	art.tooltip_text = tip
	art.mouse_filter = Control.MOUSE_FILTER_STOP
	return art


func _refresh_hand() -> void:
	_refresh_pay_banner()
	for c in _hand_layer.get_children():
		# `queue_free` libera al frame dopo: se il puntatore e' sopra una carta,
		# nel frattempo scatta il suo `mouse_exited` su un nodo gia' liberato.
		# Spegnere il mouse prima chiude quella finestra.
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.queue_free()
	var p := game.active_player()
	var cards := p.hand
	if cards.is_empty():
		return

	var view := _root_ui.size
	# L'arco ha il centro sotto lo schermo: le carte restano in basso, come se le
	# tenessi in mano, e solo il bordo superiore sporge.
	var radius := 900.0
	var spread := minf(float(cards.size() - 1) * 92.0, view.x * 0.58)
	var top := view.y - HAND_H + 44.0
	var centre := Vector2(view.x * 0.5, top + radius)

	# Di chi e' questa mano: in hotseat le carte a schermo cambiano padrone a
	# ogni turno, e senza scritta sembrano sempre le stesse.
	var caption := Label.new()
	caption.text = "MANO DI %s — %d carte" % [p.name.to_upper(), cards.size()]
	if _pending_play < 0 and game.phase == PrimalGame.Phase.ACTION:
		caption.text += "   ·   clicca per giocare"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", MUTED)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.size = Vector2(view.x, 18)
	caption.position = Vector2(0, top - 22.0)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hand_layer.add_child(caption)

	for i in cards.size():
		var cid: int = cards[i]
		var t := 0.0 if cards.size() == 1 else float(i) / float(cards.size() - 1) - 0.5
		var angle := t * (spread / radius)
		var pos := centre + Vector2(sin(angle), -cos(angle)) * radius
		_hand_layer.add_child(_hand_card(cid, p, pos, angle, i))


## Durante il pagamento la striscia dice cosa stai facendo, quanto manca e come
## entra il segnalino stamina.
func _refresh_pay_banner() -> void:
	if _pay_banner == null:
		return
	for c in _pay_banner_row.get_children():
		c.queue_free()
	_pay_banner.visible = _pending_play >= 0
	if _pending_play < 0:
		return

	var p := game.active_player()
	var cost := int(_pay_request.get("cost", 0))
	var from_cards := 0
	for cid in _pay_selection:
		from_cards += int(Db.action(cid).get("stamina", 0))

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size = Vector2(560, 26)
	title.text = "[b][color=#e08a3c]STAI PAGANDO[/color][/b]  %s costa %d stamina — clicca le carte da [b]scartare[/b]: %d/%d" % [
		Db.action(int(_pay_request.get("playing", -1))).get("name", "la carta"),
		cost, from_cards, cost]
	_pay_banner_row.add_child(title)

	# Il segnalino stamina: si vede se c'e' e se sta coprendo la differenza.
	if p.stamina_token > 0:
		var uses_token := from_cards < cost
		var token := _token("stamina", -1, 30)
		token.modulate = Color.WHITE if uses_token else Color(0.45, 0.45, 0.48)
		_pay_banner_row.add_child(_labelled(token,
			"segnalino stamina: %s" % ("copre 1 di quel che manca"
				if uses_token else "conservato, stai pagando tutto con le carte")))

	# Quando il segnalino da solo basta a coprire quel che manca serve un modo
	# per confermare: senza carte in mano da cliccare non ce ne sarebbe nessuno,
	# e il pagamento resterebbe li' per sempre.
	if _generated() >= cost:
		var pay := Button.new()
		pay.text = "Paga col segnalino" if from_cards < cost else "Paga"
		pay.pressed.connect(func(): call_deferred("_finish_payment"))
		_pay_banner_row.add_child(pay)
	elif not _has_payable_cards(p):
		# Niente carte utili e segnalino insufficiente: non si puo' pagare.
		var give_up := Button.new()
		give_up.text = "Lascia scegliere al gioco"
		give_up.pressed.connect(func(): call_deferred("_cancel_payment"))
		_pay_banner_row.add_child(give_up)

	_pay_banner.position = Vector2(_root_ui.size.x * 0.5 - 320.0,
		_root_ui.size.y - HAND_H - 74.0)


func _hand_card(card_id: int, p: PrimalPlayer, pos: Vector2, angle: float, index: int) -> Control:
	var card := Db.action(card_id)
	var btn := TextureButton.new()
	btn.texture_normal = _card_texture(card_id)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
	btn.size = Vector2(HAND_W, HAND_H)
	btn.pivot_offset = Vector2(HAND_W * 0.5, HAND_H)
	btn.position = pos - Vector2(HAND_W * 0.5, 0)
	btn.rotation = angle

	var cost := p.cost_of(card_id)
	var paying := _pending_play >= 0
	var refusal := game.why_not_playable(p, card_id)
	var playable := not paying and refusal == ""
	var usable_for_pay := paying and card_id != _pending_play \
		and int(Db.action(card_id).get("stamina", 0)) > 0
	var chosen := _pay_selection.has(card_id)

	if chosen:
		# Rosso: questa carta la stai buttando per pagare, non la stai giocando.
		btn.modulate = Color(1.35, 0.55, 0.42)
	elif paying:
		btn.modulate = Color(0.95, 0.85, 0.8) if usable_for_pay else Color(0.32, 0.32, 0.36)
	else:
		btn.modulate = Color.WHITE if playable else Color(0.5, 0.5, 0.55)

	btn.tooltip_text = "%s  (%s, costo %d, genera %d)\n%s%s" % [
		card.get("name", "?"), card.get("type", "?"), cost,
		int(card.get("stamina", 0)), Db.card_text(card),
		("\n\n[non giocabile: %s]" % refusal) if refusal != "" and not paying else ""]

	# Evidenziazione: la carta si alza, si raddrizza e si ingrandisce. Non serve
	# un'anteprima separata, e' la carta stessa a diventare leggibile.
	var base := btn.position
	btn.mouse_entered.connect(func():
		btn.position = base - Vector2(0, 92)
		btn.rotation = 0.0
		btn.scale = Vector2(1.55, 1.55)
		btn.z_index = 10)
	btn.mouse_exited.connect(func():
		btn.position = base
		btn.rotation = angle
		btn.scale = Vector2.ONE
		btn.z_index = 0)
	btn.pressed.connect(func(): _on_hand_card(card_id))
	return btn


## Un clic in mano: gioca la carta, oppure la sceglie per pagare la stamina.
func _on_hand_card(card_id: int) -> void:
	if _pending_play >= 0:
		if card_id == _pending_play:
			return
		if _pay_selection.has(card_id):
			_pay_selection.erase(card_id)
		else:
			_pay_selection.append(card_id)
		if _generated() >= int(_pay_request.get("cost", 0)):
			_finish_payment()
		else:
			_refresh_hand()
			_refresh_actions()
		return
	if game.phase != PrimalGame.Phase.ACTION:
		return
	call_deferred("_do_play", card_id)


## Stamina generata dalle carte scelte, piu' il segnalino se serve a coprire.
func _generated() -> int:
	var total := 0
	for cid in _pay_selection:
		total += int(Db.action(cid).get("stamina", 0))
	if total < int(_pay_request.get("cost", 0)):
		total += int(_pay_request.get("tokens", 0))
	return total


## Carte in mano che generano stamina e non sono quella che si sta giocando.
func _has_payable_cards(p: PrimalPlayer) -> bool:
	for cid in p.hand:
		if cid == _pending_play:
			continue
		if int(Db.action(cid).get("stamina", 0)) > 0:
			return true
	return false


## Rinuncia a scegliere: risponde con una selezione vuota e lascia che sia il
## motore a completare il pagamento con quel che c'e' (o a rifiutare la giocata).
func _cancel_payment() -> void:
	_pending_play = -1
	_pay_request = {}
	_pay_selection.clear()
	call_deferred("_deliver_answer", [])


func _finish_payment() -> void:
	var answer := _pay_selection.duplicate()
	_pending_play = -1
	_pay_request = {}
	_pay_selection.clear()
	call_deferred("_deliver_answer", answer)


func _card_thumb(card_id: int, w: int, h: int) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _card_texture(card_id)
	t.custom_minimum_size = Vector2(w, h)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	return t
func _refresh_actions() -> void:
	for c in _actions_row.get_children():
		c.queue_free()
	if _pending_play >= 0:
		_prompt.text = "[color=#c8763c]Scarta dalla mano per pagare:  %d/%d stamina[/color]" % [
			_generated(), int(_pay_request.get("cost", 0))]
		return
	_prompt.text = _phase_prompt()
	match game.phase:
		PrimalGame.Phase.CONSUME:
			_actions_row.add_child(_button("Salta la fase Consume",
				func(): call_deferred("_do_finish_consume")))
			var p := game.active_player()
			for i in p.potions.size():
				var idx := i
				_actions_row.add_child(_button("Bevi %s" % p.potions[i].get("name", "pozione"),
					func(): call_deferred("_do_consume", idx)))
		PrimalGame.Phase.MOVEMENT:
			# Ci si sposta cliccando la casella sulla plancia: si vede dove si va.
			_actions_row.add_child(_button("Resta fermo (diventa threatened)",
				func(): call_deferred("_do_move", -1)))
		PrimalGame.Phase.ACTION:
			_actions_row.add_child(_button("Termina fase Azione",
				func(): call_deferred("_do_end_action")))
			for other in game.players:
				if other == game.active_player() or other.ko or other.assisted_this_turn:
					continue
				for cid in other.hand:
					if "assist" in Db.action(cid).get("keywords", []):
						var seat := other.seat
						var c := cid
						_actions_row.add_child(_button(
							"%s assiste (%s)" % [other.name, Db.action(c).get("name", "?")],
							func(): call_deferred("_do_assist", seat, c)))
						break
			for other in game.players:
				if other.ko and other.position == game.active_player().position:
					var seat2 := other.seat
					_actions_row.add_child(_button("Revive %s (2 stamina)" % other.name,
						func(): call_deferred("_do_revive", seat2)))
		PrimalGame.Phase.OVER:
			_actions_row.add_child(_button("Nuova partita", func(): call_deferred("_do_restart")))
			if _level > 0:
				_actions_row.add_child(_button("Cambia mazzo ed equipaggiamento",
					func(): call_deferred("_open_loadout")))


## Cosa ci si aspetta adesso, da chi, e cosa succede subito dopo. La terza parte
## e' quella che mancava: senza, ogni fase sembrava l'ultima.
func _phase_prompt() -> String:
	var p := game.active_player()
	match game.phase:
		PrimalGame.Phase.CONSUME:
			return "[b]Consume[/b] — bevi una pozione o passa. " \
				+ "[color=#8a8580]Poi tocca a %s.[/color]" % game.monster_name()
		PrimalGame.Phase.UPKEEP:
			return "[b]%s[/b] — rinnova le reazioni e accumula struggle." % game.monster_name()
		PrimalGame.Phase.MOVEMENT:
			return "[b]%s — movimento[/b]: clicca una casella evidenziata, o resta fermo. " \
				% p.name + "[color=#8a8580]Poi giochi le carte.[/color]"
		PrimalGame.Phase.ACTION:
			return "[b]%s — azione[/b]: clicca una carta della mano, finisce in sequenza sul tavolo (%d/%d). " \
				% [p.name, p.sequence.size(), game.sequence_limit_of(p)] \
				+ "[color=#8a8580]Poi l'attrition, e a fine turno peschi.[/color]"
		PrimalGame.Phase.ATTRITION:
			return "[b]%s — attrition[/b]: le carte difensive in sequenza reggono il colpo." % p.name
		PrimalGame.Phase.ROUND_END:
			return "[b]Fine del round %d[/b]." % game.round_no
		PrimalGame.Phase.OVER:
			return "Partita conclusa."
	return ""


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	# Non si allarga a tutta la finestra: resta della misura del suo testo.
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(action)
	return b


# =====================================================================
#  COMANDI (coroutine: avviati con call_deferred dai pulsanti)
# =====================================================================

func _do_play(card_id: int) -> void:
	if game.phase != PrimalGame.Phase.ACTION:
		return
	if not await game.play_card(card_id):
		_on_log("[color=#ff8080]Non puoi giocare questa carta ora.[/color]")
	_refresh()


func _do_move(to_position: int) -> void:
	await game.move(to_position)
	_refresh()


func _do_end_action() -> void:
	await game.end_action_phase()
	_refresh()


func _do_finish_consume() -> void:
	await game.finish_consume_phase()
	_refresh()


func _do_consume(index: int) -> void:
	await game.consume(game.active_player(), index)
	_refresh()


func _do_assist(seat: int, card_id: int) -> void:
	await game.assist(game.players[seat], card_id)
	_refresh()


func _do_revive(seat: int) -> void:
	await game.revive(game.players[seat])
	_refresh()


func _do_restart() -> void:
	_log_lines.clear()
	_log_view.clear()
	game.expedition = _expedition
	await game.setup(_party, _level, 0, _loadouts)
	_refresh()



func _open_loadout() -> void:
	_loadout_screen.setup(_party, _level)
	_loadout_screen.visible = true
	_show_game_ui(false)


## Mentre si costruisce il mazzo la partita non c'e' ancora: finestre, registro
## e mano restano fuori dai piedi.
func _show_game_ui(on: bool) -> void:
	for title in _windows:
		var w: Window = _windows[title]
		if on:
			if title == "Mostro":
				w.show()
		else:
			w.hide()
	_log_panel.visible = on and _log_toggle.button_pressed
	_hand_layer.visible = on
	if _sequence_panel_visible() and not on:
		_sequence_window.hide()


func _sequence_panel_visible() -> bool:
	return _sequence_window != null and _sequence_window.visible


# =====================================================================
#  INTERAZIONE
# =====================================================================

func _on_sector_clicked(position: int) -> void:
	if game.phase != PrimalGame.Phase.MOVEMENT or _choice_panel.visible:
		return
	if position == game.active_player().position:
		call_deferred("_do_move", -1)
	else:
		call_deferred("_do_move", position)


func _show_zoom(path: String) -> void:
	if _choice_panel.visible:
		return
	var tex := _tex(path)
	if tex == null:
		return
	_card_zoom.texture = tex
	_card_zoom.visible = true
	_place_zoom()


func _hide_zoom() -> void:
	_card_zoom.visible = false


## Le due cose che si guardano invece di deciderle: la behavior appena rivelata
## e l'esito dell'attrition. Il motore resta sospeso finche' non si chiude il
## riquadro — al tavolo la carta la giri e la leggi con calma, e soprattutto
## cosi' la domanda che segue («la scarti?») arriva **dopo**, non sopra.
func _fill_notice() -> void:
	_choice_notice.visible = true
	match String(_choice_request.get("topic", "")):
		"behavior": _notice_behavior(_choice_request.get("behavior", {}))
		"attrition": _notice_attrition(_choice_request.get("outcome", {}))
	_add_footer_button("Continua", func(): _respond(null))


func _notice_behavior(behavior: Dictionary) -> void:
	_choice_prompt.text = "[color=#9e9a94]IL MOSTRO REAGISCE[/color]"
	var title := Label.new()
	title.text = "%s: %s" % [game.monster_name(), behavior.get("name", "?")]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", EMBER)
	_choice_notice.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_choice_notice.add_child(row)

	var art := TextureRect.new()
	art.texture = _tex(String(behavior.get("art", "")))
	art.custom_minimum_size = Vector2(230, 322)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	row.add_child(art)

	var body := Label.new()
	body.text = Db.card_text(behavior)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 420
	body.add_theme_font_size_override("font_size", 14)
	body.add_theme_color_override("font_color", PARCHMENT)
	row.add_child(body)


## Le carte attrition uscite e il conto: valore peggiore contro carte difensive.
func _notice_attrition(outcome: Dictionary) -> void:
	var who: PrimalPlayer = game.players[int(outcome.get("player", 0))]
	var worst := int(outcome.get("worst", 0))
	var defensive := int(outcome.get("defensive", 0))
	var damage := int(outcome.get("damage", 0))
	_choice_prompt.text = "[color=#9e9a94]ATTRITION — %s[/color]" % who.name.to_upper()

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_choice_notice.add_child(row)
	for idx in outcome.get("cards", []):
		var card: Dictionary = game.attrition_cards[int(idx)]
		var art := TextureRect.new()
		art.texture = _tex(String(card.get("art", "")))
		art.custom_minimum_size = Vector2(130, 182)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		row.add_child(art)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	row.add_child(col)

	var why := Label.new()
	why.text = "sei threatened: due carte, conta la peggiore" \
		if bool(outcome.get("threatened", false)) else "una carta"
	why.add_theme_font_size_override("font_size", 12)
	why.add_theme_color_override("font_color", MUTED)
	col.add_child(why)

	var kind := String(outcome.get("required_type", ""))
	var counted := "difensive" if kind == "" else String(kind)
	var sums := Label.new()
	sums.text = "valore %d   contro   %d %s in sequenza" % [worst, defensive, counted]
	sums.add_theme_font_size_override("font_size", 16)
	sums.add_theme_color_override("font_color", PARCHMENT)
	col.add_child(sums)

	var verdict := Label.new()
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.custom_minimum_size.x = 380
	verdict.add_theme_font_size_override("font_size", 17)
	if damage > 0:
		verdict.text = "Ne mancano %d: %s subisce %s." % [worst - defensive, who.name,
			"1 danno" if damage == 1 else "%d danni" % damage]
		verdict.add_theme_color_override("font_color", Color(0.92, 0.45, 0.38))
	elif String(outcome.get("prevented_by", "")) != "":
		verdict.text = "Il colpo c'era, ma lo para %s." % outcome["prevented_by"]
		verdict.add_theme_color_override("font_color", Color(0.85, 0.75, 0.45))
	else:
		verdict.text = "Reggi il colpo: nessun danno."
		verdict.add_theme_color_override("font_color", Color(0.6, 0.82, 0.55))
	col.add_child(verdict)


## Registro al contrario: l'ultima azione sta in cima. Round in evidenza e nome
## di chi agisce in grassetto colorato.
func _on_log(text: String) -> void:
	_log_lines.push_front(_format_log(text))
	if _log_lines.size() > 120:
		_log_lines.resize(120)
	_log_view.text = "\n".join(_log_lines)
	# La riga piu' recente sta in cima: la vista deve restare li'.
	_log_view.scroll_to_line(0)


func _format_log(text: String) -> String:
	if text.begins_with("--- Round"):
		return "\n[b][color=#c8763c]%s[/color][/b]" % text.replace("---", "").strip_edges()
	if text.begins_with("VITTORIA") or text.begins_with("SCONFITTA"):
		return "[b][color=#e0b070]%s[/color][/b]" % text
	# "Nome fa qualcosa": il nome va in evidenza.
	for p in game.players:
		var lead := p.name + " "
		if text.begins_with(lead):
			return "[b][color=#8fb8e0]%s[/color][/b]%s" % [p.name, text.substr(p.name.length())]
		if text.begins_with("  " + lead):
			return "  [b][color=#8fb8e0]%s[/color][/b]%s" % [p.name, text.substr(p.name.length() + 2)]
	if text.begins_with("Vyraxen") or text.begins_with("Behavior") or text.begins_with("Peril"):
		return "[color=#e08a80]%s[/color]" % text
	return text


func _on_end(won: bool, reason: String) -> void:
	_on_log("[b]%s[/b] %s" % ["VITTORIA!" if won else "SCONFITTA.", reason])


# =====================================================================
#  TEXTURE
# =====================================================================

func _card_art_path(card_id: int) -> String:
	return Db.card_art(card_id)


func _card_texture(card_id: int) -> Texture2D:
	return _tex(_card_art_path(card_id))


func _tex(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Variant = load(path)
	var tex: Texture2D = t if t is Texture2D else null
	_tex_cache[path] = tex
	return tex


func _process(_delta: float) -> void:
	if _card_zoom != null and _card_zoom.visible:
		_place_zoom()


## Lo zoom segue il puntatore restando dentro lo schermo.
func _place_zoom() -> void:
	var mouse := _root_ui.get_global_mouse_position()
	var view := _root_ui.size
	var pos := mouse + Vector2(24, -_card_zoom.size.y * 0.5)
	if pos.x + _card_zoom.size.x > view.x:
		pos.x = mouse.x - _card_zoom.size.x - 24
	pos.y = clampf(pos.y, 8.0, maxf(view.y - _card_zoom.size.y - 8.0, 8.0))
	_card_zoom.position = pos
