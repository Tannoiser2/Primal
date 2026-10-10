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
const MONSTERS := ["vyraxen", "kharja", "toramat", "dygorax"]
const MONSTER_NAMES := {
	"vyraxen": "Vyraxen", "kharja": "Kharja",
	"toramat": "Toramat", "dygorax": "Dygorax",
}
const ELEMENT_NAMES := {"fire": "fuoco", "earth": "terra", "water": "acqua", "ice": "ghiaccio"}

const CARD := Color(0.13, 0.12, 0.14)
const CARD_ON := Color(0.24, 0.17, 0.10)
const GOLD := Color(0.85, 0.62, 0.30)
const DIM := Color(0.62, 0.59, 0.55)

var _chosen: Array[String] = ["dareon", "mirah"]
var _monster := "vyraxen"
var _level := 0
var _expedition := "1"
var _body: VBoxContainer
var _footer: RichTextLabel
var _start: Button
var _tex_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.045, 0.055)
	style.set_content_margin_all(24)
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
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	center.add_child(_body)
	_refresh()


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.custom_minimum_size = Vector2(980, 62)
	title.text = "[b][color=#c8763c]PRIMAL: THE AWAKENING[/color][/b]\n" \
		+ "[color=#9a938c]Modalita' Expedition — una battaglia, un mostro.[/color]"
	_body.add_child(title)

	_body.add_child(_section("Cacciatori  (da 2 a 4)"))
	var hunters := HBoxContainer.new()
	hunters.add_theme_constant_override("separation", 8)
	for id in ALL_HUNTERS:
		hunters.add_child(_hunter_tile(id))
	_body.add_child(hunters)

	_body.add_child(_section("Mostro"))
	var monsters := HBoxContainer.new()
	monsters.add_theme_constant_override("separation", 8)
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
	levels.add_child(_section("Livello di aggression"))
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
	gear.add_theme_font_size_override("font_size", 11)
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
	_footer.custom_minimum_size = Vector2(720, 26)
	tail.add_child(_footer)
	_start = Button.new()
	_start.text = "  Inizia la caccia  "
	_start.custom_minimum_size = Vector2(0, 40)
	_start.pressed.connect(func():
		start_requested.emit(_chosen.duplicate(), _monster, _level, _expedition))
	tail.add_child(_start)
	_update_footer()


# ------------------------------------------------------------------ tessere

func _hunter_tile(id: String) -> Control:
	var ready := _hunter_ready(id)
	var picked := id in _chosen
	var tile := _tile(HUNTER_NAMES.get(id, id),
		HUNTER_WEAPONS.get(id, ""),
		_portrait_of(Db.hunter(id).get("art", {})),
		picked, ready,
		"Mancano i dati delle sue carte: non e' ancora giocabile.")
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
		"Mancano stance, behavior e peril: non e' ancora giocabile.")
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
	button.custom_minimum_size = Vector2(152, 168)
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
	portrait.custom_minimum_size = Vector2(148, 112)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.modulate = Color.WHITE if enabled else Color(0.42, 0.42, 0.45)
	box.add_child(portrait)

	var label := Label.new()
	label.text = name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", GOLD if picked else Color(0.86, 0.84, 0.8))
	box.add_child(label)

	var sub := Label.new()
	sub.text = subtitle if enabled else "in arrivo"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 10)
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
		none.add_theme_font_size_override("font_size", 11)
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
		n.add_theme_font_size_override("font_size", 11)
		n.add_theme_color_override("font_color", DIM)
		item.add_child(n)
		row.add_child(item)
	return row


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.78, 0.46, 0.24))
	return l


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
				problem = "%s non ha ancora la forge: puo' giocare solo al livello 0." \
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
