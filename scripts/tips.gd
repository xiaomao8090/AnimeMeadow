extends Node
## 游玩时偶尔冒出来的小提示（用 notice.gd 的白字，慢慢飘散）。
## - 只提示还没用过的功能：按过的键会记下来（M 看过地图就不再提示地图）
## - 看情况：附近有兔子才提示胡萝卜，走到池塘边才提示钓鱼，晚上才提示快进时间……
## - 也有一些小细节（站着不动会东张西望、晚上有萤火虫……）
## - 不刷屏：进游戏 20 秒后第一条，之后每 90-150 秒一条；开着背包 / 地图 / 暂停 / 正在摸动物 / 屏幕上已经有提示时不出
## - 有用的提示每条只出一次，小细节最多两次；记录存在 user://tips.cfg（下次打开游戏不会从头再来一遍）
## - 设置里可以关掉（Settings.tips）

const SAVE_PATH := "user://tips.cfg"
const FIRST_DELAY := 20.0
const GAP_MIN := 90.0
const GAP_MAX := 150.0
const MAX_SHOWN := 2

var boot
var world
var player
var hero
var _used := {}            # 用过的功能
var _shown := {}           # 提示 id -> 出现过几次
var _wait := FIRST_DELAY
var _moved_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(b) -> void:
	boot = b
	world = b.world
	player = world.player
	hero = player.hero
	_rng.randomize()
	_load()


func _input(event: InputEvent) -> void:
	# 只是记下来，不拦截
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		var names := {KEY_M: "map", KEY_B: "bag", KEY_V: "view", KEY_T: "time", KEY_E: "pet",
			KEY_SHIFT: "run", KEY_SPACE: "jump", KEY_F11: "fullscreen"}
		if names.has(k):
			_use(names[k])
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_use("zoom")


func _use(what: String) -> void:
	if not _used.has(what):
		_used[what] = true
		_save()


func _process(delta: float) -> void:
	if world == null or not Settings.tips:
		return
	if not _playing():
		return
	var v: Vector3 = player.velocity
	if Vector2(v.x, v.z).length() > 0.5:
		_moved_t += delta
	_wait -= delta
	if _wait > 0.0:
		return
	if _busy():
		_wait = 4.0          # 现在不方便，过一会儿再看
		return
	var tip := _pick()
	if tip.is_empty():
		_wait = 60.0
		return
	var n := get_tree().get_first_node_in_group("notice")
	if n:
		n.say(tip.text, 4.2)
	_shown[tip.id] = int(_shown.get(tip.id, 0)) + 1
	_save()
	_wait = _rng.randf_range(GAP_MIN, GAP_MAX)


func _playing() -> bool:
	var m = boot.get("menu")
	return m != null and str(m.state) == "game" and player.active and not get_tree().paused


func _busy() -> bool:
	var inv := get_tree().get_first_node_in_group("inventory")
	if inv and inv.is_open():
		return true
	var bm := get_tree().get_first_node_in_group("bigmap")
	if bm and bm.is_open():
		return true
	if hero.is_acting() or hero.busy:
		return true
	var n := get_tree().get_first_node_in_group("notice")
	if n and not n._msgs.is_empty():
		return true
	return false


func _key(item: String) -> String:
	var inv := get_tree().get_first_node_in_group("inventory")
	return inv.key_for(item) if inv else "B"


func _hold_hint(item: String, name: String) -> String:
	var k := _key(item)
	return ("按 %s 拿出%s" % [k, name]) if k != "B" else ("按 B 打开背包，把%s放进快捷栏" % name)


