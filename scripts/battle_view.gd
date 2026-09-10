extends Control
## Replaceable vector-and-type demonstration art. All gameplay lives in BattleModel.
const BattleModel = preload("res://scripts/battle_model.gd")
const INK := Color("302e28")
const PAPER := Color("eae0c9")
const RED := Color("a84435")
const GREEN := Color("3f675b")
const GOLD := Color("ae803c")
const AVATAR_GLYPHS := ["将", "赵", "关", "张", "诸", "马", "黄", "魏", "吕", "孙", "周", "司"]
const TEST_UNLOCKED_AVATARS := 6
const AVATAR_SCROLL_MAX := 145.0
var model = BattleModel.new()
var font: Font
var ui_font: Font
var floats: Array[Dictionary] = []
var buttons: Array[Dictionary] = []
var tab := 0
var barracks_kind := "sword"
var screen := "home"
var modal := ""
var modal_title := ""
var bank := 0
var permanent := 0
var bank_before := 0
var save_error := ""
var save_path := "user://campaign_v1.json"
var accumulator := 0.0
var settings := {"music": true, "sound": true, "damage_numbers": true}
var profile_stats := {"challenge_count": 0, "best_progress": 0, "avatars": TEST_UNLOCKED_AVATARS, "campaigns": 0, "talents": 0}
var current_avatar := 0
var selected_avatar := 0
var avatar_scroll := 0.0
var avatar_pointer_dragging := false
var avatar_drag_origin := Vector2.ZERO
var avatar_scroll_origin := 0.0

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
		if bool(settings.damage_numbers) or not t.begins_with("-"):
			floats.append({"text": t, "pos": p, "color": c, "life": 1.0}))
	model.finished.connect(_on_finished)
	if "--capture-avatar" in OS.get_cmdline_user_args():
		screen = "home"
		modal = "avatar"
		avatar_scroll = AVATAR_SCROLL_MAX
		set_process(false)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://avatar_preview.png")
		get_tree().quit()
	if "--capture-profile" in OS.get_cmdline_user_args():
		screen = "home"
		modal = "profile"
		set_process(false)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://profile_preview.png")
		get_tree().quit()
	if "--capture-demo" in OS.get_cmdline_user_args():
		model.buy("bow_unlock")
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
		var saved_settings: Dictionary = data.get("settings", {})
		settings.music = bool(saved_settings.get("music", true))
		settings.sound = bool(saved_settings.get("sound", true))
		settings.damage_numbers = bool(saved_settings.get("damage_numbers", true))
		var saved_stats: Dictionary = data.get("profile_stats", {})
		for key in profile_stats:
			profile_stats[key] = maxi(0, int(saved_stats.get(key, profile_stats[key])))
		profile_stats.avatars = maxi(TEST_UNLOCKED_AVATARS, int(profile_stats.avatars))
		current_avatar = clampi(int(data.get("current_avatar", 0)), 0, TEST_UNLOCKED_AVATARS - 1)
		selected_avatar = current_avatar

func save_campaign() -> bool:
	var file := FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		save_error = "存档失败，请保持窗口开启后重试"
		return false
	file.store_string(JSON.stringify({"version": 1, "jade": bank, "training": permanent,
		"settings": settings, "profile_stats": profile_stats, "current_avatar": current_avatar}))
	file.close()
	save_error = ""
	return true

func _on_finished(_victory: bool, amount: int) -> void:
	bank_before = bank
	bank += amount
	var progress := roundi(float(model.wave) / float(model.config.total_waves) * 100.0)
	profile_stats.best_progress = maxi(int(profile_stats.best_progress), progress)
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
	if modal == "avatar":
		if event is InputEventScreenTouch:
			if event.pressed:
				begin_avatar_drag(event.position)
			else:
				finish_avatar_drag(event.position)
			accept_event()
			return
		if event is InputEventScreenDrag and avatar_pointer_dragging:
			update_avatar_drag(event.position)
			accept_event()
			return
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				avatar_scroll = minf(AVATAR_SCROLL_MAX, avatar_scroll + 65.0)
				accept_event()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				avatar_scroll = maxf(0.0, avatar_scroll - 65.0)
				accept_event()
				return
			elif event.button_index == MOUSE_BUTTON_LEFT:
				begin_avatar_drag(event.position)
				accept_event()
				return
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			finish_avatar_drag(event.position)
			accept_event()
			return
		if event is InputEventMouseMotion and avatar_pointer_dragging:
			update_avatar_drag(event.position)
			accept_event()
			return
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

