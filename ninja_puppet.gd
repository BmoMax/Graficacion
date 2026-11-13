extends Node3D
## Ninja 2D de papel recortado, hecho con piezas de tu ilustracion.
## No usa el modelo 3D: las piezas (cabeza, capa, torso, brazos, piernas, espada...)
## son Sprite3D que siguen las articulaciones guardadas de TODAS las animaciones
## (res://puppet/ninja_anim.json). El mezclado cuerpo superior / inferior es el
## mismo que tenia el juego: correr y atacar a la vez, etc.

const DIR := "res://puppet/"
const LAYER_DZ := 0.03
const XFADE := 0.12
const LOOPED := ["idle", "walk", "run", "sprint", "crouch", "crouchwalk", "guard"]
const UPPER_JOINTS := ["Spine", "Chest", "UpperChest", "Neck", "NeckTop", "Head", "Tie1", "Tie2",
	"UpperArm.L", "LowerArm.L", "Hand.L", "HandTip.L", "UpperArm.R", "LowerArm.R", "Hand.R", "HandTip.R",
	"CloakBack1", "CloakBack2", "CloakBack3", "Scabbard", "ScabbardTip", "Sword", "FX_BladeGlow"]
const SHEATH_DIST := 0.3
const GHOST_LIFE := 0.3
const GHOST_EVERY := 0.04
const NEAR_TINT := Color(0.95, 0.97, 1.0)
const FAR_TINT := Color(0.58, 0.60, 0.72)

var art_px := 0.00138
var sheath_off := Vector2(0.14, -0.03)
var jn: Array = []
var ji := {}
var nj := 0
var clips := {}
var upper_mask := PackedByteArray()
var rig: Node3D
var fx_node: MeshInstance3D
var fx_mesh: ImmediateMesh
var insts: Array = []
var ok := false

var loco := {"clip": "", "t": 0.0, "since": 99.0, "prev": PackedVector2Array()}
var combat := {"clip": "", "t": 0.0, "since": 99.0, "prev": PackedVector2Array()}
var upper_amt := 0.0
var full_amt := 0.0

var floor_fn: Callable
var shadow: MeshInstance3D
var shadow_mat: ShaderMaterial
var flash := 0.0
var squash := Vector2.ONE
var facing := 1.0
var last_facing := 0.0
var was_on_floor := true
var air_vy := 0.0
var ghost_timer := 0.0
var ghosts: Array = []
var dashing := false

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


func setup(floor_callable: Callable) -> bool:
	floor_fn = floor_callable
	var anim = JSON.parse_string(FileAccess.get_file_as_string(DIR + "ninja_anim.json"))
	var spec = JSON.parse_string(FileAccess.get_file_as_string(DIR + "parts.json"))
	if anim == null or spec == null:
		push_error("No se pudo leer res://puppet/ninja_anim.json o parts.json")
		return false
	art_px = float(spec["art_px"])
	sheath_off = Vector2(float(spec["sheath_off"][0]), float(spec["sheath_off"][1]))
	jn = anim["joints"]
	nj = jn.size()
	for i in range(nj):
		ji[String(jn[i])] = i
	upper_mask.resize(nj)
	for i in range(nj):
		upper_mask[i] = 1 if String(jn[i]) in UPPER_JOINTS else 0
	for cname in anim["clips"].keys():
		var c: Dictionary = anim["clips"][cname]
		var fr := PackedFloat32Array()
		for row in c["frames"]:
			for v in row:
				fr.append(float(v))
		var fx := PackedFloat32Array()
		for row in c["fx"]:
			for v in row:
				fx.append(float(v))
		var low := String(cname).to_lower()
		clips[low] = {"n": int(c["n"]), "len": float(c["len"]), "fr": fr, "fx": fx, "loop": low in LOOPED}
	_build_rig(spec)
	_build_shadow()
	_switch(loco, "idle")
	_switch(combat, "guard")
	ok = true
	_apply_pose()
	return true


func clip_names() -> Array:
	return clips.keys()


