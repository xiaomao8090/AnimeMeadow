extends Node3D
## 角色的程序化动画 + 表情（模型 characters/hero.glb，Blender 源文件 E:\Godat\meadow_hero.blend）
##
## 动作：待机（呼吸、左右重心摇晃、小动作、久站犯困）/ 走 / 跑 / 原地转身小碎步 / 起跳拉伸 / 空中 / 落地压扁 / 爬坡
## 次级运动：帽子毛球、围巾尾巴、背包都是弹簧，跟着身体的加速度甩
## 表情：只靠眼睛——上下眼皮（边缘高度 + 倾斜）、瞳孔大小，按状态自动切换；瞳孔跟着视角转，镜头绕到正面时会看着你
##
## 模型节点：Hero(根，挤压拉伸) / Torso / Face / EyeL·R / PupilL·R / LidL·R / LowLidL·R /
##          ArmL·R / LegL·R / PomPivot / ScarfPivot / PackPivot / SweatPivot/Sweat
## 模型正面朝 +Z

const MODEL_PATH := "res://characters/hero.glb"
const EYE_MAX_YAW := deg_to_rad(38.0)
const EYE_MAX_PITCH := deg_to_rad(28.0)

# 表情预设。au = 上眼皮边缘停在眼睛哪个高度（90 全睁 / -90 全闭，单位：度），al = 下眼皮边缘（-90 全睁 / 90 全闭）
# tilt = 上眼皮倾斜（正 = 内眼角压低，生气/使劲；负 = 外眼角压低，难过/累）；pupil = 瞳孔大小
const EXPR := {
	"neutral":   {"au": 70.0, "al": -78.0, "tilt": 0.0,   "pupil": 1.0},
	"happy":     {"au": 45.0, "al": -20.0, "tilt": 0.0,   "pupil": 1.1},
	"content":   {"au": -25.0, "al": 22.0, "tilt": 0.0,   "pupil": 1.0},
	"excited":   {"au": 86.0, "al": -86.0, "tilt": -4.0,  "pupil": 1.15},
	"surprised": {"au": 90.0, "al": -90.0, "tilt": -6.0,  "pupil": 0.62},
	"scared":    {"au": 90.0, "al": -90.0, "tilt": -10.0, "pupil": 0.5},
	"effort":    {"au": 30.0, "al": -55.0, "tilt": 16.0,  "pupil": 0.95},
	"tired":     {"au": 38.0, "al": -72.0, "tilt": -12.0, "pupil": 1.0},
	"sleepy":    {"au": 4.0,  "al": -66.0, "tilt": -6.0,  "pupil": 1.0},
	"wince":     {"au": -62.0, "al": 8.0,  "tilt": 22.0,  "pupil": 1.0},
	"curious":   {"au": 80.0, "al": -82.0, "tilt": -3.0,  "pupil": 1.05},
	"focused":   {"au": 58.0, "al": -70.0, "tilt": 6.0,   "pupil": 1.0},
	"yawn":      {"au": -40.0, "al": 10.0, "tilt": -8.0,  "pupil": 1.0},
}

var player: CharacterBody3D
var model: Node3D
var root_n: Node3D
var torso: Node3D
var face: Node3D
var pom: Node3D
var scarf: Node3D
var pack: Node3D
var sweat_piv: Node3D
var sweat: Node3D
var eyes: Array[Node3D] = []
var pupils: Array[Node3D] = []
var glints: Array[Node3D] = []
var lids: Array[Node3D] = []
var low_lids: Array[Node3D] = []
var arms: Array[Node3D] = []
var legs: Array[Node3D] = []
var _torso_base := Vector3.ZERO
var _leg_base: Array[Vector3] = []
var _arm_base: Array[Vector3] = []
var _pack_base := Vector3.ZERO
var _sweat_base := Vector3.ZERO

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _yaw := 0.0
var _yaw_rate := 0.0
var _turning := false
var _shuffle := 0.0

# 状态
var _was_ground := true
var _prev_vy := 0.0
var _air_time := 0.0
var _idle_time := 0.0
var _run_time := 0.0          # 连续跑了多久
var _tired := 0.0             # 0..1 喘气程度（跑久了停下来会喘）
var _climb_time := 0.0
var _wince_t := 0.0
var _land_happy_t := 0.0
var _jump_t := 99.0           # 起跳后过了多久
var _surprise_t := 0.0
var _prev_phase := 0.0

# 待机小动作
var _fidget := ""
var _fidget_t := 0.0
var _fidget_len := 0.0
var _next_fidget := 5.0
var _look_override := Vector3.ZERO
var _yawn_t := -1.0
var _next_yawn := 8.0

# 弹簧
var _sq := 0.0                # 挤压拉伸：正 = 竖着拉长，负 = 压扁
var _sq_v := 0.0
var _lean := Vector2.ZERO     # 加速时身体前后/左右倾（弧度）
var _lean_v := Vector2.ZERO
var _pom := Vector2.ZERO
var _pom_v := Vector2.ZERO
var _scarf := Vector2.ZERO
var _scarf_v := Vector2.ZERO
var _pack := 0.0
var _pack_v := 0.0
var _pack_y := 0.0
var _pack_yv := 0.0
var _prev_vel := Vector3.ZERO
var _acc := Vector3.ZERO      # 角色本地空间的加速度（平滑过）

# 表情（当前值，平滑过渡）
var _au := 70.0
var _al := -78.0
var _tilt := 0.0
var _pupil := 1.0
var _blink := 0.0
var _blink_phase := -1.0
var _blink_t := 2.0
var _eye_saccade := Vector2.ZERO
var _saccade_t := 0.0
var _sweat_a := 0.0
var expression_override := ""   # 强制某个表情（调试用；主菜单悬停按钮时也会用）
var look_lock := false
# 互动动作（摸动物、喂东西、被点击时的反应）：play_act() 开始，按节拍发 act_beat 信号给特效用
signal act_beat(act: String, beat: String)
const ACTS := {"pet": 2.7, "feed": 3.0, "giggle": 1.5, "spin": 1.15, "boing": 1.0, "dizzy": 2.8, "wave": 1.6}
var act := ""
var act_high := false            # 对象比较高（小鹿）：手往前伸，不蹲
var _act_t := 0.0
var _act_len := 1.0
var _act_target := Vector3.ZERO
var _act_drop := 0.0
var _act_spin := 0.0
var _act_beats := {}          # true = 眼睛只看 look_target（主菜单里跟着鼠标）
var blink_override := -1.0      # 调试用

var dust: GPUParticles3D

# 第一人称 + 手持物品
var first_person := false
var held := ""                  # 现在手里拿的东西（props/ 里的文件名，空 = 空手）
var _held_node: Node3D
var _socket: Node3D             # 右手上的挂点
var _body_mat: ShaderMaterial   # 身体（含头）的材质：第一人称时把头压平
var _body_outline: ShaderMaterial
var _skin_col := Color(1, 0.8, 0.65)
var _coat_col := Color(0.85, 0.32, 0.18)
var _hold := 0.0                # 0..1 举着东西的程度
const HEAD_PARTS := ["Hat", "Eye", "Pupil", "Glint", "Eyelid", "LowEyelid", "Blush", "Sweat"]
# 第一人称：只显示两只手（袖子、袖口、手），动作和第三人称完全一样；其它部分只留影子（影子还是完整的人）
const ARM_PARTS := ["Sleeve", "Cuff", "Hand", "Thumb"]
const SIT_DROP := 0.38           # 坐下时身体降低多少（正好让屁股贴地）
const NET_HOOP := Vector3(0.061, 0.865, 0.038)     # 网圈中心（物品本地坐标）
const ROD_TIP := Vector3(0.004, 1.254, 0.262)      # 竿尖