func begin_avatar_drag(point: Vector2) -> void:
	avatar_pointer_dragging = true
	avatar_drag_origin = point
	avatar_scroll_origin = avatar_scroll

func update_avatar_drag(point: Vector2) -> void:
	var tr := transform_info()
	var moved_y := (point.y - avatar_drag_origin.y) / tr.z
	avatar_scroll = clampf(avatar_scroll_origin - moved_y, 0.0, AVATAR_SCROLL_MAX)

func finish_avatar_drag(point: Vector2) -> void:
	if not avatar_pointer_dragging:
		return
	var was_click := point.distance_to(avatar_drag_origin) < 8.0
	avatar_pointer_dragging = false
	if not was_click:
		return
	var tr := transform_info()
	var design_point := (point - Vector2(tr.x, tr.y)) / tr.z
	for item in buttons:
		if item.rect.has_point(design_point):
			if item.enabled:
				action(item.id)
			return

func action(id: String) -> void:
	if id.begins_with("tab_"):
		tab = int(id.trim_prefix("tab_"))
	elif id.begins_with("barracks_"):
		barracks_kind = id.trim_prefix("barracks_")
	elif id.begins_with("avatar_choice_"):
		var index := int(id.trim_prefix("avatar_choice_"))
		if index < TEST_UNLOCKED_AVATARS:
			selected_avatar = index
	elif id.begins_with("buy_"):
		model.buy(id.trim_prefix("buy_"))
	else:
		match id:
			"profile": modal = "profile"
			"avatar_picker":
				selected_avatar = current_avatar
				avatar_scroll = 0.0
				modal = "avatar"
			"close_avatar": modal = "profile"
			"apply_avatar":
				if selected_avatar != current_avatar and selected_avatar < TEST_UNLOCKED_AVATARS:
					current_avatar = selected_avatar
					save_campaign()
			"close_modal": modal = ""
			"start_battle":
				model.reset(permanent)
				floats.clear()
				modal = ""
				screen = "battle"
				profile_stats.challenge_count = int(profile_stats.challenge_count) + 1
				save_campaign()
			"home":
				modal = ""
				screen = "home"
			"entry_campaign", "entry_shop", "entry_strategy", "entry_training", "entry_bug", "entry_suggestion":
				modal_title = {"entry_campaign": "战役", "entry_shop": "商肆", "entry_strategy": "军略", "entry_training": "校场", "entry_bug": "BUG反馈", "entry_suggestion": "建议反馈"}[id]
				modal = "coming"
			"toggle_music":
				settings.music = not bool(settings.music)
				save_campaign()
			"toggle_sound":
				settings.sound = not bool(settings.sound)
				save_campaign()
			"toggle_damage_numbers":
				settings.damage_numbers = not bool(settings.damage_numbers)
				save_campaign()
			"pause": model.paused = true
			"resume": model.paused = false
			"retreat": model.finish(false)
			"restart":
				if not save_error.is_empty() and not save_campaign():
					return
				model.reset(permanent)
				floats.clear()
				screen = "battle"
				profile_stats.challenge_count = int(profile_stats.challenge_count) + 1
				save_campaign()
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

func setting_toggle(id: String, rect: Rect2, title: String, active: bool) -> void:
	panel(rect, Color("e0b947") if active else Color("d4d0c6"), Color("7f735e"))
	label_at("%s  %s" % [title, "开" if active else "关"], rect.get_center() + Vector2(0, 8), 21, INK, true, true)
	buttons.append({"id": id, "rect": rect, "enabled": true})

