extends CanvasLayer
## 加载界面：打开游戏 / 换地图时显示，全部生成完才淡出进入大厅（主菜单）。
## 画面：奶油色的纸面上一小丛草随风摆，加载越多草长得越高，快好的时候最高那根草顶上开出一朵小花；
## 周围有光点慢慢往上飘；下面是一条细细的金色进度线和当前在做什么；最底下轮流显示小贴士。
## 进度是真的：①后台线程加载模型/声音/着色器 ②搭地图（这一步是同步的，画面会停一下，约 0.3 秒）③等地形、树、草在后台生成完

const PAPER := Color(0.965, 0.935, 0.870)       # 和启动画面、主菜单开场的底色一样，切换时看不出接缝
const INK := Color(0.16, 0.22, 0.20)
const GREEN := [Color(0.36, 0.56, 0.31), Color(0.30, 0.50, 0.30), Color(0.44, 0.62, 0.33), Color(0.27, 0.46, 0.30)]
const GOLD := Color(0.80, 0.62, 0.32)
const PETAL := Color(1.0, 0.72, 0.78)
const TIPS := [
	"拿着胡萝卜慢慢走过去，兔子就不怕你了",
	"走到小动物跟前按 E，摸摸它",
	"按住 T，时间会过得快一点",
	"按 V 切换第一人称，低头能看到自己",
	"按 M 打开地图，走过的地方会被点亮",
	"在主菜单里戳戳那个小家伙",
]

var boot
var _ui: Control
var _bg: ColorRect
var _t := 0.0
var _target := 0.0          # 真实进度
var _shown := 0.0           # 显示的进度（平滑追上去）
var _stage := ""
var _stage_prev := ""
var _stage_t := 1.0
var _content := 0.0         # 画面内容的透明度（淡入 / 淡出）
var _content_target := 1.0
var _tip_i := 0
var _tip_t := 0.0
var _blades: Array = []     # 每根草：[x, 高, 宽, 颜色, 相位, 出现的进度]
var _motes: Array = []
var _done := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bg = ColorRect.new()
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP     # 加载时挡住鼠标
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform vec4 paper : source_color;
uniform float vig = 1.0;
void fragment() {
	vec2 d = (UV - vec2(0.5, 0.46)) * vec2(1.6, 1.0);
	float v = smoothstep(0.25, 0.95, length(d)) * 0.10 * vig;
	float n = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	COLOR = vec4(paper.rgb * (1.0 - v) + n * 0.012 * vig, 1.0);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("paper", PAPER)
	_bg.material = m
	add_child(_bg)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)

	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var n := 13
	for i in n:
		var u := (i + 0.5) / n
		var center := 1.0 - absf(u - 0.5) * 2.0
		_blades.append([
			(u - 0.5) * 120.0 + rng.randf_range(-4.0, 4.0),
			lerpf(34.0, 96.0, center * center) * rng.randf_range(0.8, 1.1),
			rng.randf_range(5.0, 7.5),
			GREEN[rng.randi() % GREEN.size()],
			rng.randf() * TAU,
			clampf(absf(u - 0.5) * 1.5 + rng.randf_range(-0.05, 0.05), 0.0, 0.8),   # 中间的先长
		])
	for i in 16:
		_motes.append([rng.randf_range(-190.0, 190.0), rng.randf(), rng.randf_range(0.6, 1.4), rng.randf() * TAU, rng.randf_range(1.5, 3.0)])
	_tip_i = randi() % TIPS.size()


# ───────────────────────── 加载流程 ─────────────────────────

