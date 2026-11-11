extends Node3D
## 兔子：程序化动画 + 简单的行为
## 状态：idle 待机（呼吸、抖耳朵、张望）/ graze 低头吃草 / wander 蹦着换地方 / alert 站直竖耳朵看你 / flee 快速蹦开
## 模型 characters/rabbit.glb（Tripo 生成 + Blender 加细节，源文件 E:\Godat\meadow_rabbit.blend），正面朝 +Z

const MODEL_PATH := "res://characters/rabbit.glb"
const SCALE := 0.42
const ALERT_DIST := 9.0
const FLEE_DIST := 5.0
const CALM_DIST := 16.0
const Fx := preload("res://scripts/fx.gd")

var world
var state := "idle"
var state_t := 0.0
var state_len := 2.0

var model: Node3D
var sk: Skeleton3D
var B := {}                 # 部位名 -> 骨头序号
var _rest := {}             # 骨头序号 -> 静止时的本地旋转
var _grest := {}            # 骨头序号 -> 静止时的全局 basis（模型空间）
var _rng := RandomNumberGenerator.new()
var _t := 0.0

# 蹦跳
var _hopping := false
var _hop_t := 0.0
var _hop_len := 0.35
var _hop_from := Vector3.ZERO
var _hop_to := Vector3.ZERO
var _hop_h := 0.12
var _hops_left := 0
var _pause := 0.0
var _target := Vector3.ZERO
var _yaw := 0.0
var _want_yaw := 0.0

# 弹簧和小动作
var _sq := 0.0
var _sq_v := 0.0
var _ear := Vector2.ZERO      # 两只耳朵往后甩的量（弹簧）
var _ear_v := Vector2.ZERO
var _twitch := [0.0, 0.0]     # 单只耳朵抖一下
var _twitch_t := 2.0
var _look := 0.0              # 头左右转
var _look_target := 0.0
var _look_t := 1.0
var _head_down := 0.0
var _stand := 0.0             # 站直警觉
var _nibble := 0.0
# 被摸 / 喂（interact.gd 调用）
var friend_t := 0.0           # >0 = 朋友：不怕你，跟着你
var _pet_feed := false
var _binky_t := -1.0          # 开心地原地扭身蹦一下
var _love_t := 4.0


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
	var want := {"root": "Root", "head": "Head_0", "ear_l": "Head_1", "ear_r": "bone_8",
		"fl": "bone_10", "fr": "0_Right_Limb_0", "bl": "0_Left_Limb_0", "br": "1_Right_Limb_0", "tail": "Spine_0"}
	for key in want:
		for i in sk.get_bone_count():
			if sk.get_bone_name(i).ends_with(want[key]):
				B[key] = i
				_rest[i] = sk.get_bone_rest(i).basis.get_rotation_quaternion()
				_grest[i] = sk.get_bone_global_rest(i).basis.orthonormalized()
				break
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
	var outline := load("res://shaders/outline.gdshader") as Shader
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(s)
			var sm := ShaderMaterial.new()
			var whisker := false
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture:
				sm.shader = load("res://shaders/toon_tex.gdshader")
				sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
			else:
				sm.shader = load("res://shaders/toon.gdshader")
				var col := Color(0.9, 0.9, 0.9)
				if src is BaseMaterial3D:
					col = (src as BaseMaterial3D).albedo_color
				whisker = src != null and String(src.resource_name).begins_with("Whisker")
				sm.set_shader_parameter("albedo", col)
				sm.set_shader_parameter("band_threshold", -0.1)
			if not whisker:
				var o := ShaderMaterial.new()
				o.shader = outline
				o.set_shader_parameter("width_px", 1.3)
				sm.next_pass = o
			mi.set_surface_override_material(s, sm)


## 绕模型空间的轴转骨头（比按骨头自己的轴转直观：X = 点头 / 前后摆，Y = 左右转，Z = 左右歪）
func _rot(key: String, axis: Vector3, angle: float, extra := Quaternion.IDENTITY) -> void:
	if not B.has(key):
		return
	var i: int = B[key]
	var g: Basis = _grest[i]
	var local := Quaternion(g.inverse() * Basis(axis, angle) * g)
	sk.set_bone_pose_rotation(i, _rest[i] * local * extra)


func _set_state(s: String) -> void:
	state = s
	state_t = 0.0
	match s:
		"idle":
			state_len = _rng.randf_range(2.0, 5.0)
		"graze":
			state_len = _rng.randf_range(3.0, 7.0)
		"wander":
			_hops_left = _rng.randi_range(3, 7)
			var a := _rng.randf() * TAU
			_target = global_position + Vector3(cos(a), 0, sin(a)) * _hops_left * 0.55
			state_len = 99.0
		"alert":
			state_len = _rng.randf_range(1.5, 3.0)
		"flee":
			_hops_left = _rng.randi_range(10, 16)
			state_len = 99.0


