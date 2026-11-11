extends Node3D
## 小鸟：程序化动画 + 简单的行为
## 状态：idle 站着张望 / peck 啄地 / hop 小跳着换位置 / fly 飞走（起飞 → 飞行 → 降落）
## 你走近会把它惊飞；偶尔也会自己飞到别处，附近有水的话多半飞去水边。
## 另有一种常驻天空的（setup_soar）：一直在玩家头顶上方盘旋，不落地。
## 模型 characters/bird.glb（Tripo 生成，骨骼和权重是在 Blender 里做的，源文件 E:\Godat\meadow_bird.blend），正面朝 +Z
## 骨头：Root / Head / WingL WingR / LegL LegR / Tail

const MODEL_PATH := "res://characters/bird.glb"
const SCALE := 0.26
const SCARE_DIST := 6.0
const FLY_SPEED := 7.0
const FLY_HEIGHT := 5.0

var world
var state := "idle"
var state_t := 0.0
var state_len := 2.0
var model: Node3D
var sk: Skeleton3D
var B := {}
var _rest := {}
var _grest := {}
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _yaw := 0.0
var _want_yaw := 0.0

# 小跳
var _hop_t := -1.0
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hops_left := 0
var _pause := 0.0

# 飞行
var _fly_from := Vector3.ZERO
var _fly_to := Vector3.ZERO
var _fly_len := 1.0
var _fly_peak := 5.0

# 动画量
var _wing := 0.0          # 0 收拢，1 完全张开
var _head_pitch := 0.0
var _head_yaw := 0.0
var _head_roll := 0.0
var _look_t := 0.5
var _look_yaw := 0.0
var _look_roll := 0.0
var _peck := 0.0
var _sq := 0.0
var _sq_v := 0.0

# 常驻天空的鸟
var soar := false
var _soar_c := Vector3.ZERO      # 盘旋的圆心（慢慢跟着玩家）
var _soar_r := 20.0
var _soar_h := 22.0
var _soar_a := 0.0
var _soar_dir := 1.0
var _soar_y := 0.0
var _glide := -1.0               # >= 0 时覆盖滑翔程度（盘旋时用）


func setup(w, pos: Vector3, yaw: float) -> void:
	world = w
	_rng.randomize()
	global_position = pos
	_yaw = yaw
	_want_yaw = yaw
	rotation.y = yaw


## 常驻天空：在 center 上方绕圈飞，圆心慢慢跟着玩家
func setup_soar(w, center: Vector3) -> void:
	world = w
	_rng.randomize()
	soar = true
	_soar_c = center + Vector3(_rng.randf_range(-12.0, 12.0), 0, _rng.randf_range(-12.0, 12.0))
	_soar_r = _rng.randf_range(12.0, 30.0)
	_soar_h = _rng.randf_range(16.0, 30.0)
	_soar_a = _rng.randf() * TAU
	_soar_dir = 1.0 if _rng.randf() < 0.7 else -1.0
	_soar_y = center.y + _soar_h
	global_position = _soar_c + Vector3(cos(_soar_a) * _soar_r, _soar_h, sin(_soar_a) * _soar_r)


func _soar_process(delta: float) -> void:
	var p: Node3D = world.player
	if p:
		# 圆心慢慢飘向玩家，所以鸟群一直在你头顶附近
		var target := p.global_position + Vector3(sin(_t * 0.05 + _soar_r) * 10.0, 0, cos(_t * 0.04 + _soar_h) * 10.0)
		_soar_c = _soar_c.lerp(Vector3(target.x, 0, target.z), clampf(delta * 0.12, 0.0, 1.0))
	var speed := 6.5
	_soar_a += _soar_dir * speed / _soar_r * delta
	var r := _soar_r + sin(_t * 0.23 + _soar_h) * 3.0
	var pos := _soar_c + Vector3(cos(_soar_a) * r, 0, sin(_soar_a) * r)
	var want_y := _ground(pos.x, pos.z) + _soar_h + sin(_t * 0.31 + _soar_r) * 2.5
	_soar_y = lerpf(_soar_y, want_y, clampf(delta * 0.6, 0.0, 1.0))
	pos.y = _soar_y
	global_position = pos
	var vx := -sin(_soar_a) * _soar_dir
	var vz := cos(_soar_a) * _soar_dir
	_yaw = atan2(vx, vz)
	_want_yaw = _yaw
	# 转弯时往圆心那边侧倾
	rotation = Vector3(0.0, _yaw, -_soar_dir * 0.35)
	# 扇几下、滑一段，交替进行
	var cyc := fmod(_t * 0.35 + _soar_r * 0.1, 1.0)
	_glide = smoothstep(0.35, 0.5, cyc) * (1.0 - smoothstep(0.85, 1.0, cyc))
	state = "fly"
	state_t = _fly_len * 0.5        # 身体保持平飞的姿态
	_animate(delta)


