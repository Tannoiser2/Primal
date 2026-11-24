class_name Tema
extends RefCounted
## Tema grafico di tutto il gioco: font, colori, pannelli, pulsanti e finestre.
##
## La grafica di Primal e' inchiostro nero su carta grezza, con il ruggine del
## logo e il rosso sangue delle carte. L'interfaccia sta su quella tavolozza:
## pannelli color inchiostro con il filo d'osso, accenti ruggine, titoli in un
## condensato spigoloso (Teko) come le intestazioni delle carte, testi in un
## semi-condensato leggibile anche piccolo (Barlow Semi Condensed).
##
## Tutti i caratteri usati nell'interfaccia devono esistere in questi font:
## `tools/controlla_glifi.py` lo verifica prima di pubblicare.

const INK := Color(0.055, 0.045, 0.043)
const PANEL := Color(0.085, 0.070, 0.064, 0.95)
const PANEL_LIGHT := Color(0.13, 0.105, 0.095)
const BONE := Color(0.91, 0.87, 0.79)
const RUST := Color(0.76, 0.40, 0.20)
const RUST_DARK := Color(0.42, 0.20, 0.10)
const BLOOD := Color(0.62, 0.11, 0.10)
const MUTED := Color(0.64, 0.60, 0.54)
const LINE := Color(0.36, 0.30, 0.26)

const BODY_SIZE := 16

static var _body: Font
static var _bold: Font
static var _title: Font
static var _theme: Theme


static func body_font() -> Font:
	if _body == null:
		_body = load("res://fonts/BarlowSemiCondensed-Medium.ttf")
	return _body


static func bold_font() -> Font:
	if _bold == null:
		_bold = load("res://fonts/BarlowSemiCondensed-Bold.ttf")
	return _bold


## Teko e' un font variabile: lo fissiamo a un peso semigrassetto.
static func title_font() -> Font:
	if _title == null:
		var v := FontVariation.new()
		v.base_font = load("res://fonts/Teko.ttf")
		v.variation_opentype = {"wght": 560}
		_title = v
	return _title


## Etichetta da titolo: maiuscolo spigoloso, ruggine.
static func title(text: String, size := 26, color := RUST) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func panel_style(accent := false, margin := 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = PANEL
	s.border_color = RUST if accent else LINE
	s.set_border_width_all(2 if accent else 1)
	s.set_corner_radius_all(3)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 6
	return s


static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = BODY_SIZE

	# --- testi
	for type in ["Label", "LinkButton"]:
		t.set_color("font_color", type, BONE)
	t.set_color("default_color", "RichTextLabel", BONE)
	t.set_font("normal_font", "RichTextLabel", body_font())
	t.set_font("bold_font", "RichTextLabel", bold_font())
	t.set_font("mono_font", "RichTextLabel", body_font())
	t.set_font("italics_font", "RichTextLabel", body_font())
	t.set_font("bold_italics_font", "RichTextLabel", bold_font())
	t.set_font_size("normal_font_size", "RichTextLabel", BODY_SIZE)
	t.set_font_size("bold_font_size", "RichTextLabel", BODY_SIZE)

	# --- pulsanti: lastra d'inchiostro con il filo ruggine
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.095, 0.085)
	normal.border_color = Color(0.45, 0.32, 0.24)
	normal.set_border_width_all(1)
	normal.border_width_bottom = 3
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	normal.content_margin_top = 6
	normal.content_margin_bottom = 6
	var hover := normal.duplicate()
	hover.bg_color = Color(0.24, 0.13, 0.08)
	hover.border_color = RUST
	var pressed := normal.duplicate()
	pressed.bg_color = RUST_DARK
	pressed.border_color = Color(0.92, 0.55, 0.30)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.08, 0.07, 0.07)
	disabled.border_color = Color(0.22, 0.19, 0.17)
	for type in ["Button", "OptionButton", "MenuButton", "CheckBox"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, BONE)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_hover_pressed_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(0.42, 0.39, 0.36))
		t.set_font("font", type, bold_font())
		t.set_font_size("font_size", type, 16)

	# --- campi di testo
	var field := StyleBoxFlat.new()
	field.bg_color = Color(0.05, 0.04, 0.04)
	field.border_color = Color(0.45, 0.32, 0.24)
	field.set_border_width_all(1)
	field.set_corner_radius_all(2)
	field.set_content_margin_all(8)
	var field_focus := field.duplicate()
	field_focus.border_color = RUST
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_color("font_color", "LineEdit", BONE)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.45, 0.41, 0.37))

	# --- pannelli
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())

	# --- tooltip
	var tip := panel_style(true, 10)
	tip.bg_color = Color(0.07, 0.055, 0.05, 0.97)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", BONE)
	t.set_font_size("font_size", "TooltipLabel", 15)

	# --- barre di scorrimento sottili
	for type in ["VScrollBar", "HScrollBar"]:
		var track := StyleBoxFlat.new()
		track.bg_color = Color(0, 0, 0, 0.25)
		track.set_content_margin_all(3)
		var grab := StyleBoxFlat.new()
		grab.bg_color = Color(0.45, 0.33, 0.25)
		grab.set_corner_radius_all(3)
		var grab_hi := grab.duplicate()
		grab_hi.bg_color = RUST
		t.set_stylebox("scroll", type, track)
		t.set_stylebox("grabber", type, grab)
		t.set_stylebox("grabber_highlight", type, grab_hi)
		t.set_stylebox("grabber_pressed", type, grab_hi)

	# --- finestre incorporate: cornice d'inchiostro, titolo in Teko
	var frame := StyleBoxFlat.new()
	frame.bg_color = PANEL
	frame.border_color = Color(0.20, 0.14, 0.11)
	frame.set_border_width_all(2)
	frame.border_width_top = 34
	frame.set_corner_radius_all(3)
	frame.expand_margin_top = 32
	frame.expand_margin_left = 2
	frame.expand_margin_right = 2
	frame.expand_margin_bottom = 2
	frame.shadow_color = Color(0, 0, 0, 0.5)
	frame.shadow_size = 10
	var focused := frame.duplicate()
	focused.border_color = Color(0.30, 0.17, 0.10)
	t.set_stylebox("embedded_border", "Window", focused)
	t.set_stylebox("embedded_unfocused_border", "Window", frame)
	t.set_font("title_font", "Window", title_font())
	t.set_font_size("title_font_size", "Window", 24)
	t.set_color("title_color", "Window", BONE)
	t.set_constant("title_height", "Window", 32)

	_theme = t
	return t