func _process(delta: float) -> void:
	if sk == null or world == null:
		return
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
		# 你拿着胡萝卜慢慢走近：不怕你，凑过来，到跟前低头吃
		var hero = p.get("hero")
		friend_t = maxf(friend_t - delta, 0.0)
		if state == "pet" or _binky_t >= 0.0:
			pass
		elif friend_t > 0.0:
			# 朋友：不怕你。离远了一跳一跳追过来，到跟前就在旁边待着，偶尔冒个小爱心
			if state in ["flee", "alert"]:
				_set_state("idle")
			if dist > 2.6 and dist < 40.0:
				if state != "wander" or state_t > 1.2:
					_set_state("wander")
					_hops_left = 5
					_target = p.global_position - to_player.normalized() * 1.4
			elif dist < 4.0:
				_love_t -= delta
				if _love_t <= 0.0:
					_love_t = _rng.randf_range(6.0, 11.0)
					Fx.heart_pop(get_parent(), head_pos() + Vector3(0, 0.25, 0), 0.16, false)
		elif hero != null and hero.held == "carrot" and not running and dist < 14.0:
			if state in ["flee", "alert"]:
				_set_state("idle")
			if dist > 1.3:
				if state != "wander" or state_t > 1.5:
					_set_state("wander")
					_hops_left = 4
					_target = p.global_position - to_player.normalized() * 1.0
			elif not _hopping and state != "graze":
				_want_yaw = atan2(to_player.x, to_player.z)
				_set_state("graze")
		# 被吓到：太近，或者你跑着冲过来
		elif state != "flee" and (dist < FLEE_DIST or (running and dist < ALERT_DIST)):
			_set_state("flee")
		elif state in ["idle", "graze", "wander"] and dist < ALERT_DIST and not _hopping:
			_set_state("alert")

	match state:
		"pet":
			_want_yaw = atan2(to_player.x, to_player.z)
		"idle":
			if state_t > state_len:
				_set_state("graze" if _rng.randf() < 0.55 else "wander")
		"graze":
			if state_t > state_len:
				_set_state("idle" if _rng.randf() < 0.5 else "wander")
		"alert":
			_want_yaw = atan2(to_player.x, to_player.z)
			if dist > ALERT_DIST + 2.0 and state_t > state_len:
				_set_state("idle")
		"wander":
			_hop_logic(delta, _target - global_position, 0.38, 0.55, 0.11, Vector2(0.15, 0.5))
			if _hops_left <= 0 and not _hopping:
				_set_state("idle")
		"flee":
			var away := -to_player if dist < 1e8 else Vector3(cos(_yaw), 0, sin(_yaw))
			# 逃跑方向稍微随机偏一点，不是死板地直线跑
			away = away.normalized().rotated(Vector3.UP, sin(_t * 0.7) * 0.4)
			_hop_logic(delta, away, 0.27, 1.05, 0.2, Vector2(0.0, 0.05))
			if _hops_left <= 0 and not _hopping:
				_set_state("alert" if dist < CALM_DIST else "idle")

	_yaw = wrapf(_yaw, -PI, PI)
	_yaw = lerp_angle(_yaw, _want_yaw, clampf(delta * (14.0 if state == "flee" else 7.0), 0.0, 1.0))
	rotation.y = _yaw
	if _binky_t >= 0.0:
		# binky：兔子开心时原地跳起来、在空中扭一下身子
		_binky_t += delta / 0.6
		var b := clampf(_binky_t, 0.0, 1.0)
		rotation.y = _yaw + sin(b * TAU) * 0.55
		global_position.y = world.height_raw(global_position.x, global_position.z) + sin(b * PI) * 0.3
		if _binky_t >= 1.0:
			_binky_t = -1.0
			_sq_v -= 5.0
			_ear_v += Vector2(3.0, 3.0)
	_animate(delta)


