extends RefCounted
## Pure battle state, independent of rendering and platform APIs.
signal finished(won: bool, jade: int)
signal feedback(text: String, point: Vector2, color: Color)

var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
var rng := RandomNumberGenerator.new()
var units: Array[Dictionary] = []
var drops: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var levels: Dictionary = {}
var elapsed := 0.0
var wave := 0
var wave_clock := 0.0
var wave_duration := 6.0
var hp := 260.0
var max_hp := 260.0
var grain := 45
var jade := 0
var ended := false
var paused := false
var won := false
var bow_open := false
var sword_clock := 0.0
var bow_clock := 0.0
var workers: Array[Dictionary] = []
var regen_clock := 0.0
var event_clock := 0.0
var next_event := 10.0
var next_id := 0
var permanent := 0
const BASE := Vector2(360, 356)

func _init() -> void:
	rng.randomize()
	reset()

func reset(permanent_level: int = 0) -> void:
	units.clear()
	drops.clear()
	effects.clear()
	levels.clear()
	permanent = permanent_level
	elapsed = 0.0
	wave = 0
	wave_clock = 0.0
	wave_duration = float(config.first_wave_delay)
	max_hp = float(config.base_hp) + permanent * 20
	hp = max_hp
	grain = int(config.starting_grain)
	jade = 0
	ended = false
	paused = false
	won = false
	bow_open = false
	sword_clock = 0.0
	bow_clock = 0.0
	regen_clock = 0.0
	reset_workers()
	event_clock = 0.0
	next_event = rng.randf_range(config.drop_min_interval, config.drop_max_interval)
	next_id = 0
	spawn_ally("sword")
	spawn_ally("sword")

func level(key: String) -> int:
	return int(levels.get(key, 0))

func cost(key: String) -> int:
	var prices := {
		"base_hp": 25, "regen_amount": 24, "regen_speed": 28,
		"worker_move": 20, "worker_yield": 22, "worker_harvest": 26, "worker_count": 40,
		"sword_damage": 22, "sword_attack": 26, "sword_spawn": 28,
		"bow_damage": 28, "bow_attack": 32, "bow_spawn": 34, "bow_unlock": 35
	}
	return int(round(int(prices[key]) * pow(1.55, level(key))))

func buy(key: String) -> bool:
	if ended or paused or grain < cost(key):
		return false
	grain -= cost(key)
	levels[key] = level(key) + 1
	match key:
		"base_hp":
			max_hp += 60
			hp += 60
		"worker_count": sync_workers()
		"bow_unlock": bow_open = true
	if key.ends_with("_damage") or key.ends_with("_attack"):
		var kind := key.get_slice("_", 0)
		for unit in units:
			if unit.ally and unit.kind == kind:
				if key.ends_with("_damage"): unit.damage *= 1.25
				else: unit.cooldown *= 0.88
	feedback.emit("强化完成", BASE + Vector2(0, -60), Color("9a702e"))
	return true

func spawn_ally(kind: String) -> void:
	if count_side(true) >= int(config.ally_cap):
		return
	var spec: Dictionary = config[kind]
	var damage_level := level(kind + "_damage")
	var attack_level := level(kind + "_attack")
	new_unit(true, kind, Vector2(265 if kind == "sword" else 455, 449), float(spec.hp),
		float(spec.damage) * pow(1.25, damage_level) * (1.0 + permanent * 0.05), float(spec.speed),
		float(spec.range), float(spec.cooldown) * pow(0.88, attack_level))

func new_unit(ally: bool, kind: String, point: Vector2, health: float, damage: float, speed: float, attack_range: float, cooldown: float) -> void:
	next_id += 1
	units.append({"id": next_id, "ally": ally, "kind": kind, "pos": point + Vector2(rng.randf_range(-18, 18), 0),
		"hp": health, "max_hp": health, "damage": damage, "speed": speed, "range": attack_range,
		"cooldown": cooldown, "timer": rng.randf_range(0.0, 0.5), "flash": 0.0, "walking": false})

