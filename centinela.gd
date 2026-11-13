extends Node3D
## CENTINELA 2D - caballero tecnologico de MOLE.
## Sprite plano por poses (recortadas de la hoja de referencia, res://centinela/p1..p8.png).
## No usa huesos: cambia de pose y se mueve (embestidas, retroceso, inclinacion, aplastado).
##
## Poses (numeracion de la hoja):
##  p1 Reposo   p2 Preparacion   p3 Corte horizontal   p4 Corte fuerte
##  p5 Estocada p6 Golpe de escudo p7 Bloqueo           p8 Remate
##
## Ataques:  combo (p2>p3>p4>p8)   thrust (p2>p5)   bash (p1>p6)   guard (p7)

# ---- AJUSTES -------------------------------------------------------------
const HEIGHT_M := 2.4          # altura del Centinela de pie (metros)
const STAND_PX := 898.0        # alto en pixeles de la pose de reposo (pies a casco)
const SPRITE_Z := 0.2          # profundidad (delante de los enemigos, detras del ninja)
const WALK_SPEED := 1.7
const KEEP_DIST := 2.9         # distancia a la que le gusta pelear
const SEE_DIST := 11.0         # a que distancia empieza a perseguir
const MAX_HP := 60
# dano que recibe segun la fuerza del golpe del jugador (power 1..5)
const DMG := {1: 2.0, 2: 3.0, 3: 4.0, 4: 6.0, 5: 8.0}
# POSTURA (como Sekiro): se llena con parrys y golpes; al llegar a 100 queda aturdido
const POSTURE_MAX := 100.0
const POSTURE_DECAY := 7.0     # por segundo, si pasa un rato sin recibir golpes
const BROKEN_TIME := 2.8       # segundos aturdido
const BROKEN_MULT := 1.75      # dano extra mientras esta aturdido (NO es golpe mortal)
const POISE_IMMUNE := 7.0      # despues de aturdirse, no se le puede romper otra vez en este tiempo
const PARRY_REFLECT := 2.0     # dano que recibe al ser parrado

# pose -> [ancho, alto, pie_x, pie_y] en pixeles del PNG (los pies quedan en el origen)
const POSE_INFO := {
	"p1": [558, 923, 349, 910],
	"p2": [644, 752, 385, 739],
	"p3": [755, 729, 370, 716],
	"p4": [701, 866, 369, 853],
	"p5": [848, 582, 490, 569],
	"p6": [690, 638, 412, 625],
	"p7": [523, 648, 306, 635],
	"p8": [768, 689, 398, 630],
}

# Cada paso: pose, t (duracion), move (m/s hacia adelante), hit {at, reach, power, push, posture, fx}
# tele = telegrafo (brilla antes de pegar). perilous = ataque PELIGROSO (brilla en rojo y "!"):
# no se puede bloquear ni parrar, hay que esquivarlo (dash / voltereta).
const ATTACKS := {
	"combo": [
		{"pose": "p2", "t": 0.42, "move": 0.8, "tele": true, "fx": "charge"},
		{"pose": "p3", "t": 0.30, "move": 3.4, "hit": {"at": 0.08, "reach": 3.3, "power": 1, "push": 2.5, "posture": 12.0, "fx": "slash_h"}},
		{"pose": "p4", "t": 0.52, "move": 2.0, "hit": {"at": 0.22, "reach": 3.1, "power": 2, "push": 3.5, "posture": 20.0, "fx": "slash_down"}},
		{"pose": "p8", "t": 0.55, "move": 3.2, "hit": {"at": 0.12, "reach": 3.7, "power": 2, "push": 5.0, "posture": 24.0, "fx": "finisher"}},
		{"pose": "p1", "t": 0.30, "move": 0.0},
	],
	"thrust": [
		{"pose": "p2", "t": 0.60, "move": -0.5, "tele": true, "perilous": true, "fx": "warn"},
		{"pose": "p5", "t": 0.34, "move": 8.5, "hit": {"at": 0.06, "reach": 4.7, "power": 2, "push": 5.0, "posture": 20.0, "unblock": true, "fx": "thrust"}},
		{"pose": "p5", "t": 0.40, "move": 0.0},
	],
	"bash": [
		{"pose": "p1", "t": 0.30, "move": 0.0, "tele": true, "fx": "charge_s"},
		{"pose": "p6", "t": 0.42, "move": 4.2, "hit": {"at": 0.10, "reach": 2.6, "power": 1, "push": 7.0, "posture": 45.0, "fx": "bash"}},
	],
	"guard": [
		{"pose": "p7", "t": 1.3, "move": 0.0, "block": true},
	],
}