func bar(rect: Rect2, ratio: float, tint: Color) -> void:
	draw_rect(rect, Color("c6bda9"))
	draw_rect(Rect2(rect.position, Vector2(rect.size.x * clampf(ratio, 0, 1), rect.size.y)), tint)

func resource_counter(center: Vector2, glyph: String, amount: int, tint: Color) -> void:
	draw_circle(center, 16, Color(tint, 0.13))
	draw_arc(center, 15, 0, TAU, 32, tint, 2, true)
	label_at(glyph, center + Vector2(0, 7), 20, tint, true, true)
	label_at("%d" % amount, center + Vector2(25, 8), 23, INK)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("272a26"))
	var tr := transform_info()
	draw_set_transform(Vector2(tr.x, tr.y), 0, Vector2.ONE * tr.z)
	buttons.clear()
	background()
	if screen == "home":
		home_screen()
	else:
		header()
		world()
		footer()
		if screen == "result":
			result_panel()
		elif model.paused:
			pause_panel()
	if modal == "profile":
		profile_panel()
	elif modal == "avatar":
		avatar_panel()
	elif modal == "coming":
		coming_panel()
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

func home_screen() -> void:
	label_at("长坂行营", Vector2(28, 45), 29, INK, false, true)
	draw_line(Vector2(28, 58), Vector2(692, 58), Color("b9a984"), 1)
	# Player portrait doubles as the personal-information entry.
	panel(Rect2(28, 78, 112, 112), Color("d8c8aa"), Color("746955"))
	draw_circle(Vector2(84, 126), 31, Color("69766c"))
	label_at(AVATAR_GLYPHS[current_avatar], Vector2(84, 140), 45, PAPER, true, true)
	label_at("无名校尉", Vector2(84, 178), 16, INK, true)
	buttons.append({"id": "profile", "rect": Rect2(28, 78, 112, 112), "enabled": true})
	resource_counter(Vector2(615, 35), "玉", bank, GREEN)

	# The central seal is temporary typographic art and can be replaced independently later.
	draw_circle(Vector2(360, 389), 145, Color(0.37, 0.32, 0.22, 0.06))
	draw_arc(Vector2(360, 389), 137, -2.8, 2.8, 64, Color("a99776"), 3, true)
	label_at("蜀", Vector2(360, 424), 144, Color("665d4c"), true, true)
	label_at("墨 阵 三 国", Vector2(360, 493), 35, INK, true, true)
	label_at("聚将于营 · 决胜长坂", Vector2(360, 531), 20, Color("83755f"), true)

	button("start_battle", Rect2(88, 806, 544, 88), "开始守城", true, true)

	var nav_ids := ["entry_shop", "entry_campaign", "entry_strategy", "entry_training"]
	var nav_titles := ["商肆", "战役", "军略", "校场"]
	for i in range(4):
		var x := 22 + i * 174
		button(nav_ids[i], Rect2(x, 1140, 154, 92), nav_titles[i])

