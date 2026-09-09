extends SceneTree
const Model = preload("res://scripts/battle_model.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		push_error(message)
		failures += 1

func _initialize() -> void:
	var m = Model.new()
	m.rng.seed = 42
	m.paused = true
	m.tick(10)
	check(m.elapsed == 0 and m.wave == 0, "Pause freezes simulation")
	m.paused = false
	var countdown_before: float = m.wave_remaining()
	m.tick(1.0)
	check(m.wave_remaining() < countdown_before, "Wave countdown decreases toward the next wave")
	m.spawn_drop()
	var point: Vector2 = m.drops[0].pos
	var before: int = m.grain
	check(m.collect(point), "Drop can be collected")
	check(m.grain == before + int(m.config.drop_amount), "Collection credits resources")
	check(not m.collect(point), "Drop cannot be collected twice")
	m.spawn_drop()
	m.next_event = 1000
	for i in range(450): m.tick(1.0 / 60)
	check(m.drops.is_empty(), "Uncollected drops expire")
	check(m.wave == 1, "Opening countdown starts the first wave")
	m.units.clear()
	m.new_unit(false, "enemy", Vector2(80, 900), 9999, 0, 0, 37, 10)
	var combat_clock: float = m.wave_clock
	var combat_grain: int = m.grain
	var grain_worker: Dictionary
	for worker in m.workers:
		if worker.kind == "grain":
			grain_worker = worker
			break
	grain_worker.pos = grain_worker.site
	grain_worker.state = "harvesting"
	grain_worker.wait = 0.1
	for i in range(120): m.tick(1.0 / 60)
	check(is_equal_approx(m.wave_clock, combat_clock), "Next-wave countdown freezes while enemies remain")
	check(m.grain == combat_grain, "Workers produce no resources during combat")
	check(grain_worker.state == "sheltered" and grain_worker.pos.distance_to(grain_worker.home) < 0.1, "Workers retreat to camp during combat")
	for unit in m.units: unit.hp = 0
	m.tick(1.0 / 60)
	m.tick(1.0 / 60)
	check(m.wave_clock > combat_clock and grain_worker.state != "sheltered", "Countdown and gathering resume after the wave is cleared")
	m.grain = 100
	check(m.buy("bow_unlock") and m.bow_open, "Bow barracks unlock")
	m.reset()
	m.hp -= 20
	for i in range(301): m.tick(1.0 / 60)
	check(m.hp > m.max_hp - 20, "Base regenerates health automatically")
	m.grain = 1000
	var old_hp: float = m.max_hp
	check(m.buy("base_hp") and m.max_hp == old_hp + 60, "Base health upgrade applies immediately")
	var old_workers: int = m.workers.size()
	check(m.buy("worker_count") and m.workers.size() == old_workers + 2, "Worker count adds one worker to each site")
	var start_grain: int = m.grain
	for worker in m.workers:
		if worker.kind == "grain":
			worker.state = "returning"
			worker.pos = worker.home
			worker.cargo = 5 + m.level("worker_yield") * 3
			worker.wait = 0.0
	m.tick(1.0 / 60)
	check(m.grain > start_grain, "Resources are credited only when workers return to base")
	var soldier: Dictionary = m.units[0]
	var old_damage: float = soldier.damage
	check(m.buy("sword_damage") and soldier.damage > old_damage, "Barracks damage upgrade affects existing soldiers")
	var old_cooldown: float = soldier.cooldown
	check(m.buy("sword_attack") and soldier.cooldown < old_cooldown, "Barracks attack speed affects existing soldiers")
	m.reset()
	m.units.clear()
	m.new_unit(true, "sword", Vector2(360, 550), 100, 1, 0, 38, 1)
	m.new_unit(false, "enemy", Vector2(360, 570), 100, 5, 0, 38, 1)
	m.units[0].pos = Vector2(360, 550)
	m.units[1].pos = Vector2(360, 570)
	for i in range(120): m.tick(1.0 / 60)
	check(m.units[0].hp < 100 and m.hp == m.max_hp, "Enemy attacks nearby soldier instead of base")
	m.units.clear()
	m.new_unit(false, "enemy", Model.BASE + Vector2(0, 90), 100, 5, 0, 38, 0.5)
	for i in range(120): m.tick(1.0 / 60)
	check(m.hp < m.max_hp and m.count_side(false) == 1, "Enemy survives repeated base attacks")
	m.jade = 17
	var settlement: Array = []
	m.finished.connect(func(victory, amount): settlement.append([victory, amount]))
	m.finish(false)
	m.finish(false)
	check(settlement.size() == 1 and settlement[0][1] == 17, "Defeat credits all jade once")
	m.reset()
	check(m.jade == 0 and m.grain == m.config.starting_grain and m.levels.is_empty(), "New run resets temporary growth")
	# Exercise a full run with automatic purchases to expose late-wave errors.
	for i in range(18000):
		m.tick(1.0 / 60)
		if i % 120 == 0:
			for key in ["bow_unlock", "worker_yield", "worker_move", "sword_damage", "sword_attack", "sword_spawn", "regen_amount", "base_hp"]: m.buy(key)
		if m.ended: break
	check(m.ended, "Complete run reaches settlement")
	print("BATTLE TESTS: ", failures, " failures; full run wave=", m.wave, " won=", m.won)
	quit(0 if failures == 0 else 1)