const ANIM_FPS := 15.0         # cuadros por segundo del "dibujo" (12 = mas dibujado, 24 = fluido)
const HIP_H := 1.15            # altura de la cadera: de ahi se inclina el cuerpo

const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform vec2 quad_size = vec2(1.0, 1.0);
uniform vec2 center_off = vec2(0.0, 0.0);
uniform float top_h = 2.4;
uniform bool flip = false;
// animacion del cuerpo (deforma la malla)
uniform float sway = 0.0;
uniform float breath = 0.0;
uniform float step_phase = 0.0;
uniform float step_amp = 0.0;
uniform float wave = 0.0;
uniform float wave_t = 0.0;
uniform float kneel = 0.0;
// efectos
uniform float flash = 0.0;
uniform float tele = 0.0;
uniform vec3 tele_col : source_color = vec3(1.0, 0.45, 0.15);
uniform float alpha = 1.0;
uniform float tint_amt = 0.0;
uniform vec3 tint : source_color = vec3(0.4, 0.8, 1.0);
// estilo dibujado a mano
uniform float anim_fps = 15.0;
uniform float boil = 0.0012;
uniform float grain = 0.07;
uniform float hatch = 0.26;
uniform float levels = 7.0;
uniform vec3 grade : source_color = vec3(0.86, 0.9, 1.0);
uniform vec4 outline_color : source_color = vec4(0.02, 0.025, 0.09, 1.0);
uniform float outline_px = 3.0;
uniform vec3 rim_a : source_color = vec3(0.25, 0.85, 1.0);
uniform vec3 rim_b : source_color = vec3(1.0, 0.35, 0.6);

void vertex() {
	vec2 p = VERTEX.xy * quad_size + center_off;
	float hn = clamp(p.y / top_h, 0.0, 1.0);
	// de rodillas: las piernas se encogen y el torso baja
	float kd = kneel * 0.62;
	if (p.y > 1.15) { p.y -= kd; } else { p.y *= (1.15 - kd) / 1.15; }
	// respiracion: el pecho sube y baja
	p.y += breath * smoothstep(0.25, 0.9, hn) * hn;
	// balanceo: la parte alta se mece mas que los pies
	p.x += sway * hn * hn;
	// pasos: cada pierna se levanta y avanza por turnos
	float legs = 1.0 - smoothstep(0.08, 0.40, hn);
	float side = smoothstep(-0.25, 0.25, p.x) * 3.14159;
	p.y += step_amp * max(0.0, sin(step_phase + side)) * legs;
	p.x += step_amp * 1.6 * cos(step_phase + side) * legs;
	// tela del faldon ondeando
	float cloth = smoothstep(0.10, 0.30, hn) * (1.0 - smoothstep(0.38, 0.55, hn));
	p.x += wave * sin(p.y * 6.0 + wave_t) * cloth;
	VERTEX = vec3(p, 0.0);
}

