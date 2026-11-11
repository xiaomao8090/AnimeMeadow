extends Node
## 全局设置（Autoload，名字叫 Settings）。存在 user://settings.cfg，下次启动自动读回来。
## 也负责菜单用的字体（直接用系统里的思源 / 微软雅黑，不用往项目里拷字体文件）。

const PATH := "user://settings.cfg"
const GRASS_AMOUNTS := [4000, 8000, 13000]     # 无限草原每 20x20 米的草叶数：低 / 中 / 高

var world_seed := 0          # 无限草原的种子；每次启动游戏随机一个，菜单里可以换
var mouse_sens := 1.0        # 倍率
var fov := 75.0
var volume := 0.8
var grass := 1               # 0 低 / 1 中 / 2 高
var fullscreen := false
var tips := true             # 游玩时偶尔出现的小提示（tips.gd）
var skip_intro := false      # 换地图 / 换种子重新加载时，开场动画放快一点

var font_title: Font         # 标题用的衬线字体
var font_ui: Font            # 菜单文字
var font_light: Font         # 小字


func _ready() -> void:
	font_title = _font(["Noto Serif SC", "Source Han Serif SC", "Songti SC", "SimSun"], 600)
	font_ui = _font(["Noto Sans SC", "Source Han Sans SC", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC"], 450)
	font_light = _font(["Noto Sans SC", "Source Han Sans SC", "Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC"], 350)
	load_settings()
	world_seed = randi() % 2000000000
	apply()


func _font(names: Array, weight: int) -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(names)
	sf.font_weight = weight
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	sf.hinting = TextServer.HINTING_LIGHT
	sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	sf.multichannel_signed_distance_field = false
	# 可变字体（Noto Sans/Serif SC 是）要手动指定字重
	var fv := FontVariation.new()
	fv.base_font = sf
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	return fv


func grass_amount() -> int:
	return GRASS_AMOUNTS[clampi(grass, 0, 2)]


func apply() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, volume <= 0.001)
	# 全屏：先确保窗口没被最大化 / 最小化，再切；切完如果系统没照做（比如窗口被嵌在编辑器里），打印一句提示
	var win := get_window()
	var want := Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	if fullscreen and win.mode != Window.MODE_FULLSCREEN and win.mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
		win.mode = Window.MODE_FULLSCREEN
	elif not fullscreen and (win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN):
		win.mode = Window.MODE_WINDOWED
	if fullscreen and win.mode != want and win.mode != Window.MODE_EXCLUSIVE_FULLSCREEN:
		print("全屏没有生效：如果游戏画面嵌在 Godot 编辑器里，请在编辑器的 游戏 面板关掉“嵌入游戏”，或者用导出的 exe 运行")


## F11：随时切换全屏
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).physical_keycode == KEY_F11:
		fullscreen = not fullscreen
		apply()
		save_settings()


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	mouse_sens = cf.get_value("game", "mouse_sens", mouse_sens)
	fov = cf.get_value("game", "fov", fov)
	volume = cf.get_value("audio", "volume", volume)
	grass = cf.get_value("video", "grass", grass)
	fullscreen = cf.get_value("video", "fullscreen", fullscreen)
	tips = cf.get_value("game", "tips", tips)


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "mouse_sens", mouse_sens)
	cf.set_value("game", "fov", fov)
	cf.set_value("audio", "volume", volume)
	cf.set_value("video", "grass", grass)
	cf.set_value("video", "fullscreen", fullscreen)
	cf.set_value("game", "tips", tips)
	cf.save(PATH)
