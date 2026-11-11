extends CanvasLayer
## 和小动物互动：走到兔子 / 小鹿跟前，它头顶会浮出一个小提示「E 摸一摸」（手里拿着它爱吃的东西时是「E 喂一喂」），
## 按 E：角色转身蹲下（小鹿就踮脚伸手），一下一下地摸，眯眼享受；动物凑过来蹭手、耳朵放松往后贴；
## 摸的时候冒小爱心，最后“啵”地弹出一颗大爱心 + 闪光，兔子开心地原地扭身蹦一下（binky），小鹿甩甩头。
## 摸过 / 喂过的动物会成为朋友：一段时间里不怕你，跟着你走，偶尔冒个小爱心。
## 动物太怕人靠不近时，会提示一次「拿着胡萝卜 / 浆果慢慢走过去」。

const Fx := preload("res://scripts/fx.gd")
const FOOD_NAME := {"carrot": "胡萝卜", "berry": "浆果"}
const FOOD_KEY := {"carrot": "1", "berry": "2"}
const FOOD_COLOR := {"carrot": Color(1.0, 0.55, 0.18), "berry": Color(0.62, 0.25, 0.62)}

var world
var player
var hero
var _ui: Control
var _target: Node3D               # 现在提示的那只
var _partner: Node3D              # 正在摸 / 喂的那只
var _feeding := false
var _alpha := 0.0
var _pop := 0.0
var _label := ""
var _screen := Vector2.ZERO
var _shown_target: Node3D        # 正在画提示的那只（消失动画时 _target 已经是空的）
var _hint_t := 0.0
var _hinted := {}
var _key: StyleBoxFlat


func setup(w) -> void:
	world = w
	player = w.player
	hero = player.hero
	layer = 20
	hero.act_beat.connect(_on_beat)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)
	_key = StyleBoxFlat.new()
	_key.draw_center = false
	_key.set_border_width_all(1)
	_key.set_corner_radius_all(5)
	_key.anti_aliasing = true


func _playing() -> bool:
	return player.active and not get_tree().paused


func _process(delta: float) -> void:
	var cand: Node3D = null
	if _playing() and not hero.is_acting() and player.is_on_floor():
		cand = _find_target()
	if cand != _target:
		_target = cand
		if cand:
			_pop = 1.0
			if _shown_target != cand:
				_screen = Vector2.ZERO
			_shown_target = cand
	if _target:
		_feeding = hero.held != "" and hero.held == _target.food()
		_label = "喂一喂" if _feeding else "摸一摸"
	_alpha = move_toward(_alpha, 1.0 if _target else 0.0, delta * (3.0 if _target else 1.6))
	_pop = move_toward(_pop, 0.0, delta * 3.5)

	# 靠不近的提示：附近有动物在躲你，手里又没拿它爱吃的
	_hint_t -= delta
	if _playing() and _hint_t <= 0.0:
		_hint_t = 0.5
		var shy := _find_shy()
		if shy and not _hinted.has(shy.food()) and hero.held == "":
			_hinted[shy.food()] = true
			var f: String = shy.food()
			var n := get_tree().get_first_node_in_group("notice")
			if n:
				var inv := get_tree().get_first_node_in_group("inventory")
				var k: String = inv.key_for(f) if inv else FOOD_KEY[f]
				var how := ("按 %s 拿出%s" % [k, FOOD_NAME[f]]) if k != "B" else ("按 B 打开背包，把%s放进快捷栏" % FOOD_NAME[f])
				n.say("%s有点怕你  ·  %s，慢慢走过去" % ["兔子" if f == "carrot" else "小鹿", how], 4.0)
	_ui.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if (event as InputEventKey).physical_keycode != KEY_E or not _playing():
		return
	if _target == null or hero.is_acting():
		return
	_partner = _target
	_feeding = hero.held != "" and hero.held == _partner.food()
	var act := "feed" if _feeding else "pet"
	hero.play_act(act, _partner.head_pos(), _partner.is_tall())
	_partner.on_pet(player, _feeding, float(hero.ACTS[act]))
	player.velocity = Vector3(0, player.velocity.y, 0)
	_target = null
	get_viewport().set_input_as_handled()


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_d := INF
	var p: Vector3 = player.global_position
	for a in get_tree().get_nodes_in_group("pettable"):
		var n := a as Node3D
		if n == null or not n.is_inside_tree() or not n.can_pet():
			continue
		var d := Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length()
		if d < float(n.pet_range()) and d < best_d:
			best = n
			best_d = d
	return best


