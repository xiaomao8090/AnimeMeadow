extends Control
## 地图（小地图 + 按 M 打开的大地图）。
## 画面：一台正上方的正交相机实时俯拍真实的世界，盖一层“纸质云雾”的探索迷雾——走过的地方周围才会亮，
## 已探索和没去过的交界处有一圈淡淡的金边，像手绘地图。
##   小地图：右上角的圆形表盘，跟着视角转（你面朝的方向永远朝上），N 标记沿着外圈走；下面是时间。
##   大地图：毛玻璃背景 + 奶油色边框的圆角卡片，北向固定，滚轮缩放；有指北针、比例尺、坐标和已探索面积。
##   成为朋友的小动物在地图上是小爱心。
## 迷雾系统沿用原来的：按 256 米一块存 L8 图（每格 4 米），走过的地方半径 40 米点亮，边缘渐变。

const Fx := preload("res://scripts/fx.gd")

const SMALL_EDGE := 196.0          # 小地图直径（像素）
const SMALL_SPAN := 220.0          # 小地图覆盖多少米
const BIG_SPAN := 700.0            # 大地图默认覆盖多少米（滚轮可以缩放）
const BIG_SPAN_MIN := 260.0
const BIG_SPAN_MAX := 1600.0
const REVEAL_R := 40.0             # 走过时照亮的半径（米）
const TILE := 256.0                # 迷雾按 256 米一块存
const TILE_PX := 64                # 每块 64 像素（4 米一格）
const FOG_RES := 112               # 合成给着色器的迷雾贴图分辨率

const CREAM := Color(0.984, 0.957, 0.902)
const GOLD := Color(0.925, 0.780, 0.500)
const INK := Color(0.07, 0.10, 0.11)
const SHADOW := Color(0.02, 0.05, 0.06)

var world
var expanded := false
var map_span := SMALL_SPAN
var map_center := Vector2.ZERO

var _vp: SubViewport
var _cam: Camera3D
var _env: Environment
var _view: TextureRect
var _overlay: Control
var _dim: ColorRect
var _dim_mat: ShaderMaterial
var _mat: ShaderMaterial
var _fog_img: Image
var _fog_tex: ImageTexture
var _tiles := {}                   # Vector2i -> Image（L8，255 = 去过）
var _explored_px := 0              # 已探索的格子数（每格 16 平方米）
var _last_reveal := Vector2(INF, INF)
var _refresh := 0.0
var _big_span := BIG_SPAN
var _span_target := BIG_SPAN
var _vis := 1.0                    # 切换大小地图时的淡出淡入
var _want_expanded := false
var _heading := 0.0
var _frame: StyleBoxFlat
var _pill: StyleBoxFlat
var _key: StyleBoxFlat


func setup(w) -> void:
	world = w
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("bigmap")
	if world.get("hud_label") != null:
		world.hud_label.visible = false      # 时间改画在小地图下面

	_vp = SubViewport.new()
	_vp.size = Vector2i(384, 384)
	_vp.own_world_3d = false
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.keep_aspect = Camera3D.KEEP_HEIGHT
	_cam.rotation_degrees = Vector3(-90, 0, 0)     # 正下方；贴图上方 = 北（-Z）
	_cam.near = 1.0
	_cam.far = 900.0
	_vp.add_child(_cam)
	_cam.current = true
	# 地图相机用自己的环境：没有雾，亮一点，晚上也看得清
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.30, 0.52, 0.58)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.85, 0.88, 0.9)
	_env.ambient_light_energy = 0.9
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_cam.environment = _env

	_fog_img = Image.create(FOG_RES, FOG_RES, false, Image.FORMAT_L8)
	_fog_tex = ImageTexture.create_from_image(_fog_img)

	_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = MAP_SHADER
	_mat.shader = sh
	_mat.set_shader_parameter("fog", _fog_tex)

	# 大地图的背景：整屏毛玻璃（放在 HUD 层里、地图下面）
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = load("res://shaders/ui_blur.gdshader")
	_dim.material = _dim_mat
	_dim.visible = false
	var layer := get_parent()
	if layer:
		layer.add_child.call_deferred(_dim)
		layer.move_child.call_deferred(_dim, 0)

	_view = TextureRect.new()
	_view.texture = _vp.get_texture()
	_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_view.stretch_mode = TextureRect.STRETCH_SCALE
	_view.material = _mat
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)

	_frame = StyleBoxFlat.new()
	_frame.bg_color = CREAM
	_frame.set_corner_radius_all(34)
	_frame.shadow_color = Color(SHADOW, 0.45)
	_frame.shadow_size = 26
	_frame.shadow_offset = Vector2(0, 8)
	_frame.anti_aliasing = true
	_pill = StyleBoxFlat.new()
	_pill.bg_color = Color(INK, 0.42)
	_pill.set_corner_radius_all(12)
	_pill.anti_aliasing = true
	_key = StyleBoxFlat.new()
	_key.draw_center = false
	_key.set_border_width_all(1)
	_key.set_corner_radius_all(4)
	_key.anti_aliasing = true