func count_side(ally: bool) -> int:
	var amount := 0
	for unit in units:
		if unit.ally == ally and unit.hp > 0:
			amount += 1
	return amount

func spawn_wave() -> void:
	wave += 1
	feedback.emit("第 %d 波 · 敌军来袭" % wave, Vector2(360, 750), Color("a33b30"))
	for i in range(5 + wave * 2):
		var heavy := i % 4 == 0
		new_unit(false, "shield" if heavy else "enemy", Vector2(rng.randf_range(72, 648), rng.randf_range(885, 1000)),
			(26.0 + wave * 8) * (1.6 if heavy else 1.0), 3.0 + wave * 1.3, 34.0 + wave * 2,
			37.0, 1.2)
	if wave == int(config.total_waves):
		new_unit(false, "boss", Vector2(360, 980), 340, 16, 27, 55, 1.4)

func spawn_drop() -> void:
	drops.append({"pos": Vector2(rng.randf_range(90, 630), rng.randf_range(540, 855)),
		"life": float(config.drop_lifetime), "amount": int(config.drop_amount)})
	feedback.emit("军需散落 · 点击拾取", Vector2(360, 590), Color("98712c"))

func collect(point: Vector2) -> bool:
	if paused or ended:
		return false
	for i in range(drops.size() - 1, -1, -1):
		if point.distance_to(drops[i].pos) <= 44:
			grain += int(drops[i].amount)
			feedback.emit("+%d 粮草" % drops[i].amount, drops[i].pos, Color("98712c"))
			drops.remove_at(i)
			return true
	return false

func finish(victory: bool) -> void:
	if ended:
		return
	ended = true
	won = victory
	finished.emit(victory, jade)

func tick(delta: float) -> void:
	if ended or paused:
		return
	elapsed += delta
	wave_clock += delta
	if wave < int(config.total_waves) and wave_clock >= wave_duration:
		wave_clock = 0.0
		wave_duration = float(config.wave_interval)
		spawn_wave()
	sword_clock += delta
	var recruit_interval: float = maxf(1.2, float(config.sword.spawn_interval) * pow(0.85, level("sword_spawn")))
	if sword_clock >= recruit_interval:
		sword_clock = 0.0
		spawn_ally("sword")
	if bow_open:
		bow_clock += delta
		if bow_clock >= float(config.bow.spawn_interval) * pow(0.85, level("bow_spawn")):
			bow_clock = 0.0
			spawn_ally("bow")
	regen_clock += delta
	var regen_interval: float = float(config.base_regen_interval) * pow(0.85, level("regen_speed"))
	if regen_clock >= regen_interval:
		regen_clock = fmod(regen_clock, regen_interval)
		hp = minf(max_hp, hp + float(config.base_regen_amount) + level("regen_amount"))
	tick_workers(delta)
	event_clock += delta
	if event_clock >= next_event:
		event_clock = 0.0
		next_event = rng.randf_range(config.drop_min_interval, config.drop_max_interval)
		spawn_drop()
	for i in range(drops.size() - 1, -1, -1):
		drops[i].life -= delta
		if drops[i].life <= 0:
			drops.remove_at(i)
	for i in range(effects.size() - 1, -1, -1):
		effects[i].life -= delta
		if effects[i].life <= 0:
			effects.remove_at(i)
	for unit in units:
		if unit.hp <= 0:
			continue
		unit.timer -= delta
		unit.flash = maxf(0, unit.flash - delta)
		unit.walking = false
		var target: Dictionary = {}
		var nearest := INF
		for other in units:
			if other.ally == unit.ally or other.hp <= 0:
				continue
			var distance: float = unit.pos.distance_to(other.pos)
			if distance < nearest:
				nearest = distance
				target = other
		var target_pos: Vector2 = BASE
		var target_base := false
		if unit.ally:
			target_pos = target.pos if not target.is_empty() else Vector2(140 + (int(unit.id) % 9) * 55, 525 + (int(unit.id) % 3) * 30)
		else:
			# Enemies intercept nearby soldiers; otherwise advance on the stationary base.
			if not target.is_empty() and nearest < 210:
				target_pos = target.pos
			else:
				target = {}
				target_base = true
		var distance: float = unit.pos.distance_to(target_pos)
		var reach: float = 100.0 if target_base else float(unit.range)
		var has_target: bool = target_base or not target.is_empty()
		if distance > (reach if has_target else 8.0):
			unit.pos = unit.pos.move_toward(target_pos, float(unit.speed) * delta)
			unit.walking = true
		elif has_target and unit.timer <= 0:
			unit.timer = unit.cooldown
			if target_base:
				hp = maxf(0, hp - float(unit.damage))
			else:
				target.hp -= unit.damage
				target.flash = 0.14
			effects.append({"from": unit.pos, "to": target_pos, "life": 0.16, "bow": unit.kind == "bow", "ally": unit.ally})
			feedback.emit("-%d" % int(unit.damage), target_pos + Vector2(0, -30), Color("b33d30") if unit.ally else Color("45493e"))
		# Gentle separation avoids stacks without requiring navigation meshes.
		for other in units:
			if other.id == unit.id or other.ally != unit.ally or other.hp <= 0:
				continue
			var diff: Vector2 = unit.pos - other.pos
			if diff.length_squared() < 24 * 24 and diff.length_squared() > 0.1:
				unit.pos += diff.normalized() * delta * 22
		unit.pos.x = clampf(unit.pos.x, 40, 680)
	for i in range(units.size() - 1, -1, -1):
		if units[i].hp <= 0:
			units.remove_at(i)
	if hp <= 0:
		finish(false)
	elif wave == int(config.total_waves) and count_side(false) == 0:
		finish(true)

