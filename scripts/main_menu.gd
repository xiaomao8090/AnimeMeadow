extends CanvasLayer
## 主菜单 + 暂停菜单。
## 菜单直接叠在真实的世界上：一台长焦的电影镜头（带景深）绕着角色慢慢转，角色的眼睛跟着鼠标看。
## 点“开始漫步”：镜头从角色正面绕一个弧线升起、落到肩后，角色转身看向草原，然后交出操作。
## Esc：游戏中打开暂停（整屏毛玻璃），暂停里可以回到主菜单（镜头再绕回正面）。
## 所有界面都是代码画的，配色：奶油白文字 + 暖金色点缀 + 墨绿色的暗部。

const Item := preload("res://scripts/ui_item.gd")
const Fx := preload("res://scripts/fx.gd")
const LOGO := preload("res://art/branding/animemeadow-logo-v1.png")
const LOGO_W := 480.0             # 主菜单 logo 的显示宽度（像素）
const POKE_ACTS := ["giggle", "boing", "spin", "wave"]

const CREAM := Color(0.984, 0.957, 0.902)
const GOLD := Color(0.925, 0.780, 0.500)
const SHADOW := Color(0.02, 0.05, 0.06)
const PAPER := Color(0.965, 0.935, 0.870)     # 开场 / 切换地图时的淡入底色

const MENU_TIME := 16.8            # 菜单里的时间：午后偏金色的光
const MENU_DAY_MINUTES := 240.0    # 菜单里时间几乎停住
const MENU_FOV := 36.0             # 长焦，背景压缩得更有电影感
const ORBIT_DIST := 4.7
const ORBIT_H := 0.72              # 镜头低一点，多拍天空
const LOOK_Y := 0.95
const COMPOSE := 0.20              # 镜头往左偏一点，让角色落在画面右三分之一
const MENU_X := 104.0
const LIST_Y := 372.0
const TO_GAME_TIME := 2.4
const TO_MENU_TIME := 2.0
const DOF_AMOUNT := 0.07
const VERSION := "v0.3"

var world
var player
var hero
var day_night
var cam: Camera3D
var cam_attr: CameraAttributesPractical
var hold_intro := false           # 加载界面还没结束时为 true，开场先等着
var state := "intro"               # intro / menu / to_game / game / pause / to_menu
var page := ""

var _hud: CanvasLayer
var _day_minutes := 10.0
var _t := 0.0                      # 菜单镜头的时钟
var _ui_t := 0.0
var _intro_t := 0.0
var _idle_jobs := 0.0
var _intro_push := 1.0             # 开场镜头慢慢推近
var _center := Vector3.ZERO
var _orbit := 0.0
var _par := Vector2.ZERO
var _mouse_moved := false
var _tr := 0.0
var _from: Transform3D
var _from_fov := 75.0
var _from_angle := 0.0
var _from_dist := 0.0
var _from_h := 0.0
var _to_angle := 0.0
var _pending_page := ""
var _pending_t := 0.0
var _pending_delay := 0.0
var _reload_t := -1.0
var _leaving := ""                 # reload / quit：等淡出完成
var _grass_dirty := false
var _expr_t := 0.0
var _hover_hero := false
var _pokes: Array[float] = []      # 最近几次戳的时间（戳太多会晕）
var _last_poke := ""
var _poke_cd := 0.0

var _root: Control
var _wash: ColorRect
var _wash_mat: ShaderMaterial
var _blur: ColorRect
var _blur_mat: ShaderMaterial
var _title: Control
var _list: VBoxContainer
var _footer: Control
var _fade: ColorRect
var _key_box: StyleBoxFlat

var _wash_amt := 0.0
var _wash_target := 1.0
var _vig := 0.0
var _vig_target := 1.0
var _blur_amt := 0.0
var _blur_target := 0.0
var _blur_side := 0.0
var _fade_amt := 1.0
var _fade_target := 1.0
var _fade_speed := 0.6
var _title_alpha := 0.0
var _title_target := 0.0
var _title_t := 0.0
var _title_text := ""
var _title_sub := ""
var _title_size := 92
var _footer_alpha := 0.0
var _footer_target := 0.0
var _tip := ""
var _tip_next := ""
var _tip_alpha := 0.0
var _hud_alpha := 0.0
var _hud_target := 0.0


# ───────────────────────── 初始化 ─────────────────────────

