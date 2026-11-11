extends CanvasLayer
## 物品栏 + 背包。
## 快捷栏：屏幕底部中间 4 个浮着的图标（不画格子），1-4 拿起 / 收起；选中的图标抬起、变亮，数字变金色，上方浮出物品名。
##         不用的时候 2.8 秒后往下滑、淡出；按 1-4、B，或者手里的东西变了（比如喂掉了）再滑上来。
## 背包（B）：和设置页一样的样式——左边一块毛玻璃，右边的世界保持清楚；标题 + 金色小菱形细线，
##         物品是一行一行的（图标 + 名字 + 右边的状态），悬停时往右滑、变暖金色、下面画细线；底部是说明和按键提示。
##         点一行 = 拿起 / 收起；拖到快捷栏 = 放进去；指着它按 1-4 = 放进那一格；快捷栏之间拖动互换；从快捷栏拖回左边 = 移出。
## 图标：运行时把 props 里的 3D 模型拍成图标（和游戏里同一套卡通着色）；蝴蝶和鱼是代码画的。
## 快捷栏的摆放存在 user://inventory.cfg。

const Slot := preload("res://scripts/inv_slot.gd")
const Row := preload("res://scripts/bag_row.gd")
const Fx := preload("res://scripts/fx.gd")
const CREAM := Color(0.984, 0.957, 0.902)
const GOLD := Color(0.925, 0.780, 0.500)
const SHADOW := Color(0.02, 0.05, 0.06)
const SAVE_PATH := "user://inventory.cfg"
const SHOW_TIME := 2.8
const MENU_X := 104.0          # 和主菜单 / 设置页对齐

const ITEMS := {
	"carrot": {"name": "胡萝卜", "desc": "兔子最爱吃。拿在手里慢慢走过去，兔子就不怕你了", "tool": true},
	"berry": {"name": "浆果", "desc": "小鹿喜欢的甜浆果。拿着它，小鹿会走过来", "tool": true},
	"net": {"name": "捕虫网", "desc": "左键挥网，可以抓花丛里的蝴蝶", "tool": true},
	"rod": {"name": "钓鱼竿", "desc": "走到水边，左键甩竿；咬钩了再点一下收竿", "tool": true},
	"bug": {"name": "蝴蝶", "desc": "用捕虫网抓到的蝴蝶", "tool": false},
	"fish": {"name": "鱼", "desc": "在池塘里钓到的鱼", "tool": false},
}
const TOOLS := ["carrot", "berry", "net", "rod"]
const COLLECT := ["bug", "fish"]

var world
var player
var hero
var slots: Array = ["carrot", "berry", "net", "rod"]
var bag_open := false

var _icons := {}
var _blur: ColorRect
var _blur_mat: ShaderMaterial
var _wash: ColorRect
var _wash_mat: ShaderMaterial
var _ui: Control
var _hot: Control
var _hot_slots: Array = []
var _rows: Array = []
var _show_t := 0.0
var _hot_a := 0.0
var _bag_a := 0.0
var _bag_t := 0.0
var _last_held := ""
var _name_t := 0.0
var _name := ""
var _hover_item := ""
var _hover_node = null
var _tip := ""
var _tip_a := 0.0
var _key_sb: StyleBoxFlat


func setup(w) -> void:
	world = w
	player = w.player
	hero = player.hero
	layer = 25
	add_to_group("inventory")
	_load()

	# 背包打开时的背景：左边毛玻璃（和设置页同一个着色器）+ 左侧压暗和暗角（和主菜单同一个着色器）
	_blur = ColorRect.new()
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur_mat = ShaderMaterial.new()
	_blur_mat.shader = load("res://shaders/ui_blur.gdshader")
	_blur_mat.set_shader_parameter("side_only", 1.0)
	_blur.material = _blur_mat
	_blur.visible = false
	add_child(_blur)
	_wash = ColorRect.new()
	_wash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wash_mat = ShaderMaterial.new()
	_wash_mat.shader = load("res://shaders/ui_wash.gdshader")
	_wash_mat.set_shader_parameter("grain", 0.0)
	_wash.material = _wash_mat
	_wash.visible = false
	add_child(_wash)

	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)

	for it in TOOLS + COLLECT:
		var r: Control = Row.new()
		r.inv = self
		r.item = it
		r.reveal = 0.0
		r.target = 0.0
		_ui.add_child(r)
		_rows.append(r)

	_hot = Control.new()
	_hot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hot.draw.connect(_draw_hot_back)
	_ui.add_child(_hot)
	for i in 4:
		var sl: Control = Slot.new()
		sl.inv = self
		sl.index = i
		_hot.add_child(sl)
		_hot_slots.append(sl)
	_refresh_hot()

	_key_sb = StyleBoxFlat.new()
	_key_sb.draw_center = false
	_key_sb.set_border_width_all(1)
	_key_sb.set_corner_radius_all(4)
	_key_sb.anti_aliasing = true
	_bake_icons()