# 工具
var busy := false               # 坐着钓鱼时不能走动
var caught_bugs := 0
var caught_fish := 0
var _use_t := -1.0              # 挥网进度 0..1（-1 = 没在挥）
var _swing_hit := false
var _fish := ""                 # 钓鱼状态："" / cast 甩竿 / wait 等 / bite 咬钩 / pull 收竿
var _fish_t := 0.0
var _fish_wait := 5.0
var _fish_ok := false
var _sit := 0.0
var _bob: Node3D
var _bob_from := Vector3.ZERO
var _bob_to := Vector3.ZERO
var _bob_level := 0.0
var _splash_t := 0.0
var _line: MeshInstance3D
var _line_mesh: ImmediateMesh
var _soft_mat: ShaderMaterial
var _soft := Vector3.ZERO
var _soft_v := Vector3.ZERO
var _sock_prev := Vector3.ZERO
var _toast: Label
var _toast_t := 0.0


func _ready() -> void:
	_rng.randomize()
	model = _load_model()
	if model == null:
		push_warning("找不到角色模型 " + MODEL_PATH)
		return
	add_child(model)
	root_n = _find("Hero")
	torso = _find("Torso")
	face = _find("Face")
	pom = _find("PomPivot")
	scarf = _find("ScarfPivot")
	pack = _find("PackPivot")
	sweat_piv = _find("SweatPivot")
	sweat = _find("Sweat")
	for side in ["L", "R"]:
		eyes.append(_find("Eye" + side))
		pupils.append(_find("Pupil" + side))
		glints.append(_find("Glint" + side))
		lids.append(_find("Lid" + side))
		low_lids.append(_find("LowLid" + side))
		arms.append(_find("Arm" + side))
		legs.append(_find("Leg" + side))
	_torso_base = torso.position if torso else Vector3.ZERO
	for i in 2:
		_leg_base.append(legs[i].position if legs[i] else Vector3.ZERO)
		_arm_base.append(arms[i].position if arms[i] else Vector3.ZERO)
	_pack_base = pack.position if pack else Vector3.ZERO
	_sweat_base = sweat_piv.position if sweat_piv else Vector3.ZERO
	_apply_toon(model)
	# 右手挂点：手心稍微靠前；转 90° 让物品在手臂往前伸时是竖着的
	if arms[1]:
		_socket = Node3D.new()
		_socket.name = "HandSocket"
		_socket.position = Vector3(-0.07, -0.37, 0.045)
		_socket.rotation.x = PI * 0.5
		arms[1].add_child(_socket)
	_build_dust()


func _find(n: String) -> Node3D:
	return model.find_child(n, true, false) as Node3D


func _load_model() -> Node3D:
	if ResourceLoader.exists(MODEL_PATH):
		var ps := load(MODEL_PATH) as PackedScene
		if ps:
			return ps.instantiate() as Node3D
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(MODEL_PATH), state) == OK:
		return doc.generate_scene(state) as Node3D
	return null


## 换成项目里的卡通着色 + 描边
func _apply_toon(n: Node) -> void:
	var toon := load("res://shaders/toon.gdshader") as Shader
	var outline := load("res://shaders/outline.gdshader") as Shader
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var nm := String(m.name)
		var face_detail := nm.begins_with("Glint") or nm.begins_with("Blush") or nm.begins_with("Zip") or nm == "Sweat"
		for s in m.mesh.get_surface_count():
			var src := m.get_active_material(s)
			var col := Color(0.8, 0.8, 0.8)
			if src is BaseMaterial3D:
				col = (src as BaseMaterial3D).albedo_color
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/toon_hero.gdshader") if nm == "Body" else toon
			if nm == "Body":
				_body_mat = sm
				_skin_col = col
			elif nm == "Coat":
				_coat_col = col
			sm.set_shader_parameter("albedo", col)
			sm.set_shader_parameter("rim_strength", 0.18)
			sm.set_shader_parameter("band_threshold", 0.0)
			if nm.begins_with("Pupil") or nm.begins_with("Glint") or nm.begins_with("EyeWhite") or nm == "Sweat":
				sm.set_shader_parameter("band_threshold", -0.7)   # 五官几乎不吃阴影，保持清楚
				sm.set_shader_parameter("rim_strength", 0.05)
			if nm.begins_with("Eyelid") or nm.begins_with("LowEyelid"):
				sm.set_shader_parameter("rim_strength", 0.03)   # 眼皮边缘光太亮会像玻璃
			if not face_detail:
				var o := ShaderMaterial.new()
				o.shader = outline
				o.set_shader_parameter("width_px", 1.6)
				sm.next_pass = o
				if nm == "Body":
					_body_outline = o
			m.set_surface_override_material(s, sm)
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if face_detail else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 第一人称（参考 CS2）：低头只看到自己的腿和脚；头、身体、背包、左手都不显示，只留影子；
## 右手只有拿着东西时才显示。这样身体不会挡住视线，镜头也不会穿进模型里
func set_first_person(fp: bool) -> void:
	first_person = fp
	if _body_mat:
		# 切回第三人称时一定要把压平取消，否则头会一直是扁的（看起来像透明了）
		if not fp:
			_body_mat.set_shader_parameter("squash_y", 100000.0)
		_body_mat.set_shader_parameter("cap_color", _coat_col.darkened(0.55))
		# 描边是往外扩的外壳，第一人称时镜头会在它里面，关掉
		_body_mat.next_pass = null if fp else _body_outline
	_refresh_parts()


func _refresh_parts() -> void:
	if model == null:
		return
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if _held_node and _held_node.is_ancestor_of(m):
			continue
		var nm := String(m.name)
		var hide := false
		if first_person:
			hide = true
			for h: String in ARM_PARTS:
				if nm.begins_with(h):
					hide = false
		var tiny := nm.begins_with("Glint") or nm.begins_with("Blush") or nm.begins_with("Zip") or nm == "Sweat"
		if hide:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		else:
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tiny else GeometryInstance3D.SHADOW_CASTING_SETTING_ON


## 拿起 / 放下东西。name 是 props/ 里的文件名（不带 .glb），空字符串 = 空手
func hold(name: String) -> void:
	_stop_fishing()
	_use_t = -1.0
	_soft_mat = null
	if _held_node:
		_held_node.queue_free()
		_held_node = null
	held = name
	_refresh_parts()
	if name == "" or _socket == null:
		return
	var path := "res://props/%s.glb" % name
	var node: Node3D = null
	if ResourceLoader.exists(path):
		var ps := load(path) as PackedScene
		if ps:
			node = ps.instantiate() as Node3D
	if node == null:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(ProjectSettings.globalize_path(path), st) == OK:
			node = doc.generate_scene(st) as Node3D
	if node == null:
		held = ""
		return
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var sm := ShaderMaterial.new()
			var soft := String(m.name).begins_with("NetBag")
			sm.shader = load("res://shaders/item_soft.gdshader" if soft else "res://shaders/toon_tex.gdshader")
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture:
				sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
			if soft:
				_soft_mat = sm       # 网兜：不描边（描边不会跟着晃），用弹簧驱动
			else:
				var o := ShaderMaterial.new()
				o.shader = load("res://shaders/outline.gdshader")
				o.set_shader_parameter("width_px", 1.2)
				sm.next_pass = o
			m.set_surface_override_material(i, sm)
	_socket.add_child(node)
	_held_node = node
	_sock_prev = _socket.global_position
	_soft = Vector3.ZERO
	_soft_v = Vector3.ZERO
	_sq_v += 2.0


# ───────────────────────── 尘土 ─────────────────────────

func _build_dust() -> void:
	dust = GPUParticles3D.new()
	dust.amount = 96
	dust.lifetime = 0.55
	dust.emitting = true
	dust.amount_ratio = 0.0       # 不自动喷，只在跳跃/落地时用 emit_particle 手动喷
	dust.local_coords = false
	dust.one_shot = false
	var pm := ParticleProcessMaterial.new()
	pm.gravity = Vector3(0, -6.0, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.0
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(0.7, 0.8))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1.0))
	g.add_point(0.75, Color(1, 1, 1, 1.0))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	dust.process_material = pm
	# 每个点就是一个小白球：不用贴图、不做透明，任何渲染器下都是干净的白点；消失时靠缩小
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1)
	var q := SphereMesh.new()
	q.radius = 0.032
	q.height = 0.064
	q.radial_segments = 8
	q.rings = 4
	q.material = mat
	dust.draw_pass_1 = q
	dust.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dust.top_level = true
	add_child(dust)


