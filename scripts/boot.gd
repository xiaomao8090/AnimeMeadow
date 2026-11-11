extends Node3D
## 游戏入口（main.tscn 的根节点）。
## 先显示加载界面（loading.gd），它在后台加载资源、再调 build_world() 生成无限草原（world.gd）
## 并叠上互动提示和主菜单，等地图全部生成完才淡出进入大厅。
## 换种子 = 改 Settings 后重新加载这个场景（会再走一遍加载界面）。

var world: Node3D
var menu: CanvasLayer
var keep: Array = []        # 加载界面预先加载的资源，留着引用，后面再 load() 就是直接拿缓存


func _ready() -> void:
	var loader := CanvasLayer.new()
	loader.name = "Loading"
	loader.set_script(load("res://scripts/loading.gd"))
	add_child(loader)
	loader.run(self)


func build_world() -> void:
	world = Node3D.new()
	world.name = "World"
	world.set_script(load("res://scripts/world.gd"))
	world.set("random_seed", false)
	world.set("world_seed", Settings.world_seed)
	world.set("grass_per_chunk", Settings.grass_amount())
	add_child(world)

	var notice := CanvasLayer.new()
	notice.name = "Notice"
	notice.set_script(load("res://scripts/notice.gd"))
	add_child(notice)

	var inter := CanvasLayer.new()
	inter.name = "Interact"
	inter.set_script(load("res://scripts/interact.gd"))
	add_child(inter)
	inter.setup(world)

	var inv := CanvasLayer.new()
	inv.name = "Inventory"
	inv.set_script(load("res://scripts/inventory.gd"))
	add_child(inv)
	inv.setup(world)

	menu = CanvasLayer.new()
	menu.name = "Menu"
	menu.set_script(load("res://scripts/main_menu.gd"))
	menu.set("hold_intro", true)      # 等加载界面放行
	add_child(menu)
	menu.setup(world)

	var tips := Node.new()
	tips.name = "Tips"
	tips.set_script(load("res://scripts/tips.gd"))
	add_child(tips)
	tips.setup(self)