const MAP_SHADER := """shader_type canvas_item;
uniform sampler2D fog : filter_linear, repeat_disable;
uniform float rot = 0.0;          // 小地图跟着视角转
uniform vec2 shift = vec2(0.0);   // 两次俯拍之间玩家走的距离（贴图 UV），让地图平滑滚动
uniform float shape = 0.0;        // 0 = 圆形，1 = 圆角方形
uniform float corner = 0.035;
uniform vec3 paper_a : source_color = vec3(0.93, 0.89, 0.80);
uniform vec3 paper_b : source_color = vec3(0.80, 0.75, 0.64);
uniform vec3 rim_col : source_color = vec3(0.86, 0.66, 0.34);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = UV - 0.5;
	float c = cos(rot);
	float s = sin(rot);
	vec2 q = vec2(c * p.x - s * p.y, s * p.x + c * p.y);
	vec2 uv = q + 0.5 + shift;

	// 实景：稍微提亮、暖一点、少一点饱和度，像印出来的地图
	vec3 m = texture(TEXTURE, uv).rgb;
	float l = dot(m, vec3(0.3, 0.59, 0.11));
	m = mix(vec3(l), m, 0.82) * vec3(1.04, 1.0, 0.92) + 0.035;

	// 迷雾：纸色云絮 + 很淡的斜线纹；边缘柔和、带一点云的形状
	float n = vnoise(uv * 13.0 + TIME * 0.025) * 0.6 + vnoise(uv * 41.0) * 0.4;
	float seen = texture(fog, uv).r;
	float vis = smoothstep(0.3, 0.7, seen + (n - 0.5) * 0.45 * (1.0 - seen));
	vec3 paper = mix(paper_b, paper_a, vnoise(uv * 7.0) * 0.55 + n * 0.45);
	float hatch = 1.0 - smoothstep(0.0, 0.18, abs(fract((uv.x + uv.y) * 70.0) - 0.5));
	paper *= 1.0 - hatch * 0.035;
	vec3 col = mix(paper, m, vis);
	// 交界处的金边
	float rim = 1.0 - abs(vis - 0.5) * 2.0;
	col = mix(col, rim_col, smoothstep(0.55, 1.0, rim) * 0.5);

	float a = 1.0;
	if (shape < 0.5) {
		float d = length(p) * 2.0;
		float fw = fwidth(d) * 1.5;
		a = 1.0 - smoothstep(1.0 - fw, 1.0, d);
		col *= 1.0 - smoothstep(0.72, 1.0, d) * 0.16;     // 圆边压暗一点，有深度
	} else {
		vec2 b = vec2(0.5 - corner);
		vec2 dd = abs(p) - b;
		float sd = length(max(dd, 0.0)) + min(max(dd.x, dd.y), 0.0) - corner;
		float fw = fwidth(sd) * 1.5;
		a = 1.0 - smoothstep(-fw, 0.0, sd);
		col *= 1.0 - smoothstep(-0.06, 0.0, sd) * 0.12;
	}
	COLOR = vec4(col, a);
}
"""


# ───────────────────────── 输入 ─────────────────────────

func _can_use() -> bool:
	return world != null and is_instance_valid(world.player) and world.player.get("active") != false and not get_tree().paused


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_M and _can_use():
		toggle()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# 大地图打开时滚轮用来缩放，不传给镜头
	if expanded and event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_span_target = clampf(_span_target * 0.85, BIG_SPAN_MIN, BIG_SPAN_MAX)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_span_target = clampf(_span_target / 0.85, BIG_SPAN_MIN, BIG_SPAN_MAX)
			get_viewport().set_input_as_handled()