func _puff(pos: Vector3, count: int, spread: float, up: float) -> void:
	if dust == null or not visible:
		return
	# 每次临时生成一个一次性爆开的粒子：一圈白色小点往外蹦，落回地上消失
	var p := GPUParticles3D.new()
	p.amount = count * 2
	p.lifetime = 0.55
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := (dust.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 0.18
	pm.emission_ring_inner_radius = 0.1
	pm.emission_ring_height = 0.02
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 75.0
	pm.initial_velocity_min = spread * 0.9
	pm.initial_velocity_max = spread * 1.7 + up
	p.process_material = pm
	p.draw_pass_1 = dust.draw_pass_1
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.top_level = true
	p.global_position = pos + Vector3(0, 0.06, 0)
	p.emitting = true
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


# ───────────────────────── 主循环 ─────────────────────────

## 每帧由 player.gd 调用。look_target：镜头瞄准的世界坐标；phase：步子相位（整数 = 一只脚落地）
func animate(delta: float, look_target: Vector3, phase: float, run: float, on_floor: bool, climbing: bool) -> void:
	if model == null or delta <= 0.0:
		return
	_t += delta
	var v := player.velocity
	var hspeed := Vector2(v.x, v.z).length()
	var move := clampf(hspeed / 2.0, 0.0, 1.0)
	var grounded := on_floor or climbing

	_tick_act(delta)
	if first_person:
		# 第一人称：身体永远正对镜头方向，低头看到的才是正的
		_yaw = player.global_rotation.y + PI
		_yaw_rate = 0.0
		_turning = false
		global_rotation = Vector3(0.0, _yaw, 0.0)
	elif act != "" and _act_target != Vector3.ZERO:
		# 互动时转身面对对象
		var to := _act_target - global_position
		if Vector2(to.x, to.z).length() > 0.2:
			_yaw = lerp_angle(_yaw, atan2(to.x, to.z), clampf(delta * 8.0, 0.0, 1.0))
		_yaw_rate = 0.0
		global_rotation = Vector3(0.0, _yaw, 0.0)
	else:
		_update_facing(delta, v, hspeed, look_target)
	_update_events(delta, v, grounded, climbing, hspeed, run)

	# 本地加速度（平滑），给身体倾斜和次级运动用
	var acc_w := (v - _prev_vel) / delta
	_prev_vel = v
	var acc_l := global_transform.basis.inverse() * acc_w
	_acc = _acc.lerp(acc_l, clampf(delta * 10.0, 0.0, 1.0))

	var idle := grounded and not climbing and hspeed < 0.25 and absf(_yaw_rate) < 0.8
	if idle:
		_idle_time += delta
	else:
		_idle_time = 0.0
		_fidget = ""
		_yawn_t = -1.0

	_animate_body(delta, phase, run, move, grounded, climbing, idle)
	_update_secondary(delta, hspeed, grounded)
	_update_tools(delta)
	_update_expression(delta, run, grounded, climbing, idle)
	_update_eyes(delta, look_target, idle)
	_prev_phase = phase


func _update_facing(delta: float, v: Vector3, hspeed: float, look_target: Vector3) -> void:
	var want := _yaw
	if hspeed > 0.3:
		want = atan2(v.x, v.z)
		_turning = false
	elif look_target != Vector3.ZERO:
		var to := look_target - global_position
		if Vector2(to.x, to.z).length() > 0.5:
			var diff := absf(wrapf(atan2(to.x, to.z) - _yaw, -PI, PI))
			if diff > deg_to_rad(55.0):
				_turning = true
			elif diff < deg_to_rad(4.0):
				_turning = false
			if _turning:
				want = atan2(to.x, to.z)
	var before := _yaw
	_yaw = lerp_angle(_yaw, want, clampf(delta * (9.0 if hspeed > 0.3 else 4.0), 0.0, 1.0))
	_yaw_rate = lerpf(_yaw_rate, wrapf(_yaw - before, -PI, PI) / delta, clampf(delta * 12.0, 0.0, 1.0))
	global_rotation = Vector3(0.0, _yaw, 0.0)


func _update_events(delta: float, v: Vector3, grounded: bool, climbing: bool, hspeed: float, run: float) -> void:
	_jump_t += delta
	# 起跳：竖着拉长，扬一点土
	if _was_ground and not grounded and v.y > 1.5:
		_jump_t = 0.0
		_sq_v += 7.5
		_puff(global_position, 6, 1.2, 0.4)
	# 落地：按下落速度压扁；摔得重会疼得闭眼
	if not _was_ground and grounded:
		var impact := maxf(-_prev_vy, 0.0)
		_sq_v -= clampf(impact * 1.6, 2.0, 16.0)
		if impact > 3.0:
			_puff(global_position, 10 if impact < 8.0 else 16, 1.0 + impact * 0.18, 0.5)
		if impact > 9.0:
			_wince_t = 0.55
		elif _air_time > 0.35:
			_land_happy_t = 0.6
		_air_time = 0.0
	if not grounded:
		_air_time += delta
	_was_ground = grounded
	_prev_vy = v.y

	# 跑久了会累；停下来后喘一会儿
	if run > 0.6 and grounded and not climbing:
		_run_time += delta
	else:
		_run_time = maxf(_run_time - delta * 2.0, 0.0)
	if _run_time > 5.0:
		_tired = minf(_tired + delta * 0.3, 1.0)
	elif hspeed < 0.5:
		_tired = maxf(_tired - delta * 0.18, 0.0)
	_climb_time = _climb_time + delta if climbing else 0.0
	_wince_t -= delta
	_land_happy_t -= delta
	_surprise_t -= delta


# ───────────────────────── 身体 ─────────────────────────

func _animate_body(delta: float, phase: float, run: float, move: float, grounded: bool, climbing: bool, idle: bool) -> void:
	var k := clampf(delta * 14.0, 0.0, 1.0)
	var p := phase * PI
	var air := 0.0 if grounded else 1.0
	var rising := not grounded and player.velocity.y > 0.0

	var leg_x := [0.0, 0.0]
	var leg_lift := [0.0, 0.0]
	var leg_z := [0.0, 0.0]
	var arm_x := [0.0, 0.0]
	var arm_z := [0.09, 0.09]
	var t_pos := Vector3.ZERO
	var t_rot := Vector3.ZERO
	var breath_s := 0.0

	if climbing:
		# 爬坡：手脚交替往上够，身体贴着坡面左右扭
		var c := sin(phase * PI)
		arm_x = [-2.5 + c * 0.55, -2.5 - c * 0.55]
		arm_z = [0.25, 0.25]
		leg_x = [-0.6 - c * 0.45, -0.6 + c * 0.45]
		leg_lift = [maxf(c, 0.0) * 0.08, maxf(-c, 0.0) * 0.08]
		t_rot = Vector3(0.35, c * 0.1, c * 0.06)
		t_pos.y = absf(c) * 0.02
	elif not grounded:
		# 空中：上升时收腿举手（兴奋），下落时手往上张、腿乱蹬；掉得久了手脚乱挥
		var flail := clampf((_air_time - 0.5) * 1.5, 0.0, 1.0) * (0.0 if rising else 1.0)
		var w := sin(_t * 16.0)
		if rising:
			arm_x = [-2.1, -2.1]
			arm_z = [0.55, 0.55]
			leg_x = [-0.55, 0.35]
			leg_lift = [0.06, 0.02]
		else:
			arm_x = [-2.5 + w * 0.5 * flail, -2.5 - w * 0.5 * flail]
			arm_z = [0.7 + w * 0.2 * flail, 0.7 - w * 0.2 * flail]
			leg_x = [-0.2 + w * 0.5 * flail, 0.15 - w * 0.5 * flail]
			leg_z = [0.12, -0.12]
		t_rot.x = -0.08 if rising else 0.05
	else:
		# ── 走 / 跑 ──
		var amp := lerpf(0.42, 0.85, run) * move
		var c := cos(p)
		var s := sin(p)
		leg_x = [amp * c, -amp * c]
		var lift_h := lerpf(0.035, 0.08, run) * move
		leg_lift = [maxf(s, 0.0) * lift_h, maxf(-s, 0.0) * lift_h]
		arm_x = [-amp * c * 0.95 - 0.35 * run * move, amp * c * 0.95 - 0.35 * run * move]
		arm_z = [0.09 + 0.05 * run, 0.09 + 0.05 * run]
		# 落脚那一下最低，两脚交错时最高
		t_pos.y = (1.0 - absf(c)) * lerpf(0.022, 0.055, run) * move - lerpf(0.0, 0.03, run) * move
		# 重心落在支撑脚那边 + 肩膀和胯反向扭
		t_rot.z = c * lerpf(0.05, 0.035, run) * move
		t_rot.y = c * lerpf(0.09, 0.14, run) * move
		t_pos.x = c * 0.012 * move
		t_rot.x = lerpf(0.04, 0.16, run) * move

		# ── 原地转身：小碎步 ──
		if move < 0.2 and absf(_yaw_rate) > 0.8:
			_shuffle += absf(_yaw_rate) * delta * 1.6
			var sh := sin(_shuffle * PI)
			leg_lift = [maxf(sh, 0.0) * 0.05, maxf(-sh, 0.0) * 0.05]
			leg_x = [sh * 0.15, -sh * 0.15]

		# ── 待机：呼吸 + 左右重心摇晃 + 手臂微摆 ──
		var still := 1.0 - move
		var breath := sin(_t * (2.1 + _tired * 3.5))
		breath_s = breath * (0.012 + _tired * 0.025) * still
		var sway := sin(_t * 1.05) * 0.055 + sin(_t * 0.43 + 1.3) * 0.02
		t_rot.z += sway * still
		t_pos.x += sway * 0.07 * still
		leg_z = [-sway * 0.35 * still, -sway * 0.35 * still]
		arm_z[0] += (0.02 + breath * 0.012 - sway * 0.25) * still
		arm_z[1] += (0.02 + breath * 0.012 + sway * 0.25) * still
		arm_x[0] += sin(_t * 1.05 + 0.6) * 0.06 * still
		arm_x[1] += sin(_t * 1.05 + 2.2) * 0.06 * still
		# 累了：弯腰喘气，手垂下来
		t_rot.x += 0.18 * _tired * still
		t_pos.y += breath * 0.012 * _tired * still

		if idle:
			_apply_fidget(delta, t_pos, t_rot, arm_x, arm_z, leg_lift)
			t_pos = _fid_pos
			t_rot = _fid_rot

	# 加速 / 刹车 / 转弯时身体前后左右倾（弹簧，会稍微过冲再回来）
	var lean_target := Vector2(clampf(_acc.z * 0.035, -0.3, 0.3), clampf(-_acc.x * 0.03, -0.25, 0.25))
	if grounded:
		lean_target.y += clampf(-_yaw_rate * Vector2(player.velocity.x, player.velocity.z).length() * 0.025, -0.2, 0.2)
	_spring2(delta, lean_target, 90.0, 11.0, "_lean", "_lean_v")
	t_rot.x += _lean.x
	t_rot.z += _lean.y

	# 手里拿着东西：右手举在身前（爬坡时两只手都要用，先放下）
	_hold = lerpf(_hold, 1.0 if (held != "" and not climbing) else 0.0, clampf(delta * 9.0, 0.0, 1.0))
	var arm_k := k * 0.8
	if _hold > 0.01:
		# 不同的东西举的角度不一样：食物举在面前，网和竿是长的，竖着拿
		var base := -1.25
		var base_fp := -1.75
		if held == "net":
			base = -1.0
			base_fp = -1.5
		elif held == "rod":
			base = -0.85
			base_fp = -1.3
		var carry := (base_fp if first_person else base) + sin(p) * 0.07 * move + sin(_t * 2.1) * 0.02
		var side := -0.06
		if _use_t >= 0.0:
			# 挥网：先举过头顶往后拉，再从右上往左下扫过身前，最后收回来
			var u := _use_t
			var wind := smoothstep(0.0, 0.22, u)
			var sweep := smoothstep(0.22, 0.6, u)
			var back := smoothstep(0.75, 1.0, u)
			carry = lerpf(lerpf(lerpf(carry, -2.9, wind), -0.75, sweep), carry, back)
			side = lerpf(lerpf(lerpf(side, 0.45, wind), -0.75, sweep), side, back)
			t_rot.y += (wind * 0.35 - sweep * 0.8) * (1.0 - back)
			t_rot.x += sweep * 0.18 * (1.0 - back)
			arm_k = 0.7
		elif _fish == "cast":
			var u := clampf(_fish_t / 0.7, 0.0, 1.0)
			carry = lerpf(lerpf(carry, -2.7, smoothstep(0.0, 0.35, u)), -0.7, smoothstep(0.35, 0.7, u))
			arm_k = 0.6
		elif _fish == "pull":
			var u := clampf(_fish_t / 0.6, 0.0, 1.0)
			carry = lerpf(-0.8, -2.6, sin(u * PI))
			t_rot.x -= 0.2 * sin(u * PI)
			arm_k = 0.6
		elif _fish == "bite":
			carry += sin(_t * 30.0) * 0.05       # 咬钩时竿子抖
		arm_x[1] = lerpf(arm_x[1], carry, _hold)
		arm_z[1] = lerpf(arm_z[1], side, _hold)

	# 坐下（钓鱼时）：整个身体降下来，腿往前伸平，上身微微后仰，左手撑在身侧
	_sit = lerpf(_sit, 1.0 if _fish != "" else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	if _sit > 0.01:
		leg_x[0] = lerpf(leg_x[0], -1.45, _sit)
		leg_x[1] = lerpf(leg_x[1], -1.45, _sit)
		leg_z[0] = lerpf(leg_z[0], 0.14, _sit)
		leg_z[1] = lerpf(leg_z[1], -0.14, _sit)
		leg_lift[0] = lerpf(leg_lift[0], 0.0, _sit)
		leg_lift[1] = lerpf(leg_lift[1], 0.0, _sit)
		arm_x[0] = lerpf(arm_x[0], 0.35, _sit)
		arm_z[0] = lerpf(arm_z[0], 0.3, _sit)
		t_rot.x = lerpf(t_rot.x, -0.1, _sit)
		t_pos.y = lerpf(t_pos.y, sin(_t * 1.8) * 0.006, _sit)
	if act != "":
		_apply_act(delta, t_pos, t_rot, arm_x, arm_z, leg_x, leg_lift)
		t_pos = _fid_pos
		t_rot = _fid_rot
	else:
		_act_drop = lerpf(_act_drop, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		_act_spin = 0.0
	if model:
		model.rotation.y = _act_spin
	if root_n:
		root_n.position.y = -SIT_DROP * _sit - _act_drop
	if arms[1]:
		# 第一人称时把举着的手往上、往中间挪一点，这样拿的东西会出现在画面右下角
		var fp_off := Vector3(0.08, 0.16, 0.14) * (_hold if first_person else 0.0)
		arms[1].position = arms[1].position.lerp(_arm_base[1] + fp_off, k)

	for i in 2:
		if legs[i]:
			legs[i].rotation.x = lerpf(legs[i].rotation.x, leg_x[i], k)
			legs[i].rotation.z = lerpf(legs[i].rotation.z, leg_z[i], k)
			legs[i].position = legs[i].position.lerp(_leg_base[i] + Vector3(0, leg_lift[i], 0), k)
		if arms[i]:
			var s := 1.0 if i == 0 else -1.0
			var ak := arm_k if i == 1 else k * 0.8
			arms[i].rotation.x = lerpf(arms[i].rotation.x, arm_x[i], ak)
			arms[i].rotation.z = lerpf(arms[i].rotation.z, arm_z[i] * s, ak)
	if torso:
		torso.position = torso.position.lerp(_torso_base + t_pos, k)
		torso.rotation = torso.rotation.lerp(t_rot, k)

	# 挤压拉伸（以脚底为中心，保持体积）
	_sq_v += (-260.0 * _sq - 14.0 * _sq_v) * delta
	_sq += _sq_v * delta
	_sq = clampf(_sq, -0.35, 0.35)
	var sy := 1.0 + _sq * 0.55 + breath_s
	var sxz := 1.0 / sqrt(maxf(sy, 0.3))
	if root_n:
		root_n.scale = Vector3(sxz, sy, sxz)
	air = air


# 待机小动作的输出（避免传数组引用的麻烦）
var _fid_pos := Vector3.ZERO
var _fid_rot := Vector3.ZERO

func _apply_fidget(delta: float, t_pos: Vector3, t_rot: Vector3, arm_x: Array, arm_z: Array, leg_lift: Array) -> void:
	_fid_pos = t_pos
	_fid_rot = t_rot
	if _idle_time > 24.0:
		# 犯困：身体慢慢往前点头，偶尔打哈欠伸懒腰
		var nod := (sin(_t * 0.7) * 0.5 + 0.5)
		_fid_rot.x += 0.08 + nod * 0.06
		_fid_pos.y -= 0.01 * nod
		arm_z[0] -= 0.04
		arm_z[1] -= 0.04
		_next_yawn -= delta
		if _yawn_t < 0.0 and _next_yawn <= 0.0:
			_yawn_t = 0.0
			_next_yawn = _rng.randf_range(7.0, 12.0)
	if _yawn_t >= 0.0:
		_yawn_t += delta
		var y := sin(clampf(_yawn_t / 2.2, 0.0, 1.0) * PI)
		arm_x[0] = lerpf(arm_x[0], -2.9, y)
		arm_x[1] = lerpf(arm_x[1], -2.9, y)
		arm_z[0] = lerpf(arm_z[0], 0.35, y)
		arm_z[1] = lerpf(arm_z[1], 0.35, y)
		_fid_rot.x -= 0.12 * y
		_sq_v += 0.6 * y * delta * 10.0
		if _yawn_t > 2.2:
			_yawn_t = -1.0
		return

	if _idle_time < 24.0:
		_next_fidget -= delta
		if _fidget == "" and _next_fidget <= 0.0:
			var choices := ["look", "look", "bounce", "stretch", "hum", "pack"]
			_fidget = choices[_rng.randi() % choices.size()]
			_fidget_t = 0.0
			_fidget_len = {"look": 3.0, "bounce": 1.3, "stretch": 2.0, "hum": 3.6, "pack": 1.6}[_fidget]
			_next_fidget = _rng.randf_range(4.0, 9.0)
			if _fidget == "look":
				var a := _rng.randf_range(-1.2, 1.2)
				_look_override = global_position + global_transform.basis * Vector3(sin(a) * 6.0, _rng.randf_range(0.5, 3.0), cos(a) * 6.0)
	if _fidget == "":
		return
	_fidget_t += delta
	var u := clampf(_fidget_t / _fidget_len, 0.0, 1.0)
	var env := sin(u * PI)
	match _fidget:
		"look":
			# 东张西望：中途换一个方向看
			if _fidget_t > 1.5 and _fidget_t - delta <= 1.5:
				var a := _rng.randf_range(-1.2, 1.2)
				_look_override = global_position + global_transform.basis * Vector3(sin(a) * 6.0, _rng.randf_range(0.3, 2.5), cos(a) * 6.0)
			var loc := global_transform.basis.inverse() * (_look_override - global_position)
			_fid_rot.y += clampf(atan2(loc.x, loc.z), -0.5, 0.5) * 0.5 * env
		"bounce":
			# 原地蹦两下
			var b := absf(sin(u * TAU))
			_fid_pos.y += b * 0.06 * env
			leg_lift[0] = b * 0.03
			leg_lift[1] = b * 0.03
			arm_z[0] += b * 0.3
			arm_z[1] += b * 0.3
			if fmod(_fidget_t, _fidget_len * 0.5) < delta:
				_sq_v -= 3.0
		"stretch":
			# 伸懒腰：双手举过头顶，身体往上拉
			arm_x[0] = lerpf(arm_x[0], -2.95, env)
			arm_x[1] = lerpf(arm_x[1], -2.95, env)
			arm_z[0] = lerpf(arm_z[0], 0.25, env)
			arm_z[1] = lerpf(arm_z[1], 0.25, env)
			_fid_rot.x -= 0.1 * env
			_fid_rot.z += sin(_fidget_t * 3.0) * 0.05 * env
			_sq = lerpf(_sq, 0.06 * env, 0.2)
		"hum":
			# 闭眼哼歌：跟着节奏左右摆
			_fid_rot.z += sin(_fidget_t * 5.0) * 0.07 * env
			_fid_pos.y += absf(sin(_fidget_t * 5.0)) * 0.012 * env
			arm_z[0] += (0.1 + sin(_fidget_t * 5.0) * 0.08) * env
			arm_z[1] += (0.1 - sin(_fidget_t * 5.0) * 0.08) * env
		"pack":
			# 拽一下背包带：右手往肩上抬，耸一下肩
			arm_x[1] = lerpf(arm_x[1], -1.9, env)
			arm_z[1] = lerpf(arm_z[1], -0.35, env)
			_fid_pos.y += sin(u * TAU * 2.0) * 0.012 * env
			if absf(_fidget_t - _fidget_len * 0.5) < delta:
				_pack_yv += 1.2
	if _fidget_t >= _fidget_len:
		_fidget = ""


func _spring2(delta: float, target: Vector2, stiff: float, damp: float, x_name: String, v_name: String) -> void:
	var x: Vector2 = get(x_name)
	var vv: Vector2 = get(v_name)
	vv += ((target - x) * stiff - vv * damp) * delta
	x += vv * delta
	set(x_name, x)
	set(v_name, vv)


# ───────────────────────── 次级运动 ─────────────────────────

func _update_secondary(delta: float, hspeed: float, grounded: bool) -> void:
	# 惯性：身体加速时挂件往反方向甩；竖直方向用挤压弹簧的速度
	var a := _acc
	var vert := _sq_v
	# 毛球：比较软，晃得明显
	var pom_t := Vector2(clampf(a.z * 0.05, -0.8, 0.8) + vert * 0.02, clampf(-a.x * 0.05, -0.8, 0.8) + _yaw_rate * 0.08)
	_spring2(delta, pom_t, 120.0, 6.0, "_pom", "_pom_v")
	if pom:
		pom.rotation = Vector3(_pom.x, 0.0, _pom.y)
	# 围巾尾巴：跑起来往后飘并抖动
	var flutter := sin(_t * 17.0) * 0.06 * clampf(hspeed / 4.0, 0.0, 1.0)
	var sc_t := Vector2(clampf(-hspeed * 0.13, -0.9, 0.0) + clampf(a.z * 0.04, -0.5, 0.5) + flutter, clampf(-a.x * 0.04, -0.5, 0.5) + _yaw_rate * 0.1)
	if not grounded:
		sc_t.x -= clampf(player.velocity.y * 0.08, -0.6, 0.6)
	_spring2(delta, sc_t, 70.0, 5.0, "_scarf", "_scarf_v")
	if scarf:
		scarf.rotation = Vector3(-_scarf.x, 0.0, _scarf.y)
	# 背包：前后晃 + 上下颠
	_pack_v += ((clampf(a.z * 0.02, -0.25, 0.25) - _pack) * 140.0 - _pack_v * 9.0) * delta
	_pack += _pack_v * delta
	_pack_yv += ((0.0 - _pack_y) * 220.0 - _pack_yv * 10.0) * delta - vert * 0.05 * delta * 60.0
	_pack_y += _pack_yv * delta
	if pack:
		pack.rotation.x = _pack
		pack.position = _pack_base + Vector3(0, clampf(_pack_y, -0.04, 0.04), 0)


# ───────────────────────── 表情 ─────────────────────────

func _pick_expression(run: float, grounded: bool, climbing: bool, idle: bool) -> String:
	if expression_override != "":
		return expression_override
	if act != "":
		var u := _act_t / _act_len
		match act:
			"pet":
				return "content" if u < 0.78 else "happy"      # 摸的时候眯着眼享受，最后开心
			"feed":
				return "curious" if u < 0.3 else ("content" if u < 0.78 else "happy")
			"giggle":
				return "happy"
			"spin":
				return "excited"
			"boing":
				return "surprised" if u < 0.3 else "happy"
			"dizzy":
				return "tired"
			"wave":
				return "happy"
	if _wince_t > 0.0:
		return "wince"
	if not grounded:
		if _air_time > 0.9 and player.velocity.y < -7.0:
			return "scared"
		if player.velocity.y < -2.0 and _air_time > 0.45:
			return "surprised"
		return "excited"
	if _land_happy_t > 0.0:
		return "happy"
	if climbing:
		return "effort"
	if _surprise_t > 0.0:
		return "surprised"
	if _yawn_t >= 0.0:
		return "yawn"
	if _tired > 0.35:
		return "tired"
	if run > 0.6:
		return "focused" if _run_time < 3.0 else "effort"
	if idle:
		if _idle_time > 24.0:
			return "sleepy"
		match _fidget:
			"look":
				return "curious"
			"hum":
				return "content"
			"stretch":
				return "content"
			"bounce":
				return "happy"
	return "neutral"


func _update_expression(delta: float, run: float, grounded: bool, climbing: bool, idle: bool) -> void:
	var was_sleepy := _idle_time > 24.0
	var name := _pick_expression(run, grounded, climbing, idle)
	# 从犯困里被叫醒（一动就醒）：吓一跳
	if not idle and _surprise_t <= 0.0 and _au < 15.0 and name == "neutral":
		_surprise_t = 0.5
	var e: Dictionary = EXPR[name]
	var k := clampf(delta * 12.0, 0.0, 1.0)
	_au = lerpf(_au, e.au, k)
	_al = lerpf(_al, e.al, k)
	_tilt = lerpf(_tilt, e.tilt, k)
	_pupil = lerpf(_pupil, e.pupil, clampf(delta * 9.0, 0.0, 1.0))

	# 眨眼（表情本身已经闭眼时就不眨）
	_blink_t -= delta
	if _blink_t <= 0.0 and _blink_phase < 0.0:
		_blink_phase = 0.0
		_blink_t = _rng.randf_range(0.22, 0.35) if _rng.randf() < 0.18 else _rng.randf_range(1.8, 5.0)
	if _blink_phase >= 0.0:
		_blink_phase += delta / 0.15
		_blink = sin(clampf(_blink_phase, 0.0, 1.0) * PI)
		if _blink_phase >= 1.0:
			_blink_phase = -1.0
			_blink = 0.0
	var b := blink_override if blink_override >= 0.0 else _blink
	var au := lerpf(_au, _al + 4.0, b)

	for i in 2:
		var s := 1.0 if i == 0 else -1.0
		if lids[i]:
			lids[i].basis = Basis(Vector3(0, 0, 1), deg_to_rad(_tilt * s)) * Basis(Vector3(1, 0, 0), deg_to_rad(70.0 - au))
		if low_lids[i]:
			low_lids[i].basis = Basis(Vector3(0, 0, 1), deg_to_rad(-_tilt * s * 0.3)) * Basis(Vector3(1, 0, 0), deg_to_rad(-(_al + 70.0)))
		if pupils[i]:
			pupils[i].scale = Vector3.ONE * _pupil
		# 高光点：闭眼时会穿过眼皮、瞳孔缩小时会跑到瞳孔外面，这两种情况藏起来
		if glints[i]:
			glints[i].visible = (au - _al) > 35.0 and _pupil > 0.75

	# 汗珠：使劲、累、害怕时冒出来，顺着脸往下滑
	var want_sweat := 1.0 if (name == "effort" and (_climb_time > 1.5 or _run_time > 4.0)) or name == "tired" or name == "scared" else 0.0
	_sweat_a = lerpf(_sweat_a, want_sweat, clampf(delta * 4.0, 0.0, 1.0))
	if sweat_piv:
		sweat_piv.visible = _sweat_a > 0.05
		var slide := fmod(_t * 0.6, 1.0)
		sweat_piv.position = _sweat_base + Vector3(0, -slide * 0.06, 0)
		sweat_piv.scale = Vector3.ONE * _sweat_a * (1.0 - slide * 0.4)
	was_sleepy = was_sleepy


# ───────────────────────── 眼睛 ─────────────────────────

func _update_eyes(delta: float, look_target: Vector3, idle: bool) -> void:
	_saccade_t -= delta
	if _saccade_t <= 0.0:
		_saccade_t = _rng.randf_range(0.5, 2.0)
		_eye_saccade = Vector2(_rng.randf_range(-0.07, 0.07), _rng.randf_range(-0.04, 0.04))
	var target := look_target
	var cam: Camera3D = player.get("cam")
	if look_lock:
		pass
	elif idle and _fidget == "look":
		target = _look_override
	elif _idle_time > 24.0:
		target = global_position + global_transform.basis * Vector3(0, 0.2, 3.0)    # 犯困时眼睛往下耷拉
	elif cam and is_instance_valid(cam):
		# 镜头绕到角色正面时，看着镜头（和你对视）
		var to_cam: Vector3 = cam.global_position - (global_position + Vector3(0, 1.1, 0))
		if to_cam.length() < 9.0 and global_transform.basis.z.dot(to_cam.normalized()) > 0.35:
			target = cam.global_position
	for e in eyes:
		if e == null:
			continue
		var parent := e.get_parent() as Node3D
		var tgt := target
		if act == "dizzy":
			# 晕：两只眼睛反着转圈
			var ang := _t * 11.0 + (PI if e == eyes[1] else 0.0)
			tgt = global_position + global_transform.basis * Vector3(cos(ang) * 0.6, 1.13 + sin(ang) * 0.6, 1.0)
		var local := parent.global_transform.affine_inverse() * tgt - e.position
		if local.length_squared() < 0.0001:
			continue
		var d := local.normalized()
		var yaw := clampf(atan2(d.x, d.z) + _eye_saccade.x, -EYE_MAX_YAW, EYE_MAX_YAW)
		var pitch := clampf(-asin(clampf(d.y, -1.0, 1.0)) + _eye_saccade.y, -EYE_MAX_PITCH, EYE_MAX_PITCH)
		var k := clampf(delta * 20.0, 0.0, 1.0)
		e.rotation = Vector3(lerp_angle(e.rotation.x, pitch, k), lerp_angle(e.rotation.y, yaw, k), 0.0)


# ───────────────────────── 工具：捕虫网 / 钓鱼竿 ─────────────────────────

## 鼠标左键：用手里的工具
func use_tool() -> void:
	match held:
		"net":
			if _use_t < 0.0:
				_use_t = 0.0
				_swing_hit = false
		"rod":
			_fish_click()


func _world():
	return player.get_parent()


func toast(text: String) -> void:
	# 有统一的提示（notice.gd：白字、慢慢飘散）就用它
	var n := get_tree().get_first_node_in_group("notice")
	if n:
		n.say(text, 2.4)
		return
	if _toast == null:
		var layer := CanvasLayer.new()
		add_child(layer)
		_toast = Label.new()
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_toast.offset_left = -400
		_toast.offset_right = 400
		_toast.offset_top = -120
		_toast.offset_bottom = -80
		_toast.add_theme_font_size_override("font_size", 24)
		_toast.add_theme_color_override("font_color", Color(1, 1, 1))
		_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
		_toast.add_theme_constant_override("shadow_offset_y", 2)
		layer.add_child(_toast)
	_toast.text = text
	_toast_t = 2.5


## 一次性的粒子爆开：一团彩色小点（挥网的风、抓到虫的星星、水花）
func _burst(pos: Vector3, count: int, speed: float, col: Color, size := 0.03, up := 1.0, grav := -5.0) -> void:
	var p := GPUParticles3D.new()
	p.amount = count
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 1.0
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.08
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0 if up < 0.5 else 70.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, grav, 0)
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(0.7, 0.8))
	sc.add_point(Vector2(1.0, 0.0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	p.process_material = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	var q := SphereMesh.new()
	q.radius = size
	q.height = size * 2.0
	q.radial_segments = 8
	q.rings = 4
	q.material = mat
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 5, 6))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.top_level = true
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _update_tools(delta: float) -> void:
	if _toast and _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t * 2.0, 0.0, 1.0)

	# ── 网兜的晃动：弹簧追着"手的反方向速度"，所以挥的时候往后甩、停下来会荡回去再晃几下 ──
	if _held_node and _socket:
		var sp := _socket.global_position
		var vel := (sp - _sock_prev) / maxf(delta, 0.001)
		_sock_prev = sp
		if _soft_mat:
			var inv := _held_node.global_basis.orthonormalized().inverse()
			var target := inv * (-vel * 0.05 + Vector3(0, -0.05, 0))
			target = target.limit_length(0.4)
			var steps := clampi(int(ceil(delta / 0.008)), 1, 12)
			var h := minf(delta, 0.096) / steps
			for i in steps:
				_soft_v += ((target - _soft) * 150.0 - _soft_v * 7.0) * h
				_soft += _soft_v * h
			_soft = _soft.limit_length(0.5)
			_soft_mat.set_shader_parameter("soft_offset", _soft)

	# ── 挥网 ──
	if _use_t >= 0.0:
		var before := _use_t
		_use_t += delta / 0.55
		if held != "net" or _held_node == null:
			_use_t = -1.0
		else:
			var hoop := _held_node.to_global(NET_HOOP)
			# 扫过身前的那一段：一路撒白色的小点（风），并检查有没有扣到蝴蝶
			if _use_t > 0.25 and _use_t < 0.62:
				if int(before * 30.0) != int(_use_t * 30.0):
					_burst(hoop, 3, 0.8, Color(1, 1, 1), 0.02, 0.0, -1.0)
				if not _swing_hit:
					var w = _world()
					var life = w.get("life") if w else null
					var n := 0
					if life != null and life.has_method("catch_near"):
						n = life.catch_near(hoop, 1.5)
					if n > 0:
						_swing_hit = true
						caught_bugs += n
						_burst(hoop, 18, 2.6, Color(1.0, 0.9, 0.3), 0.035, 0.0, -2.0)
						_burst(hoop, 8, 1.6, Color(1, 1, 1), 0.025, 0.0, -1.0)
						toast("抓到蝴蝶了！  共 %d 只" % caught_bugs)
						_sq_v += 4.0
						_land_happy_t = 1.0
			if _use_t >= 1.0:
				_use_t = -1.0

	_update_fishing(delta)


