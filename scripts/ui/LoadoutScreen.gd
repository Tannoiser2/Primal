class_name LoadoutScreen
extends PanelContainer
## Costruzione del mazzo e forge, secondo le regole Expedition (Regolamento p.66):
##
##   1. scegli weapon, armor e helm fra le carte forge del livello del mostro
##      (la weapon deve corrispondere alla classe del cacciatore);
##   2. scegli una mastery fra quelle del tuo cacciatore;
##   3. costruisci il mazzo azione: deve contenere esattamente il numero di
##      attack / maneuver / parry / dodge indicato sulla weapon scelta, pescando
##      dal mazzo starter piu' i potenziamenti presi dall'albero delle abilita';
##   4. scegli fino a 3 pozioni del livello corrispondente, senza doppioni.
##
## Il numero di potenziamenti disponibili dipende dal livello: 2, 4 o 6.

signal confirmed(loadouts: Dictionary)

const TYPES := ["attack", "maneuver", "parry", "dodge"]
const TYPE_LABEL := {"attack": "Attack", "maneuver": "Maneuver", "parry": "Parry", "dodge": "Dodge"}
const TYPE_COLOR := {
	"attack": Color(0.81, 0.34, 0.33),
	"maneuver": Color(0.37, 0.46, 0.71),
	"parry": Color(0.90, 0.75, 0.35),
	"dodge": Color(0.62, 0.72, 0.45),
}

var level: int = 1
var hunter_ids: Array = []
var _current: String = ""
var _choices: Dictionary = {}        ## hunter -> {weapon, armor, helm, mastery, upgrades, deck, potions}

var _tabs: HBoxContainer
var _body: VBoxContainer
var _footer: Label
var _start: Button


func setup(ids: Array, aggression_level: int) -> void:
	hunter_ids = ids
	level = aggression_level
	_choices.clear()
	for id in ids:
		var options := Db.loadout_options(String(id), level)
		var weapons: Array = options["weapons"]
		_choices[id] = {
			"weapon": weapons[0] if not weapons.is_empty() else {},
			"armor": (options["armor"][0] if not options["armor"].is_empty() else {}),
			"helm": (options["helm"][0] if not options["helm"].is_empty() else {}),
			"mastery": (options["masteries"][0] if not options["masteries"].is_empty() else {}),
			"upgrades": [],
			"deck": [],
			"potions": [],
		}
		_auto_deck(String(id))
	_current = String(ids[0])
	_build()


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09)
	style.set_content_margin_all(18)
	add_theme_stylebox_override("panel", style)


func _build() -> void:
	for c in get_children():
		c.queue_free()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.text = "[b]Costruzione del mazzo e forge[/b]   —   livello di aggression %d, %d potenziamenti disponibili" % [
		level, Db.loadout_options(_current, level)["upgrade_slots"]]
	root.add_child(title)

	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	root.add_child(_tabs)
	for id in hunter_ids:
		var b := Button.new()
		b.text = String(Db.hunter(String(id)).get("name", id))
		b.toggle_mode = true
		b.button_pressed = String(id) == _current
		var hid := String(id)
		b.pressed.connect(func(): _current = hid; _refresh())
		_tabs.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 560
	root.add_child(scroll)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	root.add_child(bottom)
	_footer = Label.new()
	bottom.add_child(_footer)
	_start = Button.new()
	_start.text = "Inizia la battaglia"
	_start.pressed.connect(func(): confirmed.emit(_choices))
	bottom.add_child(_start)

	_refresh()


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	for b in _tabs.get_children():
		b.button_pressed = b.text == String(Db.hunter(_current).get("name", _current))

	var options := Db.loadout_options(_current, level)
	var choice: Dictionary = _choices[_current]

	_body.add_child(_section("Weapon  (determina danno base e composizione del mazzo)"))
	_body.add_child(_equipment_row(options["weapons"], "weapon", func(item):
		return "%s  —  %d danni,  %s" % [item.get("name", "?"), int(item.get("damage", 0)),
			_composition_label(item.get("composition", {}))]))

	_body.add_child(_section("Armor e Helm  (la loro salute e' la tua)"))
	var gear := HBoxContainer.new()
	gear.add_theme_constant_override("separation", 20)
	gear.add_child(_equipment_row(options["armor"], "armor", func(item): return _health_label(item)))
	gear.add_child(_equipment_row(options["helm"], "helm", func(item): return _health_label(item)))
	_body.add_child(gear)

	_body.add_child(_section("Mastery"))
	_body.add_child(_equipment_row(options["masteries"], "mastery", func(item):
		return "%s  (%s)" % [item.get("name", "?"), item.get("track", "S")]))

	_body.add_child(_section("Pozioni  (fino a 3, senza doppioni)"))
	_body.add_child(_multi_row(options["potions"], "potions", 3, func(item):
		return String(item.get("name", "?"))))

	var slots := int(options["upgrade_slots"])
	if slots > 0:
		_body.add_child(_section("Potenziamenti  (%d/%d scelti)" % [choice["upgrades"].size(), slots]))
		_body.add_child(_upgrade_grid(options["upgrades"], slots))

	_body.add_child(_section("Mazzo azione"))
	_body.add_child(_deck_builder())

	var problem := _validate()
	_footer.text = problem if problem != "" else "Mazzo valido."
	_footer.add_theme_color_override("font_color",
		Color(0.9, 0.5, 0.45) if problem != "" else Color(0.55, 0.85, 0.55))
	_start.disabled = problem != ""


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.85, 0.72, 0.45))
	return l


