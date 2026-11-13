extends Node3D
## Ninja en 2D: el modelo 3D (con todas sus animaciones) se renderiza en un
## SubViewport con camara ortografica y se muestra como UN SOLO SPRITE plano
## dentro del mundo 3D. El mapa, los robots y el guardian siguen siendo 3D.
##
## Extras 2D: contorno de tinta, colores por bandas (cel-shading), pixeles
## definidos, giro tipo sprite (flip), sombra en el suelo, estela al hacer dash,
## aplastamiento al caer / estirado al saltar y destello blanco al recibir golpe.

# ---- AJUSTES (puedes tocarlos) -------------------------------------------
const SPRITE_RES := 640        # resolucion del sprite (640 = nitido; 264 = el pixelado de antes). Si cambias esto, ajusta tambien OUTLINE_PX, RIM_PX, HATCH_PX y GRAIN_PX (todo en pixeles del sprite)
const VIEW_SIZE := 4.0         # metros que abarca el cuadro del sprite
const VIEW_CENTER_Y := 1.3     # altura (m) del centro del cuadro respecto a los pies
const SPRITE_Z := 0.35         # el sprite se dibuja un poco al frente de los enemigos
const LEVELS := 6.0            # bandas de sombreado (menos = mas "dibujo")
const OUTLINE_PX := 3.0        # grosor de la linea de tinta en pixeles del sprite (numero entero)
const RIM_PX := 5.0            # ancho de la luz de contorno
const HATCH_PX := 7.0          # separacion del rayado de tinta
const GRAIN_PX := 5.0          # tamano del grano de pincel
const ANIM_FPS := 15.0         # cuadros por segundo del dibujo (12 = mas dibujado a mano, 24 = fluido)
const BOIL := 0.0012           # temblor de la linea en cada cuadro (0 = linea firme)
const GRAIN := 0.04            # grano de pincel
const HATCH := 0.22            # rayado de tinta en las sombras
const GHOST_LIFE := 0.3
const GHOST_EVERY := 0.04

# ---- BRAZOS 2D (recortados de tu arte, siguen los huesos del modelo) -------
const ARM_PX := 0.00138        # metros por pixel del arte original
const ARM_NEAR_Z := 0.36       # brazo cercano a la camara
const ARM_FAR_Z := -0.36       # brazo lejano (queda detras del cuerpo)
const ARM_BRIGHT_NEAR := 0.85
const ARM_BRIGHT_FAR := 0.5
const HAND_LEN := 0.207        # largo del guante en metros
# top/bot = filas del PNG donde empieza/termina el hueso. dz = orden de dibujo.
const ARM_SEGS := [
	{"key": "fore", "path": "res://arms/arm_fore.png", "top": 3.0, "bot": 160.0, "dz": 0.0},
	{"key": "hand", "path": "res://arms/arm_hand.png", "top": 8.0, "bot": 154.0, "dz": 0.01},
	{"key": "upper", "path": "res://arms/arm_upper.png", "top": 4.0, "bot": 91.0, "dz": 0.02},
]

# ---- ESPADA 2D (siempre visible, nunca de canto) ----
const SWORD_PNG := "res://sword2d/sword.png"
const SCAB_PNG := "res://sword2d/scabbard.png"
const STANCE_DIR := Vector2(0.9, -0.43)   # espada hacia adelante y abajo en pose de batalla
const SWORD_Z_DRAWN := 0.005
const SWORD_Z_BACK := -0.47
const SCAB_Z := -0.45

const SHADER_SPRITE := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform sampler2D tex : source_color, filter_nearest, repeat_disable;
uniform bool flip = false;
uniform float levels = 6.0;
uniform vec4 outline_color : source_color = vec4(0.02, 0.025, 0.09, 1.0);
uniform float outline_px = 1.0;
uniform vec3 grade : source_color = vec3(0.95, 0.97, 1.05);
uniform vec3 rim_a : source_color = vec3(0.25, 0.85, 1.0);
uniform vec3 rim_b : source_color = vec3(1.0, 0.35, 0.6);
uniform float rim_px = 2.0;
uniform vec3 tint : source_color = vec3(0.4, 0.7, 1.0);
uniform float tint_amt = 0.0;
uniform float flash = 0.0;
uniform float alpha = 1.0;
uniform bool is_reflection = false;
uniform float refl_alpha = 0.42;
uniform float feet_v = 0.825;
uniform float view_size = 4.0;
uniform float anim_fps = 15.0;
uniform float boil = 0.005;
uniform float grain = 0.06;
uniform float hatch = 0.22;
uniform float hatch_px = 7.0;
uniform float grain_px = 5.0;