# ── 钓鱼 ──

## (x, z) 处的水面高度；不是水就返回 NAN
func _water_at(x: float, z: float) -> float:
	var w = _world()
	if w == null:
		return NAN
	if w.has_method("water_surface"):
		var ws: float = w.water_surface(x, z)
		return ws if ws > w.height_raw(x, z) + 0.12 else NAN
	if w.has_method("in_pond") and w.in_pond(x, z):
		return w.water_level
	return NAN


func _fish_click() -> void:
	match _fish:
		"":
			if not player.is_on_floor():
				return
			# 往面前找水：2.5 到 10 米之内第一处水面，浮漂落在再往里一点的地方
			var fwd := -player.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var found := false
			for i in range(5, 21):
				var q := player.global_position + fwd * (i * 0.5)
				var lvl := _water_at(q.x, q.z)
				if not is_nan(lvl):
					var q2 := q + fwd * 1.5
					var lvl2 := _water_at(q2.x, q2.z)
					if not is_nan(lvl2):
						q = q2
						lvl = lvl2
					_bob_to = Vector3(q.x, lvl, q.z)
					_bob_level = lvl
					found = true
					break
			if not found:
				toast("面前没有水，走到水边再甩竿")
				return
			if not is_nan(_water_at(player.global_position.x, player.global_position.z)):
				toast("先上岸再钓鱼")
				return
			_fish = "cast"
			_fish_t = 0.0
			busy = true
			_make_bobber()
		"wait":
			_fish_ok = false
			_fish = "pull"
			_fish_t = 0.0
		"bite":
			_fish_ok = true
			_fish = "pull"
			_fish_t = 0.0
			_burst(_bob.global_position, 14, 2.8, Color(0.85, 0.95, 1.0), 0.035, 1.0)