func setup(w) -> void:
	world = w
	player = w.player
	hero = player.hero
	day_night = w.day_night
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 50

	player.active = false
	hero.look_lock = true
	for c in w.get_children():
		if c is CanvasLayer:
			_hud = c
	_set_hud_alpha(0.0)
	hero.act_beat.connect(_on_hero_beat)

	_day_minutes = day_night.day_length_minutes
	day_night.time_of_day = MENU_TIME
	day_night.day_length_minutes = MENU_DAY_MINUTES

	cam = Camera3D.new()
	cam.name = "MenuCamera"
	cam.fov = MENU_FOV
	cam.near = 0.05
	cam.far = 1500.0
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 10.0
	cam_attr.dof_blur_far_transition = 30.0
	cam_attr.dof_blur_amount = DOF_AMOUNT
	cam.attributes = cam_attr
	w.add_child(cam)

	_center = player.global_position
	_orbit = _pick_angle()
	_face_camera()
	cam.global_transform = _menu_xform(0.0)
	cam.make_current()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	_build_ui()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_blur = ColorRect.new()
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = load("res://shaders/ui_blur.gdshader")
	_blur.material = _blur_mat
	_blur.visible = false
	_root.add_child(_blur)

	_wash = ColorRect.new()
	_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wash_mat = ShaderMaterial.new()
	_wash_mat.shader = load("res://shaders/ui_wash.gdshader")
	_wash.material = _wash_mat
	_root.add_child(_wash)

	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.draw.connect(_draw_title)
	_title.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS   # logo 缩小显示也要平滑
	_root.add_child(_title)

	_list = VBoxContainer.new()
	_list.position = Vector2(MENU_X, LIST_Y)
	_list.add_theme_constant_override("separation", 2)
	_list.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_list)

	_footer = Control.new()
	_footer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(_draw_footer)
	_root.add_child(_footer)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.color = PAPER
	_root.add_child(_fade)

	_key_box = StyleBoxFlat.new()
	_key_box.draw_center = false
	_key_box.set_border_width_all(1)
	_key_box.border_color = Color(CREAM, 0.4)
	_key_box.set_corner_radius_all(4)
	_key_box.anti_aliasing = true


# ───────────────────────── 每帧 ─────────────────────────

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_t += dt
	_ui_t += dt

	match state:
		"intro":
			_intro_t += dt
			var jobs = world.get("_jobs")
			_idle_jobs = (_idle_jobs + dt) if (jobs == null or int(jobs) == 0) else 0.0
			var min_t := 0.3 if Settings.skip_intro else 0.8
			if not hold_intro and _intro_t > min_t and (_idle_jobs > 0.3 or _intro_t > 6.0):
				_begin_menu()
			cam.global_transform = _menu_xform(dt)
			_menu_hero()
		"menu":
			_intro_push = move_toward(_intro_push, 0.0, dt / 5.0)
			cam.global_transform = _menu_xform(dt)
			_menu_hero()
		"to_game":
			_process_to_game(dt)
		"to_menu":
			_process_to_menu(dt)
			_menu_hero()

	_poke_cd -= dt
	var hov := state == "menu" and _leaving == "" and _hit_hero(get_viewport().get_mouse_position())
	if hov != _hover_hero:
		_hover_hero = hov
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if hov else Input.CURSOR_ARROW)
	_update_expression(dt)
	_animate_layers(dt)

	if _pending_page != "":
		_pending_t -= dt
		if _pending_t <= 0.0:
			var p := _pending_page
			_pending_page = ""
			_build_page(p, _pending_delay)

	if _reload_t >= 0.0:
		_reload_t -= dt
		if _reload_t < 0.0:
			_leave("reload")
	if _leaving != "" and _fade_amt >= 0.999:
		if _leaving == "quit":
			get_tree().quit()
		else:
			Settings.skip_intro = true
			get_tree().paused = false
			get_tree().reload_current_scene()
		_leaving = "done"


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse_moved = true
	if _leaving != "":
		return
	if event.is_action_pressed("ui_cancel"):
		match state:
			"game":
				var bm := get_tree().get_first_node_in_group("bigmap")
				var inv := get_tree().get_first_node_in_group("inventory")
				if inv and inv.is_open():
					inv.close_bag()     # 背包开着：Esc 先关背包
				elif bm and bm.is_open():
					bm.close()          # 大地图开着：Esc 先收起地图
				else:
					open_pause()
			"pause":
				if page == "settings":
					_go("pause")
				else:
					resume()
			"menu":
				if page == "settings":
					_back()
		get_viewport().set_input_as_handled()
		return
	if (state == "menu" or state == "pause") and get_viewport().gui_get_focus_owner() == null:
		if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
			for c in _list.get_children():
				if c.target > 0.5:
					c.grab_focus()
					break
			get_viewport().set_input_as_handled()
		elif state == "menu" and page == "main" and event.is_action_pressed("ui_accept"):
			start_game()
			get_viewport().set_input_as_handled()


