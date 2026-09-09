extends Control
## Replaceable vector-and-type demonstration art. All gameplay lives in BattleModel.
const BattleModel = preload("res://scripts/battle_model.gd")
const INK := Color("302e28")
const PAPER := Color("eae0c9")
const RED := Color("a84435")
const GREEN := Color("3f675b")
const GOLD := Color("ae803c")
var model = BattleModel.new()
var font: Font
var ui_font: Font
var floats: Array[Dictionary] = []
var buttons: Array[Dictionary] = []
var tab := 0
var screen := "battle"
var bank := 0
var permanent := 0
var bank_before := 0
var save_error := ""
var save_path := "user://campaign_v1.json"
var accumulator := 0.0

func _ready() -> void:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["KaiTi", "STKaiti", "Microsoft YaHei", "sans-serif"])
	font = f
	var u := SystemFont.new()
	u.font_names = PackedStringArray(["Microsoft YaHei", "sans-serif"])
	ui_font = u
	if FileAccess.file_exists("res://assets/fonts/demo.ttf"):
		font = load("res://assets/fonts/demo.ttf")
		ui_font = font
	if "--demo-test" in OS.get_cmdline_user_args():
		save_path = "user://test_campaign_v1.json"
	load_campaign()
	model.reset(permanent)
	model.feedback.connect(func(t: String, p: Vector2, c: Color):
		floats.append({"text": t, "pos": p, "color": c, "life": 1.0}))
	model.finished.connect(_on_finished)
	if "--capture-demo" in OS.get_cmdline_user_args():
		model.buy("bow")
		for i in range(1900):
			model.tick(1.0 / 60.0)
		set_process(false)
		floats.clear()
		model.spawn_drop()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://demo_preview.png")
		get_tree().quit()

func load_campaign() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path))
	if data is Dictionary and int(data.get("version", 0)) == 1:
		bank = maxi(0, int(data.get("jade", 0)))
		permanent = maxi(0, int(data.get("training", 0)))

func save_campaign() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		save_error = "存档失败，请保持窗口开启后重试"
		return false
	file.store_string(JSON.stringify({"version": 1, "jade": bank, "training": permanent}))
	file.close()
	save_error = ""
	return true

func _on_finished(_victory: bool, amount: int) -> void:
	bank_before = bank
	bank += amount
	save_campaign()
	screen = "result"

func _process(delta: float) -> void:
	accumulator += minf(delta, 0.15)
	while accumulator >= 1.0 / 60.0:
		if screen == "battle":
			model.tick(1.0 / 60.0)
		accumulator -= 1.0 / 60.0
	if not model.paused:
		for i in range(floats.size() - 1, -1, -1):
			floats[i].life -= delta
			floats[i].pos.y -= delta * 27
			if floats[i].life <= 0:
				floats.remove_at(i)
	queue_redraw()

func transform_info() -> Vector3:
	var scale_factor := minf(size.x / 720.0, size.y / 1280.0)
	return Vector3((size.x - 720 * scale_factor) * 0.5, (size.y - 1280 * scale_factor) * 0.5, scale_factor)

func _gui_input(event: InputEvent) -> void:
	var point := Vector2.ZERO
	var accepted := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		point = event.position
		accepted = true
	elif event is InputEventScreenTouch and event.pressed:
		point = event.position
		accepted = true
	if not accepted:
		return
	var tr := transform_info()
	point = (point - Vector2(tr.x, tr.y)) / tr.z
	for item in buttons:
		if item.rect.has_point(point):
			if item.enabled:
				action(item.id)
			accept_event()
			return
	if screen == "battle":
		model.collect(point)

func action(id: String) -> void:
	if id.begins_with("tab_"):
		tab = int(id.trim_prefix("tab_"))
	elif id.begins_with("buy_"):
		model.buy(id.trim_prefix("buy_"))
	else:
		match id:
			"pause": model.paused = true
			"resume": model.paused = false
			"retreat": model.finish(false)
			"restart":
				if not save_error.is_empty() and not save_campaign():
					return
				model.reset(permanent)
				floats.clear()
				screen = "battle"
			"training":
				var price := 8 + permanent * 5
				if bank >= price:
					bank -= price
					permanent += 1
					save_campaign()

func label_at(value: String, point: Vector2, size_px: int = 24, color: Color = INK, centered: bool = false, brush: bool = false) -> void:
	var selected_font: Font = font if brush else ui_font
	var width := selected_font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
	draw_string(selected_font, point - Vector2(width * 0.5 if centered else 0.0, 0), value, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)