func profile_panel() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.10, 0.11, 0.10, 0.58))
	draw_rect(Rect2(66, 210, 588, 850), Color("302e28"))
	draw_rect(Rect2(66, 210, 588, 850), GOLD, false, 3)

	panel(Rect2(92, 252, 132, 132), Color("d8c8aa"), Color("746955"))
	draw_circle(Vector2(158, 308), 41, Color("69766c"))
	label_at(AVATAR_GLYPHS[current_avatar], Vector2(158, 325), 58, PAPER, true, true)
	label_at("无名校尉", Vector2(158, 369), 16, INK, true)
	buttons.append({"id": "avatar_picker", "rect": Rect2(92, 252, 132, 132), "enabled": true})
	panel(Rect2(250, 257, 365, 52), Color("e8dfcd"), Color("9d9078"))
	label_at("称号：无名校尉", Vector2(432, 290), 21, INK, true)
	panel(Rect2(250, 325, 365, 52), Color("e8dfcd"), Color("9d9078"))
	label_at("UID：等待账号系统接入", Vector2(432, 358), 18, Color("6f6656"), true)

	setting_toggle("toggle_music", Rect2(88, 414, 170, 55), "音乐", bool(settings.music))
	setting_toggle("toggle_sound", Rect2(275, 414, 170, 55), "音效", bool(settings.sound))
	setting_toggle("toggle_damage_numbers", Rect2(462, 414, 170, 55), "伤害数字", bool(settings.damage_numbers))

	panel(Rect2(88, 504, 544, 365), Color("e8dfcd"), Color("9d9078"))
	label_at("挑战信息", Vector2(360, 550), 29, INK, true, true)
	draw_line(Vector2(112, 570), Vector2(608, 570), Color("b9a984"), 1)
	var stat_titles := ["挑战次数", "最高挑战进度", "头像收集数量", "战役完成数量", "天赋解锁数量"]
	var stat_values := ["%d 次" % int(profile_stats.challenge_count), "%d%%" % int(profile_stats.best_progress), "%d" % int(profile_stats.avatars), "%d" % int(profile_stats.campaigns), "%d" % int(profile_stats.talents)]
	for i in range(stat_titles.size()):
		var y := 618 + i * 54
		label_at(stat_titles[i], Vector2(118, y), 20, INK)
		label_at(stat_values[i], Vector2(590, y), 22, GREEN if i == 1 else INK, true)
		if i < stat_titles.size() - 1:
			draw_line(Vector2(112, y + 17), Vector2(608, y + 17), Color(0.45, 0.4, 0.3, 0.22), 1)

	button("entry_bug", Rect2(88, 910, 258, 66), "BUG反馈")
	button("entry_suggestion", Rect2(374, 910, 258, 66), "建议反馈")
	draw_circle(Vector2(630, 222), 31, Color("302e28"))
	draw_circle(Vector2(630, 222), 29, Color("f1e7d3"))
	label_at("×", Vector2(630, 232), 34, INK, true)
	buttons.append({"id": "close_modal", "rect": Rect2(598, 190, 64, 64), "enabled": true})

func avatar_panel() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.10, 0.11, 0.10, 0.58))
	draw_rect(Rect2(66, 210, 588, 850), Color("302e28"))
	draw_rect(Rect2(66, 210, 588, 850), GOLD, false, 3)
	label_at("当前头像", Vector2(360, 260), 27, PAPER, true, true)
	draw_avatar_tile(Rect2(285, 282, 150, 142), current_avatar, true, selected_avatar == current_avatar)
	label_at("选择头像", Vector2(102, 470), 24, PAPER, false, true)
	draw_line(Vector2(102, 484), Vector2(618, 484), Color("8e8068"), 1)

	var grid_top := 505.0
	for index in range(AVATAR_GLYPHS.size()):
		var row := index / 3
		var column := index % 3
		var rect := Rect2(94 + column * 177, grid_top + row * 145 - avatar_scroll, 150, 132)
		if rect.end.y > 495 and rect.position.y < 925:
			var unlocked := index < TEST_UNLOCKED_AVATARS
			draw_avatar_tile(rect, index, unlocked, selected_avatar == index)
			if unlocked:
				buttons.append({"id": "avatar_choice_%d" % index, "rect": rect, "enabled": true})
	# Mask only the overflow; partially visible edge rows show that the list continues.
	draw_rect(Rect2(66, 470, 588, 25), Color("302e28"))
	draw_rect(Rect2(66, 925, 588, 25), Color("302e28"))
	label_at("选择头像", Vector2(102, 470), 24, PAPER, false, true)
	draw_line(Vector2(102, 484), Vector2(618, 484), Color("8e8068"), 1)
	var scroll_ratio := avatar_scroll / AVATAR_SCROLL_MAX
	draw_rect(Rect2(632, 505, 5, 412), Color("5e584d"))
	draw_rect(Rect2(632, 505 + scroll_ratio * 292, 5, 120), Color("d2bd8b"))
	avatar_change_button(Rect2(190, 955, 340, 67))
	draw_circle(Vector2(90, 222), 31, Color("302e28"))
	draw_circle(Vector2(90, 222), 29, Color("f1e7d3"))
	label_at("←", Vector2(90, 232), 32, INK, true)
	buttons.append({"id": "close_avatar", "rect": Rect2(58, 190, 64, 64), "enabled": true})