func _make_bobber() -> void:
	if _bob == null:
		var path := "res://props/bobber.glb"
		if ResourceLoader.exists(path):
			var ps := load(path) as PackedScene
			if ps:
				_bob = ps.instantiate() as Node3D
		if _bob == null:
			var doc := GLTFDocument.new()
			var st := GLTFState.new()
			if doc.append_from_file(ProjectSettings.globalize_path(path), st) == OK:
				_bob = doc.generate_scene(st) as Node3D
		if _bob == null:
			_bob = MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.06
			sm.height = 0.12
			(_bob as MeshInstance3D).mesh = sm
		for mi in _bob.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for i in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(i)
				var mat := ShaderMaterial.new()
				mat.shader = load("res://shaders/toon_tex.gdshader")
				if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture:
					mat.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
				m.set_surface_override_material(i, mat)
		add_child(_bob)
		_bob.top_level = true
		_line_mesh = ImmediateMesh.new()
		_line = MeshInstance3D.new()
		_line.mesh = _line_mesh
		var lm := StandardMaterial3D.new()
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.albedo_color = Color(1, 1, 1)
		_line.material_override = lm
		_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_line)
		_line.top_level = true
		_line.global_transform = Transform3D.IDENTITY
	_bob.visible = true
	_line.visible = true


