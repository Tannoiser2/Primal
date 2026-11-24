class_name SplashScreen
extends PanelContainer
## Schermata iniziale: si sceglie il gruppo, il mostro, lo scenario e il livello.
##
## Le immagini vengono dai componenti veri: il ritratto di un cacciatore e' il
## lato destro della sua plancia, quello di un mostro e' la sua carta Stance I
## (o la plancia mostro, dove e' stata estratta). Cacciatori e mostri senza dati
## restano visibili ma spenti: e' piu' onesto che nasconderli, e si vede cosa manca.

signal start_requested(hunter_ids: Array, monster: String, level: int, expedition: String)

const ALL_HUNTERS := ["dareon", "mirah", "heleren", "karah", "ljonar", "thoreg"]
const HUNTER_NAMES := {
	"dareon": "Dareon", "mirah": "Mirah", "heleren": "Heleren",
	"karah": "Karah", "ljonar": "Ljonar", "thoreg": "Thoreg",
}
## Come si chiama l'arma di ciascuno: aiuta a scegliere piu' del nome.
const HUNTER_WEAPONS := {
	"dareon": "Great Sword", "mirah": "Great Bow", "heleren": "Gunbow",
	"karah": "Dual Blade", "ljonar": "Sword and Shield", "thoreg": "Hammer",
}
const MONSTERS := ["vyraxen", "kharja", "toramat", "dygorax", "tarragua", "jekoros"]
const MONSTER_NAMES := {
	"vyraxen": "Vyraxen", "kharja": "Kharja",
	"toramat": "Toramat", "dygorax": "Dygorax",
	"tarragua": "Tarragua", "jekoros": "Jekoros",
}
const ELEMENT_NAMES := {"fire": "fuoco", "earth": "terra", "water": "acqua", "ice": "ghiaccio", "lightning": "fulmine"}

const CARD := Color(0.10, 0.08, 0.075)
const CARD_ON := Color(0.27, 0.13, 0.07)
const GOLD := Color(0.93, 0.62, 0.34)
const DIM := Tema.MUTED

var _chosen: Array[String] = ["dareon", "mirah"]
var _monster := "vyraxen"
var _level := 0
var _expedition := "1"
var _body: VBoxContainer
var _footer: RichTextLabel
var _start: Button
var _tex_cache: Dictionary = {}


func _ready() -> void:
	# A tutto schermo: sotto non deve vedersi niente della partita.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Tema.INK
	add_theme_stylebox_override("panel", style)
	_build()


## Un cacciatore e' giocabile se ha il mazzo starter nei dati.
func _hunter_ready(id: String) -> bool:
	return not Db.hunter(id).get("deck", []).is_empty()


