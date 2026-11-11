extends Control
## 背包里的一行（和主菜单 / 设置页的菜单项同一种样式）：
## 左边小图标 + 名字；右边：在快捷栏里就显示那一格的键帽，拿在手里显示“手里”，收集品显示数量。
## 悬停：往右滑一点、变暖金色、左边出现小菱形、下面画出一条细线。
## 点一下 = 拿起 / 收起；可以拖到快捷栏；指着它按 1-4 = 放进那一格（inventory.gd 处理）。

const CREAM := Color(0.984, 0.957, 0.902)
const GOLD := Color(0.925, 0.780, 0.500)
const SHADOW := Color(0.02, 0.05, 0.06)
const ROW_H := 54.0
const VALUE_X := 330.0
const FONT_SIZE := 23

var inv
var item := ""
var count := -1
var delay := 0.0
var target := 1.0
var reveal := 0.0

var _hl := 0.0
var _hovering := false
var _press := 0.0
var _key: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = Vector2(VALUE_X + 110.0, ROW_H)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	_key = StyleBoxFlat.new()
	_key.draw_center = false
	_key.set_border_width_all(1)
	_key.set_corner_radius_all(4)
	_key.anti_aliasing = true


func _on_enter() -> void:
	_hovering = true
	if inv:
		inv.on_hover(self, true)


func _on_exit() -> void:
	_hovering = false
	if inv:
		inv.on_hover(self, false)


func _process(delta: float) -> void:
	if delay > 0.0 and target > 0.5:
		delay -= delta
	else:
		reveal = move_toward(reveal, target, delta / (0.5 if target > 0.5 else 0.18))
	mouse_filter = Control.MOUSE_FILTER_STOP if (target > 0.5 and reveal > 0.4) else Control.MOUSE_FILTER_IGNORE
	_hl = lerpf(_hl, 1.0 if _hovering else 0.0, clampf(delta * 14.0, 0.0, 1.0))
	_press = move_toward(_press, 0.0, delta * 4.0)
	queue_redraw()


func _text(f: Font, pos: Vector2, s: String, sz: int, col: Color) -> void:
	draw_string(f, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(SHADOW, col.a * 0.28))
	draw_string(f, pos + Vector2(0, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(SHADOW, col.a * 0.22))
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _draw() -> void:
	var r := clampf(reveal, 0.0, 1.0)
	var a := r * r * (3.0 - 2.0 * r)
	if a <= 0.002 or inv == null:
		return
	var hl := _hl * _hl * (3.0 - 2.0 * _hl)
	var x0 := 28.0 - 30.0 * (1.0 - a) + 14.0 * hl - 3.0 * _press
	var cy := ROW_H * 0.5
	var f: Font = Settings.font_ui
	var fl: Font = Settings.font_light
	var dim := 0.45 if count == 0 else 1.0

	if hl > 0.01:
		var dc := Vector2(x0 - 18.0, cy)
		var s := maxf(4.5 * hl, 0.6)
		draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -s), dc + Vector2(s, 0), dc + Vector2(0, s), dc + Vector2(-s, 0)]), Color(GOLD, a * hl))

	var tex: Texture2D = inv.icon(item)
	if tex:
		var isz := 38.0 + 3.0 * hl
		draw_texture_rect(tex, Rect2(Vector2(x0, cy - isz * 0.5), Vector2(isz, isz)), false, Color(1, 1, 1, a * dim))
	var lx := x0 + 52.0
	var name: String = inv.ITEMS[item].name
	var col := CREAM.lerp(Color(1.0, 0.90, 0.70), hl)
	col.a = a * lerpf(0.86, 1.0, hl) * dim
	var by := cy + (f.get_ascent(FONT_SIZE) - f.get_descent(FONT_SIZE)) * 0.5
	_text(f, Vector2(lx, by), name, FONT_SIZE, col)
	var tw := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	if hl > 0.01:
		draw_line(Vector2(lx, by + 10.0), Vector2(lx + tw * hl, by + 10.0), Color(GOLD, 0.85 * a * hl), 1.5, true)

	# 右边的状态
	var vx := VALUE_X + 30.0 * (1.0 - a)
	var vy := cy + (fl.get_ascent(17) - fl.get_descent(17)) * 0.5
	if count >= 0:
		_text(fl, Vector2(vx, vy), "× %d" % count, 17, Color(CREAM, 0.8 * a * dim))
		return
	var k: int = inv.slot_of(item)
	var held: bool = inv.hero.held == item
	if k >= 0:
		var kr := Rect2(vx, cy - 11.0, 22.0, 22.0)
		_key.border_color = Color(GOLD if held else CREAM, (0.9 if held else 0.55) * a)
		draw_style_box(_key, kr)
		var t := str(k + 1)
		var kw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(f, Vector2(kr.get_center().x - kw * 0.5, kr.position.y + 16.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(GOLD if held else CREAM, 0.95 * a))
	else:
		_text(fl, Vector2(vx + 4.0, vy), "—", 17, Color(CREAM, 0.35 * a))
	if held:
		_text(fl, Vector2(vx + 34.0, vy), "手里", 15, Color(GOLD, 0.95 * a))


func _gui_input(event: InputEvent) -> void:
	if target < 0.5 or inv == null:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and inv.is_tool(item):
		_press = 1.0
		inv.equip(item)
		accept_event()


func _get_drag_data(_at: Vector2):
	if inv == null or not inv.bag_open or not inv.is_tool(item):
		return null
	set_drag_preview(inv.drag_preview(item))
	return {"item": item, "from": "bag", "index": -1}


func _can_drop_data(_at: Vector2, data) -> bool:
	return inv != null and inv.bag_open and typeof(data) == TYPE_DICTIONARY and data.get("from", "") == "hot"


func _drop_data(_at: Vector2, data) -> void:
	inv.on_drop(self, data)