# ───────────────────────── 数据 ─────────────────────────

func is_tool(it: String) -> bool:
	return ITEMS.has(it) and bool(ITEMS[it].tool)


func slot_of(it: String) -> int:
	return slots.find(it)


## 小动物提示里用：这个东西在第几格（没放进快捷栏就提示打开背包）
func key_for(it: String) -> String:
	var k := slot_of(it)
	return str(k + 1) if k >= 0 else "B"


func icon(it: String) -> Texture2D:
	return _icons.get(it)


func drag_preview(it: String) -> Control:
	var holder := Control.new()
	var tr := TextureRect.new()
	tr.texture = icon(it)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.size = Vector2(54, 54)
	tr.position = Vector2(-27, -27)
	tr.modulate = Color(1, 1, 1, 0.9)
	holder.add_child(tr)
	return holder


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		var sv = cf.get_value("hotbar", "slots", slots)
		if sv is Array and sv.size() == 4:
			slots = sv


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("hotbar", "slots", slots)
	cf.save(SAVE_PATH)


func _refresh_hot() -> void:
	for i in 4:
		_hot_slots[i].set_item(slots[i])


func assign(it: String, idx: int) -> void:
	if idx < 0 or idx > 3:
		return
	var old := slot_of(it)
	if old >= 0:
		slots[old] = slots[idx]       # 已经在别的格子：互换
	slots[idx] = it
	_refresh_hot()
	_save()
	show_hotbar()


func on_drop(target: Control, data: Dictionary) -> void:
	var it: String = data.item
	if target.get("role") == "hot":
		if data.from == "hot":
			var a: int = data.index
			var b: int = target.index
			var tmp: String = slots[a]
			slots[a] = slots[b]
			slots[b] = tmp
			_refresh_hot()
			_save()
		else:
			assign(it, target.index)
	elif data.from == "hot":
		# 从快捷栏拖回左边的列表：移出快捷栏
		if hero.held == slots[data.index]:
			hero.hold("")
		slots[data.index] = ""
		_refresh_hot()
		_save()


func on_hover(n: Control, h: bool) -> void:
	if h:
		_hover_node = n
		_hover_item = n.item
	elif _hover_node == n:
		_hover_node = null
		_hover_item = ""


## 拿起 / 收起第 idx 格的东西
func press_slot(idx: int) -> void:
	var it: String = slots[idx]
	if it == "" or hero.held == it:
		hero.hold("")
	else:
		hero.hold(it)
	show_hotbar()


func equip(it: String) -> void:
	hero.hold("" if hero.held == it else it)
	show_hotbar()


func show_hotbar(t := SHOW_TIME) -> void:
	_show_t = maxf(_show_t, t)


# ───────────────────────── 背包开关 ─────────────────────────

func _playing() -> bool:
	return player.active and not get_tree().paused


func open_bag() -> void:
	if bag_open:
		return
	var bm := get_tree().get_first_node_in_group("bigmap")
	if bm and bm.is_open():
		bm.close()
	bag_open = true
	_bag_t = 0.0
	player.active = false
	player.velocity = Vector3(0, player.velocity.y, 0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for i in _rows.size():
		_rows[i].target = 1.0
		_rows[i].delay = 0.08 + i * 0.05


func close_bag() -> void:
	if not bag_open:
		return
	bag_open = false
	player.active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for r in _rows:
		r.target = 0.0
		r.delay = 0.0
	_hover_item = ""
	_hover_node = null
	show_hotbar(1.2)


func is_open() -> bool:
	return bag_open


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).physical_keycode
	if key == KEY_B:
		if bag_open:
			close_bag()
		elif _playing():
			open_bag()
		else:
			return
		get_viewport().set_input_as_handled()
	elif key >= KEY_1 and key <= KEY_4:
		var idx := key - KEY_1
		if bag_open:
			if is_tool(_hover_item):
				assign(_hover_item, idx)       # 指着左边的工具按数字：放进那一格
			else:
				press_slot(idx)
		elif _playing():
			press_slot(idx)
		else:
			return
		get_viewport().set_input_as_handled()


