class_name Board3D
extends Node3D
## Plancia di combattimento in 3D con camera orbitale.
##
## Le quattro caselle sono fisse nello spazio (0 = Nord, in senso orario).
## Il ruolo di ciascuna casella (front / flank / rear) dipende dall'orientamento
## del mostro, esattamente come sul tavolo.

signal sector_clicked(position: int)

const BOARD_SIZE := 10.0
const MONSTER_FOOTPRINT := 3.6   ## ingombro orizzontale del mostro, in unita' di plancia
## Quanto girare il modello del mostro perche' guardi il settore front: dipende
## da come e' scolpito, quindi sta nei suoi dati (`art.model_yaw`, in gradi).
const MONSTER_MODEL_YAW := PI
const SECTOR_RADIUS := 3.1
const SECTOR_ANGLE := [0.0, PI * 0.5, PI, PI * 1.5]

var camera: Camera3D
var camera_pivot: Node3D
var monster: Node3D
var monster_mesh: MeshInstance3D
var hunter_nodes: Dictionary = {}     ## id cacciatore -> Sprite3D
var sector_markers: Array[MeshInstance3D] = []
var sector_arcs: Array[MeshInstance3D] = []
var _active_hunter := ""
var terrain_root: Node3D
var sequence_root: Node3D
var _last_sequence_size := 0
var _terrain_signature := ""
var _blow_queue: Array = []
var _blow_running := false

var _yaw := 0.0
var _pitch := -0.95
var _distance := 15.0
var _dragging := false
var _hovered := -1
var _reachable: Array = []
var _exposed: Array = []
var _facing := 0


func _ready() -> void:
	_build_environment()
	_build_board()
	_build_camera()
	_build_sector_arcs()
	terrain_root = Node3D.new()
	add_child(terrain_root)
	sequence_root = Node3D.new()
	add_child(sequence_root)


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.07)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.52, 0.5)
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55, -35, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	add_child(key)


func _build_board() -> void:
	var plane := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	var mat := StandardMaterial3D.new()
	var tex: Variant = load(String(Db.common.get("battle_map", "")))
	var aspect := 1.0
	if tex is Texture2D:
		mat.albedo_texture = tex
		aspect = float(tex.get_width()) / float(maxi(tex.get_height(), 1))
	quad.size = Vector2(BOARD_SIZE * aspect, BOARD_SIZE)
	plane.mesh = quad
	mat.roughness = 0.95
	plane.material_override = mat
	add_child(plane)

	# Indicatori cliccabili per le quattro caselle.
	for i in 4:
		var marker := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 1.15
		disc.bottom_radius = 1.15
		disc.height = 0.04
		marker.mesh = disc
		marker.position = sector_world_position(i) + Vector3(0, 0.02, 0)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(1, 1, 1, 0.12)
		mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = mm
		add_child(marker)
		sector_markers.append(marker)

		var area := Area3D.new()
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.3
		cyl.height = 0.5
		shape.shape = cyl
		area.add_child(shape)
		area.position = sector_world_position(i)
		area.input_ray_pickable = true
		var index := i
		area.input_event.connect(func(_c, event, _pos, _n, _s):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				sector_clicked.emit(index))
		# Serve vedere dove si sta andando prima di cliccare: la casella sotto il
		# puntatore si accende e si solleva.
		area.mouse_entered.connect(func():
			_hovered = index
			_paint_sectors())
		area.mouse_exited.connect(func():
			if _hovered == index:
				_hovered = -1
				_paint_sectors())
		add_child(area)


func _build_camera() -> void:
	camera_pivot = Node3D.new()
	add_child(camera_pivot)
	camera = Camera3D.new()
	camera.fov = 50.0
	camera_pivot.add_child(camera)
	_update_camera()


