extends SceneTree
var failures := 0

func check(value: bool, description: String) -> void:
	if not value:
		push_error(description)
		failures += 1

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var view = load("res://main.tscn").instantiate()
	view.save_path = "user://ui_test_%d.json" % Time.get_ticks_usec()
	root.add_child(view)
	view.set_process(false)
	view.queue_redraw()
	await process_frame
	await process_frame
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	var tr: Vector3 = view.transform_info()
	event.position = Vector2(640, 95) * tr.z + Vector2(tr.x, tr.y)
	view._gui_input(event)
	check(view.model.paused, "Pause button hit area works")
	view.action("resume")
	view.model.grain = 100
	var old_max_hp: float = view.model.max_hp
	view.action("buy_base_hp")
	check(view.model.max_hp == old_max_hp + 60, "Base attribute card applies its upgrade")
	view.action("tab_2")
	check(view.tab == 2 and not view.model.paused, "Resume and tab change work")
	view.model.grain = 100
	view.action("barracks_bow")
	check(view.barracks_kind == "bow", "Barracks selector changes troop type")
	view.action("buy_bow_unlock")
	check(view.model.bow_open, "UI purchase unlocks barracks")
	view.model.jade = 22
	view.action("retreat")
	check(view.screen == "result" and view.bank == 22, "Retreat settles jade")
	view.action("training")
	check(view.bank == 14 and view.permanent == 1, "Permanent upgrade spends saved jade")
	view.bank = 0
	view.permanent = 0
	view.load_campaign()
	check(view.bank == 14 and view.permanent == 1, "Saved progression survives reload")
	view.action("restart")
	check(view.model.max_hp == 280 and view.model.jade == 0 and view.screen == "battle", "Restart applies permanent growth and resets run")
	DirAccess.remove_absolute(view.save_path)
	print("UI TESTS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