func panel(rect: Rect2, fill: Color = PAPER, border: Color = INK) -> void:
	draw_rect(Rect2(rect.position + Vector2(0, 4), rect.size), Color(0.18, 0.14, 0.09, 0.16))
	draw_rect(rect, fill)
	draw_rect(rect, border, false, 2.0)
	draw_line(rect.position + Vector2(5, 5), rect.position + Vector2(rect.size.x - 5, 5), Color(1, 1, 1, 0.3), 1)

func button(id: String, rect: Rect2, title: String, enabled: bool = true, filled: bool = false) -> void:
	panel(rect, RED if filled else Color("f5ecdb"), RED if filled else Color("ac9a7a"))
	label_at(title, rect.get_center() + Vector2(0, 9), 25, Color("fff1d6") if filled else (INK if enabled else Color("ac9f89")), true)
	buttons.append({"id": id, "rect": rect, "enabled": enabled})

func bar(rect: Rect2, ratio: float, tint: Color) -> void:
	draw_rect(rect, Color("c6bda9"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), tint)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("272a26"))
	var tr := transform_info()
	draw_set_transform(Vector2(tr.x, tr.y), 0, Vector2.ONE * tr.z)
	buttons.clear()
	background()
	header()
	world()
	footer()
	if screen == "result":
		result_panel()
	elif model.paused:
		pause_panel()
	draw_set_transform(Vector2.ZERO)

func background() -> void:
	draw_rect(Rect2(0, 0, 720, 1280), PAPER)
	# Deterministic stippled paper and distant hand-drawn hills.
	for i in range(550):
		var p := Vector2(fmod(i * 127.7, 720), fmod(i * 73.37, 1280))
		draw_circle(p, 0.7 + (i % 3) * 0.3, Color(0.34, 0.27, 0.14, 0.045))
	for row in range(3):
		var points := PackedVector2Array()
		for i in range(25):
			points.append(Vector2(i * 30, 220 + row * 70 - abs(sin(i * 0.48 + row)) * 80))
		draw_polyline(points, Color(0.35, 0.39, 0.33, 0.08), 2.5, true)
	for i in range(14):
		var x := 28.0 if i % 2 == 0 else 686.0
		var y := 450 + i * 35.0
		draw_line(Vector2(x, y), Vector2(x - 9, y - 13), Color("b7b59c"), 2, true)
		draw_line(Vector2(x, y), Vector2(x + 6, y - 18), Color("b7b59c"), 1, true)
	label_at("长 坂 · 守 军", Vector2(360, 875), 42, Color(0.29, 0.3, 0.23, 0.09), true, true)

func header() -> void:
	label_at("墨阵三国", Vector2(30, 46), 30, INK, false, true)
	label_at("战斗演示 · 长坂守备", Vector2(574, 44), 18, Color("82745e"), true)
	draw_line(Vector2(28, 60), Vector2(692, 60), Color("b9a984"), 1)
	label_at("%d / %d 波" % [model.wave, model.config.total_waves], Vector2(30, 104), 28, RED, false, true)
	bar(Rect2(182, 79, 368, 12), model.wave_clock / model.wave_duration if model.wave < model.config.total_waves else 1, GOLD)
	label_at("下波来袭  %.1f 秒" % maxf(0, model.wave_duration - model.wave_clock) if model.wave < model.config.total_waves else "末波已至 · 清剿残敌", Vector2(183, 118), 19, Color("776a55"))
	button("pause", Rect2(595, 73, 96, 49), "暂停")
	panel(Rect2(28, 140, 322, 60), Color("e3d3ad"), Color("baa579"))
	label_at("粮", Vector2(47, 182), 37, GOLD, false, true)
	label_at("%d" % model.grain, Vector2(104, 181), 31)
	label_at("局内强化", Vector2(242, 178), 19, Color("776a55"))
	panel(Rect2(370, 140, 322, 60), Color("d9dfd0"), Color("9ba890"))
	label_at("玉", Vector2(389, 182), 37, GREEN, false, true)
	label_at("%d" % model.jade, Vector2(446, 181), 31)
	label_at("本局采集", Vector2(584, 178), 19, Color("5b7264"))

func resource_site(center: Vector2, glyph: String, name_text: String, progress: float, tint: Color) -> void:
	draw_circle(center, 44, Color(tint, 0.09))
	draw_arc(center, 39, 0, TAU, 48, Color(tint, 0.25), 2, true)
	label_at(glyph, center + Vector2(0, 16), 48, tint, true, true)
	var worker := center + Vector2(cos(model.elapsed * 1.7), sin(model.elapsed * 1.7)) * 39
	label_at("农", worker + Vector2(0, 7), 20, INK, true, true)
	label_at(name_text, center + Vector2(0, 68), 19, tint, true)
	bar(Rect2(center + Vector2(-44, 78), Vector2(88, 5)), progress, tint)

