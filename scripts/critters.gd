extends Node3D
## 小动物管理：在玩家周围的草地上放几只兔子和小鹿，离太远的挪到别处（不在视线里刷新）

const RABBITS := 7
const DEER := 3
const BIRDS := 12
const SKY_BIRDS := 7           # 常驻天空盘旋的鸟
const NEAR := 18.0
const FAR := 55.0
const DESPAWN := 85.0

var world
var _rng := RandomNumberGenerator.new()
var _list: Array[Node3D] = []
var _deer: Array[Node3D] = []
var _birds: Array[Node3D] = []
var _sky: Array[Node3D] = []
var _timer := 0.0


func setup(w) -> void:
	world = w
	_rng.randomize()


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var p: Vector3 = world.player.global_position
	for r in _list.duplicate():
		if Vector2(r.global_position.x - p.x, r.global_position.z - p.z).length() > DESPAWN:
			_list.erase(r)
			r.queue_free()
	if _list.size() < RABBITS:
		_spawn_group(p)
	for d in _deer.duplicate():
		if Vector2(d.global_position.x - p.x, d.global_position.z - p.z).length() > DESPAWN + 30.0:
			_deer.erase(d)
			d.queue_free()
	if _deer.size() < DEER:
		_spawn_deer(p)
	for b in _birds.duplicate():
		if Vector2(b.global_position.x - p.x, b.global_position.z - p.z).length() > DESPAWN:
			_birds.erase(b)
			b.queue_free()
	if _birds.size() < BIRDS:
		_spawn_birds(p)
	# 天上的鸟：一次放齐，之后一直跟着玩家头顶盘旋，不会消失
	while _sky.size() < SKY_BIRDS:
		var sb := Node3D.new()
		sb.set_script(load("res://scripts/bird.gd"))
		add_child(sb)
		sb.setup_soar(world, p)
		_sky.append(sb)


## 小鸟一小群 3-5 只落在一起啄地
func _spawn_birds(p: Vector3) -> void:
	for tries in 10:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(14.0, 45.0)
		var c := p + Vector3(cos(a), 0, sin(a)) * d
		var spread := 1.8
		# 附近有水塘：大多数时候落在水边，沿着岸边扎堆
		var at_water := false
		if world.get("water_level") != null and world.water_level > -500.0 and _rng.randf() < 0.8:
			var pc: Vector2 = world.POND_CENTER
			if Vector2(p.x, p.z).distance_to(pc) < 90.0:
				var pr: float = world.POND_RADIUS
				c = Vector3(pc.x + cos(a) * (pr + 1.5), 0, pc.y + sin(a) * (pr + 1.5))
				spread = 2.2
				at_water = true
		if not _good(c.x, c.z):
			continue
		var n := mini(_rng.randi_range(4, 6) if at_water else _rng.randi_range(3, 5), BIRDS - _birds.size())
		for k in n:
			var q := c + Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread, spread))
			if not _good(q.x, q.z):
				continue
			var r := Node3D.new()
			r.set_script(load("res://scripts/bird.gd"))
			add_child(r)
			r.setup(world, Vector3(q.x, world.height_raw(q.x, q.z), q.z), _rng.randf() * TAU)
			_birds.append(r)
		return


## 小鹿比兔子离得远一些，单只或两只一起
func _spawn_deer(p: Vector3) -> void:
	for tries in 10:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(30.0, 75.0)
		var c := p + Vector3(cos(a), 0, sin(a)) * d
		if not _good(c.x, c.z):
			continue
		var n := mini(_rng.randi_range(1, 2), DEER - _deer.size())
		for k in n:
			var q := c + Vector3(_rng.randf_range(-4.0, 4.0), 0, _rng.randf_range(-4.0, 4.0))
			if not _good(q.x, q.z):
				continue
			var r := Node3D.new()
			r.set_script(load("res://scripts/deer.gd"))
			add_child(r)
			r.setup(world, Vector3(q.x, world.height_raw(q.x, q.z), q.z), _rng.randf() * TAU)
			_deer.append(r)
		return


## 一次刷 2-3 只在一起（兔子成群出现更自然），位置在玩家身后或侧面、看不到的地方
func _spawn_group(p: Vector3) -> void:
	var cam_fwd: Vector3 = -(world.player.global_basis.z as Vector3)
	for tries in 12:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(NEAR, FAR)
		var c := p + Vector3(cos(a), 0, sin(a)) * d
		if Vector3(c.x - p.x, 0, c.z - p.z).normalized().dot(Vector3(cam_fwd.x, 0, cam_fwd.z).normalized()) > 0.5 and _list.size() > 0:
			continue
		if not _good(c.x, c.z):
			continue
		var n := mini(_rng.randi_range(2, 3), RABBITS - _list.size())
		for k in n:
			var q := c + Vector3(_rng.randf_range(-2.5, 2.5), 0, _rng.randf_range(-2.5, 2.5))
			if not _good(q.x, q.z):
				continue
			var r := Node3D.new()
			r.set_script(load("res://scripts/rabbit.gd"))
			add_child(r)
			r.setup(world, Vector3(q.x, world.height_raw(q.x, q.z), q.z), _rng.randf() * TAU)
			_list.append(r)
		return


func _good(x: float, z: float) -> bool:
	if world.has_method("in_pond") and world.in_pond(x, z):
		return false
	if world.has_method("animal_biome_ok") and not world.animal_biome_ok(x, z):
		return false        # 雪原、冰原、沙漠里不刷动物
	if world.has_method("blocked_at") and world.blocked_at(x, z, 0.6):
		return false        # 不刷在树、石头、冰山里
	if world.has_method("bare_at") and world.bare_at(x, z) > 0.5:
		return false
	var h: float = world.height_raw(x, z)
	if world.has_method("water_surface") and world.water_surface(x, z) > h:
		return false
	return absf(world.height_raw(x + 1.0, z) - h) < 0.6 and absf(world.height_raw(x, z + 1.0) - h) < 0.6