func toggle() -> void:
	_want_expanded = not _want_expanded


## main_menu.gd：大地图开着时按 Esc 先收起地图
func close() -> void:
	_want_expanded = false


func is_open() -> bool:
	return _want_expanded or expanded


# ───────────────────────── 每帧 ─────────────────────────

func _process(delta: float) -> void:
	if world == null or not is_instance_valid(world.player):
		return
	if not _can_use() and _want_expanded and world.player.get("active") == false:
		_want_expanded = false          # 回到主菜单时收起
	# 切换：先淡出，换模式，再淡入（带一点放大）
	var target := 0.0 if _want_expanded != expanded else 1.0
	_vis = move_toward(_vis, target, delta * (7.0 if target < _vis else 4.5))
	if _vis <= 0.0 and _want_expanded != expanded:
		expanded = _want_expanded
		_vp.size = Vector2i(768, 768) if expanded else Vector2i(384, 384)
		_refresh = 0.0
	var e := _vis * _vis * (3.0 - 2.0 * _vis)
	modulate.a = e

	var vp := get_viewport_rect().size
	var edge := SMALL_EDGE
	if expanded:
		edge = minf(minf(vp.y - 230.0, vp.x - 320.0), 780.0)
		position = Vector2((vp.x - edge) * 0.5, (vp.y - edge) * 0.5 + 18.0)
	else:
		position = Vector2(vp.x - edge - 44.0, 40.0)
	size = Vector2(edge, edge)
	pivot_offset = size * 0.5
	scale = Vector2.ONE * lerpf(0.94, 1.0, e)
	var inset := 8.0 if expanded else 0.0
	_view.position = Vector2.ONE * inset
	_view.size = Vector2.ONE * (edge - inset * 2.0)
	_overlay.size = size

	if _dim and _dim.is_inside_tree():
		var da := e if expanded else 0.0
		_dim.visible = da > 0.01
		_dim_mat.set_shader_parameter("amount", da)
		_dim_mat.set_shader_parameter("side_only", 0.0)

	_big_span = lerpf(_big_span, _span_target, clampf(delta * 10.0, 0.0, 1.0))
	map_span = _big_span if expanded else SMALL_SPAN

	var p: Vector3 = world.player.global_position
	var p2 := Vector2(p.x, p.z)
	if p2.distance_to(_last_reveal) > 3.0:
		_reveal(p2)
		_last_reveal = p2
	var fwd: Vector3 = -world.player.global_basis.z
	_heading = atan2(fwd.x, -fwd.z)

	# 俯拍不用每帧都拍：小地图 5 次/秒，大地图 10 次/秒
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.1 if expanded else 0.2
		map_center = p2
		_cam.size = map_span
		_cam.global_position = Vector3(p.x, maxf(p.y, 0.0) + 400.0, p.z)
		var dn = world.day_night
		if dn:
			var amb: Color = dn.env.ambient_light_color
			_env.ambient_light_color = amb.lerp(Color(0.88, 0.9, 0.95), 0.55)
			_env.ambient_light_energy = maxf(dn.env.ambient_light_energy, 0.85) + dn.night * 0.45
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_compose_fog()
	_mat.set_shader_parameter("shape", 1.0 if expanded else 0.0)
	_mat.set_shader_parameter("rot", 0.0 if expanded else _heading)
	_mat.set_shader_parameter("shift", (p2 - map_center) / map_span)
	_overlay.queue_redraw()
	queue_redraw()


# ───────────────────────── 探索迷雾 ─────────────────────────

func _tile(key: Vector2i) -> Image:
	if not _tiles.has(key):
		_tiles[key] = Image.create(TILE_PX, TILE_PX, false, Image.FORMAT_L8)
	return _tiles[key]