## Il lato colpibile si dice con un arco rosso sul bordo del settore, non con un
## disco: la mappa e' gia' piena di colore e i cerchi la coprivano.
func _build_sector_arcs() -> void:
	for i in 4:
		var arc := MeshInstance3D.new()
		arc.mesh = _arc_mesh(float(SECTOR_ANGLE[i]))
		arc.position.y = 0.06
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0)
		arc.material_override = mat
		add_child(arc)
		sector_arcs.append(arc)


## Una fetta di anello di 90 gradi centrata sull'angolo del settore.
func _arc_mesh(center_angle: float) -> ImmediateMesh:
	var inner := 4.25
	var outer := 4.75
	var steps := 24
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for s in steps + 1:
		var t := float(s) / float(steps)
		var a := center_angle - PI * 0.25 + t * PI * 0.5
		var dir := Vector3(sin(a), 0.0, -cos(a))
		mesh.surface_add_vertex(dir * inner)
		mesh.surface_add_vertex(dir * outer)
	mesh.surface_end()
	return mesh


func sector_world_position(index: int) -> Vector3:
	var a: float = float(SECTOR_ANGLE[index])
	return Vector3(sin(a) * SECTOR_RADIUS, 0.0, -cos(a) * SECTOR_RADIUS)


# ------------------------------------------------------------------ mostro

func spawn_monster(monster_id: String = "vyraxen") -> void:
	monster = Node3D.new()
	add_child(monster)
	# Solo Vyraxen ha mesh e miniatura: gli altri mostri restano un segnaposto
	# finche' non ne arriva uno.
	var art: Dictionary = Db.monster(monster_id).get("art", {})

	# Se c'e' una miniatura GLB si usa quella: e' un modello completo di materiali,
	# molto meglio del mesh TTS le cui UV non combaciano con la sua texture.
	var model := _instance_model(String(art.get("model", "")))
	if model != null:
		_fit_to_ground(model, MONSTER_FOOTPRINT)
		# Il GLB e' scolpito rivolto all'indietro rispetto al fronte del mostro:
		# va girato di mezzo giro perche' guardi il settore front.
		var yaw := Node3D.new()
		# Ogni sculto guarda da una parte diversa: l'angolo sta nei dati del mostro.
		yaw.rotation.y = deg_to_rad(float(art.get("model_yaw", 180.0)))
		yaw.add_child(model)
		monster.add_child(yaw)
		monster_mesh = null
		return

	var mesh_path := String(art.get("mesh", ""))
	var mesh_res: Variant = load(mesh_path) if ResourceLoader.exists(mesh_path) else null
	monster_mesh = MeshInstance3D.new()
	if mesh_res is Mesh:
		monster_mesh.mesh = mesh_res
		var mat := StandardMaterial3D.new()
		var tex_path := String(art.get("texture", ""))
		var tex: Variant = load(tex_path) if ResourceLoader.exists(tex_path) else null
		if tex is Texture2D:
			mat.albedo_texture = tex
			# Dove le UV del mesh TTS non corrispondono alla texture (Vyraxen)
			# la proiettiamo in triplanare: le squame si applicano comunque, ma
			# fuori posto. Il flag sta nei dati del mostro, non qui.
			if bool(art.get("triplanar", false)):
				mat.uv1_triplanar = true
				mat.uv1_scale = Vector3.ONE * 1.6
		mat.roughness = 0.85
		monster_mesh.material_override = mat
		var aabb: AABB = (mesh_res as Mesh).get_aabb()
		var footprint: float = maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
		var scale_factor: float = MONSTER_FOOTPRINT / footprint
		monster_mesh.scale = Vector3.ONE * scale_factor
		monster_mesh.position = Vector3(
			-aabb.get_center().x * scale_factor,
			-aabb.position.y * scale_factor,
			-aabb.get_center().z * scale_factor)
	else:
		var cap := CapsuleMesh.new()
		cap.radius = 1.0
		cap.height = 3.0
		monster_mesh.mesh = cap
		monster_mesh.position.y = 1.5
	monster.add_child(monster_mesh)