func _ready() -> void:
	model = _load_model()
	if model == null:
		return
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for i in sk.get_bone_count():
		B[sk.get_bone_name(i)] = i
		_rest[i] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
		_grest[i] = sk.get_bone_global_rest(i).basis.orthonormalized()
	_apply_toon()
	_set_state("idle")


func _load_model() -> Node3D:
	if ResourceLoader.exists(MODEL_PATH):
		var ps := load(MODEL_PATH) as PackedScene
		if ps:
			return ps.instantiate() as Node3D
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(MODEL_PATH), st) == OK:
		return doc.generate_scene(st) as Node3D
	return null


func _apply_toon() -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/toon_tex.gdshader")
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture:
				sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
			var o := ShaderMaterial.new()
			o.shader = load("res://shaders/outline.gdshader")
			o.set_shader_parameter("width_px", 1.2)
			sm.next_pass = o
			mi.set_surface_override_material(s, sm)


## 绕模型空间的轴转骨头：X 正 = 往前低头 / 腿往后，Y = 左右转，Z(BACK) 正 = 左翅膀往外抬
func _rot(name: String, rq: Basis) -> void:
	if not B.has(name):
		return
	var i: int = B[name]
	var g: Basis = _grest[i]
	sk.set_bone_pose_rotation(i, _rest[i] * Quaternion(g.inverse() * rq * g))


func _ground(x: float, z: float) -> float:
	return world.height_raw(x, z)


func _ok(x: float, z: float) -> bool:
	if world.has_method("in_pond") and world.in_pond(x, z):
		return false
	if world.has_method("blocked_at") and world.blocked_at(x, z, 0.15):
		return false
	return true


func _set_state(s: String) -> void:
	state = s
	state_t = 0.0
	match s:
		"idle":
			state_len = _rng.randf_range(1.0, 3.0)
		"peck":
			state_len = _rng.randf_range(1.5, 4.0)
		"hop":
			_hops_left = _rng.randi_range(2, 5)
			_want_yaw = _yaw + _rng.randf_range(-1.5, 1.5)
			state_len = 99.0
		"fly":
			state_len = 99.0


## 飞到 to 附近。away_from：被吓到时朝远离它的方向飞
func fly_to(to: Vector3) -> void:
	_fly_from = global_position
	_fly_to = Vector3(to.x, _ground(to.x, to.z), to.z)
	var d := Vector2(_fly_to.x - _fly_from.x, _fly_to.z - _fly_from.z).length()
	_fly_len = maxf(d / FLY_SPEED, 1.2)
	_fly_peak = clampf(d * 0.25, 2.5, FLY_HEIGHT) + _rng.randf_range(0.0, 1.5)
	_want_yaw = atan2(_fly_to.x - _fly_from.x, _fly_to.z - _fly_from.z)
	_hop_t = -1.0
	_sq_v += 5.0
	_set_state("fly")


## 附近 70 米内有水塘的话，返回水边的一个落脚点；没有就返回 fallback
func _water_edge_or(fallback: Vector3) -> Vector3:
	if world.get("water_level") == null or world.water_level < -500.0:
		return fallback
	var c: Vector2 = world.POND_CENTER
	if Vector2(global_position.x, global_position.z).distance_to(c) > 70.0:
		return fallback
	var pr: float = world.POND_RADIUS
	for tries in 10:
		var a := _rng.randf() * TAU
		var d := pr + _rng.randf_range(0.3, 3.0)
		var q := Vector3(c.x + cos(a) * d, 0, c.y + sin(a) * d)
		if _ok(q.x, q.z) and _ground(q.x, q.z) > world.water_level - 0.05:
			return q
	return fallback