func run(b) -> void:
	boot = b
	_set_stage("收拾行囊")
	await get_tree().process_frame
	await get_tree().process_frame

	# ① 后台线程加载资源（模型、声音、着色器）；加载好的留在 boot.keep 里，后面生成动物时不会再卡
	var paths := _resource_list()
	for p in paths:
		ResourceLoader.load_threaded_request(p, "", false)
	var left := paths.duplicate()
	while not left.is_empty():
		var sum := 0.0
		for p in paths:
			if not left.has(p):
				sum += 1.0
				continue
			var prog := []
			var st := ResourceLoader.load_threaded_get_status(p, prog)
			if st == ResourceLoader.THREAD_LOAD_LOADED or st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				left.erase(p)
				if st == ResourceLoader.THREAD_LOAD_LOADED:
					boot.keep.append(ResourceLoader.load_threaded_get(p))
				sum += 1.0
			elif not prog.is_empty():
				sum += float(prog[0])
		_target = 0.3 * sum / maxf(paths.size(), 1.0)
		await get_tree().process_frame
	_target = 0.3

	# ② 搭地图：同步的，会停一下，所以先把字换好、画一帧再开始
	_set_stage("铺开大地")
	_stage_t = 1.0
	_shown = 0.3
	await get_tree().process_frame
	await get_tree().process_frame
	boot.build_world()
	_target = 0.42

	# ③ 等后台把地形、树、草生成完
	_set_stage("种下花草树木")
	var w = boot.world
	var t0 := Time.get_ticks_msec()
	var full := 0.0
	while true:
		await get_tree().process_frame
		var p := 1.0
		if w.has_method("load_progress"):
			p = float(w.load_progress())
		_target = maxf(_target, 0.42 + 0.56 * p)
		if p > 0.55 and _stage != "叫醒小动物":
			_set_stage("叫醒小动物")
		full = (full + get_process_delta_time()) if p >= 0.985 else 0.0
		if full > 0.3 or Time.get_ticks_msec() - t0 > 25000:
			break

	_target = 1.0
	_set_stage("风来了")
	while _shown < 0.995:
		await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	# 内容淡出，留下和主菜单开场一样的奶油色底，主菜单从这里接着淡入
	_content_target = 0.0
	while _content > 0.01:
		await get_tree().process_frame
	_done = true
	if boot.menu:
		boot.menu.hold_intro = false
	queue_free()


func _resource_list() -> Array:
	var out := []
	var dirs := {"res://characters": ["glb"], "res://audio": ["ogg"], "res://shaders": ["gdshader"]}
	for d: String in dirs:
		for f: String in ResourceLoader.list_directory(d):
			if f.ends_with("/"):
				continue
			if f.get_extension() in dirs[d]:
				out.append(d + "/" + f)
	for f in ["carrot", "berry", "net", "rod"]:
		var p := "res://props/%s.glb" % f
		if not out.has(p) and ResourceLoader.exists(p):
			out.append(p)
	return out


func _set_stage(s: String) -> void:
	if s == _stage:
		return
	_stage_prev = _stage
	_stage = s
	_stage_t = 0.0


# ───────────────────────── 动画 ─────────────────────────

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	_t += dt
	_stage_t += dt
	_tip_t += dt
	if _tip_t > 3.8:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
	_shown = move_toward(_shown, _target, dt * maxf((_target - _shown) * 3.0, 0.1))
	_content = move_toward(_content, _content_target, dt * (2.2 if _content_target > _content else 2.0))
	(_bg.material as ShaderMaterial).set_shader_parameter("vig", _content)
	_ui.queue_redraw()


