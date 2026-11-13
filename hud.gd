extends CanvasLayer
## HUD 2D: vida de Root y del Centinela, energia, retratos y panel de controles.
## Se dibuja en coordenadas de 1280x720 (el proyecto escala con canvas_items).

var m: Node                      # main.gd (de ahi lee root_hp, root_max, energy, boss)
var canvas: Control
var tex_root: Texture2D
var tex_boss: Texture2D
var key_box: StyleBoxFlat
var panel_box: StyleBoxFlat
var font: Font
var shown_root := 1.0            # barras con "estela" que bajan suave
var shown_boss := 1.0

const RED := Color(0.93, 0.1, 0.2)
const RED_DARK := Color(0.32, 0.03, 0.08)
const CYAN := Color(0.2, 0.9, 1.0)
const INK := Color(0.02, 0.03, 0.1, 0.85)
const AMBER := Color(1.0, 0.78, 0.25)


func setup(main_node: Node) -> void:
	m = main_node
	layer = 10
	font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://ui/portrait_root.png"):
		tex_root = load("res://ui/portrait_root.png")
	if ResourceLoader.exists("res://ui/portrait_centinela.png"):
		tex_boss = load("res://ui/portrait_centinela.png")
	key_box = StyleBoxFlat.new()
	key_box.bg_color = Color(0.05, 0.08, 0.16, 0.9)
	key_box.border_color = Color(0.55, 0.75, 0.95, 0.9)
	key_box.set_border_width_all(1)
	key_box.set_corner_radius_all(4)
	panel_box = StyleBoxFlat.new()
	panel_box.bg_color = Color(0.02, 0.04, 0.1, 0.72)
	panel_box.border_color = Color(0.2, 0.7, 0.95, 0.5)
	panel_box.set_border_width_all(1)
	panel_box.set_corner_radius_all(6)
	canvas = Control.new()
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	canvas.draw.connect(_draw_hud)


func _process(delta: float) -> void:
	if m == null:
		return
	var rf := _ratio("root_hp", "root_max")
	var bf := _boss_ratio()
	shown_root = move_toward(shown_root, rf, delta * 0.6)
	shown_boss = move_toward(shown_boss, bf, delta * 0.6)
	canvas.queue_redraw()


func _ratio(a: String, b: String) -> float:
	var v := float(m.get(a))
	var mx := maxf(1.0, float(m.get(b)))
	return clampf(v / mx, 0.0, 1.0)


func _boss_ratio() -> float:
	var b = m.get("boss")
	if b == null:
		return 0.0
	return clampf(float(b.hp) / maxf(1.0, float(b.max_hp)), 0.0, 1.0)


# barra inclinada (paralelogramo). dir = 1 crece hacia la derecha, -1 hacia la izquierda
func _slant_bar(x: float, y: float, w: float, h: float, frac: float, col: Color, back: Color, dir: float, slant: float = 12.0) -> void:
	var back_pts := PackedVector2Array([
		Vector2(x + slant, y), Vector2(x + w + slant, y), Vector2(x + w, y + h), Vector2(x, y + h)])
	canvas.draw_colored_polygon(back_pts, back)
	if frac > 0.001:
		var fw := w * frac
		var x0 := x if dir > 0.0 else x + w - fw
		var pts := PackedVector2Array([
			Vector2(x0 + slant, y), Vector2(x0 + fw + slant, y), Vector2(x0 + fw, y + h), Vector2(x0, y + h)])
		canvas.draw_colored_polygon(pts, col)


func _segments(x: float, y: float, w: float, h: float, n: int, slant: float = 12.0) -> void:
	for i in range(1, n):
		var sx := x + w * float(i) / float(n)
		canvas.draw_line(Vector2(sx + slant, y), Vector2(sx, y + h), Color(0.02, 0.03, 0.1, 0.9), 2.0)


func _draw_portrait(c: Vector2, r: float, tex: Texture2D, ring: Color) -> void:
	canvas.draw_circle(c, r + 4.0, Color(0.02, 0.03, 0.1, 0.9))
	if tex != null:
		canvas.draw_texture_rect(tex, Rect2(c.x - r, c.y - r, r * 2.0, r * 2.0), false)
	canvas.draw_arc(c, r + 2.0, 0.0, TAU, 48, ring, 3.0, true)