## Un mostro serve sia le stance sia le behavior: senza mazzo behavior la
## partita non parte.
func _monster_ready(id: String) -> bool:
	var m := Db.monster(id)
	return not m.get("levels", {}).is_empty() and not m.get("behaviors", {}).is_empty()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	# Fondale: il drago della copertina, a destra e in penombra, come sulla scatola.
	var art := TextureRect.new()
	art.texture = load("res://art/ui/drago.jpg")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.anchor_left = 0.40
	art.anchor_right = 1.0
	art.anchor_bottom = 1.0
	art.modulate = Color(1, 1, 1, 0.55)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
	# Sfumatura dall'inchiostro pieno a sinistra al drago a destra.
	var fade := TextureRect.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Tema.INK, Color(Tema.INK, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	fade.texture = gt
	fade.anchor_left = 0.42
	fade.anchor_right = 0.75
	fade.anchor_bottom = 1.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	# Il contenuto scorre se lo schermo e' basso (iPad in orizzontale).
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36 if side != "top" else 28)
	scroll.add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 14)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_body)
	_refresh()


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()

	var logo := TextureRect.new()
	logo.texture = load("res://art/ui/logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	logo.custom_minimum_size = Vector2(440, 115)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_body.add_child(logo)
	var tagline := Label.new()
	tagline.text = "Modalità Expedition: una battaglia, un mostro. Da 2 a 4 cacciatori."
	tagline.add_theme_color_override("font_color", DIM)
	_body.add_child(tagline)

	_body.add_child(_section("Cacciatori  (da 2 a 4)"))
	var hunters := HFlowContainer.new()
	hunters.add_theme_constant_override("h_separation", 10)
	hunters.add_theme_constant_override("v_separation", 10)
	for id in ALL_HUNTERS:
		hunters.add_child(_hunter_tile(id))
	_body.add_child(hunters)

	_body.add_child(_section("Mostro"))
	var monsters := HFlowContainer.new()
	monsters.add_theme_constant_override("h_separation", 10)
	monsters.add_theme_constant_override("v_separation", 10)
	for id in MONSTERS:
		monsters.add_child(_monster_tile(id))
	_body.add_child(monsters)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 26)
	_body.add_child(bottom)

	var scenario := VBoxContainer.new()
	scenario.add_theme_constant_override("separation", 6)
	scenario.add_child(_section("Scenario"))
	var exps := HBoxContainer.new()
	exps.add_theme_constant_override("separation", 6)
	for key in ["1", "2"]:
		exps.add_child(_expedition_button(key))
	scenario.add_child(exps)
	scenario.add_child(_terrain_row())
	bottom.add_child(scenario)

	var levels := VBoxContainer.new()
	levels.add_theme_constant_override("separation", 6)
	levels.add_child(_section("Livello di aggressività"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for lv in 4:
		var b := Button.new()
		b.text = "  %d  " % lv
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = lv == _level
		b.custom_minimum_size = Vector2(0, 34)
		var picked := lv
		b.pressed.connect(func():
			_level = picked
			_refresh())
		row.add_child(b)
	levels.add_child(row)
	var gear := Label.new()
	gear.add_theme_font_size_override("font_size", 13)
	gear.add_theme_color_override("font_color", DIM)
	gear.text = "mazzo starter" if _level == 0 \
		else "forge e potenziamenti di livello %d" % _level
	levels.add_child(gear)
	bottom.add_child(levels)

	var tail := HBoxContainer.new()
	tail.add_theme_constant_override("separation", 14)
	_body.add_child(tail)
	_footer = RichTextLabel.new()
	_footer.bbcode_enabled = true
	_footer.fit_content = true
	_footer.autowrap_mode = TextServer.AUTOWRAP_OFF
	_footer.custom_minimum_size = Vector2(420, 26)
	_footer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tail.add_child(_footer)
	_start = Button.new()
	_start.text = "INIZIA LA CACCIA"
	_start.custom_minimum_size = Vector2(240, 52)
	_start.add_theme_font_override("font", Tema.title_font())
	_start.add_theme_font_size_override("font_size", 30)
	var hot := StyleBoxFlat.new()
	hot.bg_color = Tema.RUST_DARK
	hot.border_color = Tema.RUST
	hot.set_border_width_all(2)
	hot.border_width_bottom = 4
	hot.set_corner_radius_all(2)
	var hot_hover := hot.duplicate()
	hot_hover.bg_color = Color(0.55, 0.26, 0.12)
	_start.add_theme_stylebox_override("normal", hot)
	_start.add_theme_stylebox_override("hover", hot_hover)
	_start.pressed.connect(func():
		start_requested.emit(_chosen.duplicate(), _monster, _level, _expedition))
	tail.add_child(_start)
	# Riprendere una partita salvata online: basta il codice di 4 lettere.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(30, 0)
	tail.add_child(spacer)
	var resume := HBoxContainer.new()
	resume.add_theme_constant_override("separation", 8)
	tail.add_child(resume)
	var code := LineEdit.new()
	code.placeholder_text = "codice"
	code.tooltip_text = "Il codice di 4 lettere di una partita salvata"
	code.max_length = 4
	code.custom_minimum_size = Vector2(110, 52)
	code.add_theme_font_override("font", Tema.title_font())
	code.add_theme_font_size_override("font_size", 26)
	resume.add_child(code)
	var go := Button.new()
	go.text = "Riprendi"
	go.tooltip_text = "Riprendi la partita salvata con questo codice"
	go.custom_minimum_size = Vector2(0, 52)
	go.pressed.connect(func():
		if code.text.strip_edges().length() == 4:
			start_requested.emit([], "", 0, "RESUME:" + code.text.strip_edges().to_upper()))
	resume.add_child(go)
	_update_footer()




# ------------------------------------------------------------------ tessere

func _hunter_tile(id: String) -> Control:
	var ready := _hunter_ready(id)
	var picked := id in _chosen
	var tile := _tile(HUNTER_NAMES.get(id, id),
		HUNTER_WEAPONS.get(id, ""),
		_portrait_of(Db.hunter(id).get("art", {})),
		picked, ready,
		"Mancano i dati delle sue carte: non è ancora giocabile.")
	if ready:
		(tile.get_meta("button") as BaseButton).pressed.connect(func():
			if id in _chosen:
				_chosen.erase(id)
			elif _chosen.size() < 4:
				_chosen.append(id)
			_refresh())
	return tile


func _monster_tile(id: String) -> Control:
	var ready := _monster_ready(id)
	var data := Db.monster(id)
	var element := String(data.get("element", ""))
	var tile := _tile(MONSTER_NAMES.get(id, id),
		ELEMENT_NAMES.get(element, element),
		_portrait_of(data.get("art", {})), id == _monster, ready,
		"Mancano stance, behavior e peril: non è ancora giocabile.")
	if ready:
		(tile.get_meta("button") as BaseButton).pressed.connect(func():
			_monster = id
			_expedition = "1"
			_refresh())
	return tile


## Una tessera con ritratto, nome e sottotitolo. Il bordo dorato dice cosa e'
## selezionato; le tessere spente restano leggibili ma non cliccabili.
func _tile(name: String, subtitle: String, art: Texture2D,
		picked: bool, enabled: bool, disabled_hint: String) -> Control:
	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = picked
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(150, 176)
	if not enabled:
		button.tooltip_text = disabled_hint
	var frame := StyleBoxFlat.new()
	frame.bg_color = CARD_ON if picked else CARD
	frame.set_corner_radius_all(5)
	frame.set_border_width_all(2)
	frame.border_color = GOLD if picked else Color(0.22, 0.21, 0.23)
	for state in ["normal", "hover", "pressed", "disabled"]:
		button.add_theme_stylebox_override(state, frame)

	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(box)

	var portrait := TextureRect.new()
	portrait.texture = art
	portrait.custom_minimum_size = Vector2(146, 116)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.modulate = Color.WHITE if enabled else Color(0.42, 0.42, 0.45)
	box.add_child(portrait)

	var label := Label.new()
	label.text = name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", Tema.title_font())
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", GOLD if picked else Color(0.86, 0.84, 0.8))
	box.add_child(label)

	var sub := Label.new()
	sub.text = subtitle if enabled else "in arrivo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", DIM)
	box.add_child(sub)

	button.set_meta("button", button)
	return button


## Il ritratto: le plance cacciatore sono larghe e il personaggio sta a destra,
## quindi si ritaglia quella parte. `focus` 0 usa l'immagine intera.
## Il ritratto e' un ritaglio dell'illustrazione, e la finestra sta nei dati
## (`art.portrait`): misurata a mano su ogni plancia, perche' i personaggi non
## sono nello stesso punto — Thoreg e' al centro, Heleren tutto a destra.
## Tagliare a una frazione fissa della larghezza va bene per meta' di loro e
## decapita gli altri.
func _portrait_of(art: Dictionary) -> Texture2D:
	var portrait: Dictionary = art.get("portrait", {})
	var path := String(portrait.get("art", art.get("board", "")))
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Variant = load(path)
	if not (tex is Texture2D):
		return null
	var out: Texture2D = tex
	var region: Array = portrait.get("region", [])
	if region.size() == 4:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(
			float(region[0]) * out.get_width(), float(region[1]) * out.get_height(),
			float(region[2]) * out.get_width(), float(region[3]) * out.get_height())
		out = atlas
	_tex_cache[path] = out
	return out


# ------------------------------------------------------------------ scenario

func _expedition_button(key: String) -> Button:
	var exp: Dictionary = Db.monster(_monster).get("expeditions", {}).get(key, {})
	var b := Button.new()
	b.text = "  Expedition %s  " % key
	b.toggle_mode = true
	b.button_pressed = key == _expedition
	b.disabled = exp.is_empty()
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(func():
		_expedition = key
		_refresh())
	return b


## Il terreno che lo scenario mette sul tavolo, come lo mostra il regolamento.
func _terrain_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var exp: Dictionary = Db.monster(_monster).get("expeditions", {}).get(_expedition, {})
	var pieces: Array = exp.get("terrain", [])
	if pieces.is_empty():
		var none := Label.new()
		none.text = "nessun terreno iniziale"
		none.add_theme_font_size_override("font_size", 13)
		none.add_theme_color_override("font_color", DIM)
		row.add_child(none)
		return row
	var counted := {}
	for piece in pieces:
		var type := String(piece.get("type", ""))
		counted[type] = int(counted.get(type, 0)) + 1
	for type in counted:
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 3)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		var path := "res://art/terrain/%s.png" % type
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		item.add_child(icon)
		var n := Label.new()
		n.text = "%d" % counted[type]
		n.add_theme_font_size_override("font_size", 13)
		n.add_theme_color_override("font_color", DIM)
		item.add_child(n)
		row.add_child(item)
	return row