## Istanzia una scena GLB, se presente.
func _instance_model(path: String) -> Node3D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var res: Variant = load(path)
	if res is PackedScene:
		return (res as PackedScene).instantiate()
	return null


## Ingombro complessivo di un modello, unendo le AABB di tutte le sue mesh.
func _model_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var first := true
	for child in node.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var box: AABB = (child as MeshInstance3D).get_aabb()
			box = child.transform * box
			bounds = box if first else bounds.merge(box)
			first = false
		if child.get_child_count() > 0:
			var inner := _model_bounds(child)
			if inner.size != Vector3.ZERO:
				inner = (child as Node3D).transform * inner if child is Node3D else inner
				bounds = inner if first else bounds.merge(inner)
				first = false
	return bounds


## Scala il modello e lo appoggia sul piano della plancia.
## I mostri si normalizzano sull'ingombro orizzontale (Vyraxen e' largo di ali);
## i cacciatori sull'altezza, altrimenti chi ha una base scenica piu' larga
## finirebbe rimpicciolito rispetto agli altri.
func _fit_to_ground(model: Node3D, size: float, by_height: bool = false) -> void:
	var bounds := _model_bounds(model)
	if bounds.size == Vector3.ZERO:
		return
	var span: float = bounds.size.y if by_height \
		else maxf(bounds.size.x, bounds.size.z)
	var factor: float = size / maxf(span, 0.001)
	model.scale = Vector3.ONE * factor
	model.position = Vector3(
		-bounds.get_center().x * factor,
		-bounds.position.y * factor,
		-bounds.get_center().z * factor)


## I cacciatori usano le miniature GLB. Se manca il modello si ricade sulla
## figurina piatta del mod TTS, montata su una base come una sagoma da tavolo.
const STANDEE_HEIGHT := 2.0
const HUNTER_HEIGHT := 1.7   ## altezza della miniatura del cacciatore


func spawn_hunter(hunter_id: String) -> void:
	var holder := Node3D.new()
	var art: Dictionary = Db.hunter(hunter_id).get("art", {})

	# L'anello del giocatore attivo sta sotto la miniatura, non dentro il corpo:
	# quando il corpo scatta in avanti per colpire, l'anello resta sulla casella.
	var ring := _active_ring()
	holder.add_child(ring)
	holder.set_meta("ring", ring)

	# Il corpo e' un nodo a parte perche' gli scatti e i tremiti lo spostano: la
	# posizione sulla plancia resta quella di `holder`, che nessuno tocca.
	var body := Node3D.new()
	holder.add_child(body)
	holder.set_meta("body", body)

	var model := _instance_model(String(art.get("model", "")))
	if model != null:
		_fit_to_ground(model, HUNTER_HEIGHT, true)
		var pivot := Node3D.new()      # ruota la miniatura verso il mostro
		pivot.add_child(model)
		body.add_child(pivot)
		holder.set_meta("model", pivot)
	else:
		var base := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.42
		disc.bottom_radius = 0.46
		disc.height = 0.12
		base.mesh = disc
		base.position.y = 0.06
		var base_mat := StandardMaterial3D.new()
		base_mat.albedo_color = Color(0.12, 0.12, 0.14)
		base_mat.metallic = 0.2
		base_mat.roughness = 0.6
		base.material_override = base_mat
		body.add_child(base)

		var sprite := Sprite3D.new()
		# La sagoma piatta non esiste per tutti: quattro cacciatori su sei non
		# ce l'hanno, e caricare un percorso vuoto e' un errore a runtime.
		var standee := String(art.get("standee", ""))
		var tex: Variant = load(standee) if ResourceLoader.exists(standee) else null
		if tex is Texture2D:
			sprite.texture = tex
			sprite.pixel_size = STANDEE_HEIGHT / float(maxi(tex.get_height(), 1))
			sprite.offset = Vector2(0, tex.get_height() * 0.5)
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sprite.shaded = false
		sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		sprite.alpha_scissor_threshold = 0.35
		sprite.position.y = 0.12
		body.add_child(sprite)
		holder.set_meta("sprite", sprite)

	add_child(holder)
	hunter_nodes[hunter_id] = holder


