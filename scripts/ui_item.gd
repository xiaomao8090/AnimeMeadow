extends Control
## 菜单里的一行。全部自己画（不用 Godot 默认按钮皮肤）：
##   action：普通按钮，右边可以带一段小字（比如种子）
##   option：左右切换的选项  ‹ 值 ›
##   slider：细线滑条
## 悬停 / 键盘选中时：文字往右滑一点、变暖金色、左边出现小菱形、下面画出一条细线。

signal activated
signal changed(item)

const CREAM := Color(0.984, 0.957, 0.902)
const GOLD := Color(0.925, 0.780, 0.500)
const SHADOW := Color(0.02, 0.05, 0.06)
const ROW_H := 50.0
const VALUE_X := 250.0
const VALUE_W := 210.0
const FONT_SIZE := 25
const VALUE_SIZE := 19

var label := ""
var kind := "action"
var options: PackedStringArray = []
var index := 0
var value := 0.5                    # slider：0..1
var value_text := ""                # action 右边的小字
var format: Callable                # slider：value -> 显示的文字
var tip := ""                       # 选中时底部显示的说明
var delay := 0.0                    # 出现前等多久（错开出场）
var target := 1.0                   # 1 = 显示，0 = 隐藏
var reveal := 0.0
var font_size := FONT_SIZE

var _hl := 0.0                      # 0..1 悬停程度
var _press := 0.0
var _swap := 0.0                    # 选项切换时值文字的滑动
var _swap_dir := 1.0
var _drag := false
var _spin := 0.0                    # action 右边小图标转一下


func _init() -> void:
	custom_minimum_size = Vector2(VALUE_X + VALUE_W + 40.0, ROW_H)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)


func _on_mouse_entered() -> void:
	if target > 0.5:
		grab_focus()


func value_string() -> String:
	if kind == "option":
		return options[index] if index < options.size() else ""
	if kind == "slider":
		return format.call(value) if format.is_valid() else "%d%%" % roundi(value * 100.0)
	return value_text


func _process(delta: float) -> void:
	if delay > 0.0 and target > 0.5:
		delay -= delta
	else:
		reveal = move_toward(reveal, target, delta / (0.55 if target > 0.5 else 0.22))
	var live := target > 0.5 and reveal > 0.35
	mouse_filter = Control.MOUSE_FILTER_STOP if live else Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_ALL if live else Control.FOCUS_NONE
	if not live and has_focus():
		release_focus()
	_hl = lerpf(_hl, 1.0 if has_focus() else 0.0, clampf(delta * 14.0, 0.0, 1.0))
	_press = move_toward(_press, 0.0, delta * 4.0)
	_swap = lerpf(_swap, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	_spin = lerpf(_spin, 0.0, clampf(delta * 6.0, 0.0, 1.0))
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if target < 0.5:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			grab_focus()
			if kind == "slider" and mb.position.x > VALUE_X - 12.0:
				_drag = true
				_set_from_x(mb.position.x)
			elif kind == "option":
				var right := mb.position.x < VALUE_X or mb.position.x > VALUE_X + VALUE_W * 0.5
				_step(1 if right else -1)
			elif kind == "action":
				_fire()
		else:
			_drag = false
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_set_from_x((event as InputEventMouseMotion).position.x)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		if kind == "action":
			_fire()
		elif kind == "option":
			_step(1)
		accept_event()
	elif event.is_action_pressed("ui_left", true) or event.is_action_pressed("ui_right", true):
		var d := -1 if event.is_action_pressed("ui_left", true) else 1
		if kind == "option":
			_step(d)
			accept_event()
		elif kind == "slider":
			value = clampf(value + 0.05 * d, 0.0, 1.0)
			changed.emit(self)
			accept_event()


func _fire() -> void:
	_press = 1.0
	_spin = 1.0
	activated.emit()


func _step(d: int) -> void:
	if options.is_empty():
		return
	index = posmod(index + d, options.size())
	_swap = 1.0
	_swap_dir = float(d)
	changed.emit(self)


func _track() -> Vector2:
	return Vector2(VALUE_X, VALUE_X + VALUE_W - 64.0)


func _set_from_x(x: float) -> void:
	var t := _track()
	value = clampf((x - t.x) / (t.y - t.x), 0.0, 1.0)
	changed.emit(self)


# ───────────────────────── 画 ─────────────────────────

func _text(font: Font, pos: Vector2, s: String, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	# 柔和的投影：两层，保证在亮天空上也看得清
	draw_string(font, pos + Vector2(0, 2), s, align, width, size, Color(SHADOW, col.a * 0.28))
	draw_string(font, pos + Vector2(0, 1), s, align, width, size, Color(SHADOW, col.a * 0.22))
	draw_string(font, pos, s, align, width, size, col)


func _chevron(c: Vector2, dir: float, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-dir * s * 0.5, -s), c + Vector2(dir * s * 0.5, 0), c + Vector2(-dir * s * 0.5, s)])
	draw_polyline(pts, col, 1.6, true)