func clip_len(low: String) -> float:
	if clips.has(low):
		return float(clips[low]["len"])
	return 0.8


func set_loco(low: String) -> void:
	_switch(loco, low)


func set_combat(low: String) -> void:
	_switch(combat, low)


func set_blend(up: float, full: float) -> void:
	upper_amt = up
	full_amt = full


func flash_hit() -> void:
	flash = 1.0


# ------------------------------------------------------------------ construccion
func _tex(path: String) -> Texture2D:
	var t: Texture2D = load(path)
	if t == null:
		return null
	var img := t.get_image()
	if img == null:
		return t
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_rig(spec: Dictionary) -> void:
	rig = Node3D.new()
	add_child(rig)
	var texes := {}
	var list: Array = spec["inst"]
	list.sort_custom(func(a, b): return float(a["layer"]) < float(b["layer"]))
	for it in list:
		var pname: String = it["part"]
		var pt: Dictionary = spec["parts"][pname]
		if not texes.has(pname):
			texes[pname] = _tex(DIR + String(pt["png"]))
		var tex: Texture2D = texes[pname]
		if tex == null:
			continue
		var pa := Vector2(float(pt["pa"][0]), float(pt["pa"][1]))
		var pb := Vector2(float(pt["pb"][0]), float(pt["pb"][1]))
		var holder := Node3D.new()
		rig.add_child(holder)
		var sp := Sprite3D.new()
		sp.texture = tex
		sp.pixel_size = art_px
		sp.centered = true
		sp.shaded = false
		sp.double_sided = true
		sp.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
		sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		sp.position = Vector3((float(tex.get_width()) * 0.5 - pa.x) * art_px, (pa.y - float(tex.get_height()) * 0.5) * art_px, 0.0)
		holder.add_child(sp)
		var tint := FAR_TINT if String(it.get("side", "")) == "far" else NEAR_TINT
		insts.append({
			"holder": holder, "sprite": sp, "a": int(ji[String(it["a"])]), "b": int(ji[String(it["b"])]),
			"pa": pa, "pb": pb, "xs": float(pt["xs"]), "layer": float(it["layer"]),
			"dyn": String(it.get("dyn", "")), "name": String(it["name"]), "tint": tint,
		})
	fx_mesh = ImmediateMesh.new()
	fx_node = MeshInstance3D.new()
	fx_node.name = "FX"
	fx_node.mesh = fx_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	fx_node.material_override = m
	fx_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rig.add_child(fx_node)


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


# ------------------------------------------------------------------ animacion
func _switch(ch: Dictionary, low: String) -> void:
	if ch["clip"] == low or not clips.has(low):
		return
	if ch["clip"] != "" and ok:
		ch["prev"] = _chan_pose(ch)
	else:
		ch["prev"] = PackedVector2Array()
	ch["clip"] = low
	ch["t"] = 0.0
	ch["since"] = 0.0


func _frame_idx(c: Dictionary, t: float) -> Array:
	var f := t * 30.0
	var n: int = c["n"]
	var i0 := int(floorf(f))
	var fr := f - float(i0)
	var i1 := i0 + 1
	if c["loop"]:
		i0 = posmod(i0, n)
		i1 = (i0 + 1) % n
	elif i0 >= n:
		i0 = n
		i1 = n
		fr = 0.0
	return [i0, i1, fr]