func set_monster_facing(position_index: int) -> void:
	if monster == null:
		return
	var target: float = -float(SECTOR_ANGLE[position_index])
	var tween := create_tween()
	tween.tween_property(monster, "rotation:y", target, 0.35) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Anello sotto la miniatura di chi ha il turno: sul tavolo lo sai perche' stai
## giocando tu, a schermo no.
func _active_ring() -> MeshInstance3D:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.46
	torus.outer_radius = 0.54
	# `rings` sono i lati dell'anello grande: con pochi viene un esagono.
	torus.rings = 48
	torus.ring_segments = 6
	ring.mesh = torus
	ring.position.y = 0.04
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.82, 0.35, 0.8)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = mat
	ring.visible = false
	# Respiro lento: si nota senza chiedere attenzione.
	var pulse := create_tween().set_loops()
	pulse.tween_property(ring, "scale", Vector3.ONE * 1.09, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(ring, "scale", Vector3.ONE, 0.8) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return ring


## `slot` e `slots` distribuiscono le miniature che condividono la stessa casella.
func set_hunter_position(hunter_id: String, position_index: int, ko: bool,
		slot: int = 0, slots: int = 1, active: bool = false) -> void:
	var node: Node3D = hunter_nodes.get(hunter_id)
	if node == null:
		return
	if node.has_meta("ring"):
		(node.get_meta("ring") as MeshInstance3D).visible = active and not ko
	var target := sector_world_position(position_index)
	if slots > 1:
		# Si scostano perpendicolarmente al raggio che va dal centro alla casella.
		var side := Vector3(target.z, 0.0, -target.x).normalized()
		var spread := 1.05 * (float(slot) - float(slots - 1) * 0.5)
		target += side * spread
	var tween := create_tween()
	tween.tween_property(node, "position", target, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if node.has_meta("model"):
		# La miniatura guarda verso il mostro, al centro della plancia.
		var pivot: Node3D = node.get_meta("model")
		pivot.rotation.y = atan2(-target.x, -target.z)
		# KO: la miniatura viene coricata su un fianco, come sul tavolo.
		pivot.rotation.z = deg_to_rad(-80.0) if ko else 0.0
	elif node.has_meta("sprite"):
		var sprite: Sprite3D = node.get_meta("sprite")
		sprite.modulate = Color(0.5, 0.35, 0.35) if ko else Color.WHITE
		sprite.rotation_degrees.z = -75.0 if ko else 0.0


func highlight_sectors(reachable: Array, exposed: Array, monster_facing: int) -> void:
	_reachable = reachable
	_exposed = exposed
	_facing = monster_facing
	_paint_sectors()


## Colora le caselle: lati esposti in rosso, destinazioni raggiungibili in azzurro,
## e quella sotto il puntatore accesa e leggermente sollevata.
func _paint_sectors() -> void:
	var moving := not _reachable.is_empty()
	for i in 4:
		var role: String = PrimalGame.SECTORS[posmod(i - _facing, 4)]

		# Bordo: rosso dove il mostro e' colpibile, spento altrove.
		var arc_mat: StandardMaterial3D = sector_arcs[i].material_override
		arc_mat.albedo_color = Color(0.92, 0.18, 0.15, 0.85) if role in _exposed \
			else Color(1, 1, 1, 0.05)

		# Dischi: solo mentre si sceglie dove andare, e solo dove si puo' andare.
		var can_go: bool = i in _reachable
		var color := Color(1, 1, 1, 0)
		if can_go:
			color = Color(0.35, 0.8, 1.0, 0.30)
			if i == _hovered:
				color = Color(0.65, 0.95, 1.0, 0.70)
		elif not moving and i == _hovered:
			color = Color(1, 1, 1, 0.10)
		var marker := sector_markers[i]
		var mat: StandardMaterial3D = marker.material_override
		mat.albedo_color = color
		marker.position.y = 0.09 if (i == _hovered and can_go) else 0.02


## I segnalini terreno vengono posati sulla plancia con la loro immagine vera.
## Se un modello 3D e' disponibile in models/terrain/<tipo>.glb viene usato quello.
## Quattro terreni non hanno miniatura perche' non sono oggetti: fuoco, dust,
## acqua e sabbia sono fenomeni, e si fanno con particelle e shader.
##
## Il tavolo si ricostruisce solo quando cambia davvero: `_refresh` arriva a ogni
## variazione di stato, e rifare i nodi a ogni giro riavvierebbe le particelle
## da capo un fotogramma sì e uno no.
func set_terrain(terrain: Array, dust: Array = [0, 0, 0, 0]) -> void:
	var signature := "%s|%s" % [terrain, dust]
	if signature == _terrain_signature:
		return
	_terrain_signature = signature
	for child in terrain_root.get_children():
		child.queue_free()

	for pos in 4:
		if int(dust[pos]) > 0:
			terrain_root.add_child(_dust_cloud(sector_world_position(pos), int(dust[pos])))

		var types: Array = terrain[pos]
		for k in types.size():
			var type := String(types[k])
			var angle := TAU * float(k) / 6.0
			var spot := sector_world_position(pos) \
				+ Vector3(cos(angle) * 0.85, 0.0, sin(angle) * 0.85)

			# Il fuoco quasi spento usa la stessa fiamma, piu' bassa e piu' scura:
			# nei dati e' un tipo a se' (`fire_spent`), sul tavolo e' il segnalino
			# girato sul lato giallo.
			var spent := type.ends_with("_spent")
			var base_type := type.trim_suffix("_spent")

			match base_type:
				"fire":
					terrain_root.add_child(_flame(spot, spent))
					continue
				"water":
					terrain_root.add_child(_water_patch(spot))
					continue
				"sand":
					terrain_root.add_child(_sand_patch(spot))
					continue

			var model := _instance_model("res://models/terrain/%s.glb" % base_type)
			if model != null:
				_fit_to_ground(model, 0.9)
				model.position = spot
				terrain_root.add_child(model)
				continue

			# Altrimenti il segnalino di cartone, appoggiato piatto sulla plancia.
			var token := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(0.86, 0.86)
			token.mesh = quad
			token.rotation.x = -PI / 2
			token.position = spot + Vector3(0, 0.05, 0)
			var mat := StandardMaterial3D.new()
			var tex: Variant = load("res://art/terrain/%s.png" % base_type)
			if tex is Texture2D:
				mat.albedo_texture = tex
			else:
				mat.albedo_color = _terrain_color(type)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			token.material_override = mat
			terrain_root.add_child(token)


# ------------------------------------------------- terreni procedurali

## Batuffolo sfumato: e' la texture di ogni particella. Generarlo qui evita di
## portarsi dietro un PNG per una cosa che e' solo un gradiente radiale.
func _soft_dot() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.width = 64
	tex.height = 64
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	return tex


## Quadratino sempre rivolto alla camera, usato come passata di disegno delle
## particelle. `additive` per la luce (fiamma), altrimenti mescolanza normale.
func _particle_quad(size: float, additive: bool) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive \
		else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.disable_receive_shadows = true
	quad.material = mat
	return quad


func _color_ramp(colors: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var stops := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / float(maxi(colors.size() - 1, 1)))
		stops.append(colors[i])
	var gradient := Gradient.new()
	# I due array vanno assegnati insieme: un Gradient nasce con due punti, e
	# aggiungerne altri senza sostituire quelli lascia i colori di partenza.
	gradient.offsets = offsets
	gradient.colors = stops
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


## Fuoco: particelle che salgono strette e si spengono. Il fuoco quasi spento
## e' la stessa fiamma con meno particelle, piu' bassa e virata al giallo.
func _flame(spot: Vector3, spent: bool) -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.position = spot + Vector3(0, 0.04, 0)
	fx.amount = 18 if spent else 30
	fx.lifetime = 0.7 if spent else 1.0
	fx.preprocess = fx.lifetime          # arriva gia' acceso, non si vede nascere
	fx.draw_pass_1 = _particle_quad(0.34 if spent else 0.42, true)

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.22
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 12.0
	pm.initial_velocity_min = 0.5 if spent else 0.8
	pm.initial_velocity_max = 0.9 if spent else 1.5
	pm.gravity = Vector3(0, 0.4, 0)
	pm.damping_min = 0.4
	pm.damping_max = 0.9
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	# La fiamma si assottiglia salendo.
	var shrink := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.35))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	shrink.curve = curve
	pm.scale_curve = shrink
	pm.color_ramp = _color_ramp([
		Color(1.0, 0.95, 0.6, 1.0),
		Color(1.0, 0.55, 0.12, 0.9) if not spent else Color(0.95, 0.75, 0.2, 0.7),
		Color(0.6, 0.12, 0.03, 0.0),
	])
	fx.process_material = pm

	# La fiamma illumina il proprio settore: senza, sembra un adesivo.
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 0.9 if spent else 1.8
	glow.omni_range = 2.6
	glow.position.y = 0.5
	fx.add_child(glow)
	return fx


