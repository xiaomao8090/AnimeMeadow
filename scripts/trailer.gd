extends Node
## 宣传片导演：自动摆机位、控制时间和角色，按配乐的小节拍一组镜头，拍完自己退出。
## 渲染：godot --path . --write-movie 文件.avi --fixed-fps 30 --resolution 1920x1080 -- --trailer
## 每个镜头的有效帧打印成 "SHOT 名字 起始帧 结束帧"（含前后余量 HANDLE 秒），后期脚本按它剪辑、配乐。
## 镜头之间换地方要等地图加载，这段时间画面是黑的，后期会剪掉。
## 只拍某几个镜头：-- --trailer --only=pet,feed

const BPM := 110.0
const BAR := 240.0 / BPM
const FPS := 30.0
const HANDLE := 0.4          # 每个镜头前后多拍的余量（秒），后期淡入淡出用
const PREROLL := 1.2         # 正式记录前先让角色动起来（不记录）
const SEED := 20261111

# 镜头表：名字、地点、起止小节（配乐 110 BPM，一小节约 2.18 秒）
const SHOTS := [
	["dawn", "meadow", 1.0, 2.5],
	["reveal", "meadow", 2.5, 5.0],
	["walk", "flowers", 5.0, 7.0],
	["face", "flowers", 7.0, 8.0],
	["pet", "flowers", 8.0, 10.0],
	["feed", "flowers", 10.0, 12.0],
	["net", "flowers", 12.0, 13.0],
	["autumn", "autumn", 13.0, 14.5],
	["sakura", "sakura", 14.5, 16.0],
	["desert", "desert", 16.0, 17.5],
	["snow", "snow", 17.5, 19.0],
	["ice", "ice", 19.0, 21.0],
	["aurora", "snow", 21.0, 25.0],
	["fish", "pond", 25.0, 27.0],
	["fireflies", "flowers", 27.0, 28.5],
	["run", "plain", 28.5, 31.0],
	["wave", "plain", 31.0, 33.0],
	["final", "plain", 33.0, 35.4],
]

var boot: Node
var world
var player
var hero
var dn
var inter
var cam: Camera3D
var attr: CameraAttributesPractical
var black: ColorRect

var frame := 0
var si := -1
var phase := "boot"
var t := 0.0
var prep_t := 0.0
var shot: Array = []
var dur := 0.0
var spots := {}
var st := {}                  # 当前镜头自己的状态
var only: PackedStringArray = []
var _f0 := -1


func start(b: Node) -> void:
	boot = b
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).split(",")
	world = Node3D.new()
	world.name = "World"
	world.set_script(load("res://scripts/world.gd"))
	world.set("random_seed", false)
	world.set("world_seed", SEED)
	world.set("grass_per_chunk", 13000)
	b.add_child(world)

	var notice := CanvasLayer.new()
	notice.name = "Notice"
	notice.set_script(load("res://scripts/notice.gd"))
	b.add_child(notice)
	notice.visible = false

	inter = CanvasLayer.new()
	inter.name = "Interact"
	inter.set_script(load("res://scripts/interact.gd"))
	b.add_child(inter)
	inter.setup(world)
	inter.visible = false

	player = world.player
	hero = player.hero
	dn = world.day_night
	player.active = false
	dn.day_length_minutes = 1.0e9
	for c in world.get_children():
		if c is CanvasLayer:
			c.visible = false
			for k in c.get_children():
				k.process_mode = Node.PROCESS_MODE_DISABLED

	cam = Camera3D.new()
	cam.near = 0.05
	cam.far = 1500.0
	attr = CameraAttributesPractical.new()
	cam.attributes = attr
	world.add_child(cam)
	cam.make_current()

	var lay := CanvasLayer.new()
	lay.layer = 100
	black = ColorRect.new()
	black.color = Color.BLACK
	black.position = Vector2.ZERO
	black.size = Vector2(8000, 8000)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lay.add_child(black)
	add_child(lay)

	_find_spots()
	_next_shot()


# ───────────────────────── 主循环 ─────────────────────────