func _find_shy() -> Node3D:
	var p: Vector3 = player.global_position
	for a in get_tree().get_nodes_in_group("pettable"):
		var n := a as Node3D
		if n == null or not n.is_inside_tree():
			continue
		if n.is_shy() and Vector2(n.global_position.x - p.x, n.global_position.z - p.z).length() < 10.0:
			return n
	return null


# ───────────────────────── 特效节拍 ─────────────────────────

func _on_beat(act: String, beat: String) -> void:
	if act != "pet" and act != "feed":
		return
	if _partner == null or not is_instance_valid(_partner):
		return
	var head: Vector3 = _partner.head_pos()
	var hand: Vector3 = hero.global_position.lerp(head, 0.6) + Vector3(0, 0.1, 0)
	match beat:
		"touch":
			Fx.sparkles(world, head + Vector3(0, 0.12, 0), 6, 0.12, 0.8)
		"offer":
			Fx.sparkles(world, hand, 6, 0.1, 0.8)
		"stroke1", "stroke2":
			Fx.hearts(world, head + Vector3(0, 0.15, 0), 2, 0.8)
		"nom1", "nom2":
			Fx.crumbs(world, head + Vector3(0, -0.02, 0), FOOD_COLOR.get(hero.held, Color(0.9, 0.8, 0.5)))
			Fx.hearts(world, head + Vector3(0, 0.15, 0), 1, 0.7)
		"love":
			var big := 0.42 if _partner.is_tall() else 0.34
			Fx.heart_pop(world, head + Vector3(0, 0.35 if _partner.is_tall() else 0.28, 0), big)
			Fx.hearts(world, head + Vector3(0, 0.2, 0), 7, 1.0)
			Fx.heart_pop(world, hero.global_position + Vector3(0, 1.75, 0), 0.18, false)
			if _feeding:
				hero.hold("")          # 吃掉了
		"end":
			if is_instance_valid(_partner):
				_partner.on_pet_end()
			_partner = null


# ───────────────────────── 提示 ─────────────────────────
## 动物头顶的小提示：白色描边的键帽 + 白字，带柔和投影，没有底框；出现时浮上来，离开时往上飘着淡掉

func _draw_ui() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _alpha <= 0.003 or _shown_target == null or not is_instance_valid(_shown_target):
		return
	var font: Font = Settings.font_ui
	var wp: Vector3 = _shown_target.head_pos() + Vector3(0, 0.42 if _shown_target.is_tall() else 0.38, 0)
	if not cam.is_position_behind(wp):
		var sp := cam.unproject_position(wp)
		_screen = sp if _screen == Vector2.ZERO else _screen.lerp(sp, 0.5)
	var a := _alpha * _alpha * (3.0 - 2.0 * _alpha)
	var leaving := _target == null
	var rise := (1.0 - a) * (14.0 if leaving else -8.0)          # 出现：从下面浮上来；消失：往上飘走
	var bob := sin(Time.get_ticks_msec() * 0.003) * 2.0
	var c := _screen + Vector2(0, -rise + bob)
	var ls := 18
	var tw := font.get_string_size(_label, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
	var kw := 24.0
	var w := kw + 10.0 + tw
	var x0 := c.x - w * 0.5
	var mid := c.y - 14.0
	# 键帽：白色细描边的圆角方块
	var kr := Rect2(x0, mid - 12.0, kw, 24.0)
	_key.bg_color = Color(1, 1, 1, 0.0)
	_key.border_color = Color(0, 0.03, 0.04, 0.22 * a)
	_key.draw(_ui.get_canvas_item(), Rect2(kr.position + Vector2(0, 1.5), kr.size))
	_key.border_color = Color(1, 1, 1, 0.9 * a)
	_key.draw(_ui.get_canvas_item(), kr)
	var ks := 14
	var ew := font.get_string_size("E", HORIZONTAL_ALIGNMENT_LEFT, -1, ks).x
	var kb := mid + (font.get_ascent(ks) - font.get_descent(ks)) * 0.5
	_white(font, Vector2(kr.get_center().x - ew * 0.5, kb), "E", ks, a)
	var lb := mid + (font.get_ascent(ls) - font.get_descent(ls)) * 0.5
	_white(font, Vector2(kr.end.x + 10.0, lb), _label, ls, a)


func _white(f: Font, pos: Vector2, s: String, size: int, a: float) -> void:
	_ui.draw_string(f, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0.03, 0.04, 0.32 * a))
	_ui.draw_string(f, pos + Vector2(0, 4), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0.03, 0.04, 0.12 * a))
	_ui.draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.97 * a))
