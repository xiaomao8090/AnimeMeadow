extends CharacterBody3D
## WASD 移动，Shift 跑，空格跳，V 切换第一/第三人称，鼠标滚轮调镜头远近，1 胡萝卜 / 2 浆果 / 3 捕虫网 / 4 钓鱼竿（再按收起），鼠标左键使用
## Esc 由 main_menu.gd 处理（暂停菜单）；active = false 时（在主菜单里）不接受操作
## 速度按真人的步行/跑步来，有起步和刹车的惯性，上坡慢下坡快，镜头起伏和脚步声跟着步子走

signal stepped(landing: bool)   # 每迈一步 / 落地时发出，world.gd 用它播放脚步声

const WALK_SPEED := 2.0         # 米/秒，快步走
const RUN_SPEED := 5.0          # 米/秒，慢跑
const BACK_FACTOR := 0.7        # 后退时的速度倍率
const STRAFE_FACTOR := 0.85     # 横着走时的速度倍率
const GROUND_ACCEL := 12.0      # 起步加速度（米/秒²）
const GROUND_FRICTION := 11.0   # 松开按键后的减速度
const AIR_ACCEL := 2.5          # 空中只能稍微调整方向
const CLIMB_SPEED := 1.7        # 攀爬陡壁的速度（米/秒）
const MAX_WALK_SLOPE := 62.0    # 这个坡度以内都能直接走上去、站得稳；更陡的要爬
const JUMP_SPEED := 4.4        # 跳起高度约 0.7 米
const GRAVITY := 14.0
const WALK_STRIDE := 0.9        # 走路时一步的长度（米）
const RUN_STRIDE := 1.7         # 跑步时一步的长度
const MOUSE_SENS := 0.0025
const EYE_HEIGHT := 1.55
const BASE_FOV := 75.0

var active := true               # main_menu.gd 控制：主菜单 / 镜头过渡时为 false
var aim_override := Vector3.ZERO # active = false 时角色看向这里（主菜单里是鼠标的位置）
var bound := 78.0
var spawn_point := Vector3.ZERO
var move_scale := 1.0           # world.gd 设置：蹚水时变慢
var traction := 1.0             # world.gd 设置：冰面上很滑（加速和刹车都变慢）
var sink := 0.0                 # world.gd 设置：在雪里脚陷下去多深（只影响模型位置，碰撞不变）
var cam: Camera3D
var _pitch := 0.0
var _phase := 0.5               # 步子的相位：每过一个整数 = 一只脚落地
var _bob_amp := 0.0             # 0..1 镜头起伏的强度（站住时慢慢归零）
var _run_blend := 0.0
var _land_y := 0.0              # 落地时镜头下沉的弹簧
var _land_v := 0.0
var _roll := 0.0
var _jump_buffer := 0.0         # 提前一点按跳也算
var _coyote := 0.0              # 刚走出边缘的一小段时间内还能跳
var _was_on_floor := true
var _climbing := false
var _air_t := 0.0               # 离开地面多久了
var _vis_y := 0.0               # 平滑过的高度（模型和镜头用）
var _vis_off := 0.0
var third_person := true
var cam_dist := 3.2              # 第三人称镜头距离（滚轮调）
var _cam_cur_dist := 3.2
var hero                         # hero_rig.gd：角色模型和动画
const TP_PIVOT := Vector3(0.0, 1.35, 0.0)
const TP_SHOULDER := 0.35        # 镜头稍微偏右，角色不挡准星
const FP_EYE := 1.36             # 第一人称镜头高度（角色的眼睛高度）
const FP_FWD := 0.05             # 镜头在身体中心前面一点，低头能看到肚子、手和脚


