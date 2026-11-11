extends Control
## 快捷栏的一格：不画格子，只有一个浮着的图标 + 下面一小团柔和的影子 + 按键数字。
## 没选中：小一点、淡一点；选中：抬起来、放大、变亮，数字变金色，下面多一个金色小菱形。
## 背包开着时可以把物品拖到这里（或者在两格之间拖动互换）。

const Fx := preload("res://scripts/fx.gd")
const CREAM := Color(0.984, 0.957, 0.902)
const GOLD := Color(0.925, 0.780, 0.500)
const SHADOW := Color(0.0, 0.03, 0.04)
const W := 62.0
const H := 78.0

var inv
var role := "hot"
var index := 0
var item := ""
var selected := false

var _sel := 0.0
var _hover := 0.0
var _hovering := false
var _pop := 0.0
var _drop := 0.0              # 拖着东西经过这一格时亮一下


func _ready() -> void:
	size = Vector2(W, H)
	custom_minimum_size = size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_entered.connect(func(): _hovering = true)
	mouse_exited.connect(func(): _hovering = false)


func set_item(it: String) -> void:
	if it != item:
		_pop = 1.0
	item = it


func _process(delta: float) -> void:
	_sel = move_toward(_sel, 1.0 if selected else 0.0, delta * 6.0)
	_hover = move_toward(_hover, 1.0 if _hovering else 0.0, delta * 8.0)
	_pop = move_toward(_pop, 0.0, delta * 3.0)
	var dragging := get_viewport().gui_is_dragging() and _hovering
	_drop = move_toward(_drop, 1.0 if dragging else 0.0, delta * 8.0)
	queue_redraw()


func _draw() -> void:
	var e := _sel * _sel * (3.0 - 2.0 * _sel)
	var lift := 7.0 * e + 2.0 * _hover
	var s := 0.86 + 0.18 * e + 0.05 * _hover + 0.12 * sin(_pop * PI)
	var c := Vector2(W * 0.5, 30.0 - lift)
	var dot := Fx.dot_texture()
	# 地上的小影子：抬得越高越淡、越小
	var sw := 40.0 - 8.0 * e
	draw_texture_rect(dot, Rect2(Vector2(W * 0.5 - sw * 0.5, 47.0), Vector2(sw, 9.0)), false, Color(SHADOW, 0.32 - 0.12 * e))
	if _drop > 0.01:
		draw_arc(Vector2(W * 0.5, 30.0), 27.0, 0, TAU, 48, Color(GOLD, 0.7 * _drop), 1.5, true)
	if item != "" and inv:
		var tex: Texture2D = inv.icon(item)
		if tex:
			var isz := 46.0 * s
			var a := 0.72 + 0.28 * maxf(e, _hover)
			draw_texture_rect(tex, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, a))
	else:
		draw_arc(Vector2(W * 0.5, 30.0), 6.0, 0, TAU, 24, Color(CREAM, 0.3), 1.2, true)
	# 按键数字（选中时变金，下面加小菱形）
	var f: Font = Settings.font_ui
	var t := str(index + 1)
	var tw := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var col := CREAM.lerp(GOLD, e)
	draw_string(f, Vector2(W * 0.5 - tw * 0.5, 69.0 + 1.5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(SHADOW, 0.4))
	draw_string(f, Vector2(W * 0.5 - tw * 0.5, 69.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(col, 0.6 + 0.4 * e))
	if e > 0.01:
		var dc := Vector2(W * 0.5, 76.0)
		var ds := 3.0 * e
		draw_colored_polygon(PackedVector2Array([dc + Vector2(0, -ds), dc + Vector2(ds, 0), dc + Vector2(0, ds), dc + Vector2(-ds, 0)]), Color(GOLD, e))


# ───────────────────────── 拖放 ─────────────────────────

func _get_drag_data(_at: Vector2):
	if inv == null or not inv.bag_open or item == "":
		return null
	set_drag_preview(inv.drag_preview(item))
	return {"item": item, "from": "hot", "index": index}


func _can_drop_data(_at: Vector2, data) -> bool:
	return inv != null and inv.bag_open and typeof(data) == TYPE_DICTIONARY and data.has("item") and inv.is_tool(data.item)


func _drop_data(_at: Vector2, data) -> void:
	inv.on_drop(self, data)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and inv and inv.bag_open:
		inv.press_slot(index)