func _process(delta: float) -> void:
	frame += 1
	if phase == "prep":
		_prep(delta)
	elif phase == "roll":
		_roll(delta)


func _next_shot() -> void:
	if _f0 >= 0:
		print("SHOT %s %d %d" % [shot[0], _f0, frame])
	_f0 = -1
	si += 1
	while si < SHOTS.size() and not only.is_empty() and not only.has(SHOTS[si][0]):
		si += 1
	if si >= SHOTS.size():
		print("TRAILER_DONE frames=%d" % frame)
		get_tree().quit()
		return
	shot = SHOTS[si]
	dur = (float(shot[3]) - float(shot[2])) * BAR
	_reset_actor()
	st = {}
	phase = "prep"
	prep_t = 0.0
	black.visible = true
	var sp: Dictionary = spots[shot[1]]
	st.c = sp.c
	st.d = sp.d
	st.far = st.c.distance_to(player.global_position) > 200.0
	_place(st.c, sp.d)


func _prep(delta: float) -> void:
	prep_t += delta
	# 地图没加载好之前把人按在原地（不然会掉下去或者走掉）
	if not st.has("ready"):
		_hold_place()
		var need := 2.5 if st.far else 0.3
		if prep_t > need and (world.load_progress() >= 0.985 or prep_t > 60.0):
			st.ready = true
			st.ready_t = prep_t
			call("_setup_" + str(shot[0]))
			st.c = _on_ground(st.c)
			if st.has("cam0"):
				st.cam0 = _on_ground(st.cam0)
			t = -HANDLE - PREROLL
			_tick()
		return
	# 布置好之后再等一下：动物刷出来、草长好、粒子铺满
	if prep_t - float(st.ready_t) < (2.0 if st.far else 0.8):
		_hold_place()
		_tick()
		return
	phase = "roll"
	black.visible = false


func _roll(delta: float) -> void:
	t += delta
	if _f0 < 0 and t >= -HANDLE:
		_f0 = frame
	_tick()
	if t >= dur + HANDLE:
		_next_shot()


func _tick() -> void:
	call("_shot_" + str(shot[0]), t)
	if OS.get_cmdline_user_args().has("--debug") and phase == "roll" and frame % 15 == 0:
		var v: Vector3 = player.velocity
		var hz: Vector3 = hero.global_basis.z
		var tc: Vector3 = (cam.global_position - hero.global_position)
		tc.y = 0.0
		print("DBG %s t=%.2f d=(%.2f,%.2f) vel=(%.2f,%.2f) heroZ=(%.2f,%.2f) toCam=(%.2f,%.2f) dist=%.2f cur=%s" % [shot[0], t, st.d.x, st.d.z, v.x, v.z,
			hz.x, hz.z, tc.normalized().x, tc.normalized().z, tc.length(), get_viewport().get_camera_3d().name])


# ───────────────────────── 工具 ─────────────────────────

func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _u() -> float:
	return clampf(t / dur, 0.0, 1.0)


func _ground(p: Vector3) -> float:
	return float(world.get_height(p.x, p.z))


func _on_ground(p: Vector3) -> Vector3:
	return Vector3(p.x, _ground(p), p.z)


func _cam(pos: Vector3, look: Vector3, fov: float, clear := 0.7) -> void:
	pos.y = maxf(pos.y, _ground(pos) + clear)
	cam.global_transform = Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	cam.fov = fov


func _dof(far_dist: float, trans: float, amount: float) -> void:
	attr.dof_blur_far_enabled = far_dist > 0.0
	attr.dof_blur_far_distance = maxf(far_dist, 0.01)
	attr.dof_blur_far_transition = trans
	attr.dof_blur_amount = amount
	attr.dof_blur_near_enabled = false


func _time(a: float, b: float) -> void:
	dn.time_of_day = lerpf(a, b, _u())


func _hp() -> Vector3:
	return hero.global_position


func _side(d: Vector3) -> Vector3:
	return Vector3(-d.z, 0.0, d.x)


func _place(p: Vector3, d: Vector3) -> void:
	d = Vector3(d.x, 0.0, d.z).normalized()
	st.place_p = p
	st.place_d = d
	_hold_place()


