extends Node3D
## 小鹿：程序化动画 + 简单的行为
## 状态：idle 站着（呼吸、抖耳朵、张望）/ graze 低头吃草 / walk 慢慢走 / alert 抬头竖耳朵盯着你 / flee 跑开
## 模型 characters/deer.glb（Tripo 生成，骨骼是在 Blender 里绑的，源文件 E:\Godat\meadow_deer.blend），正面朝 +Z
## 骨头：Root / Hips / Chest / Neck / Head / EarL EarR / Tail / FL FR BL BR 各有 _Upper _Lower

const MODEL_PATH := "res://characters/deer.glb"
const SCALE := 1.25
const ALERT_DIST := 14.0
const FLEE_DIST := 7.5
const WALK_SPEED := 1.1
const RUN_SPEED := 7.5
const Fx := preload("res://scripts/fx.gd")

var world
var state := "idle"
var state_t := 0.0
var state_len := 3.0
var model: Node3D
var sk: Skeleton3D
var B := {}
var _rest := {}
var _grest := {}
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _yaw := 0.0
var _want_yaw := 0.0
var _speed := 0.0
var _phase := 0.0
var _target := Vector3.ZERO
var _neck := 0.0          # 正 = 低头
var _look := 0.0
var _look_target := 0.0
var _look_t := 1.0
var _ear := 0.0
var _ear_v := 0.0
var _twitch := [0.0, 0.0]
var _twitch_t := 2.0
var _tail_flick := 0.0
var _flee_t := 0.0
# 被摸 / 喂（interact.gd 调用）
var friend_t := 0.0
var _pet_feed := false
var _toss_t := -1.0           # 开心地甩一下头
var _love_t := 5.0


func setup(w, pos: Vector3, yaw: float) -> void:
	world = w
	_rng.randomize()
	global_position = pos
	_yaw = yaw
	_want_yaw = yaw
	rotation.y = yaw


func _ready() -> void:
	model = _load_model()
	if model == null:
		return
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	sk = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	for i in sk.get_bone_count():
		var n := sk.get_bone_name(i)
		B[n] = i
		_rest[i] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
		_grest[i] = sk.get_bone_global_rest(i).basis.orthonormalized()
	_apply_toon()
	_set_state("idle")
	add_to_group("pettable")


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
			o.set_shader_parameter("width_px", 1.4)
			sm.next_pass = o
			mi.set_surface_override_material(s, sm)


## 绕模型空间的轴转骨头：X 正 = 往前/往下摆（低头、腿往后蹬是负），Y = 左右转，Z = 左右歪
func _rot(name: String, rq: Basis) -> void:
	if not B.has(name):
		return
	var i: int = B[name]
	var g: Basis = _grest[i]
	sk.set_bone_pose_rotation(i, _rest[i] * Quaternion(g.inverse() * rq * g))


func _set_state(s: String) -> void:
	state = s
	state_t = 0.0
	match s:
		"idle":
			state_len = _rng.randf_range(2.5, 6.0)
		"graze":
			state_len = _rng.randf_range(5.0, 10.0)
		"walk":
			var a := _rng.randf() * TAU
			_target = global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(4.0, 10.0)
			state_len = 14.0
		"alert":
			state_len = _rng.randf_range(2.0, 4.0)
		"flee":
			_flee_t = _rng.randf_range(3.0, 4.5)
			state_len = 99.0
			_tail_flick = 1.0