# ───────────────────────── 每帧 ─────────────────────────

func _menu_state() -> String:
	var m = get_parent().get("menu") if get_parent() else null
	return str(m.state) if m else "game"


func _process(delta: float) -> void:
	if player == null:
		return
	if bag_open and (get_tree().paused or _menu_state() != "game"):
		bag_open = false
		for r in _rows:
			r.target = 0.0
	_show_t -= delta
	_bag_t += delta
	if hero.held != _last_held:
		_last_held = hero.held
		_name = ITEMS[hero.held].name if ITEMS.has(hero.held) else ""
		_name_t = 1.8 if _name != "" else 0.0
		show_hotbar(2.0)
	_name_t -= delta
	var in_game := _menu_state() == "game" and not get_tree().paused
	var want := 1.0 if in_game and (bag_open or _show_t > 0.0) else 0.0
	_hot_a = move_toward(_hot_a, want, delta * (5.0 if want > _hot_a else 2.2))
	_bag_a = move_toward(_bag_a, 1.0 if bag_open else 0.0, delta * (3.2 if bag_open else 4.5))

	var vp := _ui.size
	var e := _hot_a * _hot_a * (3.0 - 2.0 * _hot_a)
	var total := Slot.W * 4.0 + 10.0 * 3.0
	_hot.size = Vector2(total, Slot.H)
	_hot.position = Vector2((vp.x - total) * 0.5, vp.y - Slot.H - 26.0 + 26.0 * (1.0 - e))
	_hot.modulate.a = e
	_hot.visible = e > 0.01
	for i in 4:
		var sl: Control = _hot_slots[i]
		sl.position = Vector2(i * (Slot.W + 10.0), 0)
		sl.selected = slots[i] != "" and hero.held == slots[i]
		sl.mouse_filter = Control.MOUSE_FILTER_STOP if bag_open else Control.MOUSE_FILTER_IGNORE

	# 背包：背景、列表
	var be := _bag_a * _bag_a * (3.0 - 2.0 * _bag_a)
	_blur.visible = be > 0.002
	_wash.visible = be > 0.002
	_blur_mat.set_shader_parameter("amount", be)
	_wash_mat.set_shader_parameter("wash", be)
	_wash_mat.set_shader_parameter("vignette", be * 0.7)
	_wash_mat.set_shader_parameter("aspect", vp.x / maxf(vp.y, 1.0))
	var y := 252.0
	for i in _rows.size():
		var r: Control = _rows[i]
		if i == TOOLS.size():
			y += 52.0        # 收集那一组前面空一点，放小标题
		r.position = Vector2(MENU_X, y)
		y += 54.0
		if r.item == "bug":
			r.count = int(hero.caught_bugs)
		elif r.item == "fish":
			r.count = int(hero.caught_fish)
	# 底部说明：指着什么就说什么，换的时候淡出淡入
	var want_tip: String = ITEMS[_hover_item].desc if ITEMS.has(_hover_item) else ""
	if want_tip != _tip:
		_tip_a = move_toward(_tip_a, 0.0, delta * 7.0)
		if _tip_a <= 0.0:
			_tip = want_tip
	else:
		_tip_a = move_toward(_tip_a, 1.0 if _tip != "" else 0.0, delta * 3.5)
	_ui.queue_redraw()
	_hot.queue_redraw()


# ───────────────────────── 画 ─────────────────────────

func _txt(ci: CanvasItem, f: Font, pos: Vector2, s: String, sz: int, col: Color) -> void:
	ci.draw_string(f, pos + Vector2(0, 3), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(SHADOW, col.a * 0.22))
	ci.draw_string(f, pos + Vector2(0, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(SHADOW, col.a * 0.25))
	ci.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _diamond(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	if s < 0.6:
		return
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]), col)


## 快捷栏后面一层很淡、很宽的暗光，让图标在亮草地上也看得清（不是卡片）
func _draw_hot_back() -> void:
	var dot := Fx.dot_texture()
	var sz := _hot.size
	_hot.draw_texture_rect(dot, Rect2(Vector2(-70, -10), Vector2(sz.x + 140, sz.y + 24)), false, Color(SHADOW, 0.30))