func wave_remaining() -> float:
	return maxf(0.0, wave_duration - wave_clock) if wave < int(config.total_waves) else 0.0

func reset_workers() -> void:
	workers.clear()
	sync_workers()

func sync_workers() -> void:
	var required := 1 + level("worker_count")
	for kind in ["grain", "jade"]:
		var current := 0
		for worker in workers:
			if worker.kind == kind: current += 1
		for index in range(current, required):
			var home := Vector2(238, 363) if kind == "grain" else Vector2(482, 363)
			var site := Vector2(155, 286) if kind == "grain" else Vector2(565, 286)
			var offset := Vector2(0, (index - (required - 1) * 0.5) * 12.0)
			workers.append({"kind": kind, "home": home + offset, "site": site + offset,
				"pos": home + offset, "state": "outbound", "wait": index * 0.35, "cargo": 0})

func tick_workers(delta: float) -> void:
	for worker in workers:
		if worker.wait > 0.0 and worker.state != "harvesting":
			worker.wait -= delta
			continue
		if worker.state == "harvesting":
			worker.wait -= delta
			if worker.wait <= 0:
				worker.cargo = (5 if worker.kind == "grain" else 1) + level("worker_yield") * (3 if worker.kind == "grain" else 1)
				worker.state = "returning"
		else:
			var target: Vector2 = worker.home if worker.state == "returning" else worker.site
			var move_speed: float = float(config.worker_speed) * pow(1.15, level("worker_move"))
			worker.pos = worker.pos.move_toward(target, move_speed * delta)
			if worker.pos.distance_to(target) < 0.01:
				if worker.state == "returning":
					if worker.kind == "grain": grain += int(worker.cargo)
					else: jade += int(worker.cargo)
					feedback.emit("+%d %s" % [worker.cargo, "粮" if worker.kind == "grain" else "玉"], worker.home + Vector2(0, -24), Color("ae803c") if worker.kind == "grain" else Color("3f675b"))
					worker.cargo = 0
					worker.state = "outbound"
				else:
					worker.state = "harvesting"
					# Preserve the original approximate round-trip production rate.
					var base_wait: float = maxf(0.3, float(config[worker.kind + "_interval"]) - 2.0 * worker.home.distance_to(worker.site) / float(config.worker_speed))
					worker.wait = base_wait * pow(0.82, level("worker_harvest"))