## 一跳接一跳：朝 dir 方向蹦，每跳之间停一下
func _hop_logic(delta: float, dir: Vector3, hop_len: float, hop_dist: float, hop_h: float, pause: Vector2) -> void:
	if _hopping:
		_hop_t += delta / _hop_len
		var t := clampf(_hop_t, 0.0, 1.0)
		var pos := _hop_from.lerp(_hop_to, t)
		pos.y = world.height_raw(pos.x, pos.z) + sin(t * PI) * _hop_h
		global_position = pos
		if _hop_t >= 1.0:
			_hopping = false
			_hops_left -= 1
			_pause = _rng.randf_range(pause.x, pause.y)
			_sq_v -= 5.0          # 落地压扁
			_ear_v += Vector2(3.0, 3.0)   # 耳朵往前甩一下
		return
	_pause -= delta
	dir.y = 0.0
	if dir.length() < 0.05:
		_hops_left = 0
		return
	_want_yaw = atan2(dir.x, dir.z)
	if _pause > 0.0 or absf(wrapf(_want_yaw - _yaw, -PI, PI)) > 0.6:
		return
	var step := minf(hop_dist, dir.length()) if state == "wander" else hop_dist
	var to := global_position + dir.normalized() * step
	# 不跳进水里、不跳上陡坡
	if world.has_method("in_pond") and world.in_pond(to.x, to.z):
		_want_yaw += PI * 0.5
		return
	if absf(world.height_raw(to.x, to.z) - global_position.y) > step * 0.9:
		_want_yaw += PI * 0.5
		return
	_hopping = true
	_hop_t = 0.0
	_hop_len = hop_len
	_hop_h = hop_h
	_hop_from = global_position
	_hop_to = to
	_sq_v += 4.0                  # 起跳拉长
	_ear_v -= Vector2(5.0, 5.0)   # 耳朵往后甩


func _animate(delta: float) -> void:
	var k := clampf(delta * 10.0, 0.0, 1.0)
	var ht := clampf(_hop_t, 0.0, 1.0) if _hopping else -1.0

	# 头：吃草低头 + 一下一下啃；警觉时抬头；平时偶尔左右张望
	var want_down := 0.0
	if state == "graze":
		want_down = 0.55
		_nibble = sin(_t * 9.0) * 0.06 * (0.5 + 0.5 * sin(_t * 1.7))
	else:
		_nibble = 0.0
	if state == "alert":
		want_down = -0.25
	if state == "pet":
		if _pet_feed:
			want_down = -0.12           # 抬头够你手里的胡萝卜，一口一口啃
			_nibble = sin(_t * 12.0) * 0.07
		else:
			want_down = -0.2 + sin(_t * 3.4) * 0.08   # 往上拱，蹭你的手
	_head_down = lerpf(_head_down, want_down, clampf(delta * 5.0, 0.0, 1.0))
	_look_t -= delta
	if _look_t <= 0.0:
		_look_t = _rng.randf_range(0.8, 2.5)
		_look_target = _rng.randf_range(-0.5, 0.5) if state in ["idle", "alert"] else 0.0
	if state == "pet":
		_look_target = sin(_t * 2.3) * 0.2
	_look = lerpf(_look, _look_target, clampf(delta * 6.0, 0.0, 1.0))

	# 站直（警觉）
	_stand = lerpf(_stand, 1.0 if state == "alert" else 0.0, clampf(delta * 6.0, 0.0, 1.0))

	# 耳朵弹簧 + 单只耳朵偶尔抖一下
	var ear_target := Vector2.ZERO
	if state == "alert":
		ear_target = Vector2(0.15, 0.15)
	elif state == "flee":
		ear_target = Vector2(-0.55, -0.55)
	elif state == "graze":
		ear_target = Vector2(-0.25, -0.2)
	elif state == "pet":
		ear_target = Vector2(-0.6, -0.55)        # 舒服：耳朵放松贴到背上
	# 弹簧分成小步算：帧率低的时候一步跨太大弹簧会炸
	var steps := clampi(int(ceil(delta / 0.008)), 1, 12)
	var h := minf(delta, 0.096) / steps
	for i in steps:
		_ear_v += ((ear_target - _ear) * 160.0 - _ear_v * 10.0) * h
		_ear += _ear_v * h
		_sq_v += (-220.0 * _sq - 12.0 * _sq_v) * h
		_sq += _sq_v * h
	_ear = _ear.clamp(Vector2(-1.2, -1.2), Vector2(0.8, 0.8))
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = _rng.randf_range(1.5, 4.5)
		_twitch[_rng.randi() % 2] = 1.0
	for i in 2:
		_twitch[i] = maxf(_twitch[i] - delta * 5.0, 0.0)

	# 呼吸 + 挤压拉伸
	var breathe := sin(_t * (6.0 if state == "flee" else 2.4)) * 0.02
	_sq = clampf(_sq, -0.3, 0.3)

	# ── 身体（根骨头）：蹦跳时前后俯仰，站直时往后仰 ──
	var pitch := 0.0
	if ht >= 0.0:
		pitch = lerpf(-0.35, 0.3, ht)          # 起跳鼻子朝上，落地前鼻子朝下
	pitch -= _stand * 0.55
	pitch += maxf(_head_down, 0.0) * 0.45      # 吃草时整个身体也往前俯
	_rot("root", Vector3.RIGHT, pitch)
	if B.has("root"):
		var sy := 1.0 + _sq * 0.6 + breathe
		var sxz := 1.0 / sqrt(maxf(sy, 0.3))
		sk.set_bone_pose_scale(B.root, Vector3(sxz, sy, sxz))
		sk.set_bone_pose_position(B.root, sk.get_bone_rest(B.root).origin + Vector3(0, _stand * 0.12, 0))

	# ── 头 ──
	var head_pitch := _head_down + _nibble + _stand * 0.45 + (0.0 if ht < 0.0 else lerpf(0.15, -0.1, ht))
	if B.has("head"):
		var i: int = B.head
		var g: Basis = _grest[i]
		var rq := Basis(Vector3.UP, _look) * Basis(Vector3.RIGHT, head_pitch)
		sk.set_bone_pose_rotation(i, _rest[i] * Quaternion(g.inverse() * rq * g))

	# ── 耳朵：前后甩 + 往两边张开一点 + 抖 ──
	var tw0: float = sin(_twitch[0] * PI * 3.0) * _twitch[0] * 0.35
	var tw1: float = sin(_twitch[1] * PI * 3.0) * _twitch[1] * 0.35
	if B.has("ear_l"):
		var i: int = B.ear_l
		var g: Basis = _grest[i]
		var rq := Basis(Vector3.BACK, -0.08 - tw0 * 0.5) * Basis(Vector3.RIGHT, clampf(_ear.x, -0.9, 0.5) + tw0)
		sk.set_bone_pose_rotation(i, _rest[i] * Quaternion(g.inverse() * rq * g))
	if B.has("ear_r"):
		var i: int = B.ear_r
		var g: Basis = _grest[i]
		var rq := Basis(Vector3.BACK, 0.08 + tw1 * 0.5) * Basis(Vector3.RIGHT, clampf(_ear.y, -0.9, 0.5) + tw1)
		sk.set_bone_pose_rotation(i, _rest[i] * Quaternion(g.inverse() * rq * g))

	# ── 腿：起跳时后腿往后蹬直、前腿收起；空中前腿往前够；落地前后腿往前收 ──
	var front := 0.0
	var back := 0.0
	if ht >= 0.0:
		back = lerpf(0.9, -0.35, smoothstep(0.0, 0.85, ht))
		front = lerpf(0.4, -0.75, smoothstep(0.1, 0.6, ht)) * (1.0 - smoothstep(0.8, 1.0, ht)) + 0.0
	front -= _stand * 0.6
	back += _stand * 0.25
	for key in ["fl", "fr"]:
		_rot(key, Vector3.RIGHT, lerpf(_cur(key), front, k))
	for key in ["bl", "br"]:
		_rot(key, Vector3.RIGHT, lerpf(_cur(key), back, k))
	_legs[0] = lerpf(_legs[0], front, k)
	_legs[1] = lerpf(_legs[1], back, k)

	# 尾巴：小幅摆动，跑的时候摆得快
	_rot("tail", Vector3.UP, sin(_t * (14.0 if state in ["flee", "pet"] else 4.0)) * (0.2 if state == "pet" else 0.12))