func _process(delta: float) -> void:
	if sk == null or world == null:
		return
	delta = minf(delta, 0.1)
	_t += delta
	state_t += delta
	var p: Node3D = world.player
	var to_player := Vector3.ZERO
	var dist := 1e9
	if p:
		to_player = p.global_position - global_position
		to_player.y = 0.0
		dist = to_player.length()
		var running: bool = Vector2(p.velocity.x, p.velocity.z).length() > 3.5
		# 你拿着浆果慢慢走近：不怕你，走过来，到跟前低头吃
		var hero = p.get("hero")
		friend_t = maxf(friend_t - delta, 0.0)
		if state == "pet":
			pass
		elif friend_t > 0.0:
			# 朋友：不怕你，慢慢跟着你走，到跟前就停下；偶尔冒个小爱心
			if state in ["flee", "alert"]:
				_set_state("idle")
			if dist > 3.6 and dist < 45.0:
				if state != "walk" or state_t > 2.0:
					_set_state("walk")
					_target = p.global_position - to_player.normalized() * 2.2
			elif dist < 5.0:
				_love_t -= delta
				if _love_t <= 0.0:
					_love_t = _rng.randf_range(7.0, 12.0)
					Fx.heart_pop(get_parent(), head_pos() + Vector3(0, 0.35, 0), 0.2, false)
		elif hero != null and hero.held == "berry" and not running and dist < 20.0:
			if state in ["flee", "alert"]:
				_set_state("idle")
			if dist > 2.2:
				if state != "walk" or state_t > 2.0:
					_set_state("walk")
					_target = p.global_position - to_player.normalized() * 1.8
			elif state != "graze":
				_want_yaw = atan2(to_player.x, to_player.z)
				_set_state("graze")
		elif state != "flee" and (dist < FLEE_DIST or (running and dist < ALERT_DIST)):
			_set_state("flee")
		elif state in ["idle", "graze", "walk"] and dist < ALERT_DIST:
			_set_state("alert")

	var want_speed := 0.0
	match state:
		"pet":
			_want_yaw = atan2(to_player.x, to_player.z)
		"idle":
			if state_t > state_len:
				_set_state("graze" if _rng.randf() < 0.6 else "walk")
		"graze":
			if state_t > state_len:
				_set_state("idle" if _rng.randf() < 0.4 else "walk")
		"alert":
			_want_yaw = atan2(to_player.x, to_player.z)
			if dist > ALERT_DIST + 3.0 and state_t > state_len:
				_set_state("idle")
		"walk":
			var d := _target - global_position
			d.y = 0.0
			if d.length() < 0.6 or state_t > state_len:
				_set_state("idle")
			else:
				_want_yaw = atan2(d.x, d.z)
				want_speed = WALK_SPEED
		"flee":
			var away := (-to_player).normalized().rotated(Vector3.UP, sin(_t * 0.5) * 0.35)
			_want_yaw = atan2(away.x, away.z)
			want_speed = RUN_SPEED
			_flee_t -= delta
			if _flee_t <= 0.0 and dist > ALERT_DIST:
				_set_state("alert")

	_yaw = wrapf(_yaw, -PI, PI)
	_yaw = lerp_angle(_yaw, _want_yaw, clampf(delta * (6.0 if state == "flee" else 3.0), 0.0, 1.0))
	rotation.y = _yaw
	# 没转到位之前先别迈大步
	var facing := maxf(cos(wrapf(_want_yaw - _yaw, -PI, PI)), 0.0)
	_speed = lerpf(_speed, want_speed * facing, clampf(delta * (5.0 if want_speed > _speed else 3.0), 0.0, 1.0))
	if _speed > 0.02:
		var fwd := Vector3(sin(_yaw), 0, cos(_yaw))
		var next := global_position + fwd * _speed * delta
		var ahead := global_position + fwd * 1.5
		var blocked: bool = (world.has_method("in_pond") and world.in_pond(ahead.x, ahead.z)) \
			or absf(world.height_raw(ahead.x, ahead.z) - global_position.y) > 1.4
		if blocked:
			_want_yaw += 1.2
			if state == "walk":
				_set_state("idle")
		else:
			next.y = world.height_raw(next.x, next.z)
			global_position = next
	_animate(delta)