void fragment() {
	vec2 uv = UV;
	if (flip) {
		uv.x = 1.0 - uv.x;
	}
	float f = floor(TIME * anim_fps);
	uv += vec2(sin(uv.y * 38.0 + f * 1.7), cos(uv.x * 34.0 + f * 2.3)) * boil;
	vec2 px = 1.0 / vec2(textureSize(tex, 0));
	float h_m = (feet_v - UV.y) * view_size;
	if (is_reflection) {
		uv.x += sin(h_m * 22.0 + TIME * 2.2) * 0.004;
	}
	vec2 o = px * outline_px;
	vec4 c = texture(tex, uv);
	float n = 0.0;
	n = max(n, step(0.9, texture(tex, uv + vec2(o.x, 0.0)).a));
	n = max(n, step(0.9, texture(tex, uv - vec2(o.x, 0.0)).a));
	n = max(n, step(0.9, texture(tex, uv + vec2(0.0, o.y)).a));
	n = max(n, step(0.9, texture(tex, uv - vec2(0.0, o.y)).a));
	n = max(n, step(0.9, texture(tex, uv + vec2(o.x, o.y)).a));
	n = max(n, step(0.9, texture(tex, uv + vec2(o.x, -o.y)).a));
	n = max(n, step(0.9, texture(tex, uv + vec2(-o.x, o.y)).a));
	n = max(n, step(0.9, texture(tex, uv + vec2(-o.x, -o.y)).a));
	if (c.a > 0.1) {
		// paleta anime: sombras indigo, medios grisaceos, acentos naranja-rojizo
		vec3 col = pow(c.rgb, vec3(0.82)) * 1.12;
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		if (l > 0.002) {
			float sq = sqrt(l);
			float q = floor(sq * levels + 0.5) / levels;
			float qq = mix(sq, q, 0.5);
			col *= (qq * qq) / l;
		}
		float sh = 1.0 - smoothstep(0.0, 0.38, l);
		col += vec3(0.07, 0.08, 0.20) * sh;
		// rayado de tinta en las sombras + grano de pincel (cambia en cada cuadro)
		vec2 tsz = vec2(textureSize(tex, 0));
		float hl = step(0.55, fract((UV.x + UV.y) * tsz.x / hatch_px));
		col *= 1.0 - hatch * (1.0 - smoothstep(0.05, 0.24, l)) * hl;
		col *= 1.0 - grain * fract(sin(dot(floor(UV * tsz / grain_px) + f, vec2(12.9898, 78.233))) * 43758.5453);
		col *= grade;
		// luz de contorno: cian por la izquierda, magenta por la derecha
		float aL = texture(tex, uv - vec2(px.x * rim_px, 0.0)).a;
		float aR = texture(tex, uv + vec2(px.x * rim_px, 0.0)).a;
		float aU = texture(tex, uv - vec2(0.0, px.y * rim_px)).a;
		col += rim_a * (1.0 - aL) * 0.8 + rim_b * (1.0 - aR) * 0.8 + vec3(0.7, 0.8, 1.0) * (1.0 - aU) * 0.3;
		col = mix(col, tint, tint_amt);
		col = mix(col, vec3(1.0), flash);
		ALBEDO = col;
		ALPHA = c.a * alpha;
		if (is_reflection) {
			ALBEDO = mix(col, rim_a * 0.6 + vec3(0.1, 0.2, 0.4), 0.45);
			ALPHA = c.a * refl_alpha * exp(-h_m * 0.9) * alpha;
		}
	} else if (n > 0.5 && !is_reflection) {
		ALBEDO = mix(outline_color.rgb, tint, tint_amt);
		ALPHA = alpha;
	} else {
		discard;
	}
}
"""

const SHADER_SHADOW := """
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix;

uniform float strength = 0.55;