func _sample(low: String, t: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(nj)
	if not clips.has(low):
		return out
	var c: Dictionary = clips[low]
	var ix := _frame_idx(c, t)
	var fa: PackedFloat32Array = c["fr"]
	var b0: int = int(ix[0]) * nj * 2
	var b1: int = int(ix[1]) * nj * 2
	var fr: float = ix[2]
	for j in range(nj):
		out[j] = Vector2(lerpf(fa[b0 + 2 * j], fa[b1 + 2 * j], fr), lerpf(fa[b0 + 2 * j + 1], fa[b1 + 2 * j + 1], fr))
	return out


func _sample_fx(low: String, t: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not clips.has(low):
		return out
	var c: Dictionary = clips[low]
	var ix := _frame_idx(c, t)
	var fa: PackedFloat32Array = c["fx"]
	var per := 4 * 8 * 3
	var b0: int = int(ix[0]) * per
	var b1: int = int(ix[1]) * per
	var fr: float = ix[2]
	out.resize(per)
	for k in range(per):
		out[k] = lerpf(fa[b0 + k], fa[b1 + k], fr)
	return out


func _chan_pose(ch: Dictionary) -> PackedVector2Array:
	var cur := _sample(String(ch["clip"]), float(ch["t"]))
	var w := clampf(float(ch["since"]) / XFADE, 0.0, 1.0)
	var prev: PackedVector2Array = ch["prev"]
	if w >= 1.0 or prev.size() != nj:
		return cur
	var out := PackedVector2Array()
	out.resize(nj)
	for j in range(nj):
		out[j] = prev[j].lerp(cur[j], w)
	return out


func _process(delta: float) -> void:
	if not ok:
		return
	for ch in [loco, combat]:
		ch["t"] = float(ch["t"]) + delta
		ch["since"] = float(ch["since"]) + delta
	_apply_pose()


func _apply_pose() -> void:
	var lp := _chan_pose(loco)
	var cp := _chan_pose(combat)
	var i_spine: int = ji["Spine"]
	var ls := lp[i_spine]
	var cs := cp[i_spine]
	var fin := PackedVector2Array()
	fin.resize(nj)
	for j in range(nj):
		var lo := lp[j]
		var mix := lo
		if upper_mask[j] == 1:
			mix = lo.lerp(ls + (cp[j] - cs), upper_amt)
		fin[j] = mix.lerp(cp[j], full_amt)
	var i_sw: int = ji["Sword"]
	var i_sc: int = ji["Scabbard"]
	var dist := fin[i_sw].distance_to(fin[i_sc])
	var sheathed := dist < SHEATH_DIST
	var wsh := clampf(1.0 - dist / 0.5, 0.0, 1.0)
	var i_st: int = ji["ScabbardTip"]
	var i_bg: int = ji["FX_BladeGlow"]
	fin[i_sc] = fin[i_sc] + sheath_off
	fin[i_st] = fin[i_st] + sheath_off
	fin[i_sw] = fin[i_sw] + sheath_off * wsh
	fin[i_bg] = fin[i_bg] + sheath_off * wsh

	var boost := 1.0 + flash * 2.0
	for it in insts:
		var holder: Node3D = it["holder"]
		if it["dyn"] == "sword":
			var show: bool = (it["name"] == "sword_back") == sheathed
			holder.visible = show
			if not show:
				continue
		var a: Vector2 = fin[int(it["a"])]
		var b: Vector2 = fin[int(it["b"])]
		var w := b - a
		var pa: Vector2 = it["pa"]
		var pb: Vector2 = it["pb"]
		var plen := (pb - pa).length() * art_px
		var s := clampf(w.length() / plen, 0.5, 1.35)
		var phi := atan2(w.y, w.x) - atan2(-(pb.y - pa.y), pb.x - pa.x)
		holder.position = Vector3(a.x, a.y, float(it["layer"]) * LAYER_DZ)
		holder.rotation = Vector3(0.0, 0.0, phi)
		holder.scale = Vector3(float(it["xs"]), s, 1.0)
		var tint: Color = it["tint"]
		(it["sprite"] as Sprite3D).modulate = Color(tint.r * boost, tint.g * boost, tint.b * boost, 1.0)
	_update_fx(cp, fin)


func _update_fx(cp: PackedVector2Array, fin: PackedVector2Array) -> void:
	fx_mesh.clear_surfaces()
	if upper_amt < 0.3 and full_amt < 0.3:
		return
	var i_spine: int = ji["Spine"]
	var shift := fin[i_spine] - cp[i_spine]
	var fx := _sample_fx(String(combat["clip"]), float(combat["t"]))
	if fx.size() < 96:
		return
	var z := (float(insts.size()) + 1.0) * LAYER_DZ
	for k in range(4):
		var mx := 0.0
		for i in range(8):
			mx = maxf(mx, fx[(k * 8 + i) * 3 + 2])
		if mx < 0.04:
			continue
		fx_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in range(8):
			var base := (k * 8 + i) * 3
			var p := Vector2(fx[base], fx[base + 1]) + shift
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, 7)
			var p0 := Vector2(fx[(k * 8 + i0) * 3], fx[(k * 8 + i0) * 3 + 1])
			var p1 := Vector2(fx[(k * 8 + i1) * 3], fx[(k * 8 + i1) * 3 + 1])
			var tg := (p1 - p0)
			if tg.length() < 0.0001:
				tg = Vector2(1, 0)
			tg = tg.normalized()
			var nr := Vector2(-tg.y, tg.x)
			var sc := clampf(fx[base + 2] / 0.33, 0.0, 1.5)
			var wd := 0.10 * sc
			var al := clampf(sc, 0.0, 1.0) * (0.25 + 0.75 * float(i) / 7.0)
			fx_mesh.surface_set_color(Color(1.0, 0.85, 0.6, al))
			fx_mesh.surface_add_vertex(Vector3(p.x + nr.x * wd, p.y + nr.y * wd, z))
			fx_mesh.surface_set_color(Color(1.0, 0.85, 0.6, al))
			fx_mesh.surface_add_vertex(Vector3(p.x - nr.x * wd, p.y - nr.y * wd, z))
		fx_mesh.surface_end()


# ------------------------------------------------------------------ extras 2D
func update_visual(delta: float, face: float, on_floor: bool, vel_y: float, is_dashing: bool) -> void:
	facing = face
	dashing = is_dashing
	if last_facing != 0.0 and face != last_facing:
		squash.x = 0.8
	last_facing = face
	if not on_floor:
		air_vy = vel_y
	elif not was_on_floor and air_vy < -3.0:
		squash = Vector2(1.2, 0.82)
	was_on_floor = on_floor
	var target := Vector2.ONE
	if not on_floor and vel_y > 1.0:
		target = Vector2(0.95, 1.06)
	squash = squash.lerp(target, clampf(14.0 * delta, 0.0, 1.0))
	rig.scale = Vector3(face * squash.x, squash.y, 1.0)
	flash = maxf(0.0, flash - delta * 5.0)
	_update_ghosts(delta)
	_update_shadow()


func _spawn_ghost() -> void:
	var g := rig.duplicate() as Node3D
	g.top_level = true
	add_child(g)
	g.global_transform = rig.global_transform
	g.global_position.z -= 0.25
	var fxn := g.get_node_or_null("FX")
	if fxn != null:
		fxn.queue_free()
	var sprites: Array = []
	for h in g.get_children():
		for c in h.get_children():
			if c is Sprite3D:
				var sp := c as Sprite3D
				sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
				sp.modulate = Color(0.4, 0.7, 1.0, 0.5)
				sprites.append(sp)
	ghosts.append({"node": g, "sprites": sprites, "age": 0.0})


func _update_ghosts(delta: float) -> void:
	if dashing:
		ghost_timer -= delta
		if ghost_timer <= 0.0:
			ghost_timer = GHOST_EVERY
			_spawn_ghost()
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
			for sp in gd["sprites"]:
				(sp as Sprite3D).modulate = Color(0.4, 0.7, 1.0, 0.5 * (1.0 - k))
		i -= 1


func _update_shadow() -> void:
	if not floor_fn.is_valid():
		return
	var x := global_position.x
	var gy: float = float(floor_fn.call(x))
	var h := clampf(global_position.y - gy, 0.0, 3.0)
	shadow.global_position = Vector3(x, gy + 0.03, 0.15)
	shadow.rotation = Vector3.ZERO
	var s := 1.0 - h * 0.25
	shadow.scale = Vector3(s, 1.0, s)
	shadow_mat.set_shader_parameter("strength", 0.6 * clampf(1.0 - h * 0.3, 0.2, 1.0))