func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _draw_ui() -> void:
	var a := _content * _content * (3.0 - 2.0 * _content)
	if a <= 0.002:
		return
	var sz := _ui.size
	var c := Vector2(sz.x * 0.5, sz.y * 0.5 - 30.0)     # 草根的位置
	var ground_y := c.y

	# 光点：慢慢往上飘，左右轻晃
	for m in _motes:
		var life: float = m[4]
		var k := fmod(_t / life + float(m[1]), 1.0)
		var p := c + Vector2(float(m[0]) + sin(_t * float(m[2]) + float(m[3])) * 10.0, 20.0 - k * 190.0)
		var fa := sin(k * PI) * 0.45 * a
		_ui.draw_circle(p, 1.6 + float(m[2]) * 0.9, Color(GOLD, fa * 0.5))
		_ui.draw_circle(p, 1.0 + float(m[2]) * 0.4, Color(1, 1, 1, fa))

	# 地面的一条细线，两头淡出
	for i in 24:
		var u0 := i / 24.0
		var u1 := (i + 1) / 24.0
		var fade := sin(((u0 + u1) * 0.5) * PI)
		_ui.draw_line(Vector2(c.x - 110.0 + u0 * 220.0, ground_y), Vector2(c.x - 110.0 + u1 * 220.0, ground_y), Color(INK, 0.16 * fade * a), 1.2, true)

	# 草：每根是一条弯的细三角，随风摆；按进度一根根长出来
	var grow_p := _shown
	var tallest_tip := Vector2.ZERO
	var tallest_h := 0.0
	for b in _blades:
		var g := _ease((grow_p - float(b[5])) / 0.25)
		if g <= 0.0:
			continue
		var h: float = float(b[1]) * g
		if h < 2.0:
			continue
		var wdt: float = b[2]
		var x: float = b[0]
		var sway := sin(_t * 1.7 + float(b[4])) * 0.16 + sin(_t * 0.9 + x * 0.03) * 0.1
		var pts := PackedVector2Array()
		var left := PackedVector2Array()
		var right := PackedVector2Array()
		var segs := 8
		for s in segs + 1:
			var v := float(s) / segs
			var bend := sway * v * v * h + x * 0.12 * v * v
			var center := Vector2(c.x + x + bend, ground_y - v * h)
			var half := wdt * 0.5 * (1.0 - v) * (1.0 - v * 0.2)
			left.append(center - Vector2(half, 0))
			if s < segs:
				right.append(center + Vector2(half, 0))
		pts.append_array(left)
		right.reverse()
		pts.append_array(right)
		var col: Color = b[3]
		_ui.draw_colored_polygon(pts, Color(col, a))
		if h > tallest_h:
			tallest_h = h
			tallest_tip = left[segs]

	# 快加载完：最高那根草顶上开一朵小花（五片花瓣依次张开）
	var bloom := _ease((grow_p - 0.8) / 0.2)
	if bloom > 0.0 and tallest_h > 0.0:
		var fc := tallest_tip + Vector2(0, -2.0)
		for i in 5:
			var pb := _ease(bloom * 1.6 - i * 0.12)
			if pb <= 0.0:
				continue
			var ang := -PI * 0.5 + TAU * i / 5.0 + sin(_t * 1.2) * 0.08
			var pc := fc + Vector2(cos(ang), sin(ang)) * 6.5 * pb
			_ui.draw_circle(pc, 5.0 * pb, Color(PETAL, a))
		_ui.draw_circle(fc, 3.2 * bloom, Color(1.0, 0.86, 0.45, a))


	# 进度线：细线 + 金色填充 + 头上一个会呼吸的小点
	var bw := 240.0
	var by := ground_y + 64.0
	var bx := c.x - bw * 0.5
	_ui.draw_line(Vector2(bx, by), Vector2(bx + bw, by), Color(INK, 0.12 * a), 2.0, true)
	var fx := bx + bw * _shown
	if _shown > 0.002:
		_ui.draw_line(Vector2(bx, by), Vector2(fx, by), Color(GOLD, 0.95 * a), 2.0, true)
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_ui.draw_circle(Vector2(fx, by), 6.0 + 3.0 * pulse, Color(GOLD, 0.14 * a))
	_ui.draw_circle(Vector2(fx, by), 3.0, Color(GOLD, a))

	# 现在在做什么（换字时上一句淡出、下一句淡入）+ 百分比
	var lf: Font = Settings.font_light
	var k := clampf(_stage_t / 0.35, 0.0, 1.0)
	_center_text(lf, _stage + "…", Vector2(c.x, by + 34.0 - 6.0 * (1.0 - k)), 16, Color(INK, 0.62 * a * k))
	if k < 1.0 and _stage_prev != "":
		_center_text(lf, _stage_prev + "…", Vector2(c.x, by + 34.0 + 6.0 * k), 16, Color(INK, 0.62 * a * (1.0 - k)))
	var pct := "%d%%" % roundi(_shown * 100.0)
	_ui.draw_string(lf, Vector2(bx + bw + 14.0, by + 5.0), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(INK, 0.45 * a))

	# 小贴士
	var tk := clampf(minf(_tip_t / 0.5, (3.8 - _tip_t) / 0.5), 0.0, 1.0)
	_center_text(lf, TIPS[_tip_i], Vector2(c.x, sz.y - 54.0), 14, Color(INK, 0.42 * a * tk))


func _center_text(f: Font, s: String, pos: Vector2, size: int, col: Color) -> void:
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_ui.draw_string(f, Vector2(pos.x - w * 0.5, pos.y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