# ───────────────────────── 镜头 ─────────────────────────

func _ground(p: Vector3) -> float:
	return float(world.get_height(p.x, p.z))


## 绕 c 转的镜头：角度 th（0 = 角色正前方 +Z），水平距离 dist，比角色脚高 h，看向角色身上 look_y 的位置，再往左偏 comp 做构图
func _orbit_xform(c: Vector3, th: float, dist: float, h: float, look_y: float, comp: float) -> Transform3D:
	var pos := c + Vector3(sin(th), 0.0, cos(th)) * dist
	pos.y = maxf(c.y + h, _ground(pos) + 0.4)
	var look := c + Vector3(0.0, look_y, 0.0)
	var xf := Transform3D(Basis.looking_at(look - pos, Vector3.UP), pos)
	xf.basis = Basis(Vector3.UP, comp) * xf.basis
	return xf


func _menu_xform(dt: float) -> Transform3D:
	var push := _intro_push * _intro_push * (3.0 - 2.0 * _intro_push)
	var th := _orbit + 0.20 * sin(_t * 0.045)
	var dist := ORBIT_DIST + 0.3 * sin(_t * 0.031 + 1.0) + 1.6 * push
	var h := ORBIT_H + 0.07 * sin(_t * 0.07) + 0.35 * push
	var xf := _orbit_xform(_center, th, dist, h, LOOK_Y, COMPOSE)
	var vp := get_viewport()
	var ndc := vp.get_mouse_position() / Vector2(vp.get_visible_rect().size) * 2.0 - Vector2.ONE
	_par = _par.lerp(ndc.clamp(-Vector2.ONE, Vector2.ONE), clampf(dt * 2.0, 0.0, 1.0))
	xf.origin += xf.basis.x * _par.x * 0.14 - xf.basis.y * _par.y * 0.07
	return xf


## 找一个好看的机位：侧前方受光（不逆光）、镜头和角色之间没有遮挡、镜头不在树里 / 水里 / 坡里
func _pick_angle() -> float:
	var to_sun: Vector3 = day_night.sun.global_transform.basis.z
	var want := atan2(to_sun.x, to_sun.z) + 0.7
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var head := _center + Vector3(0.0, 1.0, 0.0)
	var trees = world.get("tree_positions")
	var best := want
	var best_s := -INF
	for i in 24:
		var th := TAU * i / 24.0
		var s := cos(wrapf(th - want, -PI, PI))
		for k in [-0.24, 0.0, 0.24]:
			var pos := _orbit_xform(_center, th + k, ORBIT_DIST + 0.6, ORBIT_H, LOOK_Y, 0.0).origin
			if pos.y > _center.y + ORBIT_H + 0.5:
				s -= 1.5
			var q := PhysicsRayQueryParameters3D.create(pos, head)
			q.exclude = [player.get_rid()]
			if not space.intersect_ray(q).is_empty():
				s -= 3.0
			if world.has_method("in_pond") and world.in_pond(pos.x, pos.z):
				s -= 2.0
			if trees != null:
				var p2 := Vector2(pos.x, pos.z)
				for tp in trees:
					if p2.distance_squared_to(tp) < 9.0:
						s -= 3.0
						break
		if s > best_s:
			best_s = s
			best = th
	return best


func _face_camera() -> void:
	hero._yaw = _orbit
	hero.global_rotation = Vector3(0.0, _orbit, 0.0)


func _menu_hero() -> void:
	player.aim_override = cam.project_position(get_viewport().get_mouse_position(), 1.5)
	# 站久了会犯困；动一下鼠标把它叫醒
	if _mouse_moved and hero._idle_time > 18.0:
		hero._idle_time = 3.0
		hero._fidget = ""
		hero._yawn_t = -1.0
	_mouse_moved = false


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


func _capture_from(xf: Transform3D, fov: float) -> void:
	_tr = 0.0
	_from = xf
	_from_fov = fov
	_from_angle = atan2(xf.origin.x - _center.x, xf.origin.z - _center.z)
	_from_dist = Vector2(xf.origin.x - _center.x, xf.origin.z - _center.z).length()
	_from_h = xf.origin.y - _center.y