## 挑一条：先看“有用又没用过”的，再看小细节；同一优先级里随机
func _pick() -> Dictionary:
	var p: Vector3 = player.global_position
	var p2 := Vector2(p.x, p.z)
	var near_rabbit := false
	var near_deer := false
	var has_friend := false
	for a in get_tree().get_nodes_in_group("pettable"):
		var n := a as Node3D
		if n == null or not n.is_inside_tree():
			continue
		var d := Vector2(n.global_position.x, n.global_position.z).distance_to(p2)
		if d < 22.0:
			if n.food() == "carrot":
				near_rabbit = true
			else:
				near_deer = true
		if float(n.get("friend_t")) > 0.0:
			has_friend = true
	var near_pond: bool = world.water_level > -500.0 and p2.distance_to(world.POND_CENTER) < 35.0
	var night: float = world.day_night.night if world.day_night else 0.0

	var useful: Array = []
	if _moved_t < 1.0:
		useful.append({"id": "move", "text": "WASD 走动  ·  按住 Shift 跑起来"})
	if not _used.has("map"):
		useful.append({"id": "map", "text": "按 M 打开地图  ·  走过的地方会被点亮"})
	if not _used.has("bag"):
		useful.append({"id": "bag", "text": "按 B 打开背包  ·  可以把东西拖到下面的快捷栏"})
	if near_rabbit and not _used.has("pet") and hero.held != "carrot":
		useful.append({"id": "rabbit", "text": "附近有兔子  ·  %s，慢慢走过去" % _hold_hint("carrot", "胡萝卜")})
	if near_deer and not _used.has("pet") and hero.held != "berry":
		useful.append({"id": "deer", "text": "附近有小鹿  ·  %s，它会走过来" % _hold_hint("berry", "浆果")})
	if near_pond and int(hero.caught_fish) == 0 and hero.held != "rod":
		useful.append({"id": "fish", "text": "前面有池塘  ·  %s，走到水边左键甩竿" % _hold_hint("rod", "钓鱼竿")})
	if int(hero.caught_bugs) == 0 and hero.held != "net" and _moved_t > 60.0:
		useful.append({"id": "net", "text": "花丛里有蝴蝶  ·  %s，左键挥网" % _hold_hint("net", "捕虫网")})
	if night > 0.5 and not _used.has("time"):
		useful.append({"id": "time", "text": "天黑了  ·  按住 T，时间会过得快一点"})
	if not _used.has("view"):
		useful.append({"id": "view", "text": "按 V 切换第一人称"})
	if not _used.has("zoom") and player.third_person:
		useful.append({"id": "zoom", "text": "鼠标滚轮可以把镜头拉远拉近"})
	if not _used.has("jump"):
		useful.append({"id": "jump", "text": "空格跳一下  ·  陡坡顶着往前走可以爬上去"})

	var details: Array = [
		{"id": "idle", "text": "站着不动一会儿，小家伙会自己东张西望、伸懒腰"},
		{"id": "tired", "text": "跑久了会累  ·  停下来让它喘口气"},
		{"id": "fullscreen", "text": "按 F11 切换全屏"},
		{"id": "settings", "text": "Esc 暂停  ·  设置里可以调鼠标灵敏度和视野"},
	]
	if night > 0.3:
		details.append({"id": "firefly", "text": "晚上草丛里会有萤火虫"})
	if has_friend:
		details.append({"id": "friend", "text": "地图上的小爱心是你的动物朋友"})
	if _used.has("pet"):
		details.append({"id": "friend_follow", "text": "摸过的小动物会跟着你走一会儿"})

	for group in [useful, details]:
		var ok: Array = []
		for t in group:
			if int(_shown.get(t.id, 0)) < MAX_SHOWN and (int(_shown.get(t.id, 0)) == 0 or group == details):
				ok.append(t)
		# 没出现过的优先
		var fresh: Array = ok.filter(func(t): return int(_shown.get(t.id, 0)) == 0)
		if not fresh.is_empty():
			return fresh[_rng.randi() % fresh.size()]
		if not ok.is_empty():
			return ok[_rng.randi() % ok.size()]
	return {}


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		_used = cf.get_value("tips", "used", {})
		_shown = cf.get_value("tips", "shown", {})


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("tips", "used", _used)
	cf.set_value("tips", "shown", _shown)
	cf.save(SAVE_PATH)