## 以 p 为中心照亮一圈（边缘渐变），可能跨好几块
func _reveal(p: Vector2) -> void:
	var px := TILE / TILE_PX
	var r := REVEAL_R
	var k0 := Vector2i(floori((p.x - r) / TILE), floori((p.y - r) / TILE))
	var k1 := Vector2i(floori((p.x + r) / TILE), floori((p.y + r) / TILE))
	for kz in range(k0.y, k1.y + 1):
		for kx in range(k0.x, k1.x + 1):
			var img := _tile(Vector2i(kx, kz))
			var origin := Vector2(kx, kz) * TILE
			var lo := ((p - Vector2.ONE * r - origin) / px).floor()
			var hi := ((p + Vector2.ONE * r - origin) / px).ceil()
			for iy in range(maxi(int(lo.y), 0), mini(int(hi.y), TILE_PX)):
				for ix in range(maxi(int(lo.x), 0), mini(int(hi.x), TILE_PX)):
					var w := origin + (Vector2(ix, iy) + Vector2(0.5, 0.5)) * px
					var v := 1.0 - smoothstep(r * 0.6, r, w.distance_to(p))
					if v <= 0.0:
						continue
					var old := img.get_pixel(ix, iy).r
					if v > old:
						if old < 0.5 and v >= 0.5:
							_explored_px += 1
						img.set_pixel(ix, iy, Color(v, v, v))


func _seen_at(w: Vector2) -> float:
	var key := Vector2i(floori(w.x / TILE), floori(w.y / TILE))
	if not _tiles.has(key):
		return 0.0
	var img: Image = _tiles[key]
	var local := (w - Vector2(key) * TILE) / (TILE / TILE_PX)
	return img.get_pixel(clampi(int(local.x), 0, TILE_PX - 1), clampi(int(local.y), 0, TILE_PX - 1)).r


## 把地图范围内的迷雾拼成一张小贴图交给着色器
func _compose_fog() -> void:
	for y in FOG_RES:
		for x in FOG_RES:
			var w := map_center + (Vector2(x + 0.5, y + 0.5) / FOG_RES - Vector2.ONE * 0.5) * map_span
			var v := _seen_at(w)
			_fog_img.set_pixel(x, y, Color(v, v, v))
	_fog_tex.update(_fog_img)


# ───────────────────────── 画 ─────────────────────────

## 地图下面的底：小地图是奶油色表盘外圈，大地图是奶油色圆角卡片
func _draw() -> void:
	if world == null:
		return
	var edge := size.x
	var c := Vector2.ONE * edge * 0.5
	if expanded:
		draw_style_box(_frame, Rect2(Vector2.ZERO, size))
	else:
		draw_circle(c + Vector2(0, 4), edge * 0.5 + 9.0, Color(SHADOW, 0.28))
		draw_circle(c, edge * 0.5 + 7.0, Color(CREAM, 0.96))