var _legs := [0.0, 0.0]
func _cur(key: String) -> float:
	return _legs[0] if key in ["fl", "fr"] else _legs[1]


# ───────────────────────── 互动（interact.gd） ─────────────────────────

func food() -> String:
	return "carrot"


func is_tall() -> bool:
	return false


func pet_range() -> float:
	return 1.9


func can_pet() -> bool:
	return sk != null and state != "flee" and state != "pet" and _binky_t < 0.0


## 怕你、靠不近（用来提示玩家拿胡萝卜）
func is_shy() -> bool:
	return friend_t <= 0.0 and (state == "flee" or state == "alert")


func head_pos() -> Vector3:
	if sk and B.has("head"):
		return sk.global_transform * sk.get_bone_global_pose(B.head).origin
	return global_position + Vector3(0, 0.3, 0)


func on_pet(p: Node3D, feeding: bool, duration: float) -> void:
	if _hopping:
		_hopping = false
		global_position = Vector3(_hop_to.x, world.height_raw(_hop_to.x, _hop_to.z), _hop_to.z)
	_set_state("pet")
	state_len = duration
	_pet_feed = feeding
	var to := p.global_position - global_position
	_want_yaw = atan2(to.x, to.z)
	friend_t = 150.0
	_ear_v += Vector2(2.0, 2.0)


func on_pet_end() -> void:
	_set_state("idle")
	_binky_t = 0.0
	_sq_v += 4.0
	_ear_v -= Vector2(4.0, 4.0)