func _hold_place() -> void:
	var p: Vector3 = st.place_p
	var d: Vector3 = st.place_d
	p.y = _ground(p) + 0.05
	player.global_position = p
	player.velocity = Vector3.ZERO
	player.rotation = Vector3(0.0, atan2(-d.x, -d.z), 0.0)
	player.set("_vis_y", p.y)
	hero._yaw = atan2(d.x, d.z)
	hero.global_rotation = Vector3(0.0, hero._yaw, 0.0)
	world.set("_stream_timer", 0.0)
	var w: float = world.biome_w(p.x, p.z).r
	world.set("_winter", w)
	world.set("_snow_k_raw", w)
	world.set("_biome_timer", 0.0)
	dn.winter = w


## 让角色走 / 跑：模拟按住 W（和 Shift），走的时候 player.active 要打开才收键盘
var _keys := {}

func _key(code: Key, down: bool) -> void:
	if _keys.get(code, false) == down:
		return
	_keys[code] = down
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


func _walk(run := false) -> void:
	player.active = true
	_key(KEY_W, true)
	_key(KEY_SHIFT, run)


func _stop() -> void:
	_key(KEY_W, false)
	_key(KEY_SHIFT, false)
	player.active = false


func _reset_actor() -> void:
	_stop()
	hero.hold("")
	hero.expression_override = ""
	hero.act = ""
	if hero.get("_fish") != "":
		hero._stop_fishing()
	player.aim_override = Vector3.ZERO
	dn.sky_mat.set_shader_parameter("aurora_force", -1.0)
	for k in ["rabbit", "deer"]:
		if st.has(k) and is_instance_valid(st[k]):
			st[k].queue_free()


## 从 c 出发沿 d 走 length 米，一路上有没有树、石头、水，坡会不会太陡
func _clear(c: Vector3, d: Vector3, length: float, rad := 1.2) -> bool:
	rad = maxf(rad, float(st.get("clear_rad", 0.0)))
	var h0 := _ground(c)
	for i in range(0, int(length) + 1):
		var p := c + d * float(i)
		if world.blocked_at(p.x, p.z, rad) or world.in_pond(p.x, p.z):
			return false
		if absf(_ground(p) - h0) > 2.0 + float(i) * 0.12:
			return false
	return true


## 在 pref 附近找一个能走 length 米的方向
func _pick_dir(c: Vector3, pref: Vector3, length: float) -> Vector3:
	pref = Vector3(pref.x, 0.0, pref.z).normalized()
	for k in 24:
		var a := deg_to_rad(15.0) * ceilf(k / 2.0) * (1.0 if k % 2 == 0 else -1.0)
		var d := pref.rotated(Vector3.UP, a)
		if _clear(c, d, length):
			return d
	return pref


## 镜头放在哪一侧（+1 右 / -1 左）：那边离开 off 米的一路上没有遮挡
func _pick_side(c: Vector3, d: Vector3, off: float, length: float) -> float:
	var s := _side(d)
	var score := [0, 0]
	for k in 2:
		var sg := 1.0 if k == 0 else -1.0
		for i in range(-2, int(length) + 3, 2):
			for f in [0.5, 1.0]:
				var p: Vector3 = c + d * float(i) + s * sg * off * f
				if world.blocked_at(p.x, p.z, 0.8):
					score[k] += 1
	return 1.0 if score[0] <= score[1] else -1.0


## 拍之前在附近挪一挪，找一块能走得开的地方
func _settle(c: Vector3, pref: Vector3, length: float) -> void:
	for ring in 12:
		for k in 8:
			var a := TAU * k / 8.0
			var p := c + Vector3(cos(a), 0.0, sin(a)) * ring * 6.0
			if ring == 0 and k > 0:
				break
			var d := _pick_dir(p, pref, length)
			if _clear(p - d * 4.0, d, length + 4.0):
				st.c = p
				st.d = d
				_place(p, d)
				return
	st.d = pref
	_place(c, pref)