func _process_to_game(dt: float) -> void:
	_tr = minf(_tr + dt / TO_GAME_TIME, 1.0)
	var e := _ease(_tr)
	var g: Transform3D = player.cam.global_transform
	var c: Vector3 = player.global_position
	var ga := atan2(g.origin.x - c.x, g.origin.z - c.z)
	var gd := Vector2(g.origin.x - c.x, g.origin.z - c.z).length()
	var da := wrapf(ga - _from_angle, -PI, PI)
	var arc := _orbit_xform(c, _from_angle + da * e, lerpf(_from_dist, gd, e),
		lerpf(_from_h, g.origin.y - c.y, e) + sin(e * PI) * 0.9, lerpf(LOOK_Y, 1.3, e), lerpf(COMPOSE, 0.0, e))
	var xf := _from.interpolate_with(arc, smoothstep(0.0, 0.18, _tr))
	cam.global_transform = xf.interpolate_with(g, smoothstep(0.62, 1.0, _tr))
	cam.fov = lerpf(_from_fov, player.cam.fov, e)
	cam_attr.dof_blur_amount = lerpf(DOF_AMOUNT, 0.0, e)
	if _tr >= 1.0:
		_enter_game()


func _process_to_menu(dt: float) -> void:
	_tr = minf(_tr + dt / TO_MENU_TIME, 1.0)
	var e := _ease(_tr)
	var td := ORBIT_DIST + 0.3 * sin(1.0)
	var da := wrapf(_to_angle - _from_angle, -PI, PI)
	var arc := _orbit_xform(_center, _from_angle + da * e, lerpf(_from_dist, td, e),
		lerpf(_from_h, ORBIT_H, e) + sin(e * PI) * 0.9, lerpf(1.3, LOOK_Y, e), lerpf(0.0, COMPOSE, e))
	cam.global_transform = _from.interpolate_with(arc, smoothstep(0.0, 0.2, _tr))
	cam.fov = lerpf(_from_fov, MENU_FOV, e)
	cam_attr.dof_blur_amount = lerpf(0.0, DOF_AMOUNT, e)
	if _tr >= 1.0:
		state = "menu"
		_orbit = _to_angle
		_t = 0.0
		_par = Vector2.ZERO


# ───────────────────────── 状态切换 ─────────────────────────

func _begin_menu() -> void:
	_center = player.global_position
	_orbit = _pick_angle()          # 树这时已经长出来了，再挑一次机位
	_face_camera()
	_t = 0.0
	state = "menu"
	_fade_target = 0.0
	_fade_speed = 1.2 if Settings.skip_intro else 0.42
	_wash_target = 1.0
	_vig_target = 1.0
	_footer_target = 1.0
	_build_page("main", 0.5 if Settings.skip_intro else 1.6)
	_title_t = -0.3 if Settings.skip_intro else -1.1


func start_game() -> void:
	if state != "menu" or _leaving != "":
		return
	state = "to_game"
	_center = player.global_position
	_capture_from(cam.global_transform, cam.fov)
	var fwd := Vector3(_center.x - _from.origin.x, 0.0, _center.z - _from.origin.z).normalized()
	player.rotation.y = atan2(-fwd.x, -fwd.z)
	player._pitch = -0.08
	player.aim_override = _center + fwd * 25.0 + Vector3(0.0, 1.3, 0.0)
	hero.look_lock = false
	_expr_t = 1.4
	day_night.day_length_minutes = _day_minutes
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_hide_items()
	_title_target = 0.0
	_wash_target = 0.0
	_vig_target = 0.3
	_footer_target = 0.0


func _enter_game() -> void:
	state = "game"
	hero.set_first_person(not player.third_person)    # 进游戏时恢复玩家选的视角（第一人称只显示手）
	player.cam.make_current()
	player.active = true
	player.aim_override = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_hud_target = 1.0
	_vig_target = 0.0


func open_pause() -> void:
	state = "pause"
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_blur_side = 0.0
	_blur_target = 1.0
	_wash_target = 0.55
	_vig_target = 1.0
	_hud_target = 0.0
	_footer_target = 1.0
	_go("pause", 0.0)


func resume() -> void:
	get_tree().paused = false
	state = "game"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_blur_target = 0.0
	_wash_target = 0.0
	_vig_target = 0.0
	_hud_target = 1.0
	_footer_target = 0.0
	_title_target = 0.0
	_hide_items()


