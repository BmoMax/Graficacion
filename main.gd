extends Node3D

const MODEL_PATH := "res://ninja_2d.glb"
const MAP_PATH := "res://map.glb"
const BOSS_PATH := "res://guardian.glb"
const NinjaSprite := preload("res://ninja_sprite.gd")
const Centinela := preload("res://centinela.gd")   # Centinela 2D por poses
const Hud := preload("res://hud.gd")
const SPAWN_ROBOTS := false     # true = vuelven los 3 robots de cajas
const BOSS_HOME_X := 4.8        # donde aparece el Centinela
const ROOT_MAX_HP := 10
# --- FONDO HIBRIDO: ciudad pintada en 2D detras + piso/escenario en 3D delante ---
const BG_PATH := "res://bg/city.png"
const BG_DIST := 45.0           # a que distancia de la camara queda la ciudad 2D
const BG_PARALLAX := 0.93       # 1.0 = pegada a la camara (sin profundidad); menos = se mueve un poco
const MAP_CLIP_H := 7.0         # altura (m) hasta donde se ve el mapa 3D; mas arriba se ve la ciudad 2D (pon 999 para ver todo el mapa)
const MAP_FADE_H := 3.0         # zona de desvanecimiento del corte
const MAP_FIX_ORANGE := true    # quita los parches naranjas de la textura del mapa
# --- ENERGIA / PARRY ---
const ENERGY_PER_POWER := 0.07  # orbes que se ganan por cada punto de fuerza de un golpe que conecta
const PARRY_ENERGY := 0.35      # orbes que da un parry perfecto
const PARRY_WINDOW := 0.18      # segundos de la ventana de parry al pulsar F
const PARRY_COOLDOWN := 0.6     # no puedes volver a abrir la ventana antes de esto (anti-spam)
const PARRY_POSTURE := 32.0     # postura que pierde el Centinela con un parry perfecto
const GUARD_SPEED := 1.6        # velocidad al caminar guardando
const ROOT_POSTURE_MAX := 100.0
const ROOT_POSTURE_REGEN := 16.0        # por segundo, sin guardia
const ROOT_POSTURE_REGEN_GUARD := 5.0   # por segundo, guardando
# --- MAPA (girado para verse de frente, como tu imagen) ---
const MAP_SCALE := 42.0        # tamano del escenario (mas grande = mas colosal)
const MAP_FRONT_X := 0.22      # profundidad (en el modelo) donde esta el piso del ninja
const MAP_FLOOR_Y := -0.207    # altura del piso en el modelo (sube/baja el ninja si flota o se hunde)
const ARENA_HALF := 0.36       # mitad del ancho jugable (en unidades del modelo)
const CAM_DIST := 5.2          # distancia de la camara al ninja
const CAM_H := 1.0             # altura de la camara (baja = todo se ve mas enorme)
const CAM_LOOK_Y := 2.1        # a que altura mira la camara (alto = mira hacia las torres)
const CAM_FOV := 52.0          # campo de vision (mas ancho = mas escenario)
const RUN_SPEED := 3.8
const SPRINT_SPEED := 5.8
const CROUCH_SPEED := 1.0
const ARMED_RUN_SPEED := 3.4
const ATTACK_MOVE_SPEED := 2.4
const DASH_SPEED := 9.5
const DASH_TIME := 0.28
const DASH_COOLDOWN := 0.7
const JUMP_VELOCITY := 5.2
const JUMP_DELAY := 0.12
const JUMP_ANIM_TIME := 0.95
const ROLL_SPEED := 4.2
const TURN_SPEED := 18.0
const GRAVITY := 12.0
const ATTACK_RANGE := 2.6
const AUTO_SHEATHE := 3.0
const SPRINT_AFTER := 1.6
const HIT_TIMES := {"attack1": 0.5, "attack2": 0.5, "attack3": 0.625, "thrust": 0.375}
const MAP_SHADER := """
shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool has_orm = false;
uniform float clip_y = 7.0;
uniform float fade_h = 3.0;
uniform bool fix_orange = true;
varying float wy;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}
vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}
float h21(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	// recorte con trama: arriba de clip_y el modelo se disuelve y deja ver la ciudad 2D
	float t = (wy - clip_y) / fade_h;
	if (t > 0.0 && h21(FRAGCOORD.xy) < t) {
		discard;
	}
	vec3 col = texture(albedo_tex, UV).rgb;
	if (fix_orange) {
		vec3 hsv = rgb2hsv(col);
		float hue_w = smoothstep(0.015, 0.045, hsv.x) * (1.0 - smoothstep(0.13, 0.19, hsv.x));
		float amt = hue_w * smoothstep(0.22, 0.45, hsv.y) * smoothstep(0.10, 0.25, hsv.z);
		vec3 repl = hsv2rgb(vec3(0.60, min(hsv.y, 0.7), hsv.z * 0.6));
		col = mix(col, repl, amt);
	}
	ALBEDO = col;
	if (has_orm) {
		vec3 orm = texture(orm_tex, UV).rgb;
		ROUGHNESS = orm.g;
		METALLIC = orm.b;
	}
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
}
"""
const BACKDROP_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_opaque;
uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float glow = 0.6;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV;
	vec3 c = texture(tex, uv).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	// neones cian que laten
	float cyan = clamp((c.b + c.g) * 0.5 - c.r, 0.0, 1.0);
	float pulse = 0.55 + 0.45 * sin(TIME * 1.1 + uv.x * 12.0 + uv.y * 5.0);
	c += c * cyan * smoothstep(0.35, 0.8, l) * glow * pulse * 1.2;
	// fuegos calidos que parpadean
	float warm = clamp(c.r - c.b, 0.0, 1.0) * smoothstep(0.35, 0.75, l);
	float flick = 0.5 + 0.5 * sin(TIME * 8.0 + uv.x * 60.0) * sin(TIME * 3.3 + uv.y * 40.0);
	c += c * warm * 0.4 * flick;
	// niebla que se desplaza cerca del piso
	float n = noise(vec2(uv.x * 9.0 + TIME * 0.04, uv.y * 14.0)) * 0.6 + noise(vec2(uv.x * 22.0 - TIME * 0.06, uv.y * 30.0)) * 0.4;
	float band = smoothstep(0.45, 0.80, uv.y) * (1.0 - smoothstep(0.88, 1.0, uv.y));
	c = mix(c, vec3(0.30, 0.22, 0.50) * (0.6 + n), band * n * 0.35);
	// la base se oscurece para fundirse con el piso 3D
	c *= 1.0 - 0.55 * smoothstep(0.86, 1.0, uv.y);
	ALBEDO = c;
}
"""
const LOCO_NAMES := ["idle", "run", "sprint", "crouch", "crouchwalk", "jump", "roll", "dash", "hit", "death"]
const COMBAT_NAMES := ["guard", "draw", "attack1", "attack2", "attack3", "thrust", "sheathe", "hitguard"]
const LOOPED := ["idle", "walk", "run", "sprint", "crouch", "crouchwalk", "guard"]
const SKY_CODE := """
shader_type sky;
uniform vec3 top_col : source_color = vec3(0.02, 0.04, 0.11);
uniform vec3 mid_col : source_color = vec3(0.10, 0.17, 0.34);
uniform vec3 glow_col : source_color = vec3(0.10, 0.55, 0.95);
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}
void sky() {
	vec3 d = EYEDIR;
	float h = clamp(d.y, 0.0, 1.0);
	vec2 uv = d.xz / (d.y + 0.4) * 1.7 + vec2(TIME * 0.012, TIME * 0.004);
	float c = fbm(uv);
	float c2 = fbm(uv * 2.1 - vec2(TIME * 0.02, 0.0));
	float clouds = smoothstep(0.38, 0.85, c * 0.65 + c2 * 0.5);
	vec3 col = mix(mid_col, top_col, pow(h, 0.45));
	col = mix(col, col * 0.3 + vec3(0.015, 0.02, 0.05), clouds);
	float g = pow(max(dot(d, normalize(vec3(0.0, 0.3, -1.0))), 0.0), 5.0);
	col += glow_col * g * (0.5 + clouds * 0.7);
	float flash = pow(max(sin(TIME * 0.37 + sin(TIME * 0.11) * 3.0), 0.0), 40.0);
	col += vec3(0.4, 0.6, 1.0) * flash * clouds * 0.6;
	COLOR = col;
}
"""

const LOCKING := ["draw", "sheathe", "attack1", "attack2", "spin", "thrust", "heavy", "prep", "special"]
const STRIKES := ["attack1", "attack2", "spin", "thrust", "heavy", "prep", "special"]
# los 7 ataques: 1 horizontal (J) - 2 vertical (J) - 3 estocada (K) - 4 giro 360 (J, tercer golpe)
# 5 pesado a dos manos (L) - 6 preparacion y ejecucion (U) - 7 especial morado (I)
const CLIP_OF := {"spin": "attack3", "heavy": "attack3", "prep": "attack2", "special": "thrust", "parry": "hitguard"}
const POWER := {"attack1": 1, "attack2": 2, "spin": 3, "thrust": 2, "heavy": 4, "prep": 3, "special": 5}
const LUNGE := {"attack1": 3.0, "attack2": 3.4, "spin": 2.0, "thrust": 4.5, "heavy": 3.0, "prep": 9.0, "special": 2.0}
const WINDUP := {"heavy": 0.3, "prep": 0.45, "special": 0.65}
# velocidad de las animaciones de espada (1.0 = original). Mas alto = mas rapido, estilo ninja
const ATTACK_SPEED := {"attack1": 1.5, "attack2": 1.5, "attack3": 1.4, "thrust": 1.4, "draw": 1.7, "sheathe": 1.6}


class Robot extends Node3D:
	var hp := 3
	var dead := false
	var home := Vector3.ZERO
	var flash := 0.0
	var vel := 0.0
	var respawn := 0.0
	var t := 0.0
	var target: Node3D
	var floor_fn: Callable
	var eye_mat: StandardMaterial3D
	var body_mat: StandardMaterial3D

	func build() -> void:
		body_mat = StandardMaterial3D.new()
		body_mat.albedo_color = Color(0.35, 0.38, 0.42)
		body_mat.metallic = 0.7
		body_mat.roughness = 0.45
		body_mat.emission = Color(1.0, 0.7, 0.3)
		eye_mat = StandardMaterial3D.new()
		eye_mat.albedo_color = Color(0.1, 0.0, 0.0)
		eye_mat.emission_enabled = true
		eye_mat.emission = Color(1.0, 0.1, 0.05)
		eye_mat.emission_energy_multiplier = 4.0
		_add_box(Vector3(0.4, 0.9, 0.7), Vector3(0, 1.15, 0), body_mat)
		_add_box(Vector3(0.4, 0.4, 0.45), Vector3(0, 1.85, 0), body_mat)
		_add_box(Vector3(0.05, 0.08, 0.3), Vector3(0.21, 1.87, 0), eye_mat)
		_add_box(Vector3(0.2, 0.8, 0.2), Vector3(0, 1.1, -0.5), body_mat)
		_add_box(Vector3(0.2, 0.8, 0.2), Vector3(0, 1.1, 0.5), body_mat)
		_add_box(Vector3(0.25, 0.7, 0.25), Vector3(0, 0.35, -0.2), body_mat)
		_add_box(Vector3(0.25, 0.7, 0.25), Vector3(0, 0.35, 0.2), body_mat)

	func _add_box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position = pos
		add_child(mi)

	func hit(dir_x: float, power: int) -> void:
		if dead:
			return
		hp -= 1
		flash = 1.0
		vel = dir_x * (4.0 + power * 1.5)
		if hp <= 0 or power >= 3:
			dead = true
			visible = false
			respawn = 2.5

	func revive() -> void:
		hp = 3
		dead = false
		visible = true
		position = home
		vel = 0.0

	func _process(delta: float) -> void:
		t += delta
		if dead:
			respawn -= delta
			if respawn <= 0.0:
				revive()
			return
		position.x += vel * delta
		vel = move_toward(vel, 0.0, 12.0 * delta)
		position.z = 0.0
		position.x = clampf(position.x, -20.0, 20.0)
		if target != null:
			var dx := target.global_position.x - global_position.x
			rotation.y = 0.0 if dx > 0.0 else PI
			if absf(vel) < 0.3 and absf(dx) > 1.7 and absf(dx) < 9.0:
				position.x += signf(dx) * 0.7 * delta
		flash = maxf(0.0, flash - delta * 4.0)
		body_mat.emission_enabled = flash > 0.0
		body_mat.emission_energy_multiplier = flash * 3.0
		var gy := 0.0
		if floor_fn.is_valid():
			gy = float(floor_fn.call(position.x))
		position.y = gy + sin(t * 2.0 + home.x) * 0.03


var player: CharacterBody3D
var model: Node3D
var sprite: NinjaSprite
var anim: AnimationPlayer
var tree: AnimationTree
var cam: Camera3D
var names := {}
var lengths := {}
var loco_req := {}
var combat_req := {}
var combat2_req := {}
var robots: Array = []
var boss: Node3D
var root_hp := ROOT_MAX_HP
var root_max := ROOT_MAX_HP
var energy := 0.0
var root_posture := 0.0
var guard_on := false
var guard_lock := 0.0
var parry_t := 99.0
var parry_cd := 0.0
var parry_streak := 0
var parry_streak_t := 0.0
var slide := 0.0
var backdrop: MeshInstance3D
var backdrop_base := Vector3.ZERO
var hurt_dir := -1.0
var hurt_push := 1.2

var facing := 1.0
var armed := false
var act := ""
var act_time := 0.0
var act_len := 0.0
var queued_attack := false
var queued_thrust := false
var want_sheathe := false
var hit_done := false
var idle_timer := 0.0
var crouching := false
var run_time := 0.0
var jump_pending := false
var jump_delay := 0.0
var jump_time := 99.0
var dash_time := 0.0
var dash_cd := 0.0
var dash_dir := 1.0
var roll_time := 0.0
var dead := false
var shake := 0.0
var lunge_timer := 0.0
var cam_x := 0.0
var cur_loco := ""
var cur_combat := ""
var upper_amt := 0.0
var full_amt := 0.0
var override_x = null
var banners: Array = []
var speed_ok := false
var exec_started := true
var queued_move := ""
var fx_cache := {}
var air_jumps := 1
var lunge_speed := 3.2
var lane_x0 := 0.0
var lane_cell := 0.004
var lane_z: Array = []
var z_ref := 0.0


func _ready() -> void:
	_build_world()
	_build_player()
	_build_robots()
	_build_hud()


func _build_hud() -> void:
	var h := Hud.new()
	add_child(h)
	h.setup(self)


func floor_y(_xg: float) -> float:
	return 0.0


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_shader := Shader.new()
	sky_shader.code = SKY_CODE
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = sky_shader
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssao_enabled = true
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.55, 0.7)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_bloom = 0.3
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.08, 0.13)
	env.fog_density = 0.006
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.35, 0.5, 0.75)
	env.volumetric_fog_length = 70.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -20, 0)
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 160, 0)
	rim.light_energy = 0.5
	add_child(rim)
	_build_atmosphere()
	_build_props()
	_build_backdrop()

	if ResourceLoader.exists(MAP_PATH):
		var map_scene: PackedScene = load(MAP_PATH)
		var map_inst: Node3D = map_scene.instantiate()
		add_child(map_inst)
		map_inst.scale = Vector3.ONE * MAP_SCALE
		map_inst.rotation = Vector3(0.0, deg_to_rad(-90.0), 0.0)
		map_inst.position = Vector3(0.0, -MAP_FLOOR_Y * MAP_SCALE, -MAP_FRONT_X * MAP_SCALE)
		_restyle_map(map_inst)
	else:
		push_error("Falta res://map.glb")

	var half := ARENA_HALF * MAP_SCALE
	var ground := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(half * 2.0 + 4.0, 1.0, 8.0)
	gcs.shape = gb
	gcs.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(gcs)
	add_child(ground)
	_add_wall(-(half + 0.5))
	_add_wall(half + 0.5)


# mapa 3D: sin naranjas y recortado en altura para que detras se vea la ciudad 2D
func _restyle_map(root: Node) -> void:
	var sh := Shader.new()
	sh.code = MAP_SHADER
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var src := mi.get_active_material(0) as BaseMaterial3D
		if src == null:
			continue
		var alb: Texture2D = src.get_texture(BaseMaterial3D.TEXTURE_ALBEDO)
		if alb == null:
			continue
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("albedo_tex", alb)
		m.set_shader_parameter("clip_y", MAP_CLIP_H)
		m.set_shader_parameter("fade_h", MAP_FADE_H)
		m.set_shader_parameter("fix_orange", MAP_FIX_ORANGE)
		var nrm: Texture2D = src.get_texture(BaseMaterial3D.TEXTURE_NORMAL)
		if nrm != null:
			m.set_shader_parameter("normal_tex", nrm)
			m.set_shader_parameter("has_normal", true)
		var orm: Texture2D = src.get_texture(BaseMaterial3D.TEXTURE_ROUGHNESS)
		if orm == null:
			orm = src.get_texture(BaseMaterial3D.TEXTURE_METALLIC)
		if orm != null:
			m.set_shader_parameter("orm_tex", orm)
			m.set_shader_parameter("has_orm", true)
		mi.material_override = m


# ciudad pintada (2D) muy atras, encuadrada igual que la camara del juego
func _build_backdrop() -> void:
	if not ResourceLoader.exists(BG_PATH):
		return
	var tex: Texture2D = load(BG_PATH)
	var h := 2.0 * BG_DIST * tan(deg_to_rad(CAM_FOV * 0.5))
	var w := h * (16.0 / 9.0) * 1.2          # la imagen trae 10% extra a cada lado
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	var sh := Shader.new()
	sh.code = BACKDROP_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tex", tex)
	backdrop = MeshInstance3D.new()
	backdrop.mesh = qm
	backdrop.material_override = m
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pitch := atan2(CAM_LOOK_Y - CAM_H, CAM_DIST)
	backdrop.rotation = Vector3(pitch, 0.0, 0.0)
	var dir := Vector3(0.0, sin(pitch), -cos(pitch))
	backdrop_base = Vector3(0.0, CAM_H, CAM_DIST) + dir * BG_DIST
	backdrop.position = backdrop_base
	add_child(backdrop)


func _add_wall(wx: float) -> void:
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(1.0, 60.0, 10.0)
	wcs.shape = wbox
	wall.add_child(wcs)
	wall.position = Vector3(wx, 25.0, 0.0)
	add_child(wall)


func _banner_texture() -> ImageTexture:
	var w := 64
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var jag := int(sin(float(x) * 0.9) * 6.0 + sin(float(x) * 2.3) * 4.0 + 14.0)
			if y > h - 1 - jag:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var shade := 0.75 + 0.25 * sin(float(x) * 0.35 + float(y) * 0.05)
			var c := Color(0.78 * shade, 0.12 * shade, 0.27 * shade, 1.0)
			var dx := float(x) - 32.0
			var dy := float(y) - 62.0
			var r := sqrt(dx * dx + dy * dy)
			if (r > 15.0 and r < 18.5) or (absf(dx) < 1.8 and absf(dy) < 28.0):
				c = Color(0.98, 0.62, 0.68, 1.0)
			if x < 3 or x > w - 4:
				c = Color(0.35, 0.05, 0.07, 1.0)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _build_props() -> void:
	# estandartes rojos rasgados
	var tex := _banner_texture()
	var bmat := StandardMaterial3D.new()
	bmat.albedo_texture = tex
	bmat.emission_enabled = true
	bmat.emission_texture = tex
	bmat.emission_energy_multiplier = 0.3
	bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.05, 0.05, 0.07)
	pole_mat.metallic = 0.8
	pole_mat.roughness = 0.4
	var spots := [Vector2(-12.0, -3.5), Vector2(12.0, -3.5), Vector2(-8.0, -7.0), Vector2(8.0, -7.0), Vector2(-13.5, -10.5), Vector2(13.5, -10.5)]
	for p in spots:
		var pole := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.1
		cm.height = 9.0
		pole.mesh = cm
		pole.material_override = pole_mat
		pole.position = Vector3(p.x, 4.5, p.y)
		add_child(pole)
		var ban := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(3.0, 7.0)
		ban.mesh = qm
		ban.material_override = bmat
		ban.position = Vector3(p.x, 5.2, p.y + 0.12)
		add_child(ban)
		banners.append(ban)
	# anillos luminosos en el piso
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.05, 0.15, 0.2)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.2, 0.8, 1.0)
	ring_mat.emission_energy_multiplier = 2.5
	for rr in [5.0, 9.0, 13.0]:
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = rr - 0.06
		tm.outer_radius = rr
		tm.rings = 96
		tm.ring_segments = 6
		ring.mesh = tm
		ring.material_override = ring_mat
		ring.position = Vector3(0.0, 0.04, -4.0)
		ring.scale = Vector3(1.0, 0.2, 1.0)
		add_child(ring)


func _beam_texture() -> ImageTexture:
	var w := 32
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var u := float(x) / float(w - 1)
			var v := float(y) / float(h - 1)
			var a := pow(sin(u * PI), 1.6) * pow(1.0 - v, 1.1)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _build_beams() -> void:
	var tex := _beam_texture()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.5, 0.8, 1.0, 0.16)
	var beams := [Vector3(-14.0, 14.0, -22.0), Vector3(-6.0, 15.0, -26.0), Vector3(4.0, 15.0, -28.0)]
	for b in beams:
		var q := QuadMesh.new()
		q.size = Vector2(7.0, 34.0)
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.position = b
		mi.rotation = Vector3(0.0, 0.0, deg_to_rad(-22.0))


func _build_atmosphere() -> void:
	_build_beams()
	# resplandor de la torre central (al fondo del escenario)
	var tower := OmniLight3D.new()
	tower.light_color = Color(0.3, 0.75, 1.0)
	tower.light_energy = 8.0
	tower.omni_range = 60.0
	tower.position = Vector3(0.0, 9.0, -MAP_SCALE * 0.45)
	add_child(tower)
	# luces frias a los lados (sin naranja)
	for sx in [-1.0, 1.0]:
		var torch := OmniLight3D.new()
		torch.light_color = Color(0.45, 0.55, 1.0)
		torch.light_energy = 3.5
		torch.omni_range = 26.0
		torch.position = Vector3(sx * MAP_SCALE * 0.3, 3.0, -MAP_SCALE * 0.2)
		add_child(torch)
	# bruma flotante
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	pm.albedo_texture = gt
	pm.albedo_color = Color(0.7, 0.45, 0.9, 0.08)
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0, 8.0)
	quad.material = pm
	var mist := CPUParticles3D.new()
	mist.mesh = quad
	mist.amount = 36
	mist.lifetime = 12.0
	mist.preprocess = 12.0
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	mist.emission_box_extents = Vector3(MAP_SCALE * 0.4, 1.2, MAP_SCALE * 0.3)
	mist.direction = Vector3(1, 0, 0)
	mist.spread = 20.0
	mist.initial_velocity_min = 0.3
	mist.initial_velocity_max = 0.8
	mist.gravity = Vector3.ZERO
	mist.scale_amount_min = 0.8
	mist.scale_amount_max = 1.8
	mist.position = Vector3(0.0, 0.6, -MAP_SCALE * 0.1)
	mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mist)


func _build_player() -> void:
	player = CharacterBody3D.new()
	var body_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.75
	body_shape.shape = capsule
	body_shape.position = Vector3(0, 0.875, 0)
	player.add_child(body_shape)
	add_child(player)
	player.position = Vector3(0.0, floor_y(0.0) + 0.2, 0.0)
	var pl := OmniLight3D.new()
	pl.light_color = Color(0.7, 0.8, 1.0)
	pl.light_energy = 1.4
	pl.omni_range = 9.0
	pl.position = Vector3(0.0, 2.4, 1.8)
	player.add_child(pl)

	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = CAM_FOV
	cam.position = Vector3(0, 3.0, 10.5)

	if not ResourceLoader.exists(MODEL_PATH):
		push_error("Falta res://ninja.glb. Copia ninja.glb dentro de la carpeta del proyecto y vuelve a abrirlo.")
		return

	var packed: PackedScene = load(MODEL_PATH)
	model = packed.instantiate()
	sprite = NinjaSprite.new()
	player.add_child(sprite)
	sprite.setup(Callable(self, "floor_y"))
	sprite.attach_model(model)
	model.rotation.y = 0.0

	anim = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim == null:
		push_error("El modelo no trae AnimationPlayer.")
		return

	for n in anim.get_animation_list():
		var key := String(n)
		var low := key.to_lower()
		names[low] = key
		lengths[low] = anim.get_animation(key).length
		anim.get_animation(key).loop_mode = Animation.LOOP_LINEAR if low in LOOPED else Animation.LOOP_NONE

	_build_tree()
	if speed_ok:
		for k in ATTACK_SPEED.keys():
			if lengths.has(k):
				lengths[k] = float(lengths[k]) / float(ATTACK_SPEED[k])


func _filter_bone(bone: String) -> bool:
	if bone in ["Spine", "Chest", "UpperChest", "Neck", "NeckTop", "Head", "Sword", "Scabbard"]:
		return true
	for p in ["Shoulder.", "UpperArm.", "LowerArm.", "Hand.", "FX_"]:
		if bone.begins_with(p):
			return true
	return false


func _make_transition(bt: AnimationNodeBlendTree, node_name: String, clips: Array, req: Dictionary, pos_y: float) -> void:
	var tr := AnimationNodeTransition.new()
	tr.input_count = clips.size()
	tr.xfade_time = 0.12
	tr.allow_transition_to_self = false
	bt.add_node(node_name, tr, Vector2(400, pos_y))
	for i in range(clips.size()):
		var an := AnimationNodeAnimation.new()
		an.animation = StringName(names[clips[i]])
		var spd := float(ATTACK_SPEED.get(clips[i], 1.0))
		if spd != 1.0 and "use_custom_timeline" in an:
			an.set("use_custom_timeline", true)
			an.set("timeline_length", float(lengths[clips[i]]) / spd)
			an.set("stretch_time_scale", true)
			speed_ok = true
		var nn: String = node_name + "_" + String(clips[i])
		bt.add_node(nn, an, Vector2(100, pos_y + i * 60))
		bt.connect_node(node_name, i, nn)
		var rn := "state_" + str(i)
		if tr.has_method("get_input_name"):
			rn = String(tr.call("get_input_name", i))
		req[clips[i]] = rn


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	_make_transition(bt, "loco", LOCO_NAMES, loco_req, 0.0)
	_make_transition(bt, "combat", COMBAT_NAMES, combat_req, 800.0)
	_make_transition(bt, "combat2", COMBAT_NAMES, combat2_req, 1400.0)
	var upper := AnimationNodeBlend2.new()
	upper.set_filter_enabled(true)
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var root := anim.get_node(anim.root_node)
	var spath := String(root.get_path_to(skel))
	for i in range(skel.get_bone_count()):
		var bn := skel.get_bone_name(i)
		if _filter_bone(bn):
			upper.set_filter_path(NodePath(spath + ":" + bn), true)
	var full := AnimationNodeBlend2.new()
	bt.add_node("upper", upper, Vector2(700, 0))
	bt.add_node("full", full, Vector2(900, 0))
	bt.connect_node("upper", 0, "loco")
	bt.connect_node("upper", 1, "combat")
	bt.connect_node("full", 0, "upper")
	bt.connect_node("full", 1, "combat2")
	bt.connect_node("output", 0, "full")
	tree = AnimationTree.new()
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(anim)
	tree.tree_root = bt
	tree.active = true
	_set_loco("idle")
	_set_combat("guard")


func _set_loco(n: String) -> void:
	if n == cur_loco or not loco_req.has(n):
		return
	cur_loco = n
	tree.set("parameters/loco/transition_request", loco_req[n])


func _set_combat(n: String) -> void:
	if n == cur_combat or not combat_req.has(n):
		return
	cur_combat = n
	tree.set("parameters/combat/transition_request", combat_req[n])
	tree.set("parameters/combat2/transition_request", combat2_req[n])


func _build_robots() -> void:
	if SPAWN_ROBOTS:
		var spots := [-13.0, -8.0, 6.5]
		for sx in spots:
			var r := Robot.new()
			r.home = Vector3(sx, 0, 0)
			r.target = player
			r.floor_fn = Callable(self, "floor_y")
			add_child(r)
			r.build()
			r.position = Vector3(sx, floor_y(sx), 0)
			robots.append(r)
	var b := Centinela.new()
	b.target = player
	b.home_x = BOSS_HOME_X
	b.arena_half = ARENA_HALF * MAP_SCALE - 1.0
	b.on_hit_player = Callable(self, "_boss_hits_player")
	b.fx_cb = Callable(self, "_boss_fx")
	add_child(b)
	b.position = Vector3(BOSS_HOME_X, floor_y(BOSS_HOME_X), 0)
	boss = b
	robots.append(b)


func _parry_window() -> float:
	return maxf(0.08, PARRY_WINDOW - 0.03 * float(parry_streak))   # cada parry seguido achica la ventana


# Los ataques del Centinela llegan aqui. info: power, dir, push, posture, unblock, pos
func _boss_hits_player(info: Dictionary) -> void:
	if dead or roll_time > 0.0 or dash_time > 0.0:
		return
	var power: int = int(info.get("power", 1))
	var dir_x: float = float(info.get("dir", -1.0))
	var push: float = float(info.get("push", 3.0))
	var post: float = float(info.get("posture", 15.0))
	var unblock: bool = bool(info.get("unblock", false))
	var front := signf(dir_x) == -facing
	if guard_on and front and not unblock:
		if parry_t <= _parry_window():
			_do_parry()
		else:
			_do_block(dir_x, push, post)
		return
	if act == "hit":
		return
	root_hp = maxi(0, root_hp - power)
	root_posture = maxf(0.0, root_posture - 25.0)
	_on_hurt()
	hurt_dir = dir_x
	hurt_push = push
	shake = 0.3 + 0.1 * float(power)
	if root_hp <= 0:
		_on_die()


# parry perfecto: no recibes dano, el Centinela se tambalea y pierde postura
func _do_parry() -> void:
	parry_streak += 1
	parry_streak_t = 0.0
	parry_t = 99.0
	parry_cd = 0.25
	energy = minf(3.0, energy + PARRY_ENERGY)
	sprite.parry_flash()
	shake = 0.45
	_begin("parry")
	act_len = 0.28
	_parry_fx(player.global_position + Vector3(facing * 0.9, 1.1, 0.7))
	_hitstop(0.12, 0.09)
	if boss != null:
		boss.parried(PARRY_POSTURE)


# bloqueo normal (no perfecto): sin dano pero sube tu postura; si se llena, se rompe la guardia
func _do_block(dir_x: float, push: float, post: float) -> void:
	root_posture += post
	sprite.flash = 0.35
	shake = 0.2
	slide = dir_x * push * 0.6
	_spark_burst(player.global_position + Vector3(facing * 0.7, 1.1, 0.7), Color(0.5, 0.85, 1.0))
	if root_posture >= ROOT_POSTURE_MAX:
		# guardia rota: aturdido, sin guardia un rato y recibes dano
		root_posture = 40.0
		guard_lock = 2.2
		parry_t = 99.0
		root_hp = maxi(0, root_hp - 1)
		_on_hurt()
		hurt_dir = dir_x
		hurt_push = push
		shake = 0.55
		if root_hp <= 0:
			_on_die()


func _hitstop(scale: float, secs: float) -> void:
	Engine.time_scale = scale
	get_tree().create_timer(secs, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)


func _guard_ring() -> void:
	_spawn_quad("ring", Vector2(2.2, 1.0), player.global_position + Vector3(facing * 0.8, 1.1, 0.75), Color(0.4, 0.9, 1.0, 0.9), 0.22, 1.5, facing < 0.0)


func _parry_fx(pos: Vector3) -> void:
	_spawn_quad("ring", Vector2(3.6, 3.6), pos, Color(1.0, 0.95, 0.7, 1.0), 0.3, 1.6, false)
	_spawn_quad("cres", Vector2(2.6, 3.0), pos, Color(1.0, 1.0, 1.0, 1.0), 0.25, 1.4, facing < 0.0)
	_spark_burst(pos, Color(1.0, 0.9, 0.5))
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.9, 0.6)
	l.light_energy = 9.0
	l.omni_range = 7.0
	add_child(l)
	l.global_position = pos
	get_tree().create_timer(0.12).timeout.connect(l.queue_free)


# ---- EFECTOS DEL CENTINELA (mismo lenguaje visual que los del Ninja, en cian) ----
func _boss_fx(kind: String, pos: Vector3, f: float) -> void:
	var cy := Color(0.35, 0.85, 1.0, 1.0)
	var wh := Color(0.85, 0.97, 1.0, 0.95)
	var energy_col := Color(0.2, 0.65, 1.0)
	match kind:
		"charge":
			_boss_charge(pos, f, 0.45, false)
		"charge_s":
			_boss_charge(pos, f, 0.3, false)
		"warn":
			_boss_charge(pos, f, 0.6, true)
			_warn_mark(pos)
		"slash_h":
			_spawn_quad("ring", Vector2(5.4, 2.1), pos + Vector3(f * 1.5, 1.2, 0.7), cy, 0.3, 1.25, f < 0.0)
			_ink_burst(pos + Vector3(f * 1.8, 0.15, 0.5), energy_col, 14, 3.0, f)
		"slash_down":
			_spawn_quad("cres", Vector2(4.4, 5.2), pos + Vector3(f * 1.5, 1.7, 0.7), cy, 0.42, 1.25, f < 0.0)
			_spawn_quad("ring", Vector2(3.4, 1.2), pos + Vector3(f * 2.4, 0.2, 0.6), wh, 0.3, 1.5, f < 0.0)
			_ink_burst(pos + Vector3(f * 2.2, 0.1, 0.5), energy_col, 20, 3.5, f)
			shake = maxf(shake, 0.2)
		"finisher":
			_spawn_quad("ring", Vector2(6.4, 2.4), pos + Vector3(f * 1.5, 0.9, 0.7), cy, 0.4, 1.4, f < 0.0)
			_spawn_quad("cres", Vector2(5.0, 6.0), pos + Vector3(f * 1.8, 1.5, 0.72), wh, 0.45, 1.3, f < 0.0)
			_ink_burst(pos + Vector3(f * 2.4, 0.1, 0.5), energy_col, 30, 4.0, f)
			shake = maxf(shake, 0.35)
		"thrust":
			_spawn_quad("thr", Vector2(7.0, 1.2), pos + Vector3(f * 3.0, 1.25, 0.7), wh, 0.3, 1.1, f < 0.0)
			_ink_burst(pos + Vector3(-f * 0.6, 0.2, 0.5), energy_col, 16, 2.5, -f)
			shake = maxf(shake, 0.2)
		"bash":
			_spawn_quad("ring", Vector2(3.4, 2.6), pos + Vector3(f * 1.3, 1.2, 0.75), cy, 0.28, 1.7, f < 0.0)
			_spark_burst(pos + Vector3(f * 1.4, 1.3, 0.7), cy)
			shake = maxf(shake, 0.35)
		"block":
			_spark_burst(pos + Vector3(-f * 0.9, 1.3, 0.8), cy)
		"parried":
			_parry_fx(pos + Vector3(f * 1.2, 1.4, 0.8))
		"break":
			_spawn_quad("ring", Vector2(6.0, 2.4), pos + Vector3(0.0, 1.3, 0.75), cy, 0.5, 1.8, false)
			_spark_burst(pos + Vector3(0.0, 1.6, 0.7), wh)
			_hitstop(0.3, 0.12)
			shake = maxf(shake, 0.5)
		"leak":
			_leak_burst(pos + Vector3(randf_range(-0.5, 0.5), randf_range(0.5, 1.7), 0.4))
		"slam":
			_spawn_quad("ring", Vector2(7.0, 2.2), pos + Vector3(f * 1.4, 0.15, 0.6), wh, 0.5, 1.8, false)
			_ink_burst(pos + Vector3(f * 1.6, 0.1, 0.5), Color(0.25, 0.3, 0.45), 26, 0.4, f)
			shake = 0.7
			_hitstop(0.25, 0.18)
		"final":
			shake = 0.6
			_hitstop(0.2, 0.5)
			_spawn_quad("ring", Vector2(8.0, 3.0), pos + Vector3(0.0, 1.3, 0.75), cy, 0.7, 2.0, false)
			_spark_burst(pos + Vector3(0.0, 1.5, 0.7), cy)


func _boss_charge(pos: Vector3, f: float, dur: float, red: bool) -> void:
	var col := Color(1.0, 0.2, 0.2) if red else Color(0.35, 0.85, 1.0)
	var p := CPUParticles3D.new()
	p.mesh = _flake_mesh(col, 4.0)
	p.amount = 30
	p.lifetime = 0.45
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.5
	p.gravity = Vector3.ZERO
	p.radial_accel_min = -9.0
	p.radial_accel_max = -6.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	add_child(p)
	p.global_position = pos + Vector3(f * 0.5, 1.3, 0.5)
	p.emitting = true
	get_tree().create_timer(dur).timeout.connect(func(): p.emitting = false)
	get_tree().create_timer(dur + 1.0).timeout.connect(p.queue_free)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 3.0
	l.omni_range = 5.0
	add_child(l)
	l.global_position = pos + Vector3(f * 0.5, 1.3, 0.8)
	get_tree().create_timer(dur).timeout.connect(l.queue_free)


# "!" rojo sobre su cabeza: ataque peligroso, no se puede bloquear ni parrar
func _warn_mark(pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = "!"
	l.font_size = 220
	l.pixel_size = 0.006
	l.modulate = Color(1.0, 0.15, 0.15)
	l.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	l.outline_size = 24
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	add_child(l)
	l.global_position = pos + Vector3(0.0, 3.2, 0.9)
	l.scale = Vector3.ONE * 0.4
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector3.ONE * 1.2, 0.15)
	tw.tween_interval(0.35)
	tw.tween_property(l, "modulate:a", 0.0, 0.2)
	tw.tween_callback(l.queue_free)


func _leak_burst(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _flake_mesh(Color(0.35, 0.85, 1.0), 4.0)
	p.amount = 6
	p.lifetime = 1.0
	p.one_shot = true
	p.explosiveness = 0.6
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.6
	p.gravity = Vector3(0, 0.6, 0)
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.8
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_J:
				_on_attack()
			KEY_K:
				_on_thrust()
			KEY_G:
				_on_sheathe()
			KEY_L:
				_on_move("heavy")
			KEY_U:
				_on_move("prep")
			KEY_I:
				_on_move("special")
			KEY_SPACE, KEY_W, KEY_UP:
				_on_jump()
			KEY_C, KEY_S, KEY_DOWN:
				_on_crouch()
			KEY_V:
				_on_roll()
			KEY_SHIFT:
				_on_dash()
			KEY_H:
				_on_hurt()
			KEY_X:
				_on_die()
			KEY_R:
				_on_revive()
			KEY_F:
				_on_guard_press()
			KEY_B:
				if boss != null:
					boss.revive()   # prueba: levanta al Centinela derrotado
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_attack()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		_on_guard_press()


# F / clic derecho: guardia. Al pulsar se abre una ventana corta de PARRY; despues sigue como bloqueo.
func _on_guard_press() -> void:
	if model == null or dead or act == "hit" or roll_time > 0.0:
		return
	if not armed:
		if act == "":
			_begin("draw")
		return
	if act != "" or guard_lock > 0.0:
		return
	if parry_cd <= 0.0:
		parry_t = 0.0
		parry_cd = PARRY_COOLDOWN
		_guard_ring()
	else:
		root_posture = minf(ROOT_POSTURE_MAX, root_posture + 6.0)   # machacar el boton se castiga


func _hit_time(a: String) -> float:
	var clip: String = String(CLIP_OF.get(a, a))
	var t := float(HIT_TIMES.get(clip, 0.5))
	if speed_ok:
		t /= float(ATTACK_SPEED.get(clip, 1.0))
	return t + float(WINDUP.get(a, 0.0))


func _jump_held() -> bool:
	return Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP)


func _begin(n: String) -> void:
	if n == "special":
		energy = maxf(0.0, energy - 1.0)
	act = n
	act_time = 0.0
	hit_done = false
	idle_timer = 0.0
	var clip: String = String(CLIP_OF.get(n, n))
	if n == "hit":
		clip = "hitguard" if armed else "hit"
	var wind := float(WINDUP.get(n, 0.0))
	act_len = wind + float(lengths.get(clip, 0.8))
	exec_started = wind <= 0.0
	if n in STRIKES:
		lunge_timer = 0.3 if exec_started else 0.0
		lunge_speed = float(LUNGE.get(n, 3.2))
		queued_attack = false
		queued_thrust = false
		queued_move = ""
		if n == "spin":
			sprite.spin_turn(act_len)
		if not exec_started:
			_charge_fx(n, wind)
			sprite.squash_jump()
	if n == "hit" and not armed:
		crouching = false


func _next_attack(cur: String) -> String:
	if cur == "attack1":
		return "attack2"
	if cur == "attack2":
		return "spin"
	return "attack1"


func _finish_act() -> void:
	var finished := act
	act = ""
	var qm := queued_move
	if finished == "draw":
		armed = true
		if qm != "":
			_begin(qm)
		elif queued_thrust:
			_begin("thrust")
		elif queued_attack:
			_begin("attack1")
	elif finished in STRIKES:
		if qm != "":
			_begin(qm)
		elif queued_thrust:
			_begin("thrust")
		elif queued_attack:
			_begin(_next_attack(finished))
		elif want_sheathe:
			want_sheathe = false
			_begin("sheathe")
	elif finished == "sheathe":
		armed = false
	queued_attack = false if act == "" else queued_attack
	queued_thrust = false if act == "" else queued_thrust
	queued_move = "" if act == "" else queued_move


func _on_attack() -> void:
	if model == null or dead or act == "hit" or roll_time > 0.0:
		return
	if not armed:
		if act == "":
			_begin("draw")
		elif act == "draw":
			queued_attack = true
	else:
		if act == "":
			_begin("attack1")
		elif act in STRIKES and act_time > 0.18:
			queued_attack = true


func _on_move(kind: String) -> void:
	if model == null or dead or act == "hit" or roll_time > 0.0:
		return
	if kind == "special" and energy < 1.0:
		return
	if not armed:
		if act == "":
			queued_move = kind
			_begin("draw")
		elif act == "draw":
			queued_move = kind
	else:
		if act == "":
			_begin(kind)
		elif act in STRIKES and act_time > 0.18:
			queued_move = kind


func _on_thrust() -> void:
	if model == null or dead or act == "hit" or roll_time > 0.0:
		return
	if not armed:
		if act == "":
			queued_thrust = true
			_begin("draw")
		elif act == "draw":
			queued_thrust = true
	else:
		if act == "":
			_begin("thrust")
		elif act in STRIKES and act_time > 0.18:
			queued_thrust = true


func _on_sheathe() -> void:
	if model == null or dead or not armed:
		return
	if act == "":
		_begin("sheathe")
	elif act in STRIKES:
		want_sheathe = true


func _on_jump() -> void:
	if model == null or dead or roll_time > 0.0 or act == "hit" or jump_pending:
		return
	if not player.is_on_floor():
		if air_jumps > 0 and not dead:
			air_jumps -= 1
			player.velocity.y = JUMP_VELOCITY * 0.95
			jump_time = 0.3
			sprite.spin_flip(0.55)
			sprite.stretch_jump()
		return
	crouching = false
	jump_pending = true
	jump_delay = JUMP_DELAY
	jump_time = 0.0
	sprite.squash_jump()


func _on_crouch() -> void:
	if model == null or dead or armed or act != "" or not player.is_on_floor():
		return
	crouching = not crouching


func _on_roll() -> void:
	if model == null or dead or act == "hit" or not player.is_on_floor() or roll_time > 0.0:
		return
	act = ""
	queued_attack = false
	queued_thrust = false
	want_sheathe = false
	crouching = false
	var d := _input_x()
	if d != 0.0:
		facing = signf(d)
	roll_time = float(lengths.get("roll", 0.9))


func _on_dash() -> void:
	if model == null or dead or dash_cd > 0.0 or roll_time > 0.0:
		return
	var d := _input_x()
	dash_dir = signf(d) if d != 0.0 else facing
	facing = dash_dir
	dash_time = DASH_TIME
	dash_cd = DASH_COOLDOWN
	crouching = false
	cur_loco = ""
	_set_loco("dash")


func _on_hurt() -> void:
	if model == null or dead or act == "hit" or roll_time > 0.0:
		return
	queued_attack = false
	queued_thrust = false
	hurt_dir = -facing
	hurt_push = 1.2
	_begin("hit")
	shake = 0.3
	sprite.flash_hit()


func _on_die() -> void:
	if model == null or dead:
		return
	dead = true
	crouching = false
	act = ""
	armed = false
	shake = 0.2
	get_tree().create_timer(2.5).timeout.connect(_on_revive)


func _on_revive() -> void:
	if not dead:
		return
	dead = false
	root_hp = root_max
	root_posture = 0.0
	cur_loco = ""
	_set_loco("idle")


func _input_x() -> float:
	if override_x != null:
		return float(override_x)
	var d := 0.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		d += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		d -= 1.0
	return d


func _nearest_front(max_d: float) -> Node3D:
	var best: Node3D = null
	var best_d := max_d
	for r in robots:
		if r.dead:
			continue
		var dx: float = r.global_position.x - player.global_position.x
		if signf(dx) != facing:
			continue
		if absf(dx) < best_d:
			best_d = absf(dx)
			best = r
	return best


func _apply_hit() -> void:
	var reach := ATTACK_RANGE
	match act:
		"thrust":
			reach += 0.8
		"prep":
			reach += 1.4
		"heavy":
			reach += 0.6
		"spin":
			reach += 0.4
		"special":
			reach = 6.5
	var around := act == "spin"
	var power: int = int(POWER.get(act, 1))
	var hit_any := false
	for r in robots:
		if r.dead:
			continue
		var dx: float = r.global_position.x - player.global_position.x
		if absf(dx) < reach and (signf(dx) == facing or absf(dx) < 0.4 or around):
			r.hit(facing, power)
			hit_any = true
			if r == boss:
				if boss.last_dmg > 0.0:
					energy = minf(3.0, energy + ENERGY_PER_POWER * float(power))   # el especial solo se carga golpeando
					_spawn_sparks(r.global_position + Vector3(0, 1.1, 0.3))
			else:
				_spawn_sparks(r.global_position + Vector3(0, 1.1, 0.3))
	if hit_any:
		shake = 0.25 if power < 3 else 0.55
	if act == "heavy" or act == "special":
		shake = maxf(shake, 0.5)
		Engine.time_scale = 0.2
		get_tree().create_timer(0.07, true, false, true).timeout.connect(func(): Engine.time_scale = 1.0)
	_slash_fx()


func _fx_tex(kind: String) -> ImageTexture:
	if fx_cache.has(kind):
		return fx_cache[kind]
	var tex: ImageTexture
	if kind == "ring":
		tex = _arc_tex(384, 144, 0.5, 0.5, 0.47, 0.2, -3.0, 2.7, 0.16)
	elif kind == "cres":
		tex = _arc_tex(256, 256, 0.02, 0.5, 0.9, 0.46, -1.2, 1.2, 0.1)
	else:
		tex = _thr_tex()
	fx_cache[kind] = tex
	return tex


func _arc_tex(w: int, h: int, cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, thick: float) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		for x in range(w):
			var u := (float(x) / float(w) - cx) / rx
			var v := (float(y) / float(h) - cy) / ry
			var q := sqrt(u * u + v * v)
			var a := atan2(v, u)
			var t := (a - a0) / (a1 - a0)
			if t < 0.0 or t > 1.0:
				continue
			var prof := pow(sin(t * PI), 0.7)
			var th := thick * prof
			var d := absf(q - 1.0)
			if d > th:
				continue
			var core := 1.0 - d / th
			var streak := 0.65 + 0.35 * sin(a * 40.0 + q * 60.0)
			var al := clampf(pow(core, 0.8) * streak * (0.5 + 0.5 * prof), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, al))
	return ImageTexture.create_from_image(img)


func _thr_tex() -> ImageTexture:
	var w := 256
	var h := 64
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var offs := [0.17, -0.2, 0.3, -0.33]
	for y in range(h):
		for x in range(w):
			var u := float(x) / float(w)
			var v := float(y) / float(h) - 0.5
			var al := 0.0
			var wid := 0.07 * pow(maxf(1.0 - u, 0.0), 0.8) + 0.004
			if absf(v) < wid:
				al = maxf(al, 1.0 - absf(v) / wid)
			for o in offs:
				if absf(v - o) < 0.012 and u < 0.7:
					al = maxf(al, 0.6 * (1.0 - u / 0.7))
			var fr := Vector2((u - 0.93) * 4.0, v * 2.0).length()
			al = maxf(al, clampf(1.0 - fr * 3.0, 0.0, 1.0))
			if al > 0.0:
				img.set_pixel(x, y, Color(1, 1, 1, clampf(al, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _spawn_quad(kind: String, size: Vector2, pos: Vector3, tint: Color, life: float, grow: float, flip_x: bool) -> void:
	var qm := QuadMesh.new()
	qm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _fx_tex(kind)
	m.albedo_color = tint
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = pos
	var sx := -1.0 if flip_x else 1.0
	mi.scale = Vector3(sx, 1.0, 1.0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(sx * grow, grow, 1.0), life)
	tw.tween_property(m, "albedo_color:a", 0.0, life)
	tw.chain().tween_callback(mi.queue_free)


func _flake_mesh(col: Color, glow: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col.lightened(0.3)
	mat.emission_energy_multiplier = glow
	mesh.material = mat
	return mesh


func _ink_burst(pos: Vector3, col: Color, amount: int, glow: float = 0.6, dir_x: float = 0.0) -> void:
	var p := CPUParticles3D.new()
	p.mesh = _flake_mesh(col, glow)
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3(dir_x if dir_x != 0.0 else facing, 0.6, 0.0)
	p.spread = 70.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 6.0
	p.gravity = Vector3(0, -9.0, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.8
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)


func _charge_fx(kind: String, dur: float) -> void:
	var col := Color(0.55, 0.55, 0.7)
	var glow := 1.0
	if kind == "special":
		col = Color(0.6, 0.2, 1.0)
		glow = 5.0
	var p := CPUParticles3D.new()
	p.mesh = _flake_mesh(col, glow)
	p.amount = 40
	p.lifetime = 0.55
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 1.4
	p.gravity = Vector3.ZERO
	p.radial_accel_min = -8.0
	p.radial_accel_max = -5.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 1.2
	player.add_child(p)
	p.position = Vector3(0.0, 1.0, 0.6)
	p.emitting = true
	get_tree().create_timer(dur + 0.2).timeout.connect(func(): p.emitting = false)
	get_tree().create_timer(dur + 1.0).timeout.connect(p.queue_free)
	if kind == "special":
		var aura := _flame_particles(player, Vector3(0.0, 0.9, 0.4), 50, 0.8, 2.5, 1.0, false)
		aura.emission_sphere_radius = 0.5
		get_tree().create_timer(dur + 0.7).timeout.connect(func(): aura.emitting = false)
		get_tree().create_timer(dur + 1.6).timeout.connect(aura.queue_free)
		var l := OmniLight3D.new()
		l.light_color = Color(0.65, 0.25, 1.0)
		l.light_energy = 4.0
		l.omni_range = 7.0
		player.add_child(l)
		l.position = Vector3(0.0, 1.2, 0.8)
		get_tree().create_timer(dur + 0.3).timeout.connect(l.queue_free)


func _exec_fx() -> void:
	var base := player.global_position
	if act == "special":
		_ink_burst(base + Vector3(facing * 0.8, 0.9, 0.6), Color(0.6, 0.2, 1.0), 40, 5.0)
	elif act == "prep":
		_ink_burst(base + Vector3(-facing * 0.5, 0.2, 0.5), Color(0.05, 0.06, 0.1), 20)


func _slash_fx() -> void:
	var f := facing
	var base := player.global_position
	var white := Color(1, 1, 1, 0.95)
	var ink := Color(0.04, 0.05, 0.1)
	match act:
		"attack1":
			_spawn_quad("ring", Vector2(4.8, 1.9), base + Vector3(f * 0.9, 1.1, 0.7), white, 0.3, 1.25, f < 0.0)
			_ink_burst(base + Vector3(f * 1.2, 0.15, 0.5), ink, 14)
		"attack2":
			_spawn_quad("cres", Vector2(3.0, 3.6), base + Vector3(f * 1.0, 1.35, 0.7), white, 0.32, 1.2, f < 0.0)
			_ink_burst(base + Vector3(f * 1.6, 0.1, 0.5), ink, 18)
		"spin":
			_spawn_quad("ring", Vector2(5.4, 2.0), base + Vector3(0.0, 1.1, 0.7), white, 0.4, 1.3, false)
			_spawn_quad("ring", Vector2(4.2, 1.5), base + Vector3(0.0, 1.0, 0.75), white, 0.4, 1.4, true)
			_ink_burst(base + Vector3(0.0, 0.2, 0.5), ink, 24)
		"thrust":
			_spawn_quad("thr", Vector2(5.2, 1.0), base + Vector3(f * 2.3, 1.15, 0.7), white, 0.28, 1.1, f < 0.0)
		"heavy":
			_spawn_quad("cres", Vector2(4.4, 5.2), base + Vector3(f * 1.4, 1.6, 0.7), white, 0.42, 1.25, f < 0.0)
			_ink_burst(base + Vector3(f * 1.8, 0.1, 0.5), ink, 34)
		"prep":
			_spawn_quad("ring", Vector2(5.6, 1.6), base + Vector3(f * 1.0, 1.1, 0.7), white, 0.3, 1.2, f < 0.0)
			_spawn_quad("thr", Vector2(5.0, 0.9), base + Vector3(f * 2.0, 1.15, 0.72), white, 0.26, 1.1, f < 0.0)
		"special":
			var purple := Color(0.8, 0.35, 1.0, 1.0)
			_spawn_quad("cres", Vector2(6.0, 7.0), base + Vector3(f * 2.0, 1.6, 0.7), purple, 0.55, 1.35, f < 0.0)
			_spawn_quad("ring", Vector2(6.5, 2.4), base + Vector3(f * 1.0, 1.1, 0.72), Color(0.65, 0.25, 1.0, 0.9), 0.5, 1.5, f < 0.0)
			_ink_burst(base + Vector3(f * 1.5, 0.2, 0.5), Color(0.5, 0.1, 0.9), 30, 4.0)
			_purple_wave()


func _flame_tex() -> GradientTexture2D:
	if fx_cache.has("flame"):
		return fx_cache["flame"]
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	fx_cache["flame"] = gt
	return gt


func _flame_particles(parent: Node, pos: Vector3, amount: int, life: float, rise: float, size: float, burst: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _flame_tex()
	qm.material = m
	p.mesh = qm
	p.amount = amount
	p.lifetime = life
	p.one_shot = burst
	p.explosiveness = 0.85 if burst else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.35
	p.direction = Vector3(0, 1, 0)
	p.spread = 35.0
	p.initial_velocity_min = rise * 0.5
	p.initial_velocity_max = rise
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 1.0, 0.9))
	ramp.set_color(1, Color(0.45, 0.05, 0.9, 0.0))
	p.color_ramp = ramp
	parent.add_child(p)
	p.position = pos
	p.emitting = true
	return p


func _ground_flame(x: float) -> void:
	var p := _flame_particles(self, Vector3(x, 0.15, 0.5), 22, 0.9, 3.2, 1.3, true)
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _purple_wave() -> void:
	var f := facing
	var start := player.global_position + Vector3(f * 1.2, 1.3, 0.75)
	var purple := Color(0.85, 0.4, 1.0, 1.0)
	var qm := QuadMesh.new()
	qm.size = Vector2(3.6, 5.2)
	var mi := MeshInstance3D.new()
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_texture = _fx_tex("cres")
	m.albedo_color = purple
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	mi.global_position = start
	mi.scale = Vector3(-1.0 if f < 0.0 else 1.0, 1.0, 1.0)
	var l := OmniLight3D.new()
	l.light_color = Color(0.65, 0.25, 1.0)
	l.light_energy = 7.0
	l.omni_range = 9.0
	mi.add_child(l)
	# llamas moradas que quedan detras de la onda
	var trail := _flame_particles(mi, Vector3.ZERO, 90, 0.8, 2.0, 1.5, false)
	trail.emission_sphere_radius = 1.2
	trail.local_coords = false
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position:x", start.x + f * 10.0, 0.6)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.3).set_delay(0.3)
	tw.chain().tween_callback(mi.queue_free)
	# incendio morado en el piso a lo largo del recorrido
	for i in range(1, 8):
		var gx := player.global_position.x + f * float(i) * 1.5
		get_tree().create_timer(float(i) * 0.06).timeout.connect(func(): _ground_flame(gx))


func _spark_burst(pos: Vector3, col: Color) -> void:
	_spawn_sparks(pos, col)


func _spawn_sparks(pos: Vector3, col: Color = Color(1.0, 0.6, 0.2)) -> void:
	var p := CPUParticles3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 6.0
	mesh.material = mat
	p.mesh = mesh
	p.amount = 28
	p.lifetime = 0.5
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 7.0
	p.gravity = Vector3(0, -9.8, 0)
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)
	var l := OmniLight3D.new()
	l.light_color = col
	l.light_energy = 6.0
	l.omni_range = 5.0
	add_child(l)
	l.global_position = pos
	get_tree().create_timer(0.12).timeout.connect(l.queue_free)


func _physics_process(delta: float) -> void:
	if model == null or tree == null:
		return
	var x := _input_x()
	var on_floor := player.is_on_floor()
	parry_t += delta
	parry_cd = maxf(0.0, parry_cd - delta)
	guard_lock = maxf(0.0, guard_lock - delta)
	parry_streak_t += delta
	if parry_streak_t > 6.0:
		parry_streak = 0
	slide = move_toward(slide, 0.0, 14.0 * delta)
	var want_guard := Input.is_key_pressed(KEY_F) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	guard_on = want_guard and armed and not dead and act == "" and roll_time <= 0.0 and dash_time <= 0.0 and guard_lock <= 0.0 and on_floor
	root_posture = maxf(0.0, root_posture - (ROOT_POSTURE_REGEN_GUARD if guard_on else ROOT_POSTURE_REGEN) * delta)

	dash_cd = maxf(0.0, dash_cd - delta)
	jump_time += delta
	if dash_time > 0.0:
		dash_time -= delta
	if roll_time > 0.0:
		roll_time -= delta
	if lunge_timer > 0.0:
		lunge_timer -= delta
	if act != "":
		act_time += delta
		if not exec_started and act_time >= float(WINDUP.get(act, 0.0)):
			exec_started = true
			lunge_timer = 0.3
			_exec_fx()
		if act in STRIKES and exec_started and not hit_done and act_time >= _hit_time(act):
			hit_done = true
			_apply_hit()
		if act_time >= act_len:
			_finish_act()
	elif armed and not dead:
		idle_timer += delta
		if x != 0.0:
			idle_timer = 0.0
		if idle_timer > AUTO_SHEATHE:
			_begin("sheathe")
	if jump_pending:
		jump_delay -= delta
		if jump_delay <= 0.0:
			jump_pending = false
			player.velocity.y = JUMP_VELOCITY
			sprite.stretch_jump()

	var locking := act in LOCKING
	var vx := 0.0
	if dead:
		vx = 0.0
	elif roll_time > 0.0:
		vx = facing * ROLL_SPEED
	elif dash_time > 0.0:
		vx = dash_dir * DASH_SPEED
	elif act == "hit":
		vx = hurt_dir * hurt_push
	else:
		if x != 0.0:
			if not locking:
				facing = signf(x)
			var base := RUN_SPEED
			if locking:
				base = ATTACK_MOVE_SPEED
			elif guard_on:
				base = GUARD_SPEED
			elif crouching:
				base = CROUCH_SPEED
			elif armed:
				base = ARMED_RUN_SPEED
			elif run_time > SPRINT_AFTER:
				base = SPRINT_SPEED
			vx = x * base
		if lunge_timer > 0.0:
			vx += facing * lunge_speed

	if not dead and roll_time <= 0.0 and dash_time <= 0.0 and act != "hit":
		vx += slide

	if x != 0.0 and on_floor and not armed and not crouching and act == "" and dash_time <= 0.0:
		run_time += delta
	else:
		run_time = 0.0

	var loco := "idle"
	if dead:
		loco = "death"
	elif act == "hit" and not armed:
		loco = "hit"
	elif roll_time > 0.0:
		loco = "roll"
	elif dash_time > 0.0:
		loco = "dash"
	elif jump_pending or not on_floor or jump_time < JUMP_ANIM_TIME:
		loco = "jump"
	elif crouching:
		loco = "crouchwalk" if x != 0.0 else "crouch"
	elif x != 0.0:
		loco = "sprint" if (run_time > SPRINT_AFTER and not armed) else "run"
	_set_loco(loco)

	var combat_on := (armed or act == "draw" or act == "sheathe") and not dead and roll_time <= 0.0
	if combat_on:
		var cname := "guard"
		if act == "draw" or act == "sheathe":
			cname = act
		elif act in STRIKES:
			cname = "guard" if not exec_started else String(CLIP_OF.get(act, act))
		elif act == "hit" or act == "parry":
			cname = "hitguard"
		_set_combat(cname)
	var still := x == 0.0 and on_floor and dash_time <= 0.0 and jump_time >= JUMP_ANIM_TIME and not crouching and not jump_pending
	upper_amt = move_toward(upper_amt, 1.0 if combat_on else 0.0, 14.0 * delta)
	full_amt = move_toward(full_amt, 1.0 if (combat_on and still) else 0.0, 10.0 * delta)
	tree.set("parameters/upper/blend_amount", upper_amt)
	tree.set("parameters/full/blend_amount", full_amt)

	model.rotation.y = 0.0

	if dash_time > 0.0 or roll_time > 0.0 or act == "hit" or dead:
		player.velocity.x = vx
	else:
		var acc := 60.0 if on_floor else 18.0
		player.velocity.x = move_toward(player.velocity.x, vx, acc * delta)
	if on_floor:
		air_jumps = 1
	player.velocity.z = 0.0
	if on_floor and player.velocity.y <= 0.0 and not jump_pending:
		player.velocity.y = 0.0
	elif dash_time > 0.0:
		player.velocity.y = maxf(player.velocity.y, 0.0)
	else:
		var g := GRAVITY
		if player.velocity.y < 0.0:
			g *= 1.15
		elif player.velocity.y < 1.4:
			g *= 0.6
		player.velocity.y -= g * delta
		if player.velocity.y > 2.0 and not _jump_held() and not jump_pending:
			player.velocity.y = 2.0
	player.move_and_slide()
	player.position.z = 0.0
	sprite.set_stance(armed and not dead and roll_time <= 0.0 and (act == "" or act == "hit" or (act in STRIKES and not exec_started)))
	sprite.set_guard(guard_on, guard_on and parry_t <= _parry_window())
	sprite.update_visual(delta, facing, player.is_on_floor(), player.velocity.y, dash_time > 0.0 or (act == "prep" and exec_started), player.velocity.x)

	var lim := maxf(0.0, ARENA_HALF * MAP_SCALE - 4.6)
	var target_x := clampf(player.global_position.x + facing * 0.9, -lim, lim)
	cam_x = lerpf(cam_x, target_x, clampf(5.0 * delta, 0.0, 1.0))
	var jitter := Vector3.ZERO
	if shake > 0.0:
		jitter = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), 0.0) * shake * 0.15
		shake = maxf(0.0, shake - delta * 2.0)
	var t := Time.get_ticks_msec() * 0.001
	var sway := Vector3(sin(t * 0.35) * 0.08, sin(t * 0.5) * 0.04, 0.0)
	cam.global_position = Vector3(cam_x, CAM_H, CAM_DIST) + jitter + sway
	var bi := 0
	for b in banners:
		(b as Node3D).rotation = Vector3(0.0, sin(t * 0.7 + float(bi)) * 0.07, sin(t * 0.9 + float(bi) * 1.7) * 0.04)
		bi += 1
	cam.look_at(Vector3(cam_x, CAM_LOOK_Y, 0.0) + jitter, Vector3.UP)
	if backdrop != null:
		backdrop.position = backdrop_base + Vector3(cam_x * BG_PARALLAX, 0.0, 0.0)