func draw_avatar_tile(rect: Rect2, index: int, unlocked: bool, selected: bool) -> void:
	panel(rect, Color("d8c8aa"), GOLD if selected else Color("746955"))
	draw_circle(rect.position + Vector2(rect.size.x * 0.5, 52), 35, Color("69766c"))
	label_at(AVATAR_GLYPHS[index], rect.position + Vector2(rect.size.x * 0.5, 66), 48, PAPER, true, true)
	label_at("头像 %02d" % (index + 1), rect.position + Vector2(rect.size.x * 0.5, 116), 16, INK, true)
	if not unlocked:
		draw_rect(rect, Color(0.22, 0.22, 0.22, 0.66))
		var lock_center := rect.get_center() + Vector2(0, -4)
		draw_arc(lock_center + Vector2(0, -8), 13, PI, TAU, 16, PAPER, 4, true)
		draw_rect(Rect2(lock_center + Vector2(-16, -7), Vector2(32, 29)), PAPER)
		label_at("锁", lock_center + Vector2(0, 15), 18, INK, true, true)

func avatar_change_button(rect: Rect2) -> void:
	var enabled := selected_avatar != current_avatar and selected_avatar < TEST_UNLOCKED_AVATARS
	panel(rect, Color("e0b947") if enabled else Color("d4d0c6"), Color("7f735e"))
	label_at("更换头像", rect.get_center() + Vector2(0, 9), 25, INK if enabled else Color("8d887d"), true, true)
	buttons.append({"id": "apply_avatar", "rect": rect, "enabled": enabled})

func coming_panel() -> void:
	buttons.clear()
	draw_rect(Rect2(0, 0, 720, 1280), Color(0.13, 0.14, 0.12, 0.66))
	panel(Rect2(105, 435, 510, 350), PAPER, GOLD)
	label_at(modal_title, Vector2(360, 535), 52, RED, true, true)
	label_at("入口已经开放", Vector2(360, 596), 25, INK, true)
	label_at("具体玩法将在后续版本制作", Vector2(360, 641), 21, Color("7d6e55"), true)
	button("close_modal", Rect2(160, 690, 400, 57), "返回行营", true, true)

func header() -> void:
	label_at("墨阵三国", Vector2(30, 46), 30, INK, false, true)
	resource_counter(Vector2(508, 35), "粮", model.grain, GOLD)
	resource_counter(Vector2(615, 35), "玉", model.jade, GREEN)
	draw_line(Vector2(28, 60), Vector2(692, 60), Color("b9a984"), 1)
	label_at("%d / %d 波" % [model.wave, model.config.total_waves], Vector2(30, 104), 28, RED, false, true)
	var remaining: float = model.wave_remaining()
	var preparing: bool = model.is_intermission()
	var urgent: bool = preparing and remaining <= 5.0
	bar(Rect2(182, 79, 368, 12), remaining / model.wave_duration, RED if urgent or not preparing else GOLD)
	var wave_text := "下波来袭  %.1f 秒" % remaining if preparing else ("末波已至 · 清剿残敌" if model.wave >= model.config.total_waves else "本波交战中 · 敌军 %d" % model.count_side(false))
	label_at(wave_text, Vector2(183, 118), 21 if urgent else 19, RED if urgent or not preparing else Color("776a55"))
	button("pause", Rect2(595, 73, 96, 49), "暂停")

func resource_site(center: Vector2, glyph: String, name_text: String, tint: Color) -> void:
	draw_circle(center, 44, Color(tint, 0.09))
	draw_arc(center, 39, 0, TAU, 48, Color(tint, 0.25), 2, true)
	label_at(glyph, center + Vector2(0, 16), 48, tint, true, true)
	label_at(name_text, center + Vector2(0, 68), 19, tint, true)

