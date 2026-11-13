extends SceneTree

func _initialize() -> void:
	var packed: PackedScene = load("res://main.tscn")
	var m = packed.instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	print("suelo x=-20: ", snappedf(m.floor_y(-20.0), 0.01), "  x=0: ", snappedf(m.floor_y(0.0), 0.01), "  x=20: ", snappedf(m.floor_y(20.0), 0.01))
	for i in range(90):
		await physics_frame
	print("ninja: x=", snappedf(m.player.global_position.x, 0.01), " y=", snappedf(m.player.global_position.y, 0.01), " en suelo=", m.player.is_on_floor())
	m.override_x = 1.0
	for i in range(200):
		await physics_frame
	print("corrio a la derecha: x=", snappedf(m.player.global_position.x, 0.1), " y=", snappedf(m.player.global_position.y, 0.01), " suelo esperado=", snappedf(m.floor_y(m.player.global_position.x), 0.01), " en suelo=", m.player.is_on_floor())
	for i in range(500):
		await physics_frame
	print("contra la pared derecha: x=", snappedf(m.player.global_position.x, 0.1), " (limite 21.4)")
	m.override_x = -1.0
	for i in range(700):
		await physics_frame
	print("contra la pared izquierda: x=", snappedf(m.player.global_position.x, 0.1), " y=", snappedf(m.player.global_position.y, 0.01))
	m.override_x = 0.0
	var boss = m.robots[m.robots.size() - 1]
	print("guardian: hp=", boss.hp, " x=", snappedf(boss.position.x, 0.1), " y=", snappedf(boss.position.y, 0.01), " visible=", boss.visible)
	boss.position.x = m.player.global_position.x + 2.2
	m.facing = 1.0
	m._on_attack()
	for i in range(110):
		await physics_frame
	m._on_attack()
	for i in range(30):
		await physics_frame
	m._on_attack()
	for i in range(60):
		await physics_frame
	print("tras combo: hp guardian=", boss.hp, " act=", m.act)
	quit(0)