func _section(text: String) -> Label:
	return Tema.title(text.to_upper(), 26)


func _update_footer() -> void:
	var problem := ""
	if _chosen.size() < 2:
		problem = "Servono almeno 2 cacciatori (in solitario ne controlli 2)."
	elif _chosen.size() > 4:
		problem = "Al massimo 4 cacciatori."
	elif _level > 0:
		# Dal livello 1 in su si passa dalla forge, e la forge di Heleren non e'
		# ancora stata estratta dal mod: al livello 0 gioca col mazzo starter,
		# piu' su non avrebbe da cosa scegliere.
		for id in _chosen:
			if Db.loadout_options(id, _level)["weapons"].is_empty():
				problem = "%s non ha ancora la forge: può giocare solo al livello 0." \
					% HUNTER_NAMES.get(id, id)
				break
	if problem != "":
		_footer.text = "[color=#e6807a]%s[/color]" % problem
	else:
		var names: Array[String] = []
		for id in _chosen:
			names.append(String(HUNTER_NAMES.get(id, id)))
		_footer.text = "[color=#9e9a94]%s contro [/color][color=#e0b070]%s[/color]" \
			% [", ".join(names), MONSTER_NAMES.get(_monster, _monster)] \
			+ "[color=#9e9a94] — Expedition %s, livello %d.[/color]" % [_expedition, _level]
	_start.disabled = problem != ""