func _stop_fishing() -> void:
	_fish = ""
	busy = false
	if _bob:
		_bob.visible = false
	if _line:
		_line.visible = false


func _rod_tip() -> Vector3:
	if _held_node:
		return _held_node.to_global(ROD_TIP)
	return global_position + Vector3(0, 1.2, 0)


func _update_fishing(delta: float) -> void:
	if _fish == "":
		return
	if held != "rod" or _held_node == null:
		_stop_fishing()
		return
	_fish_t += delta
	var tip := _rod_tip()
	var pos := _bob.global_position
	var water := Vector3(_bob_to.x, _bob_level, _bob_to.z)
	match _fish:
		"cast":
			# 前 0.35 秒是往后引竿，然后浮漂沿抛物线飞出去
			var u := clampf((_fish_t - 0.35) / 0.55, 0.0, 1.0)
			pos = tip.lerp(water, u)
			pos.y += sin(u * PI) * 1.6
			if _fish_t >= 0.9:
				_fish = "wait"
				_fish_t = 0.0
				_fish_wait = _rng.randf_range(3.0, 8.0)
				_burst(water, 10, 1.8, Color(0.85, 0.95, 1.0), 0.03, 1.0)
		"wait":
			# 漂在水面上：上下轻轻浮动，慢慢左右晃
			pos = water + Vector3(sin(_t * 0.7) * 0.05, sin(_t * 2.2) * 0.015 - 0.02, cos(_t * 0.9) * 0.05)
			_bob.rotation = Vector3(sin(_t * 1.7) * 0.12, 0, cos(_t * 1.3) * 0.12)
			if _fish_t > _fish_wait:
				_fish = "bite"
				_fish_t = 0.0
				_splash_t = 0.0
				toast("咬钩了！点左键收竿")
		"bite":
			# 被鱼拽着一沉一沉，水花四溅
			pos = water + Vector3(sin(_t * 9.0) * 0.06, -0.03 - absf(sin(_t * 13.0)) * 0.09, cos(_t * 7.0) * 0.06)
			_splash_t -= delta
			if _splash_t <= 0.0:
				_splash_t = 0.22
				_burst(water, 6, 1.5, Color(0.85, 0.95, 1.0), 0.025, 1.0)
			if _fish_t > 1.8:
				_fish = "wait"
				_fish_t = 0.0
				_fish_wait = _rng.randf_range(3.0, 7.0)
				toast("跑掉了……")
		"pull":
			var u := clampf(_fish_t / 0.6, 0.0, 1.0)
			pos = water.lerp(tip, u)
			pos.y += sin(u * PI) * 1.2
			if u >= 1.0:
				if _fish_ok:
					caught_fish += 1
					toast("钓到了！  共 %d 条" % caught_fish)
					_burst(tip, 16, 2.4, Color(1.0, 0.9, 0.3), 0.035, 0.0, -2.0)
					_land_happy_t = 1.2
					_sq_v += 4.0
				_stop_fishing()
				return
	_bob.global_position = pos
	# 鱼线：从竿尖到浮漂，中间稍微下垂
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var sag := 0.25 if _fish in ["wait", "bite"] else 0.05
	for i in 9:
		var t := i / 8.0
		var q := tip.lerp(pos + Vector3(0, 0.06, 0), t)
		q.y -= sin(t * PI) * sag
		_line_mesh.surface_add_vertex(q)
	_line_mesh.surface_end()