func _butterflies_at(p: Vector3, spread: float) -> void:
	var life = world.life
	if life == null:
		return
	var i := 0
	for b in life._bf:
		var a := TAU * i / 16.0
		b.home = p + Vector3(cos(a), 0.0, sin(a)) * spread * (0.4 + 0.6 * fmod(i * 0.37, 1.0))
		b.r1 = randf_range(0.8, 2.2)
		b.r2 = randf_range(0.8, 2.2)
		i += 1


## 附近最近的一丛花（花丛是加载后才有的）
func _near_flowers(c: Vector3) -> Vector3:
	var best := c
	var bd := 80.0
	for f: Vector3 in world.flower_centers:
		var dd := Vector2(f.x - c.x, f.z - c.z).length()
		if dd < bd and not world.blocked_at(f.x, f.z, 1.5):
			bd = dd
			best = f
	return Vector3(best.x, 0.0, best.z)


# ───────────────────────── 找地点 ─────────────────────────

func _find_spots() -> void:
	var s: Vector3 = world.spawn
	spots.meadow = {"c": s, "d": Vector3(1, 0, 0.15)}
	# 花多的地方：离出生点不远、平坦、周围是草原
	spots.flowers = {"c": s + Vector3(30, 0, 30), "d": Vector3(0.3, 0, -1)}
	spots.plain = {"c": s + Vector3(-60, 0, 40), "d": Vector3(0, 0, 1)}
	var names := {"autumn": 3, "sakura": 4, "desert": 2, "snow": 1, "ice": 5}
	for n in names:
		var p := _find_biome(names[n], Vector2(s.x, s.z))
		spots[n] = {"c": Vector3(p.x, 0, p.y), "d": Vector3(0.3, 0, -1)}
		print("SPOT %s (%d, %d)" % [n, int(p.x), int(p.y)])
	spots.pond = _find_pond(Vector2(s.x, s.z))
	print("SPOT pond ", spots.pond.c)


func _find_biome(id: int, from: Vector2) -> Vector2:
	var step := 80.0
	for ring in range(1, 160):
		var n := ring * 8
		for k in n:
			var a := TAU * k / n
			var p := from + Vector2(cos(a), sin(a)) * ring * step
			if _biome_ok(id, p):
				return p
	push_warning("没找到群系 %d" % id)
	return from


func _biome_ok(id: int, p: Vector2) -> bool:
	for off: Vector2 in [Vector2.ZERO, Vector2(70, 0), Vector2(-70, 0), Vector2(0, 70), Vector2(0, -70)]:
		var q := p + off
		var b: Vector2 = world.biome_at(q.x, q.y)
		if int(b.x) != id or b.y < 0.95:
			return false
		if world.mountain_mask(q.x, q.y) > 0.0:
			return false
	var h0: float = world.height_raw(p.x, p.y)
	for off: Vector2 in [Vector2(25, 0), Vector2(-25, 0), Vector2(0, 25), Vector2(0, -25)]:
		if absf(world.height_raw(p.x + off.x, p.y + off.y) - h0) > 2.5:
			return false
	var pond: Vector4 = world.pond_at(p.x, p.y)
	if pond.w > 0.5 and Vector2(pond.x, pond.y).distance_to(p) < 40.0:
		return false
	return true


func _find_pond(from: Vector2) -> Dictionary:
	var cell: float = world.POND_CELL
	var c0 := Vector2i(floori(from.x / cell), floori(from.y / cell))
	var best := Vector4.ZERO
	var best_d := INF
	for dz in range(-12, 13):
		for dx in range(-12, 13):
			var pd: Vector4 = world.pond_at((c0.x + dx + 0.5) * cell, (c0.y + dz + 0.5) * cell)
			if pd.w < 0.5 or pd.w > 1.5:
				continue
			var b: Vector2 = world.biome_at(pd.x, pd.y)
			if int(b.x) != 0 or b.y < 0.9:
				continue
			var d := Vector2(pd.x, pd.y).distance_to(from)
			if d < best_d:
				best_d = d
				best = pd
	# 站在池塘东岸，面朝西边（傍晚的太阳在那边，水面有倒影）
	var r: float = world.POND_RADIUS
	var c := Vector3(best.x + r + 1.6, 0, best.y)
	return {"c": c, "d": Vector3(-1, 0, 0), "pond": Vector3(best.x, 0, best.y)}