func _draw_ui() -> void:
	# 快捷栏上方：刚拿起的东西的名字（白字，慢慢淡掉）
	if _name_t > 0.0 and _name != "" and _hot.visible and not bag_open:
		var f: Font = Settings.font_ui
		var k := clampf(_name_t / 0.6, 0.0, 1.0)
		var a := k * _hot.modulate.a
		var w := f.get_string_size(_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		_txt(_ui, f, Vector2(_ui.size.x * 0.5 - w * 0.5, _hot.position.y - 12.0 - (1.0 - k) * 8.0), _name, 17, Color(1, 1, 1, 0.95 * a))

	if _bag_a <= 0.002:
		return
	var be := _bag_a * _bag_a * (3.0 - 2.0 * _bag_a)
	var ft: Font = Settings.font_title
	var fu: Font = Settings.font_ui
	var fl: Font = Settings.font_light
	var x0 := MENU_X + 28.0
	var sz := _ui.size

	# 标题：一个字一个字浮上来（和设置页一样），下面金色小菱形 + 细线
	var x := x0
	var i := 0
	for ch in "背包":
		var k := clampf((_bag_t - i * 0.06) / 0.7, 0.0, 1.0) if bag_open else 1.0
		var e := 1.0 - pow(1.0 - k, 3.0)
		_txt(_ui, ft, Vector2(x, 176.0 + 18.0 * (1.0 - e)), ch, 52, Color(CREAM, e * be))
		x += ft.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, 52).x + 6.0
		i += 1
	var kl := clampf((_bag_t - 0.35) / 0.8, 0.0, 1.0) if bag_open else 1.0
	var el := (1.0 - pow(1.0 - kl, 3.0)) * be
	var lc := Vector2(x0 + 4.0, 200.0)
	_diamond(_ui, lc, 4.0 * el, Color(GOLD, el))
	_ui.draw_line(lc + Vector2(14, 0), lc + Vector2(14 + 64 * el, 0), Color(GOLD, 0.8 * el), 1.4, true)

	# 小标题
	_txt(_ui, fu, Vector2(x0, 240.0), "工具与食物", 13, Color(GOLD, 0.9 * be))
	_txt(_ui, fu, Vector2(x0, 252.0 + 4 * 54.0 + 40.0), "收集", 13, Color(GOLD, 0.9 * be))

	# 说明（和主菜单底部的说明同一种样式）
	var ty := sz.y - 46.0
	if _tip_a > 0.0 and _tip != "":
		var ta := be * _tip_a
		_ui.draw_line(Vector2(x0, ty - 51.0), Vector2(x0 + 18.0, ty - 51.0), Color(GOLD, 0.8 * ta), 1.4, true)
		_txt(_ui, fl, Vector2(x0 + 30.0, ty - 45.0), _tip, 16, Color(CREAM, 0.8 * ta))

	# 按键提示
	var hx := x0
	for pair in [["B", "关闭"], ["1-4", "放进快捷栏"], ["拖动", "到下面的快捷栏"], ["点击", "拿起 / 收起"]]:
		var kw := fu.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var r := Rect2(hx, ty - 15.0, kw + 14.0, 21.0)
		_key_sb.border_color = Color(CREAM, 0.38 * be)
		_ui.draw_style_box(_key_sb, r)
		_ui.draw_string(fu, Vector2(hx + 7.0, ty), pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(CREAM, 0.8 * be))
		hx += r.size.x + 7.0
		_ui.draw_string(fl, Vector2(hx, ty), pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(CREAM, 0.55 * be))
		hx += fl.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 20.0


# ───────────────────────── 图标 ─────────────────────────

## 把 props 里的模型拍成图标：单独的小世界，正面略俯视，柔和的光，透明背景
func _bake_icons() -> void:
	_icons["bug"] = _draw_butterfly()
	_icons["fish"] = _draw_fish()
	for it in TOOLS:
		var path := "res://props/%s.glb" % it
		if not ResourceLoader.exists(path):
			continue
		var vp := SubViewport.new()
		vp.size = Vector2i(160, 160)
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.msaa_3d = Viewport.MSAA_4X
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.85, 0.88, 0.95)
		env.ambient_light_energy = 0.85
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		var we := WorldEnvironment.new()
		we.environment = env
		vp.add_child(we)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-45, -35, 0)
		sun.light_energy = 0.9
		vp.add_child(sun)
		var node := (load(path) as PackedScene).instantiate() as Node3D
		_toonify(node)
		vp.add_child(node)
		# 按模型大小摆镜头
		var box := AABB()
		var first := true
		for mi in node.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			var b := m.global_transform * m.get_aabb() if m.is_inside_tree() else m.transform * m.get_aabb()
			box = b if first else box.merge(b)
			first = false
		var cam := Camera3D.new()
		cam.fov = 26.0
		vp.add_child(cam)
		var c := box.get_center()
		var r := maxf(box.size.length() * 0.5, 0.05)
		var dist := r / sin(deg_to_rad(cam.fov * 0.5)) * 0.98
		cam.position = c + Vector3(0.0, 0.42, 1.0).normalized() * dist
		cam.look_at(c, Vector3.UP)
		cam.near = maxf(dist - r * 2.0, 0.01)
		cam.far = dist + r * 2.0
		cam.current = true
		_finish_icon.call_deferred(it, vp)