func world() -> void:
	resource_site(Vector2(155, 260), "禾", "粮田 · 局内", model.grain_clock / model.config.grain_interval, GOLD)
	resource_site(Vector2(565, 260), "玉", "玉矿 · 局外", model.jade_clock / model.config.jade_interval, GREEN)
	# Stationary fortified base.
	panel(Rect2(248, 301, 224, 105), Color("d2c2a3"), Color("696a57"))
	for i in range(7):
		draw_rect(Rect2(250 + i * 32, 290, 20, 22), Color("696a57"))
	label_at("蜀", Vector2(360, 365), 61, INK, true, true)
	label_at("长坂主营", Vector2(360, 392), 19, INK, true)
	bar(Rect2(260, 280, 200, 9), model.hp / model.max_hp, GREEN)
	label_at("%d / %d" % [int(model.hp), int(model.max_hp)], Vector2(360, 269), 19, GREEN, true)
	draw_line(Vector2(473, 307), Vector2(473, 247), INK, 3)
	draw_colored_polygon(PackedVector2Array([Vector2(474, 248), Vector2(506, 251), Vector2(500, 281), Vector2(474, 278)]), RED)
	label_at("蜀", Vector2(487, 271), 20, PAPER, true, true)
	for i in range(2):
		var x := 265 + i * 190
		var active: bool = i == 0 or model.bow_open
		panel(Rect2(x - 65, 422, 130, 65), Color("eee5d1"), GREEN if active else Color("b2aa98"))
		label_at("刀营" if i == 0 else "弓营", Vector2(x, 457), 28, GREEN if active else Color("a69a84"), true, true)
		bar(Rect2(x - 53, 470, 106, 5), model.sword_clock / maxf(1.2, model.config.sword.spawn_interval * pow(0.85, model.level("recruit"))) if i == 0 else (model.bow_clock / (model.config.bow.spawn_interval * pow(0.85, model.level("recruit"))) if active else 0.0), GREEN)
	label_at("自动出兵 %d / %d" % [model.count_side(true), model.config.ally_cap], Vector2(360, 515), 17, Color("7a7b68"), true)
	var ordered: Array = model.units.duplicate()
	ordered.sort_custom(func(a, b): return a.pos.y < b.pos.y)
	for unit in ordered:
		draw_unit(unit)
	for effect in model.effects:
		var tint := GOLD if effect.bow else (GREEN if effect.ally else RED)
		draw_line(effect.from, effect.to, tint, 2 if effect.bow else 4, true)
		draw_arc(effect.to, 17, -1.2, 1.2, 8, tint, 2, true)
	for drop in model.drops:
		var p: Vector2 = drop.pos
		draw_circle(p, 32 + sin(model.elapsed * 5) * 2, Color("ecd08a"))
		draw_arc(p, 34, -PI / 2, -PI / 2 + TAU * drop.life / model.config.drop_lifetime, 36, GOLD, 3, true)
		label_at("粮", p + Vector2(0, 12), 36, INK, true, true)
		label_at("点击  %ds" % ceili(drop.life), p + Vector2(0, 51), 18, RED, true)
	for item in floats:
		var tint: Color = item.color
		tint.a = minf(1, item.life * 2)
		label_at(item.text, item.pos, 22, tint, true)
	label_at("↓ 敌军由下方进入战场 ↓", Vector2(360, 990), 18, Color("938773"), true)

func draw_unit(unit: Dictionary) -> void:
	var p: Vector2 = unit.pos
	var is_boss: bool = unit.kind == "boss"
	var sz := 53 if is_boss else 37
	var tint := GREEN if unit.ally else RED
	if unit.flash > 0:
		tint = Color("d8994a")
	var tr := transform_info()
	# Compose local unit pose with the logical canvas transform.
	var canvas := Transform2D(0, Vector2.ONE * tr.z, 0, Vector2(tr.x, tr.y))
	draw_set_transform_matrix(canvas * Transform2D(0, Vector2(1, 0.3), 0, p + Vector2(0, 15)))
	draw_circle(Vector2.ZERO, 18, Color(0.15, 0.12, 0.08, 0.12))
	var angle: float = sin(model.elapsed * 10 + unit.id) * 0.08 if unit.walking else sin(model.elapsed * 2 + unit.id) * 0.025
	var pose := Transform2D(angle, Vector2(1, 1.06), -0.11 if unit.ally else 0.08, p)
	draw_set_transform_matrix(canvas * pose)
	var glyph := "刀" if unit.kind == "sword" else ("弓" if unit.kind == "bow" else ("盾" if unit.kind == "shield" else ("将" if is_boss else "卒")))
	label_at(glyph, Vector2(0, 12), sz, tint, true, true)
	# Spear, bow or blade strokes turn the glyph into an animated soldier.
	if unit.kind == "bow":
		draw_arc(Vector2(20, -4), 18, -1.4, 1.4, 12, GOLD, 2, true)
		draw_line(Vector2(23, -22), Vector2(23, 14), INK, 1, true)
	else:
		draw_line(Vector2(21, 17), Vector2(27, -28), INK, 2, true)
		draw_colored_polygon(PackedVector2Array([Vector2(23, -25), Vector2(29, -36), Vector2(31, -22)]), GOLD if unit.ally else INK)
	draw_line(Vector2(-12, -25), Vector2(10, -25), tint, 4, true)
	draw_line(Vector2(9, -25), Vector2(18, -19), tint, 2, true)
	draw_set_transform_matrix(canvas)
	if unit.hp < unit.max_hp or is_boss:
		bar(Rect2(p + Vector2(-20, -37), Vector2(40, 4)), unit.hp / unit.max_hp, tint)