# ───────────────────────── 互动动作 ─────────────────────────

## 开始一个动作。target：要面对的位置（摸 / 喂的动物）；high：对象高（小鹿）
func play_act(name: String, target := Vector3.ZERO, high := false) -> void:
	if not ACTS.has(name):
		return
	act = name
	act_high = high
	_act_t = 0.0
	_act_len = ACTS[name]
	_act_target = target
	_act_beats = {}
	_fidget = ""
	_yawn_t = -1.0
	_idle_time = 0.0


func is_acting() -> bool:
	return act != ""


## 摸 / 喂的时候不能走动
func locks_movement() -> bool:
	return act == "pet" or act == "feed"


func _beat(name: String, at: float) -> void:
	if _act_t >= at and not _act_beats.has(name):
		_act_beats[name] = true
		act_beat.emit(act, name)


func _tick_act(delta: float) -> void:
	if act == "":
		return
	_act_t += delta
	match act:
		"pet":
			_beat("touch", 0.55)
			_beat("stroke1", 1.05)
			_beat("stroke2", 1.55)
			_beat("love", 2.05)
		"feed":
			_beat("offer", 0.6)
			_beat("nom1", 1.2)
			_beat("nom2", 1.7)
			_beat("love", 2.3)
		"giggle":
			_beat("pop", 0.1)
		"spin":
			_beat("pop", 0.85)
		"boing":
			_beat("pop", 0.35)
		"dizzy":
			_beat("pop", 0.05)
		"wave":
			_beat("pop", 0.3)
	if _act_t >= _act_len:
		var done := act
		act = ""
		act_beat.emit(done, "end")