## Dust: polvere bassa e lenta, che copre tutto il settore invece di stare su un
## segnalino. Piu' segnalini dust, piu' e' densa (il tetto e' 2 per settore).
func _dust_cloud(center: Vector3, count: int) -> GPUParticles3D:
	var fx := GPUParticles3D.new()
	fx.position = center + Vector3(0, 0.12, 0)
	fx.amount = 18 * count
	fx.lifetime = 3.2
	fx.preprocess = 3.2
	fx.draw_pass_1 = _particle_quad(0.55, false)

	var pm := ParticleProcessMaterial.new()
	# Un disco, non un cubo: la casella e' tonda e una foschia quadrata si vede.
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3(0, 1, 0)
	pm.emission_ring_radius = 0.95
	pm.emission_ring_inner_radius = 0.0
	pm.emission_ring_height = 0.12
	pm.direction = Vector3(1, 0.15, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.22
	pm.gravity = Vector3(0, 0.02, 0)
	pm.damping_min = 0.05
	pm.damping_max = 0.15
	pm.scale_min = 0.7
	pm.scale_max = 1.6
	pm.color_ramp = _color_ramp([
		Color(0.62, 0.54, 0.42, 0.0),
		Color(0.62, 0.54, 0.42, 0.30),
		Color(0.55, 0.48, 0.38, 0.0),
	])
	fx.process_material = pm
	return fx


## Acqua: una pezza di piano suddivisa, mossa da due onde incrociate. Il colore
## e la lucentezza vengono dallo shader, non da una texture.
func _water_patch(spot: Vector3) -> MeshInstance3D:
	var patch := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.15, 1.15)
	plane.subdivide_width = 12
	plane.subdivide_depth = 12
	patch.mesh = plane
	patch.position = spot + Vector3(0, 0.04, 0)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode cull_disabled;