func _pick_far(center: Vector3, dir: Vector3, dmin: float, dmax: float) -> Vector3:
	for tries in 8:
		var a := atan2(dir.x, dir.z) + _rng.randf_range(-0.8, 0.8) if dir.length() > 0.01 else _rng.randf() * TAU
		var d := _rng.randf_range(dmin, dmax)
		var q := center + Vector3(sin(a), 0, cos(a)) * d
		if _ok(q.x, q.z):
			return q
	return center + Vector3(dmin, 0, 0)


func _process(delta: float) -> void:
	if sk == null or world == null:
		return
	delta = minf(delta, 0.1)
	_t += delta
	if soar:
		_soar_process(delta)
		return
	state_t += delta
	var p: Node3D = world.player
	var to_player := Vector3.ZERO
	var dist := 1e9
	if p:
		to_player = p.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
		var running: bool = Vector2(p.velocity.x, p.velocity.z).length() > 3.5
		if state != "fly" and (dist < SCARE_DIST or (running and dist < SCARE_DIST * 1.8)):
			var dest := _pick_far(global_position, -to_player, 18.0, 32.0)
			var edge := _water_edge_or(dest)
			if _rng.randf() < 0.6 and p and Vector2(edge.x - p.global_position.x, edge.z - p.global_position.z).length() > 14.0:
				dest = edge
			fly_to(dest)

	match state:
		"idle":
			if state_t > state_len:
				var r := _rng.randf()
				if r < 0.5:
					_set_state("peck")
				elif r < 0.93:
					_set_state("hop")
				else:
					fly_to(_water_edge_or(_pick_far(global_position, Vector3.ZERO, 10.0, 25.0)))    # 偶尔自己飞走，有水就去水边
		"peck":
			if state_t > state_len:
				_set_state("idle" if _rng.randf() < 0.5 else "hop")
		"hop":
			_hop_logic(delta)
			if _hops_left <= 0 and _hop_t < 0.0:
				_set_state("idle" if _rng.randf() < 0.5 else "peck")
		"fly":
			var t := clampf(state_t / _fly_len, 0.0, 1.0)
			var e := t * t * (3.0 - 2.0 * t)                 # 起飞和降落慢，中间快
			var pos := _fly_from.lerp(_fly_to, e)
			var base := lerpf(_fly_from.y, _fly_to.y, e)
			pos.y = maxf(base + sin(t * PI) * _fly_peak, _ground(pos.x, pos.z) + 0.02) + sin(_t * 9.0) * 0.06 * sin(t * PI)
			global_position = pos
			if t >= 1.0:
				_sq_v -= 6.0
				_set_state("idle")

	_yaw = wrapf(_yaw, -PI, PI)
	_yaw = lerp_angle(_yaw, _want_yaw, clampf(delta * 9.0, 0.0, 1.0))
	rotation.y = _yaw
	_animate(delta)


func _hop_logic(delta: float) -> void:
	if _hop_t >= 0.0:
		_hop_t += delta / 0.2
		var t := clampf(_hop_t, 0.0, 1.0)
		var pos := _hop_from.lerp(_hop_to, t)
		pos.y = _ground(pos.x, pos.z) + sin(t * PI) * 0.07
		global_position = pos
		if _hop_t >= 1.0:
			_hop_t = -1.0
			_hops_left -= 1
			_pause = _rng.randf_range(0.08, 0.35)
			_sq_v -= 3.0
			if _rng.randf() < 0.3:
				_want_yaw += _rng.randf_range(-0.9, 0.9)
		return
	_pause -= delta
	if _pause > 0.0 or absf(wrapf(_want_yaw - _yaw, -PI, PI)) > 0.4:
		return
	var to := global_position + Vector3(sin(_want_yaw), 0, cos(_want_yaw)) * 0.22
	if not _ok(to.x, to.z) or absf(_ground(to.x, to.z) - global_position.y) > 0.25:
		_want_yaw += 1.6
		return
	_hop_t = 0.0
	_hop_from = global_position
	_hop_to = to
	_sq_v += 2.5


