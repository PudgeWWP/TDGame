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
	check(view.screen == "home", "Game opens on the out-of-battle home screen")
	view.action("profile")
	check(view.screen == "profile", "Portrait opens the player profile page")
	check(bool(view.settings.music) and bool(view.settings.sound) and bool(view.settings.damage_numbers), "Profile settings default to enabled")
	view.action("toggle_music")
	view.action("toggle_damage_numbers")
	check(not bool(view.settings.music) and not bool(view.settings.damage_numbers), "Profile settings can be disabled")
	view.action("back_home")
	view.action("entry_strategy")
	check(view.modal == "coming" and view.modal_title == "军略", "Strategy entry is available")
	view.action("close_modal")
	view.action("start_battle")
	check(view.screen == "battle", "Start button enters battle")
	check(int(view.profile_stats.challenge_count) == 1, "Starting a run records one challenge")
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
	view.model.wave = 3
	view.action("retreat")
	check(view.screen == "result" and view.bank == 22, "Retreat settles jade")
	check(int(view.profile_stats.best_progress) == 50, "Settlement saves the highest challenge progress")
	view.action("training")
	check(view.bank == 14 and view.permanent == 1, "Permanent upgrade spends saved jade")
	view.bank = 0
	view.permanent = 0
	view.load_campaign()
	check(view.bank == 14 and view.permanent == 1, "Saved progression survives reload")
	check(not bool(view.settings.music) and not bool(view.settings.damage_numbers), "Profile settings survive reload")
	view.action("restart")
	check(view.model.max_hp == 280 and view.model.jade == 0 and view.screen == "battle", "Restart applies permanent growth and resets run")
	view.action("home")
	check(view.screen == "home", "Settlement can return to the home screen")
	DirAccess.remove_absolute(view.save_path)
	print("UI TESTS: ", failures, " failures")
	quit(0 if failures == 0 else 1)
