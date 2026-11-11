extends CanvasLayer
## 游戏里的提示文字（抓到蝴蝶、钓鱼、小动物怕你…）：白色细字、没有底框，
## 出现时一个字一个字从下面浮上来；停一会儿后，从左到右每个字依次往上飘、字距慢慢散开、变淡消失。
## 新提示来的时候旧的直接开始飘散，新的在原位置浮现，两条会交叠着换过去。
## 用法：get_tree().get_first_node_in_group("notice").say("文字", 停留秒数)

const WHITE := Color(1, 1, 1)
const SHADOW := Color(0.0, 0.03, 0.04)
const SIZE := 22
const TRACK := 1.5          # 字距
const IN_STAGGER := 0.035   # 出现：每个字错开多久
const IN_TIME := 0.55
const OUT_STAGGER := 0.045  # 消失：每个字错开多久
const OUT_TIME := 1.3

var _ui: Control
var _msgs: Array = []       # 每条：{text, t, hold, out_t（<0 = 还没开始消失）}


func _ready() -> void:
	layer = 30
	add_to_group("notice")
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)


func say(text: String, hold := 2.6) -> void:
	for m in _msgs:
		if m.text == text and m.out_t < 0.0:
			m.hold = maxf(m.hold, m.t + hold)     # 同一句话：延长，不重新播
			return
	for m in _msgs:
		if m.out_t < 0.0:
			m.out_t = 0.0
	_msgs.append({"text": text, "t": -0.12 if not _msgs.is_empty() else 0.0, "hold": hold, "out_t": -1.0})


func _process(delta: float) -> void:
	for m in _msgs.duplicate():
		m.t += delta
		var n: int = (m.text as String).length()
		if m.out_t < 0.0 and m.t > m.hold + IN_STAGGER * n + IN_TIME:
			m.out_t = 0.0
		if m.out_t >= 0.0:
			m.out_t += delta
			if m.out_t > OUT_STAGGER * n + OUT_TIME:
				_msgs.erase(m)
	if not _msgs.is_empty():
		_ui.queue_redraw()
	elif _ui.get_meta("drawn", false):
		_ui.set_meta("drawn", false)
		_ui.queue_redraw()


func _ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)


func _draw_ui() -> void:
	if _msgs.is_empty():
		return
	_ui.set_meta("drawn", true)
	var font: Font = Settings.font_ui
	var sz := _ui.size
	var cy := sz.y * 0.72
	for m in _msgs:
		var text: String = m.text
		var n := text.length()
		var widths: Array[float] = []
		var total := 0.0
		for ch in text:
			var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
			widths.append(w)
			total += w + TRACK
		total -= TRACK
		var x := sz.x * 0.5 - total * 0.5
		var mid := sz.x * 0.5
		var base_y := cy + (font.get_ascent(SIZE) - font.get_descent(SIZE)) * 0.5
		var line_a := 1.0
		for i in n:
			var ch := text[i]
			var a_in := _ease_out((m.t - i * IN_STAGGER) / IN_TIME)
			var a := a_in
			var dy := 9.0 * (1.0 - a_in)
			var dx := 0.0
			if m.out_t >= 0.0:
				var o := clampf((m.out_t - i * OUT_STAGGER) / OUT_TIME, 0.0, 1.0)
				var e := o * o * (3.0 - 2.0 * o)
				a *= 1.0 - e
				dy -= 16.0 * e                                   # 往上飘
				dx = (x + widths[i] * 0.5 - mid) * 0.18 * e      # 字距慢慢散开
			if a > 0.003 and ch != " ":
				var p := Vector2(x + dx, base_y + dy)
				_ui.draw_string(font, p + Vector2(0, 2), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(SHADOW, 0.30 * a))
				_ui.draw_string(font, p + Vector2(0, 4), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(SHADOW, 0.12 * a))
				_ui.draw_string(font, p, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color(WHITE, 0.96 * a))
			x += widths[i] + TRACK
		# 两边的细线：出现时往外长，消失时先淡掉
		var grow := _ease_out((m.t - 0.1) / 0.8)
		if m.out_t >= 0.0:
			line_a = 1.0 - clampf(m.out_t / 0.6, 0.0, 1.0)
		var la := grow * line_a
		if la > 0.003:
			var gap := total * 0.5 + 20.0
			var ln := 34.0 * grow
			_ui.draw_line(Vector2(mid - gap - ln, cy + 1), Vector2(mid - gap, cy + 1), Color(SHADOW, 0.2 * la), 1.0, true)
			_ui.draw_line(Vector2(mid + gap, cy + 1), Vector2(mid + gap + ln, cy + 1), Color(SHADOW, 0.2 * la), 1.0, true)
			_ui.draw_line(Vector2(mid - gap - ln, cy), Vector2(mid - gap, cy), Color(WHITE, 0.6 * la), 1.0, true)
			_ui.draw_line(Vector2(mid + gap, cy), Vector2(mid + gap + ln, cy), Color(WHITE, 0.6 * la), 1.0, true)