func _draw() -> void:
	var r := clampf(reveal, 0.0, 1.0)
	var a := r * r * (3.0 - 2.0 * r)
	if a <= 0.002:
		return
	var font: Font = Settings.font_ui
	var hl := _hl * _hl * (3.0 - 2.0 * _hl)
	var x0 := 28.0 - 30.0 * (1.0 - a) + 14.0 * hl - 3.0 * _press
	var cy := ROW_H * 0.5
	var base_y := cy + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5

	# 左边的小菱形
	if hl > 0.01:
		var c := Vector2(x0 - 18.0, cy)
		var s := maxf(4.5 * hl, 0.6)
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0)]),
			Color(GOLD, a * hl))

	var col := CREAM.lerp(Color(1.0, 0.90, 0.70), hl)
	col.a = a * lerpf(0.86, 1.0, hl)
	_text(font, Vector2(x0, base_y), label, font_size, col)
	var tw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	if hl > 0.01:
		draw_line(Vector2(x0, base_y + 10.0), Vector2(x0 + tw * hl, base_y + 10.0), Color(GOLD, 0.85 * a * hl), 1.5, true)

	var vfont: Font = Settings.font_light
	var vy := cy + (vfont.get_ascent(VALUE_SIZE) - vfont.get_descent(VALUE_SIZE)) * 0.5
	var shift := 30.0 * (1.0 - a)
	if kind == "option":
		var vx := VALUE_X + shift
		var arrow_a := a * lerpf(0.35, 1.0, hl)
		_chevron(Vector2(vx + 6.0, cy), -1.0, 5.5, Color(GOLD, arrow_a))
		_chevron(Vector2(vx + VALUE_W - 6.0, cy), 1.0, 5.5, Color(GOLD, arrow_a))
		var off := _swap * 14.0 * _swap_dir
		var vcol := Color(CREAM, a * (0.92 - 0.6 * _swap))
		_text(vfont, Vector2(vx + 18.0 + off, vy), value_string(), VALUE_SIZE, vcol, HORIZONTAL_ALIGNMENT_CENTER, VALUE_W - 36.0)
	elif kind == "slider":
		var t := _track() + Vector2(shift, shift)
		var fx := lerpf(t.x, t.y, value)
		draw_line(Vector2(t.x, cy), Vector2(t.y, cy), Color(CREAM, 0.22 * a), 2.0, true)
		draw_line(Vector2(t.x, cy), Vector2(fx, cy), Color(GOLD, 0.95 * a), 2.0, true)
		if hl > 0.01:
			draw_circle(Vector2(fx, cy), 11.0 * hl, Color(GOLD, 0.16 * a * hl))
		draw_circle(Vector2(fx, cy), 5.0 + 1.5 * hl, Color(CREAM, a))
		_text(vfont, Vector2(t.y + 16.0, vy), value_string(), VALUE_SIZE, Color(CREAM, a * 0.8))
	elif value_text != "":
		var vx := VALUE_X + shift
		_text(vfont, Vector2(vx + 18.0, vy), value_text, VALUE_SIZE, Color(CREAM, a * lerpf(0.55, 0.85, hl)))
		# 小的循环箭头（悬停时出现，点击转一圈）
		var c := Vector2(vx + 6.0, cy)
		var ang := -_spin * TAU
		var ia := a * lerpf(0.3, 1.0, hl)
		draw_arc(c, 6.0, ang + 0.5, ang + TAU - 0.6, 20, Color(GOLD, ia), 1.6, true)
		var tip_p := c + Vector2(cos(ang + 0.5), sin(ang + 0.5)) * 6.0
		var tdir := Vector2(-sin(ang + 0.5), cos(ang + 0.5))
		draw_colored_polygon(PackedVector2Array([tip_p + tdir * 3.5, tip_p - tdir * 1.2 + (tip_p - c).normalized() * 3.0,
			tip_p - tdir * 1.2 - (tip_p - c).normalized() * 3.0]), Color(GOLD, ia))