func back_to_menu() -> void:
	get_tree().paused = false
	state = "to_menu"
	player.active = false
	hero.set_first_person(false)    # 主菜单里镜头在外面拍角色，要显示完整的身体
	_center = player.global_position
	_to_angle = _pick_angle()
	_capture_from(player.cam.global_transform, player.cam.fov)
	cam.global_transform = _from
	cam.fov = _from_fov
	cam_attr.dof_blur_amount = 0.0
	cam.make_current()
	hero.look_lock = true
	day_night.day_length_minutes = MENU_DAY_MINUTES
	_blur_target = 0.0
	_hud_target = 0.0
	_wash_target = 1.0
	_vig_target = 1.0
	_footer_target = 1.0
	_title_target = 0.0
	_go("main", 1.0)


func _leave(kind: String) -> void:
	if _leaving != "":
		return
	Settings.save_settings()
	_leaving = kind
	_fade_target = 1.0
	_fade_speed = 2.6
	_hide_items()


func _quit() -> void:
	_leave("quit")


# ───────────────────────── 页面 ─────────────────────────

func _go(p: String, extra_delay := 0.0) -> void:
	var had := false
	for c in _list.get_children():
		if c.target > 0.5:
			had = true
	_hide_items()
	_pending_page = p
	_pending_t = 0.22 if had else 0.0
	_pending_delay = extra_delay
	if p != "main":
		_title_target = 0.0


func _hide_items() -> void:
	for c in _list.get_children():
		c.target = 0.0
		c.delay = 0.0
		if c.has_focus():
			c.release_focus()


func _set_title(text: String, sub: String, size: int) -> void:
	_title_text = text
	_title_sub = sub
	_title_size = size
	_title_t = 0.0
	_title_target = 1.0


func _build_page(p: String, delay: float) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	page = p
	var focus_first := false
	match p:
		"main":
			_set_title("@logo", "", 0)
			_add_action("开始漫步", start_game, "", "按 Enter 也可以直接出发", "excited")
			_add_action("种子", _reroll, str(Settings.world_seed), "换一个种子 = 换一片全新的草原，走到哪生成到哪", "curious")
			_add_action("设置", func(): _go("settings"), "", "", "focused")
			_add_action("退出", _quit, "", "", "sleepy")
			_blur_side = 1.0
			_blur_target = 0.0
		"settings":
			_set_title("设置", "", 52)
			_add_slider("鼠标灵敏度", inverse_lerp(0.3, 2.0, Settings.mouse_sens),
				func(v): return "%.1f×" % lerpf(0.3, 2.0, v),
				func(v): Settings.mouse_sens = lerpf(0.3, 2.0, v), "")
			_add_slider("视野", inverse_lerp(55.0, 100.0, Settings.fov),
				func(v): return "%d°" % roundi(lerpf(55.0, 100.0, v)),
				func(v): Settings.fov = roundf(lerpf(55.0, 100.0, v)), "第三人称和第一人称都会用这个视野")
			_add_slider("音量", Settings.volume,
				func(v): return "%d%%" % roundi(v * 100.0),
				func(v): Settings.volume = v, "")
			_add_option("草地密度", PackedStringArray(["稀疏", "适中", "茂密"]), Settings.grass, _on_grass,
				"重新生成地图后生效；电脑卡的话调成稀疏", "content")
			_add_option("全屏", PackedStringArray(["关", "开"]), 1 if Settings.fullscreen else 0, _on_fullscreen, "", "")
			_add_option("游戏提示", PackedStringArray(["关", "开"]), 1 if Settings.tips else 0, _on_tips, "玩的时候偶尔在屏幕下方提示按键和小细节", "")
			_add_action("返回", _back, "", "Esc 也可以返回", "")
			if state == "pause":
				_blur_side = 0.0
			else:
				_blur_side = 1.0
			_blur_target = 1.0
			focus_first = state == "pause"
		"pause":
			_set_title("暂停", "", 52)
			_add_action("继续", resume, "", "", "")
			_add_action("设置", func(): _go("settings"), "", "", "")
			_add_action("回到主菜单", back_to_menu, "", "", "")
			_add_action("退出游戏", _quit, "", "", "")
			_blur_side = 0.0
			_blur_target = 1.0
			focus_first = true
	var i := 0
	for c in _list.get_children():
		c.delay = delay + 0.12 + i * 0.065
		i += 1
	_title_t = -delay
	if focus_first and _list.get_child_count() > 0:
		_list.get_child(0).grab_focus()