func _txt(f: Font, pos: Vector2, s: String, sz: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	_overlay.draw_string(f, pos + Vector2(0, 2), s, align, width, sz, Color(SHADOW, col.a * 0.3))
	_overlay.draw_string(f, pos, s, align, width, sz, col)


## 世界坐标 → 地图上的像素位置
func _to_map(wp: Vector2, center: Vector2, edge: float) -> Vector2:
	var p: Vector3 = world.player.global_position
	var d := (wp - Vector2(p.x, p.z)) / map_span * edge
	if not expanded:
		d = d.rotated(-_heading)
	return center + d


func _draw_player(at: Vector2, heading: float) -> void:
	var o := _overlay
	# 视野扇形：金色、从中间往外淡
	var pts := PackedVector2Array([at])
	var cols := PackedColorArray([Color(GOLD, 0.42)])
	var r := 46.0 if expanded else 40.0
	for i in 13:
		var a := heading - 0.62 + 1.24 * i / 12.0
		pts.append(at + Vector2(sin(a), -cos(a)) * r)
		cols.append(Color(GOLD, 0.0))
	o.draw_polygon(pts, cols)
	# 箭头：奶油色、墨色描边
	var arrow := PackedVector2Array()
	for v in [Vector2(0, -11), Vector2(7.5, 7.5), Vector2(0, 3.5), Vector2(-7.5, 7.5)]:
		arrow.append(at + (v as Vector2).rotated(heading))
	var sh := PackedVector2Array()
	for v in arrow:
		sh.append(v + Vector2(0, 2))
	o.draw_colored_polygon(sh, Color(SHADOW, 0.3))
	o.draw_colored_polygon(arrow, CREAM)
	arrow.append(arrow[0])
	o.draw_polyline(arrow, Color(INK, 0.9), 1.6, true)


func _draw_friends(center: Vector2, edge: float, radius: float) -> void:
	var tex := Fx.heart_texture()
	for a in get_tree().get_nodes_in_group("pettable"):
		var n := a as Node3D
		if n == null or not n.is_inside_tree() or float(n.get("friend_t")) <= 0.0:
			continue
		var at := _to_map(Vector2(n.global_position.x, n.global_position.z), center, edge)
		if at.distance_to(center) > radius - 8.0:
			continue
		var s := 15.0 + sin(Time.get_ticks_msec() * 0.005) * 1.2
		_overlay.draw_texture_rect(tex, Rect2(at - Vector2(s, s) * 0.5, Vector2(s, s)), false)


func _draw_overlay() -> void:
	if world == null:
		return
	var o := _overlay
	var edge := size.x
	var c := Vector2.ONE * edge * 0.5
	var fu: Font = Settings.font_ui
	var fl: Font = Settings.font_light
	var ft: Font = Settings.font_title
	if expanded:
		_draw_big(o, edge, c, fu, fl, ft)
		return

	# ── 小地图 ──
	var r := edge * 0.5
	o.draw_arc(c, r - 0.5, 0, TAU, 96, Color(GOLD, 0.75), 1.2, true)
	o.draw_arc(c, r + 3.5, 0, TAU, 96, Color(INK, 0.12), 1.0, true)
	# 外圈刻度（跟着视角转）：东南西北是小圆点，其它是短线
	for i in 24:
		var ang := -_heading + TAU * i / 24.0
		var dir := Vector2(sin(ang), -cos(ang))
		if i % 6 == 0:
			if i != 0:
				o.draw_circle(c + dir * (r + 3.5), 1.8, Color(INK, 0.45))
		else:
			o.draw_line(c + dir * (r + 1.5), c + dir * (r + 4.5), Color(INK, 0.22), 1.0, true)
	_draw_friends(c, edge, r)
	_draw_player(c, 0.0)
	# N：外圈上一个金色小徽章
	var nd := Vector2(sin(-_heading), -cos(-_heading))
	var np := c + nd * (r + 3.5)
	o.draw_circle(np + Vector2(0, 1.5), 10.0, Color(SHADOW, 0.25))
	o.draw_circle(np, 10.0, GOLD)
	o.draw_arc(np, 10.0, 0, TAU, 24, Color(CREAM, 0.9), 1.2, true)
	var nw := fu.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	o.draw_string(fu, np + Vector2(-nw * 0.5, 4.5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)

	# 时间：表盘下面一个小胶囊，左边是太阳 / 月亮
	var dn = world.day_night
	var t: String = dn.clock_text() if dn else ""
	var tw := fu.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
	var pr := Rect2(c.x - (tw + 40.0) * 0.5, edge + 18.0, tw + 40.0, 26.0)
	o.draw_style_box(_pill, pr)
	var ic := pr.position + Vector2(15.0, 13.0)
	var night: float = dn.night if dn else 0.0
	if night > 0.5:
		o.draw_circle(ic, 5.5, Color(1.0, 0.95, 0.8))
		o.draw_circle(ic + Vector2(2.6, -1.8), 4.6, Color(0.17, 0.2, 0.24))     # 月牙：盖掉一块
	else:
		o.draw_circle(ic, 4.0, Color(1.0, 0.82, 0.4))
		for i in 8:
			var d := Vector2.UP.rotated(TAU * i / 8.0)
			o.draw_line(ic + d * 5.8, ic + d * 7.6, Color(1.0, 0.82, 0.4), 1.2, true)
	o.draw_string(fu, Vector2(pr.position.x + 27.0, pr.position.y + 18.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(CREAM, 0.95))
	# 右下角一个很淡的 M 键帽
	var kr := Rect2(c.x + r * 0.62, c.y + r * 0.62, 18.0, 18.0)
	o.draw_circle(kr.get_center(), 13.0, Color(INK, 0.35))
	_key.border_color = Color(CREAM, 0.7)
	o.draw_style_box(_key, kr)
	var mw := fu.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	o.draw_string(fu, kr.position + Vector2(9.0 - mw * 0.5, 13.0), "M", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(CREAM, 0.85))


func _draw_big(o: Control, edge: float, c: Vector2, fu: Font, fl: Font, ft: Font) -> void:
	var inner := edge - 16.0
	var ic := Vector2.ONE * 8.0 + Vector2.ONE * inner * 0.5
	o.draw_style_box(_inner_line(), Rect2(Vector2.ONE * 8.0, Vector2.ONE * inner))

	# 标题 + 副标题（卡片上方）
	_txt(ft, Vector2(4.0, -46.0), "无限草原", 34, CREAM)
	var km := _explored_px * 16.0 / 1.0e6
	_txt(fl, Vector2(6.0, -18.0), "种子 %d   ·   已探索 %.2f km²" % [Settings.world_seed, km], 14, Color(CREAM, 0.78))
	# 右上：操作提示
	var hx := edge
	for pair in [["滚轮", "缩放"], ["M", "收起"]]:
		var kw := fu.get_string_size(pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 14.0
		var lw := fl.get_string_size(pair[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		hx -= lw
		_txt(fl, Vector2(hx, -20.0), pair[1], 13, Color(CREAM, 0.7))
		hx -= kw + 7.0
		var kr := Rect2(hx, -35.0, kw, 21.0)
		_key.border_color = Color(CREAM, 0.55)
		o.draw_style_box(_key, kr)
		o.draw_string(fu, kr.position + Vector2(7.0, 15.0), pair[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(CREAM, 0.9))
		hx -= 22.0

	# 玩家 + 朋友
	_draw_friends(ic, inner, inner * 0.5)
	var p: Vector3 = world.player.global_position
	_draw_player(ic, _heading)

	# 指北针（右上角）
	var cc := Vector2(edge - 54.0, 54.0)
	o.draw_circle(cc, 28.0, Color(INK, 0.38))
	o.draw_arc(cc, 28.0, 0, TAU, 48, Color(CREAM, 0.55), 1.0, true)
	o.draw_colored_polygon(PackedVector2Array([cc + Vector2(0, -20), cc + Vector2(5, 0), cc + Vector2(-5, 0)]), GOLD)
	o.draw_colored_polygon(PackedVector2Array([cc + Vector2(0, 20), cc + Vector2(5, 0), cc + Vector2(-5, 0)]), Color(CREAM, 0.6))
	o.draw_circle(cc, 2.2, INK)
	var nw := fu.get_string_size("N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	o.draw_string(fu, cc + Vector2(-nw * 0.5, -31.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CREAM)

	# 比例尺（左下角）：挑一个整数米数，长度 60-140 像素
	var mpp := map_span / inner
	var meters := 50.0
	for m in [25.0, 50.0, 100.0, 200.0, 250.0, 500.0]:
		meters = m
		if m / mpp >= 60.0:
			break
	var bl := meters / mpp
	var sr := Rect2(24.0, edge - 54.0, bl + 64.0, 28.0)
	o.draw_style_box(_pill, sr)
	var s0 := sr.position + Vector2(12.0, 17.0)
	o.draw_line(s0, s0 + Vector2(bl, 0), CREAM, 2.0, true)
	o.draw_line(s0 + Vector2(0, -4), s0 + Vector2(0, 2), CREAM, 1.5, true)
	o.draw_line(s0 + Vector2(bl, -4), s0 + Vector2(bl, 2), CREAM, 1.5, true)
	o.draw_string(fl, s0 + Vector2(bl + 8.0, 4.5), "%d m" % int(meters), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(CREAM, 0.9))

	# 坐标（右下角）
	var coord := "X %d   Z %d" % [roundi(p.x), roundi(p.z)]
	var cw := fl.get_string_size(coord, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var cr := Rect2(edge - 24.0 - cw - 24.0, edge - 54.0, cw + 24.0, 28.0)
	o.draw_style_box(_pill, cr)
	o.draw_string(fl, cr.position + Vector2(12.0, 18.5), coord, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(CREAM, 0.9))


var _inner_sb: StyleBoxFlat
func _inner_line() -> StyleBoxFlat:
	if _inner_sb == null:
		_inner_sb = StyleBoxFlat.new()
		_inner_sb.draw_center = false
		_inner_sb.set_border_width_all(1)
		_inner_sb.border_color = Color(GOLD, 0.8)
		_inner_sb.set_corner_radius_all(26)
		_inner_sb.anti_aliasing = true
	return _inner_sb