# ───────────────────────── 镜头 ─────────────────────────
# _setup_xxx：地图加载好后布置一次；_shot_xxx(t)：每帧更新，t 从 -HANDLE-PREROLL 到 dur+HANDLE

# 1 清晨：镜头贴着草尖往前推，逆光看日出
func _setup_dawn() -> void:
	_settle(st.c, Vector3(1, 0, 0.1), 16.0)
	spots.meadow = {"c": st.c, "d": st.d}
	st.cam0 = st.c
	_place(st.c + st.d * 9.0, st.d)       # 角色在前面远一点，逆光的小背影
	_dof(7.0, 18.0, 0.05)


func _shot_dawn(_t: float) -> void:
	_time(6.42, 6.58)
	var c: Vector3 = st.cam0
	var d: Vector3 = st.d
	var u := _ease((t + HANDLE) / (dur + HANDLE * 2.0))
	var pos := c - d * lerpf(4.0, 1.6, u) + Vector3(0, 0.3, 0)
	pos.y = _ground(pos) + 0.3
	_cam(pos, pos + d * 10.0 + Vector3(0, 0.75, 0), 46.0, 0.25)
	player.aim_override = c + d * 30.0 + Vector3(0, 2, 0)


# 2 升起：从草里升到半空，露出整片草原和远山（标题在这里出现）
func _setup_reveal() -> void:
	_dof(0.0, 1.0, 0.0)
	_place(st.c + st.d * 9.0, st.d)


func _shot_reveal(_t: float) -> void:
	_time(6.58, 6.85)
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var s := _side(d)
	var u := _ease((t + HANDLE) / (dur + HANDLE * 2.0))
	var pos := c - d * lerpf(1.6, 8.0, u) + s * lerpf(0.0, 2.5, u)
	pos.y = _ground(pos) + lerpf(0.35, 17.0, u * u)
	var look := c + d * lerpf(12.0, 90.0, u)
	look.y = _ground(c) + lerpf(1.6, 2.0, u)
	_cam(pos, look, lerpf(50.0, 58.0, u), 0.3)
	player.aim_override = c + d * 30.0 + Vector3(0, 2, 0)


# 3 侧面跟拍：角色走过草地，蝴蝶飞过
func _setup_walk() -> void:
	_settle(_near_flowers(st.c), Vector3(0.3, 0, -1), 18.0)
	spots.flowers = {"c": st.c, "d": st.d}
	st.side = _pick_side(st.c, st.d, 3.4, 14.0)
	st.start = st.c - st.d * 2.5
	_place(st.start, st.d)
	_butterflies_at(st.c + st.d * 6.0, 4.0)
	_dof(4.0, 16.0, 0.07)


func _shot_walk(_t: float) -> void:
	_time(8.6, 8.7)
	_walk()
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	var u := _u()
	var pos := h + s * lerpf(3.3, 2.9, u) + d * 2.6 + Vector3(0, 1.0, 0)
	_cam(pos, h + Vector3(0, 0.85, 0) + d * 0.3, 40.0)
	player.aim_override = Vector3.ZERO


# 4 正面特写：角色朝镜头走过来，看着镜头
func _setup_face() -> void:
	_settle(st.c, Vector3(-0.3, 0, 1), 12.0)
	_place(st.c, st.d)
	_dof(3.2, 10.0, 0.1)
	hero.expression_override = "happy"


func _shot_face(_t: float) -> void:
	_time(8.8, 8.85)
	_walk()
	var d: Vector3 = st.d
	var h := _hp()
	var pos := h + d * 2.4 + _side(d) * 0.35 + Vector3(0, 1.0, 0)
	_cam(pos, h + Vector3(0, 1.05, 0), 32.0)
	player.aim_override = cam.global_position