func _finish_icon(it: String, vp: SubViewport) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img and not img.is_empty() and img.get_used_rect().size.x > 0:
		img.generate_mipmaps()
		_icons[it] = ImageTexture.create_from_image(img)
	else:
		_icons[it] = _fallback_icon(it)
	vp.queue_free()


func _toonify(node: Node) -> void:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(i)
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/toon_tex.gdshader")
			if src is BaseMaterial3D and (src as BaseMaterial3D).albedo_texture:
				sm.set_shader_parameter("albedo_tex", (src as BaseMaterial3D).albedo_texture)
			var o := ShaderMaterial.new()
			o.shader = load("res://shaders/outline.gdshader")
			o.set_shader_parameter("width_px", 2.0)
			sm.next_pass = o
			m.set_surface_override_material(i, sm)


## 拍不出来的时候（比如没有显卡的环境）用一个简单的彩色圆当图标
func _fallback_icon(it: String) -> ImageTexture:
	var cols := {"carrot": Color(1.0, 0.55, 0.2), "berry": Color(0.62, 0.25, 0.62), "net": Color(0.9, 0.85, 0.7), "rod": Color(0.7, 0.5, 0.3)}
	var col: Color = cols.get(it, Color(0.8, 0.8, 0.8))
	return _sdf_icon(func(p: Vector2) -> float: return p.length() - 0.55, col)


func _sdf_icon(sd: Callable, col: Color) -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var px := 2.0 / n
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			var d: float = sd.call(p)
			var fill := 1.0 - smoothstep(-px, px, d)
			var line := 1.0 - smoothstep(-px, px, d - 0.06)
			var c := Color(0.18, 0.12, 0.1).lerp(col.lightened(0.15 * (1.0 - p.y)), fill)
			img.set_pixel(x, y, Color(c, line))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _draw_butterfly() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var px := 2.0 / n
	var wing := Color(1.0, 0.72, 0.35)
	var wing2 := Color(1.0, 0.55, 0.62)
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			var q := Vector2(absf(p.x), p.y)
			var up := (q - Vector2(0.38, -0.25)).length() - 0.36
			var lo := (q - Vector2(0.3, 0.32)).length() - 0.25
			var body := Vector2(p.x / 0.09, p.y / 0.55).length() - 1.0
			var wings := minf(up, lo)
			var d := minf(wings, body * 0.09)
			var fill := 1.0 - smoothstep(-px, px, d)
			var line := 1.0 - smoothstep(-px, px, d - 0.06)
			var c := Color(0.2, 0.13, 0.1)
			if body * 0.09 < wings:
				c = c.lerp(Color(0.32, 0.22, 0.18), fill)
			else:
				var wc := wing if up < lo else wing2
				var spot := 1.0 - smoothstep(0.08, 0.1, (q - Vector2(0.45, -0.32)).length())
				c = c.lerp(wc.lerp(Color(1, 0.97, 0.9), spot * 0.85), fill)
			img.set_pixel(x, y, Color(c, line))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _draw_fish() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var px := 2.0 / n
	var top := Color(0.45, 0.68, 0.85)
	var belly := Color(0.92, 0.95, 0.9)
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n * 2.0 - 1.0, (y + 0.5) / n * 2.0 - 1.0)
			var b := Vector2((p.x + 0.12) / 0.62, p.y / 0.38).length() - 1.0
			var t := p - Vector2(0.62, 0.0)
			var tail := maxf(absf(t.y) - t.x * 1.1 - 0.02, t.x - 0.3)
			var d := minf(b * 0.38, tail)
			var fill := 1.0 - smoothstep(-px, px, d)
			var line := 1.0 - smoothstep(-px, px, d - 0.06)
			var c := Color(0.12, 0.17, 0.22).lerp(top.lerp(belly, smoothstep(-0.05, 0.25, p.y)), fill)
			var eye := 1.0 - smoothstep(0.06, 0.075, (p - Vector2(-0.45, -0.06)).length())
			c = c.lerp(Color(0.1, 0.1, 0.12), eye)
			img.set_pixel(x, y, Color(c, line))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