func _draw_hud() -> void:
	if m == null or font == null:
		return
	# ---- ROOT (izquierda) ----
	_draw_portrait(Vector2(62, 62), 38.0, tex_root, Color(0.35, 0.85, 1.0))
	canvas.draw_string(font, Vector2(150, 44), "Root", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.9, 0.97, 1.0))
	var rf := _ratio("root_hp", "root_max")
	_slant_bar(146, 54, 330, 22, shown_root, Color(1.0, 0.85, 0.3, 0.9), RED_DARK, 1.0)
	_slant_bar(146, 54, 330, 22, rf, RED, Color(0, 0, 0, 0), 1.0)
	_segments(146, 54, 330, 22, 10)
	var dash_frac := 1.0 - clampf(float(m.get("dash_cd")) / 0.7, 0.0, 1.0)
	_slant_bar(144, 82, 250, 6, dash_frac, CYAN, Color(0.04, 0.12, 0.2, 0.85), 1.0, 6.0)
	var rp := clampf(float(m.get("root_posture")) / 100.0, 0.0, 1.0)
	var rp_col := AMBER if rp < 0.75 else Color(1.0, 0.35, 0.2)
	_slant_bar(142, 92, 250, 6, rp, rp_col, Color(0.12, 0.08, 0.02, 0.85), 1.0, 6.0)
	var en := int(floor(float(m.get("energy"))))
	var frac_en := float(m.get("energy")) - float(en)
	for i in range(3):
		var c := Vector2(160 + i * 36, 128)
		canvas.draw_circle(c, 13.0, Color(0.02, 0.05, 0.12, 0.85))
		if i < en:
			canvas.draw_circle(c, 10.0, CYAN)
			canvas.draw_circle(c, 5.0, Color(0.85, 1.0, 1.0))
		elif i == en:
			canvas.draw_arc(c, 8.0, -PI * 0.5, -PI * 0.5 + TAU * frac_en, 24, CYAN, 3.0, true)
		canvas.draw_arc(c, 12.0, 0.0, TAU, 24, Color(0.4, 0.85, 1.0, 0.8), 1.5, true)

	# ---- CENTINELA (derecha) ----
	_draw_portrait(Vector2(1218, 62), 38.0, tex_boss, Color(0.3, 0.6, 1.0))
	canvas.draw_string(font, Vector2(1000, 44), "Centinela", HORIZONTAL_ALIGNMENT_RIGHT, 190, 24, Color(0.9, 0.97, 1.0))
	var bf := _boss_ratio()
	_slant_bar(740, 54, 440, 22, shown_boss, Color(1.0, 0.85, 0.3, 0.9), RED_DARK, -1.0, -12.0)
	_slant_bar(740, 54, 440, 22, bf, RED, Color(0, 0, 0, 0), -1.0, -12.0)
	_segments(740, 54, 440, 22, 14, -12.0)
	var bobj = m.get("boss")
	if bobj != null:
		var bp := clampf(float(bobj.posture) / 100.0, 0.0, 1.0)
		var is_broken: bool = bool(bobj.broken)
		var pcol := Color(0.6, 0.9, 1.0) if is_broken else (AMBER if bp < 0.75 else Color(1.0, 0.35, 0.2))
		_slant_bar(740, 82, 440, 7, 1.0 if is_broken else bp, pcol, Color(0.12, 0.08, 0.02, 0.85), -1.0, -12.0)
		if is_broken:
			canvas.draw_string(font, Vector2(740, 112), "POSTURA ROTA", HORIZONTAL_ALIGNMENT_RIGHT, 440, 16, Color(0.7, 0.95, 1.0))
		if bool(bobj.defeated) and float(bobj.dying_t) > 3.6:
			var a := clampf((float(bobj.dying_t) - 3.6) / 1.2, 0.0, 1.0)
			canvas.draw_string(font, Vector2(0, 300), "CENTINELA DERROTADO", HORIZONTAL_ALIGNMENT_CENTER, 1280, 46, Color(0.75, 0.95, 1.0, a))
			canvas.draw_line(Vector2(440, 318), Vector2(840, 318), Color(0.35, 0.85, 1.0, a * 0.8), 2.0)

	# ---- Mensaje de muerte ----
	if bool(m.get("dead")):
		canvas.draw_string(font, Vector2(0, 340), "Has caido  -  R para revivir", HORIZONTAL_ALIGNMENT_CENTER, 1280, 34, Color(1.0, 0.8, 0.85))

	# ---- Controles (abajo a la izquierda) ----
	var base_y := 612.0
	canvas.draw_style_box(panel_box, Rect2(18, base_y - 8, 640, 106))
	_key_row(Vector2(34, base_y), ["A", "W", "S", "D"], "Mover")
	_key_row(Vector2(34, base_y + 25), ["Shift"], "Correr / Dash")
	_key_row(Vector2(34, base_y + 50), ["Espacio"], "Saltar")
	_key_row(Vector2(34, base_y + 75), ["C"], "Agacharse")
	_key_row(Vector2(264, base_y), ["Clic"], "Atacar")
	_key_row(Vector2(264, base_y + 25), ["J", "K"], "Combo / Estocada")
	_key_row(Vector2(264, base_y + 50), ["G"], "Guardar espada")
	_key_row(Vector2(264, base_y + 75), ["V"], "Voltereta")
	_key_row(Vector2(500, base_y), ["L"], "Pesado")
	_key_row(Vector2(500, base_y + 25), ["U"], "Embestida")
	_key_row(Vector2(500, base_y + 50), ["I"], "Especial (golpea)")
	_key_row(Vector2(500, base_y + 75), ["F"], "Parry / Guardia")


func _key_row(pos: Vector2, keys: Array, label: String) -> void:
	var x := pos.x
	for k in keys:
		var kw := 22.0 + 8.0 * float(maxi(0, String(k).length() - 1))
		canvas.draw_style_box(key_box, Rect2(x, pos.y, kw, 20))
		canvas.draw_string(font, Vector2(x, pos.y + 15), String(k), HORIZONTAL_ALIGNMENT_CENTER, kw, 13, Color(0.9, 0.96, 1.0))
		x += kw + 4.0
	canvas.draw_string(font, Vector2(x + 6.0, pos.y + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.78, 0.86, 0.95))