void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0);
	ALBEDO = vec3(0.0);
	ALPHA = (1.0 - smoothstep(0.25, 1.0, d)) * strength;
}
"""

var viewport: SubViewport
var model_root: Node3D
var pivot: Node3D
var quad: MeshInstance3D
var mat: ShaderMaterial
var shadow: MeshInstance3D
var refl: MeshInstance3D
var refl_mat: ShaderMaterial
var shadow_mat: ShaderMaterial
var floor_fn: Callable

var flash := 0.0
var frame_acc := 0.0
var guard_amt := 0.0       # 0..1 brillo de guardia (parry)
var guard_target := 0.0
var parry_pulse := 0.0
var squash := Vector2.ONE
var last_facing := 0.0
var was_on_floor := true
var air_vy := 0.0
var ghost_timer := 0.0
var ghosts: Array = []
var spin_kind := 0        # 0 nada, 1 voltereta, 2 giro
var spin_t := 0.0
var spin_dur := 0.5
var spin_dir := 1.0
var sword_ok := false
var sword_holder: Node3D
var scab_holder: Node3D
var b_sw := -1
var b_gl := -1
var b_sc := -1
var b_hd := -1
var scab_local := Vector3.DOWN
var stance := false
var stance_amt := 0.0
var last_sword_dir := Vector2(0.0, 1.0)
var skel: Skeleton3D
var arms: Array = []
var arm_tex := {}


func setup(floor_callable: Callable) -> void:
	floor_fn = floor_callable
	_build_viewport()
	_build_quad()
	_build_shadow()


func attach_model(m: Node3D) -> void:
	model_root.add_child(m)
	_restyle_body(m)
	_setup_arms(m)


func flash_hit() -> void:
	flash = 1.0


# guardia: la silueta se tine de cian; open = ventana de parry abierta (brilla mas)
func set_guard(on: bool, open: bool) -> void:
	guard_target = (1.0 if open else 0.55) if on else 0.0


func parry_flash() -> void:
	parry_pulse = 1.0
	flash = 1.0


func set_stance(on: bool) -> void:
	stance = on


func spin_flip(dur: float) -> void:
	spin_kind = 1
	spin_t = 0.0
	spin_dur = maxf(0.2, dur)
	spin_dir = -last_facing if last_facing != 0.0 else -1.0


func spin_turn(dur: float) -> void:
	spin_kind = 2
	spin_t = 0.0
	spin_dur = maxf(0.2, dur)


func squash_jump() -> void:
	squash = Vector2(1.18, 0.78)


func stretch_jump() -> void:
	squash = Vector2(0.84, 1.2)


func _build_viewport() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(SPRITE_RES, SPRITE_RES)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE   # se redibuja a ANIM_FPS (ver update_visual)
	viewport.gui_disable_input = true
	add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.30, 0.36, 0.60)
	sky_mat.sky_horizon_color = Color(0.55, 0.60, 0.80)
	sky_mat.ground_horizon_color = Color(0.45, 0.48, 0.65)
	sky_mat.ground_bottom_color = Color(0.20, 0.22, 0.34)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	var vcam := Camera3D.new()
	vcam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vcam.size = VIEW_SIZE
	vcam.near = 0.05
	vcam.far = 40.0
	vcam.environment = env
	vcam.position = Vector3(0.0, VIEW_CENTER_Y, 10.0)
	viewport.add_child(vcam)
	vcam.current = true

	var key := DirectionalLight3D.new()
	key.light_color = Color(0.70, 0.90, 1.0)
	key.light_energy = 1.1
	key.rotation_degrees = Vector3(-30.0, 20.0, 0.0)
	viewport.add_child(key)

	var rim := DirectionalLight3D.new()
	rim.light_color = Color(1.0, 0.45, 0.65)
	rim.light_energy = 0.9
	rim.rotation_degrees = Vector3(-10.0, 155.0, 0.0)
	viewport.add_child(rim)

	model_root = Node3D.new()
	viewport.add_child(model_root)


func _build_quad() -> void:
	pivot = Node3D.new()
	pivot.position = Vector3(0.0, 0.0, SPRITE_Z)
	add_child(pivot)

	var qm := QuadMesh.new()
	qm.size = Vector2(VIEW_SIZE, VIEW_SIZE)
	quad = MeshInstance3D.new()
	quad.mesh = qm
	quad.position = Vector3(0.0, VIEW_CENTER_Y, 0.0)
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sh := Shader.new()
	sh.code = SHADER_SPRITE
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex", viewport.get_texture())
	mat.set_shader_parameter("levels", LEVELS)
	mat.set_shader_parameter("outline_px", OUTLINE_PX)
	mat.set_shader_parameter("anim_fps", ANIM_FPS)
	mat.set_shader_parameter("boil", BOIL)
	mat.set_shader_parameter("grain", GRAIN)
	mat.set_shader_parameter("hatch", HATCH)
	mat.set_shader_parameter("hatch_px", HATCH_PX)
	mat.set_shader_parameter("grain_px", GRAIN_PX)
	mat.set_shader_parameter("rim_px", RIM_PX)
	quad.material_override = mat
	pivot.add_child(quad)
	mat.set_shader_parameter("feet_v", 0.5 + VIEW_CENTER_Y / VIEW_SIZE)
	mat.set_shader_parameter("view_size", VIEW_SIZE)

	# reflejo en el piso mojado
	var rsh := Shader.new()
	rsh.code = SHADER_SPRITE.replace("depth_draw_opaque;", "depth_test_disabled;")
	refl_mat = ShaderMaterial.new()
	refl_mat.shader = rsh
	refl_mat.render_priority = -2
	refl_mat.set_shader_parameter("tex", viewport.get_texture())
	refl_mat.set_shader_parameter("levels", LEVELS)
	refl_mat.set_shader_parameter("outline_px", OUTLINE_PX)
	refl_mat.set_shader_parameter("is_reflection", true)
	refl_mat.set_shader_parameter("anim_fps", ANIM_FPS)
	refl_mat.set_shader_parameter("boil", BOIL)
	refl_mat.set_shader_parameter("rim_px", RIM_PX)
	refl_mat.set_shader_parameter("hatch_px", HATCH_PX)
	refl_mat.set_shader_parameter("grain_px", GRAIN_PX)
	refl_mat.set_shader_parameter("feet_v", 0.5 + VIEW_CENTER_Y / VIEW_SIZE)
	refl_mat.set_shader_parameter("view_size", VIEW_SIZE)
	refl = MeshInstance3D.new()
	refl.mesh = qm
	refl.top_level = true
	refl.material_override = refl_mat
	refl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(refl)


func _build_shadow() -> void:
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.5, 0.9)
	shadow = MeshInstance3D.new()
	shadow.mesh = pm
	shadow.top_level = true
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh := Shader.new()
	sh.code = SHADER_SHADOW
	shadow_mat = ShaderMaterial.new()
	shadow_mat.shader = sh
	shadow.material_override = shadow_mat
	add_child(shadow)


func update_visual(delta: float, facing: float, on_floor: bool, vel_y: float, dashing: bool, vel_x: float = 0.0) -> void:
	# animacion "a cuadros": el modelo se redibuja solo ANIM_FPS veces por segundo
	frame_acc += delta
	if frame_acc >= 1.0 / ANIM_FPS:
		frame_acc = fmod(frame_acc, 1.0 / ANIM_FPS)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# giro estilo 2D: el sprite se voltea al instante (con un pequeno "pellizco")
	if last_facing != 0.0 and facing != last_facing:
		squash.x = 0.78
	last_facing = facing
	mat.set_shader_parameter("flip", facing < 0.0)

	# aplastar al caer, estirar al subir
	if not on_floor:
		air_vy = vel_y
	elif not was_on_floor and air_vy < -3.0:
		squash = Vector2(1.2, 0.8)
	was_on_floor = on_floor
	stance_amt = move_toward(stance_amt, 1.0 if stance else 0.0, 6.0 * delta)
	var target := Vector2.ONE
	if not on_floor and vel_y > 1.0:
		target = Vector2(0.94, 1.07)
	elif on_floor and stance_amt > 0.0:
		var br := sin(Time.get_ticks_msec() * 0.0024) * 0.012 * stance_amt
		target = Vector2(1.0 + 0.04 * stance_amt, 1.0 - 0.05 * stance_amt + br)
	squash = squash.lerp(target, clampf(14.0 * delta, 0.0, 1.0))

	# giros 2D (voltereta / giro) e inclinacion al moverse
	var spin_ang := 0.0
	var turn_x := 1.0
	if spin_kind != 0:
		spin_t += delta / spin_dur
		if spin_t >= 1.0:
			spin_kind = 0
		else:
			var e := spin_t * spin_t * (3.0 - 2.0 * spin_t)
			if spin_kind == 1:
				spin_ang = spin_dir * TAU * e
			else:
				turn_x = cos(TAU * 2.0 * e)
	var lean := -clampf(vel_x * 0.018, -0.14, 0.14) - 0.05 * stance_amt
	if not on_floor:
		lean += -clampf(vel_x * 0.01, -0.08, 0.08)
	var ang := lean + spin_ang
	pivot.rotation = Vector3(0.0, 0.0, ang)
	pivot.position = Vector3(sin(ang), 1.0 - cos(ang), SPRITE_Z)
	pivot.scale = Vector3(squash.x * turn_x, squash.y, 1.0)

	# destello blanco al recibir un golpe
	flash = maxf(0.0, flash - delta * 5.0)
	guard_amt = move_toward(guard_amt, guard_target, 8.0 * delta)
	parry_pulse = maxf(0.0, parry_pulse - delta * 4.0)
	mat.set_shader_parameter("flash", flash * 0.85)
	mat.set_shader_parameter("tint", Color(0.35, 0.85, 1.0))
	mat.set_shader_parameter("tint_amt", clampf(guard_amt * 0.22 + parry_pulse * 0.5, 0.0, 0.8))

	_update_ghosts(delta, dashing, facing)
	_update_shadow()
	_update_reflection()


func _update_reflection() -> void:
	if refl == null or not floor_fn.is_valid():
		return
	var gy: float = float(floor_fn.call(global_position.x))
	var cy := global_position.y + VIEW_CENTER_Y * pivot.scale.y
	refl.global_position = Vector3(global_position.x, 2.0 * gy - cy, global_position.z + SPRITE_Z - 0.05)
	refl.scale = Vector3(pivot.scale.x, -pivot.scale.y, 1.0)
	refl.rotation = Vector3.ZERO
	refl_mat.set_shader_parameter("flip", last_facing < 0.0)


func _spawn_ghost(facing: float) -> void:
	var g := MeshInstance3D.new()
	g.mesh = quad.mesh
	g.top_level = true
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var gm := mat.duplicate() as ShaderMaterial
	gm.set_shader_parameter("tex", viewport.get_texture())
	gm.set_shader_parameter("flip", facing < 0.0)
	gm.set_shader_parameter("tint_amt", 0.85)
	gm.set_shader_parameter("flash", 0.0)
	gm.set_shader_parameter("alpha", 0.5)
	g.material_override = gm
	add_child(g)
	g.global_transform = quad.global_transform
	g.global_position.z -= 0.06
	ghosts.append({"node": g, "mat": gm, "age": 0.0})


func _update_ghosts(delta: float, dashing: bool, facing: float) -> void:
	if dashing:
		ghost_timer -= delta
		if ghost_timer <= 0.0:
			ghost_timer = GHOST_EVERY
			_spawn_ghost(facing)
	else:
		ghost_timer = 0.0
	var i := ghosts.size() - 1
	while i >= 0:
		var gd: Dictionary = ghosts[i]
		gd["age"] = float(gd["age"]) + delta
		var k: float = float(gd["age"]) / GHOST_LIFE
		if k >= 1.0:
			(gd["node"] as Node3D).queue_free()
			ghosts.remove_at(i)
		else:
			(gd["mat"] as ShaderMaterial).set_shader_parameter("alpha", 0.5 * (1.0 - k))
		i -= 1


func _update_shadow() -> void:
	if not floor_fn.is_valid():
		return
	var x := global_position.x
	var gy: float = float(floor_fn.call(x))
	var slope := atan2(float(floor_fn.call(x + 0.5)) - float(floor_fn.call(x - 0.5)), 1.0)
	shadow.global_position = Vector3(x, gy + 0.05, 0.0)
	shadow.rotation = Vector3(0.0, 0.0, slope)
	var h := clampf(global_position.y - gy, 0.0, 3.0)
	var s := 1.0 - h * 0.25
	shadow.scale = Vector3(s, 1.0, s)
	shadow_mat.set_shader_parameter("strength", 0.55 * clampf(1.0 - h * 0.3, 0.2, 1.0))


# ---------------------------------------------------------------- brazos 2D
func _arm_texture(path: String) -> Texture2D:
	var t: Texture2D = load(path)
	if t == null:
		return null
	var img := t.get_image()
	if img == null:
		return t
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _bone_world(i: int, gt: Transform3D, rest: bool) -> Vector3:
	var p := skel.get_bone_global_rest(i) if rest else skel.get_bone_global_pose(i)
	return (gt * p).origin


func _setup_arms(m: Node3D) -> void:
	skel = m.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		push_warning("ninja_sprite: no hay Skeleton3D, los brazos 2D no se crean.")
		return
	for seg in ARM_SEGS:
		arm_tex[seg["key"]] = _arm_texture(seg["path"])
	var gt := skel.global_transform
	for side in ["R", "L"]:
		var ua := skel.find_bone("UpperArm." + side)
		var la := skel.find_bone("LowerArm." + side)
		var hd := skel.find_bone("Hand." + side)
		if ua < 0 or la < 0 or hd < 0:
			push_warning("ninja_sprite: faltan huesos del brazo " + side)
			continue
		var p_ua := _bone_world(ua, gt, true)
		var p_la := _bone_world(la, gt, true)
		var p_hd := _bone_world(hd, gt, true)
		var rest_dir := (p_hd - p_la).normalized()
		var hand_rest := (gt.basis * skel.get_bone_global_rest(hd).basis).orthonormalized().inverse() * rest_dir
		var near: bool = (side == "R")
		var arm := {
			"ids": [ua, la, hd],
			"near": near,
			"hand_rest": hand_rest,
			"len_upper": maxf(0.05, Vector2(p_la.x - p_ua.x, p_la.y - p_ua.y).length()),
			"len_fore": maxf(0.05, Vector2(p_hd.x - p_la.x, p_hd.y - p_la.y).length()),
			"holders": {},
			"last_dir": {"upper": Vector2(0, -1), "fore": Vector2(0, -1), "hand": Vector2(0, -1)},
		}
		for seg in ARM_SEGS:
			var tex: Texture2D = arm_tex[seg["key"]]
			if tex == null:
				continue
			var bone_len: float = HAND_LEN
			if seg["key"] == "upper":
				bone_len = arm["len_upper"]
			elif seg["key"] == "fore":
				bone_len = arm["len_fore"]
			var k: float = bone_len / ((float(seg["bot"]) - float(seg["top"])) * ARM_PX)
			var holder := Node3D.new()
			model_root.add_child(holder)
			var sp := Sprite3D.new()
			sp.texture = tex
			sp.pixel_size = ARM_PX * k
			sp.centered = true
			sp.shaded = false
			sp.double_sided = true
			sp.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
			sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			var b := ARM_BRIGHT_NEAR if near else ARM_BRIGHT_FAR
			sp.modulate = Color(b, b, b, 1.0)
			sp.position = Vector3(0.0, -(float(tex.get_height()) * 0.5 - float(seg["top"])) * ARM_PX * k, 0.0)
			holder.add_child(sp)
			arm["holders"][seg["key"]] = holder
		arms.append(arm)
	_setup_sword(m)
	skel.skeleton_updated.connect(_update_arms)
	_update_arms()


func _place(arm: Dictionary, key: String, from: Vector3, d: Vector2, base_z: float, stretch: float) -> void:
	var holder: Node3D = arm["holders"].get(key)
	if holder == null:
		return
	var dir: Vector2 = d
	if dir.length() < 0.0005:
		dir = arm["last_dir"][key]
	else:
		dir = dir.normalized()
		arm["last_dir"][key] = dir
	var dz := 0.0
	for seg in ARM_SEGS:
		if seg["key"] == key:
			dz = float(seg["dz"])
	holder.position = Vector3(from.x, from.y, base_z + dz)
	holder.rotation = Vector3(0.0, 0.0, atan2(dir.x, -dir.y))
	holder.scale = Vector3(1.0, stretch, 1.0)


func _update_arms() -> void:
	if skel == null:
		return
	var gt := skel.global_transform
	var blade := _compute_blade(gt)
	for arm in arms:
		var ids: Array = arm["ids"]
		var p_ua := _bone_world(ids[0], gt, false)
		var p_la := _bone_world(ids[1], gt, false)
		var p_hd := _bone_world(ids[2], gt, false)
		var z: float = ARM_NEAR_Z if arm["near"] else ARM_FAR_Z
		var ik_far := false
		if sword_ok and not arm["near"] and stance_amt > 0.001 and not bool(blade["sheathed"]):
			var bd: Vector2 = blade["dir"]
			var bb: Vector2 = blade["butt"]
			var tgt := bb + bd * 0.05
			var el := _elbow(Vector2(p_ua.x, p_ua.y), tgt, float(arm["len_upper"]), float(arm["len_fore"]))
			el = Vector2(p_la.x, p_la.y).lerp(el, stance_amt)
			tgt = Vector2(p_hd.x, p_hd.y).lerp(tgt, stance_amt)
			p_la = Vector3(el.x, el.y, p_la.z)
			p_hd = Vector3(tgt.x, tgt.y, p_hd.z)
			ik_far = true
			if stance_amt > 0.5:
				z = ARM_NEAR_Z - 0.02
		var d_up := Vector2(p_la.x - p_ua.x, p_la.y - p_ua.y)
		var d_fo := Vector2(p_hd.x - p_la.x, p_hd.y - p_la.y)
		_place(arm, "upper", p_ua, d_up, z, clampf(d_up.length() / float(arm["len_upper"]), 0.4, 1.25))
		_place(arm, "fore", p_la, d_fo, z, clampf(d_fo.length() / float(arm["len_fore"]), 0.4, 1.25))
		var hb := (gt.basis * skel.get_bone_global_pose(ids[2]).basis).orthonormalized()
		var hdir3: Vector3 = hb * arm["hand_rest"]
		var hdir := Vector2(hdir3.x, hdir3.y)
		if hdir.length() < 0.15 or ik_far:
			hdir = d_fo
		_place(arm, "hand", p_hd, hdir, z, 1.0)
	_update_sword(blade)


# ---------------------------------------------------------------- espada 2D
func _blade_holder(tex: Texture2D) -> Node3D:
	var holder := Node3D.new()
	model_root.add_child(holder)
	var sp := Sprite3D.new()
	sp.texture = tex
	sp.pixel_size = ARM_PX
	sp.centered = true
	sp.shaded = false
	sp.double_sided = true
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sp.position = Vector3(0.0, -float(tex.get_height()) * 0.5 * ARM_PX, 0.0)
	holder.add_child(sp)
	return holder


func _setup_sword(m: Node3D) -> void:
	b_sw = skel.find_bone("Sword")
	b_gl = skel.find_bone("FX_BladeGlow")
	b_sc = skel.find_bone("Scabbard")
	b_hd = skel.find_bone("Hand.R")
	if b_sw < 0 or b_gl < 0 or b_sc < 0 or b_hd < 0:
		push_warning("ninja_sprite: faltan huesos de la espada, se usa la espada 3D.")
		return
	var tex_s := _arm_texture(SWORD_PNG)
	var tex_c := _arm_texture(SCAB_PNG)
	if tex_s == null or tex_c == null:
		push_warning("ninja_sprite: faltan res://sword2d/*.png, se usa la espada 3D.")
		return
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var nm := String(n.name)
		if nm.begins_with("Sword") or nm.begins_with("Scabbard"):
			(n as Node3D).visible = false
	sword_holder = _blade_holder(tex_s)
	scab_holder = _blade_holder(tex_c)
	var gt := skel.global_transform
	var rest_dir := (_bone_world(b_gl, gt, true) - _bone_world(b_sw, gt, true)).normalized()
	scab_local = (gt.basis * skel.get_bone_global_rest(b_sc).basis).orthonormalized().inverse() * rest_dir
	sword_ok = true


func _compute_blade(gt: Transform3D) -> Dictionary:
	var out := {"sheathed": true, "butt": Vector2.ZERO, "dir": last_sword_dir, "scab_dir": Vector2(0.0, -1.0), "scab_pos": Vector2.ZERO}
	if not sword_ok:
		return out
	var p_sw := _bone_world(b_sw, gt, false)
	var p_gl := _bone_world(b_gl, gt, false)
	var p_sc := _bone_world(b_sc, gt, false)
	var p_hd := _bone_world(b_hd, gt, false)
	var sheathed := Vector2(p_sw.x - p_sc.x, p_sw.y - p_sc.y).length() < 0.3
	var d := Vector2(p_gl.x - p_sw.x, p_gl.y - p_sw.y)
	if d.length() < 0.001:
		d = last_sword_dir
	d = d.normalized()
	var butt := Vector2(p_sw.x, p_sw.y)
	if not sheathed and stance_amt > 0.001:
		var ang := lerp_angle(d.angle(), STANCE_DIR.angle(), stance_amt)
		d = Vector2.from_angle(ang)
		butt = butt.lerp(Vector2(p_hd.x, p_hd.y) - d * 0.16, stance_amt)
	last_sword_dir = d
	var sb3: Vector3 = (gt.basis * skel.get_bone_global_pose(b_sc).basis).orthonormalized() * scab_local
	var sd := Vector2(sb3.x, sb3.y)
	if sd.length() < 0.001:
		sd = Vector2(0.0, -1.0)
	out["sheathed"] = sheathed
	out["butt"] = butt
	out["dir"] = d
	out["scab_dir"] = sd.normalized()
	out["scab_pos"] = Vector2(p_sc.x, p_sc.y)
	return out


func _update_sword(b: Dictionary) -> void:
	if not sword_ok:
		return
	var sheathed: bool = b["sheathed"]
	var d: Vector2 = b["dir"]
	var bt: Vector2 = b["butt"]
	var z_s := SWORD_Z_BACK if sheathed else ARM_NEAR_Z + SWORD_Z_DRAWN
	sword_holder.position = Vector3(bt.x, bt.y, z_s)
	sword_holder.rotation = Vector3(0.0, 0.0, atan2(d.x, -d.y))
	var sd: Vector2 = b["scab_dir"]
	var sp: Vector2 = b["scab_pos"]
	scab_holder.position = Vector3(sp.x, sp.y, SCAB_Z)
	scab_holder.rotation = Vector3(0.0, 0.0, atan2(sd.x, -sd.y))


func _elbow(p0: Vector2, target: Vector2, l1: float, l2: float) -> Vector2:
	var d := target - p0
	var dist := clampf(d.length(), 0.02, l1 + l2 - 0.002)
	var dir := Vector2.DOWN
	if d.length() > 0.0001:
		dir = d.normalized()
	var a := (l1 * l1 - l2 * l2 + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var perp := Vector2(-dir.y, dir.x)
	var e1 := p0 + dir * a + perp * h
	var e2 := p0 + dir * a - perp * h
	return e1 if e1.y < e2.y else e2


# ---------------------------------------------------------------- textura del ninja (tu ilustracion)
const ART_TEX := "res://ninja_art.png"


func _load_color_tex(path: String) -> Texture2D:
	var img := Image.new()
	if img.load(path) == OK:
		img.convert(Image.FORMAT_RGBA8)
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	var t: Texture2D = load(path)
	return t


func _restyle_body(m: Node3D) -> void:
	var tex := _load_color_tex(ART_TEX)
	if tex == null:
		push_warning("ninja_sprite: falta res://ninja_art.png, se usa la textura original.")
		return
	var best: MeshInstance3D = null
	var best_n := -1
	for n in m.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if nm.begins_with("Sword") or nm.begins_with("Scabbard") or nm.begins_with("FX") or nm.begins_with("Eye"):
			continue
		if mi.mesh == null:
			continue
		var cnt: int = mi.mesh.surface_get_array_len(0)
		if nm.begins_with("Ninja_Body"):
			best = mi
			break
		if cnt > best_n:
			best_n = cnt
			best = mi
	if best == null:
		return
	for i in range(best.mesh.get_surface_count()):
		var base := best.get_active_material(i) as BaseMaterial3D
		if base == null:
			continue
		var mat2 := base.duplicate() as BaseMaterial3D
		mat2.albedo_texture = tex
		mat2.albedo_color = Color(1, 1, 1, 1)
		mat2.vertex_color_use_as_albedo = false
		mat2.metallic = 0.0
		mat2.metallic_texture = null
		mat2.roughness = 0.85
		mat2.roughness_texture = null
		best.set_surface_override_material(i, mat2)