## Il database fan-made ha qualche valore di salute mancante: quelle carte
## restano visibili ma non selezionabili, per non spacciare uno 0 per un dato.
func _health_label(item: Dictionary) -> String:
	if bool(item.get("health_missing", false)):
		return "%s  —  salute non presente nel database" % item.get("name", "?")
	return "%s  —  %d salute" % [item.get("name", "?"), int(item.get("health", 0))]


func _composition_label(comp: Dictionary) -> String:
	var parts: Array[String] = []
	for t in TYPES:
		parts.append("%d%s" % [int(comp.get(t, 0)), TYPE_LABEL[t].substr(0, 1)])
	return " ".join(parts)


## Scelta singola fra una lista di carte equipaggiamento.
func _equipment_row(items: Array, key: String, labeller: Callable) -> Control:
	var box := VBoxContainer.new()
	var current: Dictionary = _choices[_current].get(key, {})
	for item in items:
		var b := Button.new()
		b.text = labeller.call(item)
		b.toggle_mode = true
		b.button_pressed = item.get("name", "") == current.get("name", "") \
			and item.get("level", 1) == current.get("level", 1)
		b.tooltip_text = Db.card_text(item)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = bool(item.get("health_missing", false))
		var picked: Dictionary = item
		b.pressed.connect(func():
			_choices[_current][key] = picked
			if key == "weapon":
				_auto_deck(_current)
			_refresh())
		box.add_child(b)
	return box


## Scelta multipla con un massimo (pozioni).
func _multi_row(items: Array, key: String, limit: int, labeller: Callable) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var chosen: Array = _choices[_current][key]
	for item in items:
		var b := Button.new()
		b.text = labeller.call(item)
		b.toggle_mode = true
		var name := String(item.get("name", ""))
		b.button_pressed = chosen.any(func(c): return String(c.get("name", "")) == name)
		b.tooltip_text = Db.card_text(item)
		var picked: Dictionary = item
		b.pressed.connect(func():
			var list: Array = _choices[_current][key]
			var at := -1
			for i in list.size():
				if String(list[i].get("name", "")) == name:
					at = i
			if at >= 0:
				list.remove_at(at)
			elif list.size() < limit:
				list.append(picked)
			_refresh())
		box.add_child(b)
	return box