# 5 摸兔子
func _setup_pet() -> void:
	_settle(st.c, Vector3(1, 0, 0.4), 4.0)
	st.side = _pick_side(st.c, st.d, 2.0, 2.0)
	var d: Vector3 = st.d
	var rp: Vector3 = st.c + d * 0.85
	var r := Node3D.new()
	r.set_script(load("res://scripts/rabbit.gd"))
	world.add_child(r)
	r.setup(world, Vector3(rp.x, world.height_raw(rp.x, rp.z), rp.z), atan2(-d.x, -d.z))
	r.set("friend_t", 150.0)
	st.rabbit = r
	_dof(3.0, 8.0, 0.09)


func _shot_pet(_t: float) -> void:
	_time(9.4, 9.5)
	_stop()
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var m := c + d * 0.45
	var a := lerpf(0.0, 0.25, _u())
	var dir := (s * 0.75 + d * 0.65).normalized().rotated(Vector3.UP, a * float(st.side))
	_cam(m + dir * 3.0 + Vector3(0, 1.05, 0), m + Vector3(0, 0.6, 0), 40.0, 0.9)
	player.aim_override = st.rabbit.global_position + Vector3(0, 0.2, 0) if is_instance_valid(st.rabbit) else Vector3.ZERO
	if t >= 0.15 and not st.has("acted") and is_instance_valid(st.rabbit):
		st.acted = true
		inter.set("_partner", st.rabbit)
		inter.set("_feeding", false)
		hero.play_act("pet", st.rabbit.head_pos(), false)
		st.rabbit.on_pet(player, false, float(hero.ACTS["pet"]))


# 6 喂小鹿
func _setup_feed() -> void:
	_settle(st.c + Vector3(14, 0, -6), Vector3(-1, 0, 0.3), 5.0)
	st.side = _pick_side(st.c, st.d, 3.5, 3.0)
	var d: Vector3 = st.d
	var dp: Vector3 = st.c + d * 1.55
	var r := Node3D.new()
	r.set_script(load("res://scripts/deer.gd"))
	world.add_child(r)
	r.setup(world, Vector3(dp.x, world.height_raw(dp.x, dp.z), dp.z), atan2(-d.x, -d.z))
	r.set("friend_t", 150.0)
	st.deer = r
	hero.hold("berry")
	_dof(4.0, 10.0, 0.08)


func _shot_feed(_t: float) -> void:
	_time(9.8, 9.9)
	_stop()
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var m := c + d * 0.8
	var a := lerpf(0.0, -0.2, _u())
	var dir := (s * 0.95 + d * 0.2).normalized().rotated(Vector3.UP, a * float(st.side))
	_cam(m + dir * 3.6 + Vector3(0, 1.35, 0), m + Vector3(0, 0.95, 0), 40.0, 0.9)
	if is_instance_valid(st.deer):
		player.aim_override = st.deer.head_pos()
	if t >= 0.2 and not st.has("acted") and is_instance_valid(st.deer):
		st.acted = true
		inter.set("_partner", st.deer)
		inter.set("_feeding", true)
		hero.play_act("feed", st.deer.head_pos(), true)
		st.deer.on_pet(player, true, float(hero.ACTS["feed"]))


# 7 捕蝴蝶
func _setup_net() -> void:
	_settle(st.c + Vector3(-10, 0, 8), Vector3(0.2, 0, 1), 5.0)
	st.side = _pick_side(st.c, st.d, 3.0, 3.0)
	hero.hold("net")
	_butterflies_at(st.c + st.d * 1.3 + Vector3(0, 0, 0), 1.2)
	_dof(3.6, 10.0, 0.07)


func _shot_net(_t: float) -> void:
	_time(10.2, 10.25)
	_stop()
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	_cam(c + d * 3.3 + s * 1.5 + Vector3(0, 1.0, 0), c + d * 0.9 + Vector3(0, 0.9, 0), 44.0, 0.9)
	player.aim_override = c + d * 1.5 + Vector3(0, 1.0, 0)
	if t >= 0.55 and not st.has("swung"):
		st.swung = true
		hero.use_tool()