func footer() -> void:
	draw_rect(Rect2(0, 1014, 720, 266), Color("d9cbb1"))
	draw_line(Vector2(0, 1014), Vector2(720, 1014), INK, 3)
	for i in range(3):
		button("tab_%d" % i, Rect2(28 + i * 232, 1030, 218, 47), ["主城", "采集", "兵营"][i], true, tab == i)
	var keys: Array = [["repair", "wall"], ["grain", "jade"], ["sword", "recruit", "bow"]][tab]
	var titles := {"repair": "修缮城防", "wall": "加固城墙", "grain": "粮田增产", "jade": "玉矿增产", "sword": "刀兵训练", "recruit": "征兵提速", "bow": "弓营"}
	var details := {"repair": "恢复 70 生命", "wall": "生命上限 +60", "grain": "每次产粮 +3", "jade": "每次采玉 +1", "sword": "攻击 +25% / 生命 +22%", "recruit": "出兵间隔缩短 15%", "bow": "解锁远程弓兵" if not model.bow_open else "弓兵攻击、生命提升"}
	var width: float = (664.0 - (keys.size() - 1) * 12) / keys.size()
	for i in range(keys.size()):
		var key: String = keys[i]
		var rect := Rect2(28 + i * (width + 12), 1090, width, 131)
		var enabled: bool = model.grain >= model.cost(key) and not (key == "repair" and model.hp >= model.max_hp)
		panel(rect, Color("f2e8d3"), Color("b09a72"))
		label_at(titles[key], rect.position + Vector2(13, 30), 25, INK, false, true)
		label_at("%d阶" % model.level(key), rect.position + Vector2(width - 55, 28), 16, GOLD)
		label_at(details[key], rect.position + Vector2(13, 62), 16, Color("776c58"))
		button("buy_" + key, Rect2(rect.position + Vector2(9, 79), Vector2(width - 18, 43)), "粮 %d" % model.cost(key), enabled)
	label_at("玉石战败全额保留  ·  散落粮草需点击拾取", Vector2(360, 1256), 18, Color("7d6e55"), true)

func pause_panel() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.13, 0.14, 0.12, 0.65))
	panel(Rect2(90, 416, 540, 366), PAPER, GOLD)
	label_at("鸣金暂歇", Vector2(360, 485), 48, INK, true, true)
	label_at("战斗、采集与掉落计时均已暂停", Vector2(360, 537), 23, Color("7d6e55"), true)
	button("resume", Rect2(145, 583, 430, 61), "继续守城", true, true)
	button("retreat", Rect2(145, 665, 430, 61), "撤退结算 · 玉石全部带走")

func result_panel() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.13, 0.14, 0.12, 0.72))
	panel(Rect2(75, 315, 570, 670), PAPER, GOLD)
	label_at("守城告捷" if model.won else "整军再战", Vector2(360, 400), 56, RED, true, true)
	label_at("抵御 %d / %d 波 · 坚守 %d 秒" % [model.wave, model.config.total_waves, int(model.elapsed)], Vector2(360, 450), 23, INK, true)
	label_at("本局玉石全部入库", Vector2(360, 507), 24, GREEN, true)
	label_at("+ %d 玉" % model.jade, Vector2(360, 565), 48, GREEN, true, true)
	label_at("府库 %d 玉  ·  永久练兵 %d 阶" % [bank, permanent], Vector2(360, 617), 24, INK, true)
	label_at("永久练兵：下局主城生命 +20，士兵攻击 +5%", Vector2(360, 659), 20, Color("7d6e55"), true)
	button("training", Rect2(130, 696, 460, 62), "永久练兵 · %d 玉" % (8 + permanent * 5), bank >= 8 + permanent * 5)
	button("restart", Rect2(130, 786, 460, 65), "再守一局", true, true)
	label_at(save_error if not save_error.is_empty() else "已自动保存 · 局内粮草与强化下局重置", Vector2(360, 917), 19, RED if not save_error.is_empty() else Color("7d6e55"), true)