uniform vec3 shallow_color : source_color = vec3(0.30, 0.55, 0.55);
uniform vec3 deep_color : source_color = vec3(0.06, 0.20, 0.26);

void vertex() {
	VERTEX.y += (sin(VERTEX.x * 22.0 + TIME * 1.1)
		+ sin(VERTEX.z * 17.0 - TIME * 0.8)) * 0.012;
}

void fragment() {
	// Onde larghe e lente: alzando la frequenza il riflesso si spezza in una
	// griglia di puntini e la pozza sembra una palla da bowling.
	float a = UV.x * 11.0 + TIME * 1.1;
	float b = UV.y * 9.0 - TIME * 0.8;
	ALBEDO = mix(deep_color, shallow_color, (sin(a) + sin(b)) * 0.3 + 0.5);
	// Il bordo sfuma: la pozza non ha un contorno netto.
	float edge = 1.0 - smoothstep(0.28, 0.48, length(UV - vec2(0.5)));
	ALPHA = 0.78 * edge;
	NORMAL_MAP = normalize(vec3(cos(a) * 0.16, cos(b) * 0.16, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = 0.22;
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	patch.material_override = mat
	return patch


## Sabbia: resta la tessera, ma le sue increspature si muovono. Il rilievo e'
## tutto nella normale calcolata a schermo — la geometria e' un quadrato piatto.
func _sand_patch(spot: Vector3) -> MeshInstance3D:
	var patch := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.95, 0.95)
	patch.mesh = plane
	patch.position = spot + Vector3(0, 0.045, 0)
	var shader := Shader.new()
	shader.code = """
shader_type spatial;

uniform vec3 sand_color : source_color = vec3(0.78, 0.66, 0.43);
uniform sampler2D token : source_color, hint_default_transparent;
uniform float use_token = 0.0;

void fragment() {
	// Creste parallele che ondeggiano lentamente: una sinusoide deformata da
	// una seconda, piu' lenta, lungo l'altro asse.
	float phase = UV.y * 7.0 + TIME * 0.22;
	float u = UV.x * 18.0 + sin(phase) * 2.0;
	float h = sin(u);
	vec3 n = normalize(vec3(-cos(u) * 0.16, -cos(u) * cos(phase) * 0.13, 1.0));
	NORMAL_MAP = n * 0.5 + 0.5;
	// Appena accennate: sotto c'e' gia' il disegno della duna sul segnalino, e
	// due rilievi sovrapposti fanno sembrare la sabbia carta accartocciata.
	NORMAL_MAP_DEPTH = 0.45;
	vec4 t = texture(token, UV);
	ALBEDO = mix(sand_color * (0.92 + 0.08 * h), t.rgb, use_token);
	ALPHA = mix(1.0, t.a, use_token);
	ROUGHNESS = 0.95;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var tex: Variant = load("res://art/terrain/sand.png")
	if tex is Texture2D:
		mat.set_shader_parameter("token", tex)
		mat.set_shader_parameter("use_token", 1.0)
	patch.material_override = mat
	return patch


func _terrain_color(type: String) -> Color:
	match type:
		"fire": return Color(1.0, 0.45, 0.1)
		"brush": return Color(0.3, 0.6, 0.25)
		"cyricae": return Color(0.6, 0.35, 0.8)
		"baethanis": return Color(0.9, 0.8, 0.3)
		"rock": return Color(0.55, 0.55, 0.6)
		"plateau": return Color(0.7, 0.6, 0.45)
	return Color.WHITE


# ------------------------------------------------------------------- colpi

## Un colpo alla volta: il motore ne emette anche tre di fila (attacco, battle
## dance, weapon) e sovrapporli darebbe solo un tremolio confuso.
func strike(attacker_id: String, target_id: String, amount: int) -> void:
	_blow_queue.append([attacker_id, target_id, amount])
	if not _blow_running:
		_run_blow_queue()


func _run_blow_queue() -> void:
	_blow_running = true
	while not _blow_queue.is_empty():
		var next: Array = _blow_queue.pop_front()
		await _play_blow(String(next[0]), String(next[1]), int(next[2]))
	_blow_running = false


## Il corpo animabile di un combattente: la miniatura del cacciatore o il mostro.
func _body_of(id: String) -> Node3D:
	if id == "monster":
		return monster
	var node: Node3D = hunter_nodes.get(id)
	if node != null and node.has_meta("body"):
		return node.get_meta("body")
	return node


## Chi colpisce scatta verso il bersaglio e torna al suo posto; chi incassa
## trema, tanto piu' forte quanto pesa il colpo. Se colpitore e bersaglio
## coincidono (fatigue, burning) resta solo il tremito.
func _play_blow(attacker_id: String, target_id: String, amount: int) -> void:
	var attacker := _body_of(attacker_id)
	var target := _body_of(target_id)
	if target == null:
		return

	var shake := clampf(0.05 + 0.012 * float(amount), 0.05, 0.16)
	var target_home: Vector3 = target.position
	var shudder := create_tween()
	var moves := 0.0
	if attacker != null and attacker != target:
		# Il tremito parte quando lo scatto arriva a segno, non prima.
		shudder.tween_interval(0.13)
		moves = 0.13
	for i in 4:
		var side := shake * (1.0 - float(i) * 0.22) * (1.0 if i % 2 == 0 else -1.0)
		shudder.tween_property(target, "position",
			target_home + Vector3(side, 0.0, side * 0.6), 0.05) \
			.set_trans(Tween.TRANS_SINE)
	shudder.tween_property(target, "position", target_home, 0.06)
	moves += 0.26

	if attacker != null and attacker != target:
		var toward := target.global_position - attacker.global_position
		toward.y = 0.0
		if toward.length() > 0.01:
			var home: Vector3 = attacker.position
			var lunge: Vector3 = home + toward.normalized() * 0.42
			var strike_tween := create_tween()
			strike_tween.tween_property(attacker, "position", lunge, 0.13) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			strike_tween.tween_property(attacker, "position", home, 0.20) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			moves = maxf(moves, 0.33)

	await get_tree().create_timer(moves).timeout


# ------------------------------------------------------------- camera orbit

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or \
		   (event.button_index == MOUSE_BUTTON_LEFT and Input.is_key_pressed(KEY_SHIFT)) or \
		   event.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = clampf(_distance - 1.0, 6.0, 30.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = clampf(_distance + 1.0, 6.0, 30.0)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch - event.relative.y * 0.006, -1.45, -0.15)
		_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		-sin(_pitch),
		cos(_pitch) * cos(_yaw)) * _distance
	camera.position = offset
	camera.look_at(Vector3.ZERO, Vector3.UP)


# --------------------------------------------------- carte giocate sul tavolo

const SEQ_CARD_W := 0.82
const SEQ_CARD_H := 1.15


## Dispone la sequenza del giocatore attivo sul tavolo, davanti alla sua casella:
## le carte si giocano sulla plancia, non in un pannello dell'interfaccia.
func show_sequence(cards: Array, position_index: int) -> void:
	for child in sequence_root.get_children():
		child.queue_free()
	if cards.is_empty():
		return

	var spot := sector_world_position(position_index)
	var outward := spot.normalized()                       # dal centro verso il giocatore
	var side := Vector3(outward.z, 0.0, -outward.x)        # lungo il bordo
	var origin := spot + outward * 1.35

	for i in cards.size():
		var is_new := i == cards.size() - 1 and cards.size() > _last_sequence_size
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(SEQ_CARD_W, SEQ_CARD_H)
		quad.mesh = mesh
		var mat := StandardMaterial3D.new()
		var tex: Variant = load(Db.card_art(int(cards[i])))
		if tex is Texture2D:
			mat.albedo_texture = tex
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		quad.material_override = mat
		quad.rotation.x = -PI / 2                          # coricata sul tavolo
		quad.rotation.y = atan2(outward.x, outward.z)
		var offset := (float(i) - float(cards.size() - 1) * 0.5) * (SEQ_CARD_W + 0.08)
		var seat := origin + side * offset + Vector3(0, 0.03, 0)
		quad.position = seat
		sequence_root.add_child(quad)
		if is_new:
			# Arriva dall'alto e si posa: si vede che la carta e' stata giocata.
			quad.position = seat + Vector3(0, 3.2, 1.4)
			quad.scale = Vector3.ONE * 1.6
			var tween := create_tween().set_parallel(true)
			tween.tween_property(quad, "position", seat, 0.32) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tween.tween_property(quad, "scale", Vector3.ONE, 0.32) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_last_sequence_size = cards.size()