func _ready() -> void:
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(MAX_WALK_SLOPE)
	floor_constant_speed = true     # 上下坡沿着坡面走的速度不被物理再打折（减速由下面的 grade 统一控制）

	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	col.shape = capsule
	col.position.y = 0.85
	add_child(col)

	cam = Camera3D.new()
	cam.position.y = EYE_HEIGHT
	cam.fov = BASE_FOV
	cam.near = 0.08
	cam.far = 1500.0
	add_child(cam)
	cam.make_current()

	hero = Node3D.new()
	hero.name = "Hero"
	hero.set_script(load("res://scripts/hero_rig.gd"))
	hero.player = self
	add_child(hero)
	hero.top_level = true       # 身体朝向自己算，不跟着鼠标转
	hero.set_first_person(not third_person)


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := MOUSE_SENS * Settings.mouse_sens
		rotate_y(-motion.relative.x * sens)
		_pitch = clampf(_pitch - motion.relative.y * sens, -1.45, 1.45)
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_SPACE:
			_jump_buffer = 0.12
		elif key == KEY_V:
			third_person = not third_person
			hero.set_first_person(not third_person)
		# 1-4 拿东西、B 背包：由 inventory.gd 处理
	elif event is InputEventMouseButton and event.pressed and third_person and \
			(event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		cam_dist = clampf(cam_dist + (-0.3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 0.3), 1.6, 7.0)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and event.button_index == MOUSE_BUTTON_LEFT:
			hero.use_tool()         # 左键：用手里的工具
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	var input := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		input.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		input.y += 1.0
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		input.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		input.x += 1.0
	input = input.limit_length(1.0)
	if hero.busy or hero.locks_movement():
		input = Vector2.ZERO        # 坐着钓鱼时不能走，也不能跳
		_jump_buffer = 0.0
	if not active:
		input = Vector2.ZERO
	var moving := input.length_squared() > 0.01

	var grounded := is_on_floor()
	var dir3 := global_transform.basis * Vector3(input.x, 0.0, input.y)
	var dir := Vector2(dir3.x, dir3.z)

	# 目标速度：只有向前才能跑；后退、横移慢一些；上坡慢、下坡略快；蹚水慢
	var running := moving and input.y < -0.5 and Input.is_physical_key_pressed(KEY_SHIFT)
	var speed := RUN_SPEED if running else WALK_SPEED
	if input.y > 0.1:
		speed *= BACK_FACTOR
	elif moving and absf(input.y) < 0.1:
		speed *= STRAFE_FACTOR
	if grounded and moving:
		var n := get_floor_normal()
		var grade := -(dir.x * n.x + dir.y * n.z) / maxf(n.y, 0.2)   # 正 = 上坡
		speed *= clampf(1.0 - grade * 0.35, 0.65, 1.12)   # 上坡稍微慢一点，但不会慢得走不动
	speed *= move_scale

	# 有惯性的加速 / 刹车；在空中保持原来的速度，只能稍微调整
	var hv := Vector2(velocity.x, velocity.z)
	if grounded:
		hv = hv.move_toward(dir * speed, (GROUND_ACCEL if moving else GROUND_FRICTION) * traction * delta)
	elif moving:
		hv = hv.move_toward(dir * speed, AIR_ACCEL * delta)
	velocity.x = hv.x
	velocity.z = hv.y

	# 攀爬：坡陡到走不上去（约 62-80 度）时，正对着它继续往前顶，就手脚并用爬上去；
	# 松开就会滑下来。再陡的就是峭壁，爬不了，得绕路
	_climbing = false
	if moving and input.y < -0.3 and is_on_wall():
		var wn := get_wall_normal()
		var into := Vector3(-wn.x, 0.0, -wn.z)
		if wn.y > 0.15 and wn.y < 0.6 and into.length() > 0.01 and dir3.normalized().dot(into.normalized()) > 0.35:
			# 沿着坡面往上爬，再往坡里贴一点，不会被弹开
			velocity = (Vector3.UP - wn * wn.y).normalized() * CLIMB_SPEED * move_scale - wn * 0.4
			_climbing = true

	# 跳：按下才跳一次（按住不会连跳）
	_jump_buffer -= delta
	_coyote = 0.1 if (grounded or _climbing) else _coyote - delta
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_SPEED
		_jump_buffer = 0.0
		_coyote = 0.0
	elif not grounded and not _climbing:
		velocity.y -= GRAVITY * delta

	var fall_speed := -velocity.y
	move_and_slide()

	var on_floor := is_on_floor()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	# 在凹凸不平的地方物理有时会一帧在地上一帧不在：给动画和镜头用一个带 0.12 秒缓冲的“在地上”，
	# 再把模型和镜头的高度平滑一下，这样不会跟着上下闪
	_air_t = 0.0 if (on_floor or _climbing) else _air_t + delta
	var on_floor_vis := on_floor or (_air_t < 0.12 and velocity.y < 1.0)
	if on_floor_vis and absf(global_position.y - _vis_y) < 0.6:
		_vis_y = lerpf(_vis_y, global_position.y, clampf(delta * 20.0, 0.0, 1.0))
	else:
		_vis_y = global_position.y
	_vis_off = _vis_y - global_position.y

	# 步子：按走过的距离推进相位，每过一个整数就是一只脚落地 → 脚步声和镜头最低点对齐
	if on_floor and not _was_on_floor:
		if fall_speed > 1.5:
			stepped.emit(true)
			_land_v -= clampf(fall_speed * 0.28, 0.4, 2.4)
		_phase = 0.5
	elif (on_floor or _climbing) and hspeed > 0.25:
		var run_t := clampf((hspeed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0)
		var before := floorf(_phase)
		_phase += hspeed * delta / lerpf(WALK_STRIDE, RUN_STRIDE, run_t)
		if floorf(_phase) > before:
			stepped.emit(false)
	elif on_floor and _bob_amp < 0.05:
		_phase = 0.5      # 站定之后，下次起步半步就落第一脚
	_was_on_floor = on_floor

	# 地图边界 & 掉出世界保护
	global_position.x = clampf(global_position.x, -bound, bound)
	global_position.z = clampf(global_position.z, -bound, bound)
	if global_position.y < -60.0:
		global_position = spawn_point
		velocity = Vector3.ZERO

	_update_camera(delta, on_floor_vis, hspeed)


func _update_camera(delta: float, on_floor: bool, hspeed: float) -> void:
	var k := clampf(8.0 * delta, 0.0, 1.0)
	_bob_amp = lerpf(_bob_amp, clampf(hspeed / WALK_SPEED, 0.0, 1.0) if on_floor else 0.0, k)
	_run_blend = lerpf(_run_blend, clampf((hspeed - WALK_SPEED) / (RUN_SPEED - WALK_SPEED), 0.0, 1.0), k)

	# 落地下沉：一个有阻尼的弹簧
	_land_v += (-140.0 * _land_y - 17.0 * _land_v) * delta
	_land_y += _land_v * delta

	# 每一步镜头上下一次（脚落地时最低），每两步左右晃一次；跑步时幅度更大
	var up := -cos(_phase * TAU) * lerpf(0.022, 0.05, _run_blend) * _bob_amp
	var side := sin(_phase * PI) * lerpf(0.014, 0.026, _run_blend) * _bob_amp
	cam.position = Vector3(side, FP_EYE + up + _land_y + _vis_off - hero.SIT_DROP * hero._sit, -FP_FWD)

	# 横移时身体微微侧倾
	var local_vx := (global_transform.basis.inverse() * velocity).x
	_roll = lerpf(_roll, -local_vx / RUN_SPEED * 0.03 - sin(_phase * PI) * 0.004 * _bob_amp, k)
	cam.rotation = Vector3(_pitch, 0.0, _roll)
	cam.fov = Settings.fov + 4.0 * _run_blend

	if third_person:
		_third_person_camera(delta)

	# 角色：跟着玩家位置走，眼睛看镜头正在看的地方
	hero.global_position = global_position + Vector3(0.0, _vis_off - sink, 0.0)
	var aim := cam.global_position - cam.global_transform.basis.z * 25.0
	if not active and aim_override != Vector3.ZERO:
		aim = aim_override
	hero.animate(delta, aim, _phase, _run_blend, on_floor, _climbing)


## 第三人称：镜头在角色身后，被地形/石头/树挡住时自动拉近
func _third_person_camera(delta: float) -> void:
	var pivot_local := TP_PIVOT + Vector3(0.0, _land_y * 0.5 + _vis_off - hero.SIT_DROP * 0.6 * hero._sit, 0.0)
	var back := Basis(Vector3.RIGHT, _pitch) * Vector3(TP_SHOULDER, 0.0, cam_dist)
	var pivot_w := global_transform * pivot_local
	var want_w := global_transform * (pivot_local + back)
	var q := PhysicsRayQueryParameters3D.create(pivot_w, want_w)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var dist := cam_dist
	if hit:
		dist = maxf(pivot_w.distance_to(hit.position) - 0.25, 0.4)
	# 被挡住时立刻拉近，放开后慢慢退回去
	_cam_cur_dist = dist if dist < _cam_cur_dist else lerpf(_cam_cur_dist, dist, clampf(delta * 4.0, 0.0, 1.0))
	cam.position = pivot_local + back * (_cam_cur_dist / cam_dist)
	cam.rotation = Vector3(_pitch, 0.0, 0.0)