func world() -> void:
	resource_site(Vector2(155, 195), "禾", "粮田 · 局内", GOLD)
	resource_site(Vector2(565, 195), "玉", "玉矿 · 局外", GREEN)
	for worker in model.workers:
		draw_line(worker.home, worker.site, Color(0.45, 0.37, 0.23, 0.15), 9, true)
	# Stationary fortified base.
	panel(Rect2(248, 236, 224, 105), Color("d2c2a3"), Color("696a57"))
	for i in range(7):
		draw_rect(Rect2(250 + i * 32, 225, 20, 22), Color("696a57"))
	label_at("蜀", Vector2(360, 300), 61, INK, true, true)
	label_at("长坂主营", Vector2(360, 327), 19, INK, true)
	bar(Rect2(260, 215, 200, 9), model.hp / model.max_hp, GREEN)
	label_at("%d / %d" % [int(model.hp), int(model.max_hp)], Vector2(360, 204), 19, GREEN, true)
	draw_line(Vector2(473, 242), Vector2(473, 182), INK, 3)
	draw_colored_polygon(PackedVector2Array([Vector2(474, 183), Vector2(506, 186), Vector2(500, 216), Vector2(474, 213)]), RED)
	label_at("蜀", Vector2(487, 206), 20, PAPER, true, true)
	for i in range(2):
		var x := 265 + i * 190
		var active: bool = i == 0 or model.bow_open
		panel(Rect2(x - 65, 357, 130, 65), Color("eee5d1"), GREEN if active else Color("b2aa98"))
		label_at("刀营" if i == 0 else "弓营", Vector2(x, 392), 28, GREEN if active else Color("a69a84"), true, true)
		var kind := "sword" if i == 0 else "bow"
		var interval: float = float(model.config[kind].spawn_interval) * pow(0.85, model.level(kind + "_spawn"))
		bar(Rect2(x - 53, 405, 106, 5), (model.sword_clock if i == 0 else model.bow_clock) / interval if active else 0.0, GREEN)
	label_at("自动出兵 %d / %d" % [model.count_side(true), model.config.ally_cap], Vector2(360, 450), 17, Color("7a7b68"), true)
	for worker in model.workers:
		draw_worker(worker)
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
	if tab == 2:
		button("barracks_sword", Rect2(172, 1085, 180, 36), "刀营", true, barracks_kind == "sword")
		button("barracks_bow", Rect2(368, 1085, 180, 36), "弓营" if model.bow_open else "解锁弓营 · 粮%d" % model.cost("bow_unlock"), model.bow_open or model.grain >= model.cost("bow_unlock"), barracks_kind == "bow")
		if barracks_kind == "bow" and not model.bow_open:
			button("buy_bow_unlock", Rect2(190, 1143, 340, 62), "建造弓营 · 粮%d" % model.cost("bow_unlock"), model.grain >= model.cost("bow_unlock"), true)
			label_at("建成后可强化弓兵的三项属性", Vector2(360, 1237), 16, Color("776c58"), true)
			return
	var keys: Array = [["base_hp", "regen_amount", "regen_speed"], ["worker_move", "worker_yield", "worker_harvest", "worker_count"], [barracks_kind + "_damage", barracks_kind + "_attack", barracks_kind + "_spawn"]][tab]
	var titles := {"base_hp": "生命上限", "regen_amount": "回复血量", "regen_speed": "回复速度", "worker_move": "移动速度", "worker_yield": "采集数量", "worker_harvest": "采集速度", "worker_count": "农民个数", "sword_damage": "刀兵伤害", "sword_attack": "刀兵攻速", "sword_spawn": "刀兵产速", "bow_damage": "弓兵伤害", "bow_attack": "弓兵攻速", "bow_spawn": "弓兵产速"}
	var width: float = (664.0 - (keys.size() - 1) * 12) / keys.size()
	for i in range(keys.size()):
		var key: String = keys[i]
		var rect := Rect2(28 + i * (width + 12), 1129 if tab == 2 else 1090, width, 107 if tab == 2 else 131)
		var enabled: bool = model.grain >= model.cost(key)
		panel(rect, Color("f2e8d3"), Color("b09a72"))
		label_at(titles[key], rect.position + Vector2(10, 26), 21 if keys.size() == 4 else 23, INK, false, true)
		label_at("%d阶" % model.level(key), rect.position + Vector2(width - 45, 24), 14, GOLD)
		label_at(attribute_value(key), rect.position + Vector2(10, 51), 14, Color("776c58"))
		button("buy_" + key, Rect2(rect.position + Vector2(8, rect.size.y - 43), Vector2(width - 16, 35)), "%s · 粮%d" % [upgrade_gain(key), model.cost(key)], enabled)
	label_at("玉石战败全额保留  ·  散落粮草需点击拾取", Vector2(360, 1256), 18, Color("7d6e55"), true)