func _animate(delta: float) -> void:
	var k := clampf(delta * 8.0, 0.0, 1.0)
	var run := clampf((_speed - 2.0) / (RUN_SPEED - 2.0), 0.0, 1.0)
	var move := clampf(_speed / WALK_SPEED, 0.0, 1.0)
	# 步子相位：走路一圈迈四步；跑起来是前腿一组、后腿一组的跳跃步
	_phase += delta * lerpf(_speed / 0.75, 2.6, run) * (1.0 if _speed > 0.02 else 0.0)
	var ph := _phase * TAU

	# 脖子和头
	var want_neck := 0.0
	if state == "graze":
		want_neck = 1.4
	elif state == "alert":
		want_neck = -0.22
	elif state == "flee":
		want_neck = 0.25
	elif state == "pet":
		want_neck = (0.75 if _pet_feed else 0.42) + sin(_t * 2.6) * 0.06    # 低头凑到你手边
	if _toss_t >= 0.0:
		# 开心地把头往上一甩
		_toss_t += delta / 0.7
		want_neck = -0.55 * sin(clampf(_toss_t, 0.0, 1.0) * PI)
		if _toss_t >= 1.0:
			_toss_t = -1.0
	_neck = lerpf(_neck, want_neck, clampf(delta * (9.0 if _toss_t >= 0.0 else 3.5), 0.0, 1.0))
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = _rng.randf_range(1.0, 3.0)
		_look_target = _rng.randf_range(-0.6, 0.6) if state in ["idle", "alert"] else 0.0
	if state == "pet":
		_look_target = sin(_t * 1.9) * 0.22
	_look = lerpf(_look, _look_target, clampf(delta * 4.0, 0.0, 1.0))
	var chew := sin(_t * 7.0) * 0.05 if state == "graze" and _neck > 1.1 else 0.0
	if state == "pet" and _pet_feed:
		chew = sin(_t * 9.0) * 0.06
	var bob := sin(ph * 2.0) * 0.05 * move * (1.0 - run) + sin(ph) * 0.12 * run
	_rot("Neck", Basis(Vector3.UP, _look * 0.5) * Basis(Vector3.RIGHT, _neck * 0.75 + bob))
	_rot("Head", Basis(Vector3.UP, _look * 0.5) * Basis(Vector3.RIGHT, _neck * 0.3 + chew - bob * 0.5))

	# 耳朵：警觉时竖直朝前，逃跑时往后压；偶尔单只抖一下
	var ear_target := 0.0
	if state == "alert":
		ear_target = 0.2
	elif state == "flee":
		ear_target = -0.6
	elif state == "pet":
		ear_target = -0.35          # 舒服：耳朵往两边放松
	var steps := clampi(int(ceil(delta / 0.008)), 1, 12)
	var h := delta / steps
	for i in steps:
		_ear_v += ((ear_target - _ear) * 140.0 - _ear_v * 11.0) * h
		_ear += _ear_v * h
	_ear = clampf(_ear, -1.0, 0.6)
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = _rng.randf_range(1.5, 5.0)
		_twitch[_rng.randi() % 2] = 1.0
	for i in 2:
		_twitch[i] = maxf(_twitch[i] - delta * 5.0, 0.0)
	var tw0: float = sin(_twitch[0] * PI * 3.0) * _twitch[0] * 0.4
	var tw1: float = sin(_twitch[1] * PI * 3.0) * _twitch[1] * 0.4
	_rot("EarL", Basis(Vector3.UP, -_ear * 0.8 - tw0) * Basis(Vector3.BACK, tw0 * 0.5))
	_rot("EarR", Basis(Vector3.UP, _ear * 0.8 + tw1) * Basis(Vector3.BACK, -tw1 * 0.5))

	# 尾巴：平时轻轻摆，受惊时竖起来
	_tail_flick = maxf(_tail_flick - delta * 0.4, 1.0 if state == "flee" else 0.0)
	var wag := 16.0 if state == "pet" else 5.0
	_rot("Tail", Basis(Vector3.UP, sin(_t * wag) * (0.4 if state == "pet" else 0.25) * (1.0 - _tail_flick)) * Basis(Vector3.RIGHT, -_tail_flick * 0.9))

	# 身体：呼吸、走路时的起伏和左右晃、跑步时的前后俯仰
	var breathe := sin(_t * (5.0 if state == "flee" else 1.8)) * 0.012
	var body_y := -absf(sin(ph * 2.0)) * 0.012 * move * (1.0 - run) + sin(ph + 0.6) * 0.07 * run
	var body_pitch := sin(ph) * 0.14 * run + maxf(_neck, 0.0) * 0.05
	var body_roll := sin(ph) * 0.03 * move * (1.0 - run)
	if B.has("Root"):
		var i: int = B.Root
		sk.set_bone_pose_position(i, sk.get_bone_rest(i).origin + Vector3(0, body_y, 0))
		sk.set_bone_pose_scale(i, Vector3(1.0 + breathe, 1.0 + breathe * 0.5, 1.0))
	_rot("Root", Basis(Vector3.BACK, body_roll) * Basis(Vector3.RIGHT, body_pitch))

	# 腿。走路：左后 → 左前 → 右后 → 右前，一条一条迈；跑：两条前腿一起、两条后腿一起
	var offs := {"BL": 0.0, "FL": 0.25, "BR": 0.5, "FR": 0.75}
	for leg: String in ["FL", "FR", "BL", "BR"]:
		var front := leg.begins_with("F")
		var wp: float = ph + (offs[leg] as float) * TAU
		var w_swing := sin(wp) * 0.38
		var w_lift := maxf(cos(wp), 0.0) * 0.55            # 往前迈的那半圈把小腿收起来
		var rp := ph + (0.0 if front else PI * 0.85) + (0.25 if leg.ends_with("R") else 0.0)
		var r_swing := sin(rp) * 0.85
		var r_lift := maxf(cos(rp), 0.0) * 1.0
		var swing := lerpf(w_swing, r_swing, run) * (move if run < 0.01 else 1.0)
		var lift := lerpf(w_lift, r_lift, run) * (move if run < 0.01 else 1.0)
		# 吃草时前腿微微叉开，站得更稳
		var splay := (0.06 if leg.ends_with("L") else -0.06) * clampf(_neck, 0.0, 1.0) if front else 0.0
		_rot(leg + "_Upper", Basis(Vector3.BACK, splay) * Basis(Vector3.RIGHT, -swing + (lift * 0.35 if front else -lift * 0.15)))
		_rot(leg + "_Lower", Basis(Vector3.RIGHT, lift * (1.0 if front else -0.8)))
	k = k


# ───────────────────────── 互动（interact.gd） ─────────────────────────

func food() -> String:
	return "berry"


func is_tall() -> bool:
	return true


func pet_range() -> float:
	return 2.6


func can_pet() -> bool:
	return sk != null and state != "flee" and state != "pet"


func is_shy() -> bool:
	return friend_t <= 0.0 and (state == "flee" or state == "alert")


func head_pos() -> Vector3:
	if sk and B.has("Head"):
		return sk.global_transform * sk.get_bone_global_pose(B.Head).origin
	return global_position + Vector3(0, 1.4, 0)


func on_pet(p: Node3D, feeding: bool, duration: float) -> void:
	_set_state("pet")
	state_len = duration
	_pet_feed = feeding
	_speed = 0.0
	var to := p.global_position - global_position
	_want_yaw = atan2(to.x, to.z)
	friend_t = 150.0


func on_pet_end() -> void:
	_set_state("idle")
	_toss_t = 0.0
	_tail_flick = 0.6