func _new_item(label: String, kind: String, tip: String, expr: String) -> Control:
	var it: Control = Item.new()
	it.label = label
	it.kind = kind
	it.tip = tip
	it.reveal = 0.0
	it.set_meta("expr", expr)
	_list.add_child(it)
	return it


func _add_action(label: String, cb: Callable, value_text: String, tip: String, expr: String) -> Control:
	var it := _new_item(label, "action", tip, expr)
	it.value_text = value_text
	it.activated.connect(cb)
	return it


func _add_option(label: String, opts: PackedStringArray, index: int, cb: Callable, tip: String, expr: String) -> Control:
	var it := _new_item(label, "option", tip, expr)
	it.options = opts
	it.index = index
	it.changed.connect(_on_option_changed.bind(cb))
	return it


func _add_slider(label: String, value: float, fmt: Callable, cb: Callable, tip: String) -> Control:
	var it := _new_item(label, "slider", tip, "")
	it.value = clampf(value, 0.0, 1.0)
	it.format = fmt
	it.changed.connect(_on_slider_changed.bind(cb))
	return it


func _on_option_changed(item, cb: Callable) -> void:
	cb.call(item)
	Settings.save_settings()
	Settings.apply()


func _on_slider_changed(item, cb: Callable) -> void:
	cb.call(item.value)
	Settings.apply()


func _on_grass(it) -> void:
	Settings.grass = it.index
	_grass_dirty = true


func _on_tips(it) -> void:
	Settings.tips = it.index == 1


func _on_fullscreen(it) -> void:
	Settings.fullscreen = it.index == 1
	Settings.apply()            # 立刻切换（之前只改了设置值，没有真正去切窗口）
	Settings.save_settings()


func _back() -> void:
	Settings.save_settings()
	if state == "pause":
		_go("pause")
	elif _grass_dirty:
		_leave("reload")
	else:
		_blur_target = 0.0
		_go("main")


func _reroll() -> void:
	Settings.world_seed = randi() % 2000000000
	for c in _list.get_children():
		if c.label == "种子":
			c.value_text = str(Settings.world_seed)
	_reload_t = 0.45


# ───────────────────────── 表情 ─────────────────────────

func _update_expression(dt: float) -> void:
	var want := ""
	if _expr_t > 0.0:
		_expr_t -= dt
		want = "happy"
	elif hero.is_acting():
		want = ""                # 动作自己有表情
	elif state == "menu":
		var f := get_viewport().gui_get_focus_owner()
		if f != null and f.get_parent() == _list:
			want = str(f.get_meta("expr", ""))
		elif _hover_hero:
			want = "curious"
	hero.expression_override = want


# ───────────────────────── 画面层 ─────────────────────────

func _set_hud_alpha(a: float) -> void:
	if _hud == null:
		return
	_hud.visible = a > 0.01
	for c in _hud.get_children():
		if c is CanvasItem:
			(c as CanvasItem).modulate.a = a


func _animate_layers(dt: float) -> void:
	_fade_amt = move_toward(_fade_amt, _fade_target, dt * _fade_speed)
	var f := _fade_amt * _fade_amt * (3.0 - 2.0 * _fade_amt)
	_fade.color = Color(PAPER, f)
	_fade.visible = f > 0.001

	_wash_amt = lerpf(_wash_amt, _wash_target, clampf(dt * 2.5, 0.0, 1.0))
	_vig = lerpf(_vig, _vig_target, clampf(dt * 2.5, 0.0, 1.0))
	_wash_mat.set_shader_parameter("wash", _wash_amt)
	_wash_mat.set_shader_parameter("vignette", _vig)
	var sz := _root.size
	_wash_mat.set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	_wash.visible = _wash_amt > 0.002 or _vig > 0.002

	_blur_amt = move_toward(_blur_amt, _blur_target, dt * 2.8)
	var b := _blur_amt * _blur_amt * (3.0 - 2.0 * _blur_amt)
	_blur_mat.set_shader_parameter("amount", b)
	_blur_mat.set_shader_parameter("side_only", _blur_side)
	_blur.visible = b > 0.002

	_title_alpha = move_toward(_title_alpha, _title_target, dt * (1.4 if _title_target > _title_alpha else 3.5))
	_title_t += dt
	_title.queue_redraw()

	_footer_alpha = move_toward(_footer_alpha, _footer_target, dt * 2.0)
	var fo := get_viewport().gui_get_focus_owner()
	_tip_next = str(fo.tip) if (fo != null and fo.get_parent() == _list) else ""
	if _tip_next == "" and _hover_hero:
		_tip_next = "戳戳它试试"
	if _tip_next != _tip:
		_tip_alpha = move_toward(_tip_alpha, 0.0, dt * 6.0)
		if _tip_alpha <= 0.0:
			_tip = _tip_next
	else:
		_tip_alpha = move_toward(_tip_alpha, 1.0 if _tip != "" else 0.0, dt * 3.0)
	_footer.queue_redraw()

	if absf(_hud_alpha - _hud_target) > 0.001:
		_hud_alpha = move_toward(_hud_alpha, _hud_target, dt * 2.0)
		_set_hud_alpha(_hud_alpha)