void fragment() {
	float f = floor(TIME * anim_fps);
	vec2 uv = UV;
	if (flip) { uv.x = 1.0 - uv.x; }
	// linea "hirviendo": el trazo tiembla un poco en cada cuadro, como dibujo a mano
	uv += vec2(sin(uv.y * 38.0 + f * 1.7), cos(uv.x * 34.0 + f * 2.3)) * boil;
	vec2 tsz = vec2(textureSize(tex, 0));
	vec2 px = outline_px / tsz;
	vec4 c = texture(tex, uv);
	float a = c.a;
	float nb = 0.0;
	nb = max(nb, step(0.5, texture(tex, uv + vec2(px.x, 0.0)).a));
	nb = max(nb, step(0.5, texture(tex, uv - vec2(px.x, 0.0)).a));
	nb = max(nb, step(0.5, texture(tex, uv + vec2(0.0, px.y)).a));
	nb = max(nb, step(0.5, texture(tex, uv - vec2(0.0, px.y)).a));
	nb = max(nb, step(0.5, texture(tex, uv + px).a));
	nb = max(nb, step(0.5, texture(tex, uv - px).a));
	nb = max(nb, step(0.5, texture(tex, uv + vec2(px.x, -px.y)).a));
	nb = max(nb, step(0.5, texture(tex, uv + vec2(-px.x, px.y)).a));
	if (a > 0.1) {
		vec3 col = c.rgb;
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		// sombreado por bandas (cel)
		if (l > 0.002) {
			float sq = sqrt(l);
			float q = floor(sq * levels + 0.5) / levels;
			float qq = mix(sq, q, 0.5);
			col *= (qq * qq) / l;
		}
		col *= grade;
		// rayado de tinta en las sombras
		float line = step(0.55, fract((UV.x + UV.y) * tsz.x / 3.0));
		col *= 1.0 - hatch * (1.0 - smoothstep(0.06, 0.26, l)) * line;
		// grano de pincel que cambia en cada cuadro
		float g = fract(sin(dot(floor(UV * tsz * 0.5) + f, vec2(12.9898, 78.233))) * 43758.5453);
		col *= 1.0 - grain * g;
		// luz de contorno: cian a la izquierda, magenta a la derecha (de pantalla)
		float dirx = flip ? -1.0 : 1.0;
		vec2 rr = 4.0 / tsz;
		float aL = texture(tex, uv - vec2(rr.x * dirx, 0.0)).a;
		float aR = texture(tex, uv + vec2(rr.x * dirx, 0.0)).a;
		col += rim_a * (1.0 - aL) * 0.5 + rim_b * (1.0 - aR) * 0.35;
		col = mix(col, vec3(1.0, 0.95, 0.85), clamp(flash, 0.0, 1.0));
		col += tele_col * tele * 0.45;
		col = mix(col, tint, tint_amt);
		ALBEDO = col;
		ALPHA = a * alpha;
	} else if (nb > 0.5) {
		ALBEDO = mix(outline_color.rgb, tint, tint_amt);
		ALPHA = alpha;
	} else {
		discard;
	}
}
"""

# ---- ESTADO (lo usa main.gd y el HUD) ------------------------------------
var hp := float(MAX_HP)
var max_hp := float(MAX_HP)
var dead := false                  # true en cuanto cae derrotado (ya no reaparece)
var defeated := false
var posture := 0.0
var broken := false
var broken_t := 0.0
var poise_t := 0.0
var posture_idle := 0.0
var last_dmg := 0.0                # dano de la ultima vez que lo golpearon (0 = bloqueado)
var target: Node3D
var home_x := 5.0
var arena_half := 14.0
var on_hit_player: Callable        # func(info: Dictionary)
var fx_cb: Callable                # func(kind: String, pos: Vector3, face: float)

var state := "idle"                # idle | walk | attack | stagger | broken
var cur_attack := ""
var steps: Array = []
var step_i := 0
var step_t := 0.0
var hit_done := false
var blocking := false
var blocked_hits := 0
var cooldown := 1.4
var face := -1.0                   # 1 = mira a la derecha, -1 = a la izquierda
var vel := 0.0
var flash := 0.0
var stagger_t := 0.0
var dying_t := 0.0
var slammed := false
var leak_t := 0.0
var t := 0.0
var cur_pose := ""
var moving_now := false
var walk_amt := 0.0
var kneel_amt := 0.0

# animacion suavizada
var rot := 0.0
var sx := 1.0
var sy := 1.0
var extra_sway := 0.0
var hop := 0.0
var fade := 1.0
var ghost_timer := 0.0
var ghosts: Array = []

var pivot: Node3D
var quad: MeshInstance3D           # pose actual
var quad_prev: MeshInstance3D      # pose anterior (se desvanece = "cuadro de estela")
var grid: ArrayMesh
var mat: ShaderMaterial
var mat_prev: ShaderMaterial
var shadow: MeshInstance3D
var tex_cache := {}
var px_m := HEIGHT_M / STAND_PX


func _ready() -> void:
	_build_visual()
	_set_pose("p1", false)


# malla de 11x23 puntos en coordenadas unitarias; el shader la escala y la deforma
func _grid_mesh(nx: int, ny: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for j in range(ny + 1):
		for i in range(nx + 1):
			var u := float(i) / float(nx)
			var v := float(j) / float(ny)
			verts.append(Vector3(u - 0.5, 0.5 - v, 0.0))
			uvs.append(Vector2(u, v))
	for j in range(ny):
		for i in range(nx):
			var p0 := j * (nx + 1) + i
			var p1 := p0 + 1
			var p2 := p0 + (nx + 1)
			var p3 := p2 + 1
			idx.append(p0)
			idx.append(p2)
			idx.append(p1)
			idx.append(p1)
			idx.append(p2)
			idx.append(p3)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _make_quad(m: ShaderMaterial, z: float) -> MeshInstance3D:
	var q := MeshInstance3D.new()
	q.mesh = grid
	q.material_override = m
	q.position = Vector3(0.0, -HIP_H, z)
	q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# la malla real la agranda el shader, asi que se le da una caja de visibilidad grande
	q.custom_aabb = AABB(Vector3(-6.0, -2.0, -1.0), Vector3(12.0, 8.0, 2.0))
	return q


func _build_visual() -> void:
	grid = _grid_mesh(10, 22)
	pivot = Node3D.new()
	add_child(pivot)
	var sh := Shader.new()
	sh.code = SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("anim_fps", ANIM_FPS)
	mat_prev = ShaderMaterial.new()
	mat_prev.shader = sh
	mat_prev.set_shader_parameter("anim_fps", ANIM_FPS)
	mat_prev.set_shader_parameter("alpha", 0.0)
	quad_prev = _make_quad(mat_prev, SPRITE_Z - 0.01)
	quad = _make_quad(mat, SPRITE_Z)
	pivot.add_child(quad_prev)
	pivot.add_child(quad)
	# sombra suave en el piso
	var grad := Gradient.new()
	grad.set_color(0, Color(0.0, 0.0, 0.05, 0.6))
	grad.set_color(1, Color(0.0, 0.0, 0.05, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 128
	gt.height = 128
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = gt
	var qm := QuadMesh.new()
	qm.size = Vector2(2.6, 0.7)
	shadow = MeshInstance3D.new()
	shadow.mesh = qm
	shadow.material_override = sm
	shadow.rotation.x = -PI * 0.5
	shadow.position = Vector3(0.0, 0.03, 0.15)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shadow)


func _get_tex(key: String) -> Texture2D:
	if not tex_cache.has(key):
		tex_cache[key] = load("res://centinela/%s.png" % key)
	return tex_cache[key]


# pone textura, tamano y punto de apoyo de una pose en un material
func _apply_pose(m: ShaderMaterial, key: String, facing: float) -> void:
	var info: Array = POSE_INFO[key]
	var w: float = float(info[0])
	var h: float = float(info[1])
	var fx: float = float(info[2])
	var fy: float = float(info[3])
	# el origen = los pies; el arte mira a la derecha, asi que se espeja con 'face'
	var ox := (w * 0.5 - fx) * px_m * facing
	var oy := (fy - h * 0.5) * px_m
	m.set_shader_parameter("tex", _get_tex(key))
	m.set_shader_parameter("quad_size", Vector2(w * px_m, h * px_m))
	m.set_shader_parameter("center_off", Vector2(ox, oy))
	m.set_shader_parameter("top_h", fy * px_m)
	m.set_shader_parameter("flip", facing < 0.0)


func _set_pose(key: String, crossfade: bool = true) -> void:
	if key == cur_pose:
		return
	if crossfade and cur_pose != "":
		# la pose anterior queda un instante detras, desvaneciendose (cuadro de estela)
		_apply_pose(mat_prev, cur_pose, face)
		fade = 0.0
	cur_pose = key
	_apply_pose(mat, key, face)


func _refresh_flip() -> void:
	# al cambiar de lado se redibuja la pose sin cruce
	var k := cur_pose
	cur_pose = ""
	fade = 1.0
	_set_pose(k, false)


# ---- EFECTOS / AVISOS A main.gd -------------------------------------------
func _fx(kind: String) -> void:
	if fx_cb.is_valid():
		fx_cb.call(kind, global_position, face)


# ---- DANO RECIBIDO -------------------------------------------------------
# Lo llama el jugador. Deja en last_dmg cuanto dano entro (0 = bloqueado).
func hit(dir_x: float, power: int) -> void:
	last_dmg = 0.0
	if dead:
		return
	var from_front := signf(dir_x) == -face
	if blocking and from_front and power < 5:
		# bloqueado: sin dano, chispa y empujon corto
		flash = 0.45
		vel = dir_x * 1.2
		blocked_hits += 1
		_fx("block")
		if blocked_hits >= 2:
			blocked_hits = 0
			_start_attack("bash")   # contraataque con el escudo
		return
	var dmg: float = float(DMG.get(clampi(power, 1, 5), 2.0))
	if broken:
		dmg *= BROKEN_MULT
	last_dmg = dmg
	flash = 1.0
	vel = dir_x * (1.5 + power * 0.5)
	_fx("hit")
	if not broken:
		_add_posture(3.0 + 2.0 * float(power))
	if _take_damage(dmg):
		return
	# solo los golpes fuertes interrumpen un ataque; el resto lo deja en su sitio
	if not broken and (state != "attack" or power >= 4):
		state = "stagger"
		stagger_t = 0.25 + 0.05 * float(power)
		blocking = false
		_set_pose("p1")


# el jugador le hizo parry a un ataque: se tambalea, pierde postura y un poco de vida
func parried(posture_dmg: float) -> void:
	if dead:
		return
	flash = 0.9
	vel = -face * 2.5
	blocking = false
	if not broken:
		state = "stagger"
		stagger_t = 0.55
		_set_pose("p1")
	_fx("parried")
	if _take_damage(PARRY_REFLECT):
		return
	_add_posture(posture_dmg)


func _take_damage(dmg: float) -> bool:
	hp = maxf(0.0, hp - dmg)
	if hp <= 0.0:
		_die()
		return true
	return false


func _add_posture(v: float) -> void:
	if dead or broken or poise_t > 0.0:
		return
	posture = minf(POSTURE_MAX, posture + v)
	posture_idle = 0.0
	if posture >= POSTURE_MAX:
		_break()


# postura rota: queda aturdido y recibe mas dano, pero NO muere de un golpe
func _break() -> void:
	broken = true
	broken_t = BROKEN_TIME
	state = "broken"
	blocking = false
	steps = []
	_set_pose("p1")
	_fx("break")


func _die() -> void:
	dead = true
	defeated = true
	blocking = false
	broken = false
	state = "dying"
	dying_t = 0.0
	slammed = false
	leak_t = 0.0
	vel = 0.0
	_set_pose("p1")
	_fx("final")


# solo para pruebas (tecla B en main.gd): lo vuelve a levantar
func revive() -> void:
	hp = max_hp
	dead = false
	defeated = false
	broken = false
	posture = 0.0
	poise_t = 0.0
	dying_t = 0.0
	visible = true
	position.x = home_x
	vel = 0.0
	state = "idle"
	blocking = false
	cooldown = 1.4
	rot = 0.0
	sx = 1.0
	sy = 1.0
	kneel_amt = 0.0
	mat.set_shader_parameter("alpha", 1.0)
	_set_pose("p1", false)


# ---- IA + ANIMACION ------------------------------------------------------
func _process(delta: float) -> void:
	t += delta
	var at := floorf(t * ANIM_FPS) / ANIM_FPS     # tiempo "a cuadros" para la animacion
	var target_rot := 0.0
	var target_sx := 1.0
	var target_sy := 1.0
	var target_kneel := 0.0
	var tele := 0.0
	var tele_red := false
	extra_sway = 0.0
	hop = 0.0
	var alpha := 1.0

	if dead:
		# DERROTADO: tambalea, cae de rodillas, queda jadeando y por fin se desploma. No reaparece.
		dying_t += delta
		flash = maxf(0.0, flash - delta * 2.0)
		position.x += vel * delta
		vel = move_toward(vel, 0.0, 8.0 * delta)
		if dying_t < 0.7:
			var k := smoothstep(0.0, 0.7, dying_t)
			target_kneel = 0.8 * k
			target_rot = face * 0.12 * (1.0 - k)
			extra_sway = sin(at * 45.0) * 0.035 * (1.0 - k)
		elif dying_t < 3.2:
			target_kneel = 0.8 + sin(at * 1.7) * 0.012
			target_rot = -face * (0.24 + sin(at * 1.7) * 0.012)     # cabeza gacha
			flash = 0.12 + 0.1 * sin(at * 9.0)
			leak_t -= delta
			if leak_t <= 0.0:
				leak_t = 0.28
				_fx("leak")
		else:
			var c := clampf((dying_t - 3.2) / 0.5, 0.0, 1.0)
			target_kneel = 0.8
			target_rot = -face * lerpf(0.24, 1.5, c * c)
			if c >= 1.0:
				var bt := dying_t - 3.7
				target_rot = -face * (1.5 - 0.1 * exp(-9.0 * bt) * cos(20.0 * bt))
				if not slammed:
					slammed = true
					_fx("slam")
			target_sy = 1.0 - 0.06 * c
		alpha = 1.0 - smoothstep(9.0, 12.0, dying_t)
		if dying_t > 12.0:
			visible = false
	else:
		position.x += vel * delta
		vel = move_toward(vel, 0.0, 8.0 * delta)
		position.z = 0.0
		flash = maxf(0.0, flash - delta * 4.0)
		# la postura baja sola si pasa un rato sin presion
		posture_idle += delta
		poise_t = maxf(0.0, poise_t - delta)
		if not broken and posture_idle > 1.6:
			posture = maxf(0.0, posture - POSTURE_DECAY * delta)

		var dx := 0.0
		var dist := 99.0
		if target != null:
			dx = target.global_position.x - global_position.x
			dist = absf(dx)

		moving_now = false
		match state:
			"idle", "walk":
				_face_to(dx)
				cooldown -= delta
				if dist < SEE_DIST:
					if dist > KEEP_DIST + 0.5:
						position.x += face * WALK_SPEED * delta
						moving_now = true
					elif dist < 1.7:
						position.x -= face * 0.9 * delta
						moving_now = true
				state = "walk" if moving_now else "idle"
				_set_pose("p1")
				if moving_now:
					hop = absf(sin(at * 7.0)) * 0.04
					target_rot = -face * 0.035
				if cooldown <= 0.0 and dist < SEE_DIST:
					_choose_attack(dist)
			"attack":
				var st: Dictionary = steps[step_i]
				_set_pose(String(st["pose"]))
				step_t += delta
				var dur := maxf(0.01, float(st["t"]))
				var u := clampf(step_t / dur, 0.0, 1.0)
				var mv := float(st.get("move", 0.0))
				position.x += face * mv * delta
				if bool(st.get("tele", false)):
					# anticipacion: se echa hacia atras, se encoge y tiembla cargando
					target_rot = face * 0.13 * u
					target_sy = 1.0 - 0.05 * u
					target_sx = 1.0 + 0.03 * u
					extra_sway = sin(at * 40.0) * 0.012
					tele = 0.5 + 0.5 * sin(t * 30.0)
					tele_red = bool(st.get("perilous", false))
					hop = -0.02 * u
				elif st.has("hit"):
					# golpe: pasa de atras a adelante con estiramiento (smear) y se asienta
					var k2 := smoothstep(0.0, 0.3, u)
					var settle := 1.0 - 0.6 * smoothstep(0.5, 1.0, u)
					target_rot = -face * lerpf(-0.13, 0.14, k2) * settle
					target_sx = 1.0 + 0.14 * sin(k2 * PI)
					target_sy = 1.0 - 0.04 * k2
				elif bool(st.get("block", false)):
					target_rot = -face * 0.05
					target_sy = 0.97
					extra_sway = sin(at * 3.0) * 0.01
				if mv > 2.0:
					ghost_timer -= delta
					if ghost_timer <= 0.0:
						ghost_timer = 0.05
						_spawn_ghost()
				if st.has("hit") and not hit_done:
					var hd: Dictionary = st["hit"]
					if step_t >= float(hd["at"]):
						hit_done = true
						if hd.has("fx"):
							_fx(String(hd["fx"]))
						_strike(hd)
				if step_t >= float(st["t"]):
					_next_step()
			"stagger":
				stagger_t -= delta
				_set_pose("p1")
				target_rot = face * 0.15
				target_sy = 0.96
				extra_sway = sin(at * 50.0) * 0.03
				if stagger_t <= 0.0:
					state = "idle"
					cooldown = randf_range(0.3, 0.8)
			"broken":
				# aturdido: una rodilla en el suelo, mareado, vulnerable
				broken_t -= delta
				_set_pose("p1")
				target_kneel = 0.42
				target_rot = face * 0.1
				extra_sway = sin(at * 5.0) * 0.05
				tele = 0.25 + 0.2 * sin(at * 10.0)
				if broken_t <= 0.0:
					broken = false
					posture = 0.0
					poise_t = POISE_IMMUNE
					state = "idle"
					cooldown = 0.7
		position.x = clampf(position.x, -arena_half, arena_half)

	# suavizado de la pose del cuerpo (se inclina desde la cadera, con los pies fijos)
	var sm := 1.0 - exp(-26.0 * delta)
	rot = lerpf(rot, target_rot, sm)
	sx = lerpf(sx, target_sx, sm)
	sy = lerpf(sy, target_sy, sm)
	kneel_amt = lerpf(kneel_amt, target_kneel, 1.0 - exp(-9.0 * delta))
	walk_amt = move_toward(walk_amt, 1.0 if moving_now else 0.0, 6.0 * delta)
	pivot.rotation.z = rot
	pivot.scale = Vector3(sx, sy, 1.0)
	pivot.position = Vector3(-HIP_H * sy * sin(rot), HIP_H * sy * cos(rot) + hop, 0.0)

	# deformacion del cuerpo (a cuadros, para que se vea dibujado)
	var sway := sin(at * 1.4) * 0.03 + extra_sway
	var breath := sin(at * 2.4) * 0.025
	var amp := 0.06 * walk_amt
	var ph := at * 9.0
	var wv := 0.015 + 0.02 * walk_amt
	for m in [mat, mat_prev]:
		var mm: ShaderMaterial = m
		mm.set_shader_parameter("sway", sway)
		mm.set_shader_parameter("breath", breath)
		mm.set_shader_parameter("step_amp", amp)
		mm.set_shader_parameter("step_phase", ph)
		mm.set_shader_parameter("wave", wv)
		mm.set_shader_parameter("wave_t", at * 4.0)
		mm.set_shader_parameter("kneel", kneel_amt)
	mat.set_shader_parameter("flash", flash)
	mat.set_shader_parameter("tele", tele)
	mat.set_shader_parameter("tele_col", Color(1.0, 0.1, 0.1) if tele_red else (Color(0.3, 0.7, 1.0) if broken else Color(1.0, 0.45, 0.15)))
	mat.set_shader_parameter("alpha", alpha)

	# cruce de la pose anterior (estela de 1-2 cuadros)
	if fade < 1.0:
		fade = minf(1.0, fade + delta / 0.09)
	mat_prev.set_shader_parameter("alpha", 0.65 * (1.0 - fade) * alpha)
	quad_prev.visible = fade < 1.0
	shadow.scale = Vector3(sx, 1.0, 1.0)
	_update_ghosts(delta)


func _spawn_ghost() -> void:
	var g := MeshInstance3D.new()
	g.mesh = grid
	g.top_level = true
	g.custom_aabb = AABB(Vector3(-6.0, -2.0, -1.0), Vector3(12.0, 8.0, 2.0))
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := mat.duplicate() as ShaderMaterial
	gm.set_shader_parameter("tint_amt", 0.8)
	gm.set_shader_parameter("alpha", 0.45)
	gm.set_shader_parameter("flash", 0.0)
	gm.set_shader_parameter("tele", 0.0)
	g.material_override = gm
	add_child(g)
	g.global_transform = quad.global_transform
	g.global_position.z -= 0.05
	ghosts.append({"node": g, "mat": gm, "age": 0.0})


func _update_ghosts(delta: float) -> void:
	var i := ghosts.size() - 1
	while i >= 0:
		var gd: Dictionary = ghosts[i]
		gd["age"] = float(gd["age"]) + delta
		var k: float = float(gd["age"]) / 0.28
		if k >= 1.0:
			(gd["node"] as Node3D).queue_free()
			ghosts.remove_at(i)
		else:
			(gd["mat"] as ShaderMaterial).set_shader_parameter("alpha", 0.45 * (1.0 - k))
		i -= 1


func _face_to(dx: float) -> void:
	if absf(dx) < 0.05:
		return
	var f := 1.0 if dx > 0.0 else -1.0
	if f != face:
		face = f
		_refresh_flip()


func _choose_attack(dist: float) -> void:
	var r := randf()
	var pick := ""
	if dist > 7.5:
		cooldown = 0.3
		return
	elif dist > 4.2:
		pick = "thrust" if r < 0.6 else ""
	elif dist > 2.4:
		if r < 0.5:
			pick = "combo"
		elif r < 0.75:
			pick = "thrust"
		else:
			pick = "guard"
	else:
		if r < 0.4:
			pick = "bash"
		elif r < 0.8:
			pick = "combo"
		else:
			pick = "guard"
	if pick == "":
		cooldown = 0.4
		return
	_start_attack(pick)


func _start_attack(atk: String) -> void:
	cur_attack = atk
	steps = ATTACKS[atk]
	step_i = 0
	_enter_step()
	state = "attack"


func _enter_step() -> void:
	step_t = 0.0
	hit_done = false
	var st: Dictionary = steps[step_i]
	blocking = bool(st.get("block", false))
	_set_pose(String(st["pose"]))
	if st.has("fx"):
		_fx(String(st["fx"]))


func _next_step() -> void:
	step_i += 1
	if step_i >= steps.size():
		state = "idle"
		blocking = false
		cur_attack = ""
		var base := randf_range(0.8, 1.6)
		cooldown = base * (0.6 if hp <= max_hp * 0.4 else 1.0)   # enfurecido con poca vida
		_set_pose("p1")
	else:
		_enter_step()


func _strike(hd: Dictionary) -> void:
	if target == null:
		return
	var dx: float = target.global_position.x - global_position.x
	var dy: float = target.global_position.y - global_position.y
	if signf(dx) != face and absf(dx) > 0.5:
		return
	if absf(dx) > float(hd.get("reach", 3.0)) or dy > 1.7:
		return
	if on_hit_player.is_valid():
		on_hit_player.call({
			"power": int(hd.get("power", 1)),
			"dir": face,
			"push": float(hd.get("push", 3.0)),
			"posture": float(hd.get("posture", 15.0)),
			"unblock": bool(hd.get("unblock", false)),
			"pos": global_position,
		})