# 8-12 群系快切
func _setup_biome_walk(pref: Vector3, side_off: float) -> void:
	_settle(st.c, pref, 22.0)
	st.side = _pick_side(st.c, st.d, side_off, 16.0)
	st.start = st.c - st.d * 3.0
	_place(st.start, st.d)


func _setup_autumn() -> void:
	_setup_biome_walk(Vector3(0, 0, 1), 6.0)
	_dof(9.0, 25.0, 0.05)


func _shot_autumn(_t: float) -> void:
	_time(15.6, 15.7)
	if phase == "roll" or t > -HANDLE - PREROLL + 0.2:
		_walk()
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	var u := _u()
	var pos := h + s * 4.6 + d * lerpf(4.0, 2.4, u) + Vector3(0, 1.4, 0)
	_cam(pos, h + Vector3(0, 0.9, 0), 46.0)


func _setup_sakura() -> void:
	_setup_biome_walk(Vector3(1, 0, 0), 2.0)
	_dof(0.0, 1.0, 0.0)


func _shot_sakura(_t: float) -> void:
	_time(10.5, 10.6)
	_walk()
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	var pos := h + d * 4.4 + s * 1.6 + Vector3(0, 0.9, 0)
	_cam(pos, h + Vector3(0, 1.5, 0) + d * 0.5, 50.0, 0.8)
	player.aim_override = cam.global_position


func _setup_desert() -> void:
	_setup_biome_walk(Vector3(0, 0, -1), 9.0)
	_dof(0.0, 1.0, 0.0)


func _shot_desert(_t: float) -> void:
	_time(16.9, 17.0)
	_walk()
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	var u := _u()
	var pos := h - d * lerpf(1.0, 2.5, u) + s * 8.5 + Vector3(0, 3.2, 0)
	_cam(pos, h + d * 3.0 + Vector3(0, 0.6, 0), 48.0)


func _setup_snow() -> void:
	_setup_biome_walk(Vector3(0.5, 0, -1), 2.0)
	_dof(8.0, 20.0, 0.04)


func _shot_snow(_t: float) -> void:
	_time(13.0, 13.1)
	_walk()
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	var pos := h - d * 3.2 + s * 1.7 + Vector3(0, 1.0, 0)
	_cam(pos, h + d * 1.2 + Vector3(0, 0.55, 0), 46.0)


func _setup_ice() -> void:
	_setup_biome_walk(Vector3(1, 0, 0), 5.0)
	_dof(0.0, 1.0, 0.0)


func _shot_ice(_t: float) -> void:
	_time(15.2, 15.3)
	# 跑一段，松手，在冰面上滑出去
	if t < 1.6:
		_walk(true)
	else:
		_stop()
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	var a := lerpf(-0.7, 0.8, _ease(_u()))
	var dir := s * cos(a) + d * sin(a)
	_cam(h + dir * 5.0 + Vector3(0, 1.3, 0), h + Vector3(0, 0.8, 0), 44.0)


# 13 雪原夜里的极光：从角色身后慢慢抬头看天
func _setup_aurora() -> void:
	_settle(st.c, Vector3(0, 0, -1), 4.0)
	_place(st.c, Vector3(0, 0, -1))
	st.d = Vector3(0, 0, -1)
	dn.sky_mat.set_shader_parameter("aurora_force", 0.85)
	_dof(0.0, 1.0, 0.0)


func _shot_aurora(_t: float) -> void:
	_time(23.4, 23.6)
	_stop()
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var s := _side(d)
	var u := _ease((t + HANDLE) / (dur + HANDLE * 2.0))
	var pos := c - d * lerpf(3.0, 5.5, u) + s * lerpf(0.7, 1.4, u) + Vector3(0, lerpf(0.75, 1.3, u), 0)
	var look := c + d * lerpf(3.0, 30.0, u) + Vector3(0, lerpf(1.0, 24.0, u), 0)
	_cam(pos, look, lerpf(58.0, 72.0, u))
	player.aim_override = c + d * 20.0 + Vector3(0, 16.0, 0)