func _shadowed(ci: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color) -> void:
	ci.draw_string(font, pos + Vector2(0, 3), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SHADOW, col.a * 0.22))
	ci.draw_string(font, pos + Vector2(0, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SHADOW, col.a * 0.25))
	ci.draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_title() -> void:
	var ga := _title_alpha
	if ga <= 0.002 or _title_text == "":
		return
	if _title_text == "@logo":
		_draw_logo(ga)
		return
	var font: Font = Settings.font_title
	var heading := _title_sub == ""
	var base_y := 322.0 if heading else 236.0
	var x0 := MENU_X + 28.0
	var x := x0
	var tracking := 6.0 if heading else 1.5
	var i := 0
	# 一个字一个字浮上来；出现后随风轻轻起伏
	for ch in _title_text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, _title_size).x
		var k := clampf((_title_t - i * 0.06) / 0.9, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 3.0)
		if ch != " " and e > 0.0:
			var y := base_y + 24.0 * (1.0 - e) + sin(_ui_t * 1.1 - i * 0.55) * 1.5 * e
			_shadowed(_title, font, Vector2(x, y), ch, _title_size, Color(CREAM, e * ga))
		x += w + tracking
		i += 1

	# 金色细线 + 小菱形
	var kl := clampf((_title_t - 0.55) / 0.9, 0.0, 1.0)
	var el := 1.0 - pow(1.0 - kl, 3.0)
	if el > 0.0:
		var ly := base_y + (24.0 if heading else 34.0)
		var c := Vector2(x0 + 4.0, ly)
		var s := maxf(4.0 * el, 0.6)
		_title.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]),
			Color(GOLD, el * ga))
		_title.draw_line(c + Vector2(14.0, 0), c + Vector2(14.0 + (64.0 if heading else 96.0) * el, 0), Color(GOLD, 0.8 * el * ga), 1.4, true)

	if not heading:
		var ks := clampf((_title_t - 0.9) / 1.0, 0.0, 1.0)
		var es := 1.0 - pow(1.0 - ks, 3.0)
		if es > 0.0:
			_shadowed(_title, Settings.font_light, Vector2(x0 + 2.0, base_y + 78.0 + 8.0 * (1.0 - es)), _title_sub, 20,
				Color(CREAM, 0.82 * es * ga))