func attribute_value(key: String) -> String:
	match key:
		"base_hp": return "当前 %d" % int(model.max_hp)
		"regen_amount": return "每次 +%d" % (int(model.config.base_regen_amount) + model.level(key))
		"regen_speed": return "每 %.1f秒" % (float(model.config.base_regen_interval) * pow(0.85, model.level(key)))
		"worker_move": return "当前 %d" % int(float(model.config.worker_speed) * pow(1.20, model.level(key)))
		"worker_yield": return "粮%d / 玉%d" % [5 + model.level(key) * 3, 1 + model.level(key)]
		"worker_harvest": return "效率 +%d%%" % int((1.0 - pow(0.82, model.level(key))) * 100)
		"worker_count": return "每处 %d人" % (1 + model.level(key))
	var kind := key.get_slice("_", 0)
	if key.ends_with("_damage"): return "伤害 %.1f" % (float(model.config[kind].damage) * pow(1.25, model.level(key)))
	if key.ends_with("_attack"): return "间隔 %.2f秒" % (float(model.config[kind].cooldown) * pow(0.88, model.level(key)))
	return "间隔 %.1f秒" % (float(model.config[kind].spawn_interval) * pow(0.85, model.level(key)))

func upgrade_gain(key: String) -> String:
	var gains := {"base_hp": "+60", "regen_amount": "+1", "regen_speed": "+15%", "worker_move": "+20%", "worker_yield": "+数量", "worker_harvest": "+18%", "worker_count": "+1人"}
	if gains.has(key): return gains[key]
	if key.ends_with("_damage"): return "+25%"
	if key.ends_with("_attack"): return "+12%"
	return "+15%"

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
	button("home", Rect2(130, 786, 220, 65), "返回行营", true, true)
	button("restart", Rect2(370, 786, 220, 65), "再守一局", true, true)
	label_at(save_error if not save_error.is_empty() else "已自动保存 · 局内粮草与强化下局重置", Vector2(360, 917), 19, RED if not save_error.is_empty() else Color("7d6e55"), true)

func draw_worker(worker: Dictionary) -> void:
	var p: Vector2 = worker.pos
	var moving: bool = worker.state != "harvesting" and worker.state != "sheltered"
	var step := sin(model.elapsed * 13.0) * 3.0
	var tint := GOLD if worker.kind == "grain" else GREEN
	draw_circle(p + Vector2(0, 13), 12, Color(0.2, 0.16, 0.1, 0.13))
	label_at("兵", p + Vector2(0, 8 + (absf(step) if moving else 0.0)), 29, INK, true, true)
	draw_line(p + Vector2(-10, -19), p + Vector2(10, -19), tint, 4, true)
	draw_line(p + Vector2(-5, 10), p + Vector2(-8 - (step if moving else 0.0), 18), INK, 2, true)
	draw_line(p + Vector2(5, 10), p + Vector2(8 + (step if moving else 0.0), 18), INK, 2, true)
	if worker.cargo > 0:
		draw_circle(p + Vector2(16, -2), 11, tint)
		label_at("粮" if worker.kind == "grain" else "玉", p + Vector2(16, 3), 15, PAPER, true)
	elif not moving:
		draw_line(p + Vector2(13, -3), p + Vector2(24, -13 + step * 2), tint, 3, true)