# 14 黄昏钓鱼
func _setup_fish() -> void:
	var sp: Dictionary = spots.pond
	st.d = sp.d
	_place(st.c, st.d)
	hero.hold("rod")
	st.side = _pick_side(st.c, st.d, 4.0, 2.0)
	_dof(0.0, 1.0, 0.0)


func _shot_fish(_t: float) -> void:
	_time(17.35, 17.85)
	_stop()
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var u := _u()
	_cam(c + s * lerpf(4.6, 4.2, u) - d * 1.0 + Vector3(0, 1.3, 0), c + d * 1.6 + Vector3(0, 0.45, 0), 50.0, 0.9)
	if not st.has("cast") and t > -HANDLE - PREROLL + 0.3 and player.is_on_floor():
		st.cast = true
		hero.use_tool()
	if hero._fish == "wait" and not st.has("wait_set"):
		st.wait_set = true
		hero._fish_wait = maxf(0.5, 1.5 - t)
	if hero._fish == "bite" and not st.has("pulled") and hero._fish_t > 0.45:
		st.pulled = true
		hero.use_tool()


# 15 夜里的萤火虫
func _setup_fireflies() -> void:
	_settle(st.c + Vector3(-20, 0, -15), Vector3(1, 0, 0), 14.0)
	st.side = _pick_side(st.c, st.d, 3.2, 10.0)
	st.start = st.c - st.d * 2.0
	_place(st.start, st.d)
	_dof(5.0, 14.0, 0.06)


func _shot_fireflies(_t: float) -> void:
	_time(21.3, 21.35)
	_walk()
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	_cam(h + s * 3.0 + d * 2.6 + Vector3(0, 0.95, 0), h + Vector3(0, 0.85, 0) + d * 0.3, 42.0)


# 16 金色时刻奔跑，航拍跟随
func _setup_run() -> void:
	_settle(st.c, Vector3(0, 0, 1), 50.0)
	st.side = _pick_side(st.c, st.d, 4.0, 40.0)
	st.start = st.c - st.d * 5.0
	_place(st.start, st.d)
	_dof(0.0, 1.0, 0.0)


func _shot_run(_t: float) -> void:
	_time(17.0, 17.05)
	_walk(true)
	var d: Vector3 = st.d
	var s: Vector3 = _side(d) * float(st.side)
	var h := _hp()
	var u := _ease(_u())
	var pos := h - d * lerpf(5.0, 3.4, u) + s * lerpf(2.6, 1.8, u) + Vector3(0, lerpf(3.4, 1.9, u), 0)
	_cam(pos, h + d * 4.0 + Vector3(0, 0.8, 0), 52.0)


# 17 回头挥手
func _setup_wave() -> void:
	_settle(st.c + Vector3(8, 0, 30), Vector3(1, 0, 0.3), 4.0)
	_place(st.c, st.d)
	hero.expression_override = "happy"
	_dof(3.4, 10.0, 0.09)


func _shot_wave(_t: float) -> void:
	_time(17.15, 17.2)
	_stop()
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var u := _u()
	var pos := c + d * lerpf(3.0, 2.5, u) + _side(d) * 0.5 + Vector3(0, 1.1, 0)
	_cam(pos, c + Vector3(0, 1.1, 0), 34.0)
	player.aim_override = cam.global_position
	if t >= 0.5 and not st.has("waved"):
		st.waved = true
		hero.play_act("wave")


# 18 结尾：角色走向夕阳
func _setup_final() -> void:
	st.clear_rad = 4.5
	_settle(st.c + Vector3(-30, 0, 10), Vector3(-1, 0, 0.15), 22.0)
	_dof(0.0, 1.0, 0.0)


func _shot_final(_t: float) -> void:
	_time(17.55, 17.75)
	if t > -0.2:
		_walk()
	var c: Vector3 = st.c
	var d: Vector3 = st.d
	var u := _ease((t + HANDLE) / (dur + HANDLE * 2.0))
	var pos := c - d * 2.2 + _side(d) * 0.5 + Vector3(0, lerpf(0.9, 2.0, u), 0)
	_cam(pos, c + d * 30.0 + Vector3(0, lerpf(2.5, 3.5, u), 0), 50.0)