## 主菜单 logo：弹性地放大出现，之后像被风吹着一样轻轻上下浮、微微摆
func _draw_logo(ga: float) -> void:
	var k := clampf(_title_t / 0.9, 0.0, 1.0)
	if k <= 0.0:
		return
	var c1 := 1.70158
	var back := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)    # ease-out-back
	var a := clampf(k * 1.6, 0.0, 1.0) * ga
	var sz := Vector2(LOGO_W, LOGO_W * LOGO.get_height() / LOGO.get_width())
	var center := Vector2(MENU_X + 8.0 + sz.x * 0.5, 112.0 + sz.y * 0.5)
	center.y += sin(_ui_t * 1.15) * 3.0 * k + 14.0 * (1.0 - k)
	var s := lerpf(0.86, 1.0, back)
	var rot := sin(_ui_t * 0.7) * 0.008 * k
	var rect := Rect2(-sz * 0.5, sz)
	_title.draw_set_transform(center + Vector2(0, 9.0), rot, Vector2(s, s))
	_title.draw_texture_rect(LOGO, rect, false, Color(SHADOW, 0.26 * a))
	_title.draw_set_transform(center, rot, Vector2(s, s))
	_title.draw_texture_rect(LOGO, rect, false, Color(1, 1, 1, a))
	_title.draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_footer() -> void:
	var a := _footer_alpha
	if a <= 0.002:
		return
	var sz := _footer.size
	var fl: Font = Settings.font_light
	var fu: Font = Settings.font_ui
	var x := MENU_X + 28.0
	var y := sz.y - 46.0

	# 说明文字（选中某一项时）
	if _tip_alpha > 0.0 and _tip != "":
		var ta := a * _tip_alpha
		_footer.draw_line(Vector2(x, y - 51.0), Vector2(x + 18.0, y - 51.0), Color(GOLD, 0.8 * ta), 1.4, true)
		_shadowed(_footer, fl, Vector2(x + 30.0, y - 45.0), _tip, 16, Color(CREAM, 0.78 * ta))

	# 操作提示：键帽 + 说明
	if state == "menu" or state == "intro":
		var keys := [["WASD", "移动"], ["Shift", "奔跑"], ["空格", "跳跃"], ["E", "摸摸小动物"], ["1-4", "物品"], ["B", "背包"], ["V", "视角"], ["M", "地图"], ["Esc", "暂停"]]
		for pair in keys:
			var kw := fu.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var r := Rect2(x, y - 15.0, kw + 14.0, 21.0)
			_key_box.border_color = Color(CREAM, 0.38 * a)
			_key_box.draw(_footer.get_canvas_item(), r)
			_footer.draw_string(fu, Vector2(x + 7.0, y), pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(CREAM, 0.8 * a))
			x += r.size.x + 7.0
			_footer.draw_string(fl, Vector2(x, y), pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(CREAM, 0.55 * a))
			x += fl.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 20.0

	# 右下角：地图 / 种子 / 版本
	var info := "无限草原  ·  种子 %d" % Settings.world_seed
	info += "  ·  " + VERSION + "  ·  by XiaoMao"
	var iw := fl.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_footer.draw_string(fl, Vector2(sz.x - 56.0 - iw, y), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(CREAM, 0.5 * a))


# ───────────────────────── 戳一戳角色 ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if state != "menu" or _leaving != "":
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp := (event as InputEventMouseButton).position
		if _hit_hero(mp):
			_poke(mp)
			get_viewport().set_input_as_handled()


## 鼠标是不是点在角色身上：把角色当成一根竖着的胶囊投到屏幕上
func _hit_hero(mp: Vector2) -> bool:
	if cam == null or not cam.current:
		return false
	var base: Vector3 = hero.global_position
	var a := base + Vector3(0, 0.3, 0)
	var b := base + Vector3(0, 1.3, 0)
	if cam.is_position_behind(a) or cam.is_position_behind(b):
		return false
	var sa := cam.unproject_position(a)
	var sb := cam.unproject_position(b)
	var r := sb.distance_to(cam.unproject_position(b + cam.global_transform.basis.x * 0.36))
	var ab := sb - sa
	var t := clampf((mp - sa).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
	return mp.distance_to(sa + ab * t) < r


func _poke(mp: Vector2) -> void:
	if _poke_cd > 0.0 or hero.act == "dizzy":
		return
	_poke_cd = 0.28
	var now := _ui_t
	_pokes.append(now)
	while _pokes.size() > 0 and now - _pokes[0] > 3.0:
		_pokes.pop_front()
	# 戳的位置：先给一个立刻的反馈（身体一缩 + 一小撮闪光）
	var dist := cam.global_position.distance_to(hero.global_position + Vector3(0, 0.8, 0))
	var hit := cam.project_position(mp, dist - 0.35)
	Fx.sparkles(world, hit, 6, 0.06, 0.7)
	hero._sq_v -= 3.5
	var act := ""
	if _pokes.size() >= 5:
		act = "dizzy"
		_pokes.clear()
	else:
		var pool: Array = POKE_ACTS.duplicate()
		pool.erase(_last_poke)
		act = pool[randi() % pool.size()]
	_last_poke = act
	hero.play_act(act)


func _on_hero_beat(act: String, beat: String) -> void:
	if act == "pet" or act == "feed" or beat == "end":
		return
	var head: Vector3 = hero.global_position + Vector3(0, 1.3, 0)
	match act:
		"giggle":
			Fx.hearts(world, head, 4, 0.9)
		"boing":
			Fx.sparkles(world, head + Vector3(0, 0.1, 0), 14, 0.35, 1.1)
		"spin":
			Fx.sparkles(world, hero.global_position + Vector3(0, 0.5, 0), 16, 0.5, 1.0)
			Fx.hearts(world, head, 2, 0.8)
		"wave":
			Fx.heart_pop(world, head + Vector3(0, 0.3, 0), 0.3)
		"dizzy":
			Fx.dizzy_stars(hero, 1.62, float(hero.ACTS["dizzy"]))