func _animate(delta: float) -> void:
	var k := clampf(delta * 12.0, 0.0, 1.0)
	var flying := state == "fly"
	var ft := clampf(state_t / _fly_len, 0.0, 1.0) if flying else 0.0

	# 翅膀：飞的时候张开并上下扇；小跳时微微张一下保持平衡
	var want_wing := 0.0
	if flying:
		want_wing = 1.0
	elif _hop_t >= 0.0:
		want_wing = 0.18
	_wing = lerpf(_wing, want_wing, clampf(delta * 14.0, 0.0, 1.0))
	# 起飞和降落时扇得又快又大，中途滑一小段
	var glide := smoothstep(0.35, 0.5, ft) * (1.0 - smoothstep(0.6, 0.75, ft)) if flying else 0.0
	if _glide >= 0.0:
		glide = _glide
	var flap := sin(_t * (16.0 if soar else 26.0)) * (1.0 - glide * 0.8)
	var spread := _wing * (1.25 + flap * 0.75)
	_rot("WingL", Basis(Vector3.BACK, spread) * Basis(Vector3.RIGHT, -_wing * 0.25))
	_rot("WingR", Basis(Vector3.BACK, -spread) * Basis(Vector3.RIGHT, -_wing * 0.25))

	# 头：鸟的头是一顿一顿地转；啄地时快速点头
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = _rng.randf_range(0.3, 1.4)
		_look_yaw = _rng.randf_range(-0.8, 0.8)
		_look_roll = _rng.randf_range(-0.35, 0.35)
	var snap := clampf(delta * 28.0, 0.0, 1.0)
	_head_yaw = lerpf(_head_yaw, 0.0 if (flying or state == "peck") else _look_yaw, snap)
	_head_roll = lerpf(_head_roll, 0.0 if (flying or state == "peck") else _look_roll, snap)
	var want_peck := 0.0
	if state == "peck":
		var cyc := fmod(state_t, 0.55) / 0.55
		want_peck = 1.0 if cyc < 0.35 else 0.0
	_peck = lerpf(_peck, want_peck, clampf(delta * 26.0, 0.0, 1.0))
	_head_pitch = lerpf(_head_pitch, _peck * 0.7 + (-0.25 if flying else 0.0), k)
	_rot("Head", Basis(Vector3.UP, _head_yaw) * Basis(Vector3.BACK, _head_roll) * Basis(Vector3.RIGHT, _head_pitch))

	# 身体：啄地时整个往前栽；飞行时身体放平；落地压扁回弹；呼吸
	var steps := clampi(int(ceil(delta / 0.008)), 1, 12)
	var h := delta / steps
	for i in steps:
		_sq_v += (-260.0 * _sq - 14.0 * _sq_v) * h
		_sq += _sq_v * h
	_sq = clampf(_sq, -0.3, 0.3)
	var body_pitch := _peck * 0.75
	if flying:
		body_pitch = lerpf(0.2, 0.95, sin(ft * PI)) - (1.0 - ft) * 0.0
	var breathe := sin(_t * 5.0) * 0.012
	if B.has("Root"):
		var i: int = B.Root
		var sy := 1.0 + _sq * 0.6 + breathe
		var sxz := 1.0 / sqrt(maxf(sy, 0.3))
		sk.set_bone_pose_scale(i, Vector3(sxz, sy, sxz))
	_rot("Root", Basis(Vector3.RIGHT, body_pitch))

	# 腿：小跳时往后一蹬；飞的时候收起来贴着肚子
	var leg := 0.0
	if flying:
		leg = -0.9 - body_pitch
	elif _hop_t >= 0.0:
		leg = lerpf(0.5, -0.4, clampf(_hop_t, 0.0, 1.0))
	else:
		leg = -body_pitch       # 身体前倾时腿保持竖直
	_rot("LegL", Basis(Vector3.RIGHT, leg))
	_rot("LegR", Basis(Vector3.RIGHT, leg))

	# 尾巴：站着时偶尔上下抖，飞的时候展平
	var wag := sin(_t * 11.0) * 0.12 * (1.0 if fmod(_t, 3.0) < 0.5 else 0.0)
	_rot("Tail", Basis(Vector3.RIGHT, (-0.4 if flying else 0.0) + wag - _peck * 0.4))