func _upgrade_grid(upgrades: Array, slots: int) -> Control:
	var grid := GridContainer.new()
	grid.columns = 10
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var chosen: Array = _choices[_current]["upgrades"]
	for card in upgrades:
		var cid := int(card["id"])
		var btn := TextureButton.new()
		btn.texture_normal = load(Db.card_art(cid))
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
		btn.custom_minimum_size = Vector2(84, 118)
		btn.modulate = Color.WHITE if cid in chosen else Color(0.45, 0.45, 0.5)
		var note := ""
		if card.has("not_implemented"):
			note = "\n\n[!] Effetto non ancora applicato dal motore: %s" % card["not_implemented"]
			btn.modulate = btn.modulate * Color(1.0, 0.82, 0.82)
		btn.tooltip_text = "%s  [%s]  (%s, costo %d, genera %d)\n%s%s" % [
			card.get("name", "?"), card.get("track", ""), card.get("type", ""),
			int(card.get("cost", 0)), int(card.get("stamina", 0)), Db.card_text(card), note]
		btn.pressed.connect(func():
			var list: Array = _choices[_current]["upgrades"]
			if cid in list:
				list.erase(cid)
				_choices[_current]["deck"].erase(cid)
			elif list.size() < slots:
				list.append(cid)
			_refresh())
		grid.add_child(btn)
	return grid


## Il mazzo deve rispettare esattamente la composizione della weapon scelta.
func _deck_builder() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var comp: Dictionary = _choices[_current].get("weapon", {}).get("composition", {})
	var deck: Array = _choices[_current]["deck"]
	for type in TYPES:
		var want := int(comp.get(type, 0))
		var pool := _pool_of(type)
		var have := 0
		for cid in deck:
			if String(Db.action(cid).get("type", "")) == type:
				have += 1

		var header := Label.new()
		header.text = "%s  %d/%d" % [TYPE_LABEL[type], have, want]
		header.add_theme_color_override("font_color",
			TYPE_COLOR[type] if have == want else Color(0.9, 0.5, 0.45))
		box.add_child(header)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 3)
		for cid in pool:
			var btn := TextureButton.new()
			btn.texture_normal = load(Db.card_art(cid))
			btn.ignore_texture_size = true
			btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT
			btn.custom_minimum_size = Vector2(58, 82)
			btn.modulate = Color.WHITE if cid in deck else Color(0.4, 0.4, 0.46)
			var card := Db.action(cid)
			btn.tooltip_text = "%s  (costo %d, genera %d)\n%s" % [
				card.get("name", "?"), int(card.get("cost", 0)),
				int(card.get("stamina", 0)), Db.card_text(card)]
			var id := cid
			btn.pressed.connect(func():
				var d: Array = _choices[_current]["deck"]
				if id in d:
					d.erase(id)
				else:
					d.append(id)
				_refresh())
			row.add_child(btn)
		box.add_child(row)
	return box


## Carte disponibili di un tipo: mazzo starter + potenziamenti scelti.
func _pool_of(type: String) -> Array[int]:
	var out: Array[int] = []
	for card in Db.hunter(_current).get("deck", []):
		if String(card.get("type", "")) == type:
			out.append(int(card["id"]))
	for cid in _choices[_current]["upgrades"]:
		if String(Db.action(int(cid)).get("type", "")) == type:
			out.append(int(cid))
	return out


## Riempie il mazzo con le prime carte disponibili, per non partire da zero.
func _auto_deck(hunter: String) -> void:
	var comp: Dictionary = _choices[hunter].get("weapon", {}).get("composition", {})
	var deck: Array = []
	var saved := _current
	_current = hunter
	for type in TYPES:
		var pool := _pool_of(type)
		for i in mini(int(comp.get(type, 0)), pool.size()):
			deck.append(pool[i])
	_current = saved
	_choices[hunter]["deck"] = deck


func _validate() -> String:
	for id in hunter_ids:
		var hunter := String(id)
		var choice: Dictionary = _choices[hunter]
		var name := String(Db.hunter(hunter).get("name", hunter))
		if choice.get("weapon", {}).is_empty():
			return "%s: manca la weapon." % name
		var comp: Dictionary = choice["weapon"].get("composition", {})
		var counts := {"attack": 0, "maneuver": 0, "parry": 0, "dodge": 0}
		for cid in choice["deck"]:
			var t := String(Db.action(int(cid)).get("type", ""))
			if counts.has(t):
				counts[t] += 1
		for type in TYPES:
			var want := int(comp.get(type, 0))
			if counts[type] != want:
				return "%s: servono %d carte %s, ne hai %d." % [
					name, want, TYPE_LABEL[type], counts[type]]
	return ""