func _apply_act(delta: float, t_pos: Vector3, t_rot: Vector3, arm_x: Array, arm_z: Array, leg_x: Array, leg_lift: Array) -> void:
	_fid_pos = t_pos
	_fid_rot = t_rot
	var u := clampf(_act_t / _act_len, 0.0, 1.0)
	var env := smoothstep(0.0, 0.16, u) * (1.0 - smoothstep(0.84, 1.0, u))
	var drop := 0.0
	match act:
		"pet", "feed":
			# 摸 / 喂：矮的（兔子）蹲下来往前探身，高的（小鹿）踮脚往前伸手；
			# 摸的时候手一下一下顺着毛抚，身体跟着轻轻晃；最后站直、举手开心地颠一下
			var stroke := sin(maxf(_act_t - 0.5, 0.0) * 6.5) if act == "pet" else sin(_act_t * 2.2) * 0.3
			var main := smoothstep(0.0, 0.2, u) * (1.0 - smoothstep(0.72, 0.86, u))
			var happy := smoothstep(0.78, 0.86, u) * (1.0 - smoothstep(0.92, 1.0, u))
			if act_high:
				arm_x[1] = lerpf(arm_x[1], -1.6 + stroke * 0.14, main)
				arm_z[1] = lerpf(arm_z[1], -0.08, main)
				_fid_rot.x += 0.12 * main
				_fid_pos.y += 0.025 * main
			else:
				drop = 0.17 * main
				arm_x[1] = lerpf(arm_x[1], -0.72 + stroke * 0.16, main)
				arm_z[1] = lerpf(arm_z[1], -0.04, main)
				arm_z[0] = lerpf(arm_z[0], 0.32, main)          # 左手张开保持平衡
				_fid_rot.x += 0.42 * main
				leg_x[0] = lerpf(leg_x[0], -0.35, main)
				leg_x[1] = lerpf(leg_x[1], -0.35, main)
			_fid_rot.z += stroke * 0.035 * main
			arm_x[0] = lerpf(arm_x[0], -2.3, happy)
			arm_x[1] = lerpf(arm_x[1], -2.3, happy)
			arm_z[0] = lerpf(arm_z[0], 0.55, happy)
			arm_z[1] = lerpf(arm_z[1], 0.55, happy)
			_fid_pos.y += sin(happy * PI) * 0.05
		"giggle":
			# 被戳了一下：捂着脸左右扭着笑
			var w := sin(_act_t * 17.0)
			arm_x[0] = lerpf(arm_x[0], -2.05, env)
			arm_x[1] = lerpf(arm_x[1], -2.05, env)
			arm_z[0] = lerpf(arm_z[0], -0.25, env)
			arm_z[1] = lerpf(arm_z[1], -0.25, env)
			_fid_rot.z += w * 0.11 * env
			_fid_rot.x -= 0.06 * env
			_fid_pos.y += absf(sin(_act_t * 8.5)) * 0.035 * env
		"spin":
			# 原地转一圈，手张开，转完落地压扁一下
			var e := u * u * (3.0 - 2.0 * u)
			_act_spin = TAU * e
			arm_z[0] = lerpf(arm_z[0], 1.25, env)
			arm_z[1] = lerpf(arm_z[1], 1.25, env)
			_fid_pos.y += sin(u * PI) * 0.12
			leg_lift[0] += sin(u * PI) * 0.05
			if u > 0.9 and u - delta / _act_len <= 0.9:
				_sq_v -= 4.5
		"boing":
			# 吓一跳：先压扁，再弹得老高，手脚张开
			if _act_t < delta * 1.5:
				_sq_v -= 7.0
			if _act_t >= 0.18 and _act_t - delta < 0.18:
				_sq_v += 11.0
			var hop := sin(clampf((u - 0.18) / 0.55, 0.0, 1.0) * PI)
			_fid_pos.y += hop * 0.28
			arm_x[0] = lerpf(arm_x[0], -2.6, hop)
			arm_x[1] = lerpf(arm_x[1], -2.6, hop)
			arm_z[0] = lerpf(arm_z[0], 0.9, hop)
			arm_z[1] = lerpf(arm_z[1], 0.9, hop)
			leg_lift[0] += hop * 0.06
			leg_lift[1] += hop * 0.06
		"dizzy":
			# 被戳太多下：晕乎乎地画圈晃，手耷拉着
			var a := _act_t * 4.2
			_fid_rot.z += sin(a) * 0.17 * env
			_fid_rot.x += cos(a) * 0.09 * env
			arm_z[0] = lerpf(arm_z[0], 0.35 + sin(a) * 0.15, env)
			arm_z[1] = lerpf(arm_z[1], 0.35 - sin(a) * 0.15, env)
			arm_x[0] = lerpf(arm_x[0], 0.15, env)
			arm_x[1] = lerpf(arm_x[1], 0.15, env)
		"wave":
			# 招手打招呼
			arm_x[1] = lerpf(arm_x[1], -2.75, env)
			arm_z[1] = lerpf(arm_z[1], 0.3 + sin(_act_t * 13.0) * 0.32, env)
			_fid_rot.z += sin(_act_t * 6.5) * 0.04 * env
	_act_drop = lerpf(_act_drop, drop, clampf(delta * 10.0, 0.0, 1.0))
