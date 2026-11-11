extends Node3D
## 无限地图：地形、树、石头、花、草、池塘都按区块在后台线程里生成，玩家走到哪生成到哪，走远的卸掉。
## 整个世界由一个种子决定：同一个种子 + 同一个位置，永远生成同样的东西（和我的世界一样）。
## 模型和贴图都是代码生成的（只有 audio/ 里的声音是外部文件）。改下面的参数再运行即可。
##
## 其它脚本：day_night.gd 昼夜和天空 / life.gd 花瓣、光点、蝴蝶 / ambience.gd 声音 / player.gd 移动

const CHUNK := 80.0                 # 地形区块边长（米）
const GCHUNK := 20.0                # 草的区块边长（一个地形区块 = 4x4 个草区块）
const CELL := 2.0                   # 最精细一档地形的格子大小
const VIEW_CHUNKS := 12             # 地形能看多远（区块数，12 ≈ 1 公里）
const DECO_CHUNKS := 3              # 树 / 石头 / 花生成到多远（区块数）
const POND_CELL := 320.0            # 每 320x320 米的格子里最多一个池塘
const POND_RADIUS := 10.0
const POND_DEPTH := 0.9
const WIND_DIR := Vector2(1.0, 0.35)
const CORE_SCALE := 0.55           # 树冠里填缝的芯相对叶片层的大小，要小一圈，免得露出来（露出来像树里塞了块石头）
const TREE_LINE := 95.0            # 高过这里不长树
const GRASS_LINE := 105.0          # 高过这里草开始变稀，再往上是岩石和雪

# 草的远近过渡：fade_start 米内是满密度，到 fade_end 米降到 min_density，再远缩回地面
const GRASS_FADE_START := 28.0
const GRASS_FADE_END := 72.0
const GRASS_MIN_DENSITY := 0.3

const PUSH_N := 24                  # 要和 push.gdshaderinc 里的数组长度一致
const PUSH_SPACING := 0.35          # 每走这么远留一个脚印（回弹的快慢在 push.gdshaderinc 里调）

# 雪地 / 沙地的脚印：一张跟着玩家走的贴图（每像素 6 厘米，覆盖约 61 米见方），踩一步就在上面印一个脚印；
# 玩家走出中心 15 米时整张图平移重新居中（移出范围的旧脚印就没了）。terrain.gdshader 读它画出凹下去的脚印
const TRAIL_RES := 1024
const TRAIL_PX := 0.06

@export var random_seed := true             # true = 每次启动换一个新种子，地图都不一样；false = 用下面的固定种子
@export var world_seed := 20261110
@export var grass_per_chunk := 8000         # 每块 20x20 米的草叶数量，卡就调低
@export var grass_view_distance := 85.0     # 草的可见距离
# 下面四个是"每 160x160 米"的数量（沿用原来小地图的手感）
@export var tree_count := 55
@export var bush_count := 70
@export var rock_group_count := 18
@export var pebble_count := 500
@export var flower_count := 5000

var hill_noise := FastNoiseLite.new()
var detail_noise := FastNoiseLite.new()
var patch_noise := FastNoiseLite.new()
var range_noise := FastNoiseLite.new()      # 哪里是草原、哪里是山区
var mountain_noise := FastNoiseLite.new()   # 山区里哪里是高峰、哪里是垭口
var ridge_noise := FastNoiseLite.new()      # 山脊
var dirt_noise := FastNoiseLite.new()
var path_noise := FastNoiseLite.new()       # 小路 = 这张噪声图的等高线，所以会无限延伸、自然弯曲
var flat_noise := FastNoiseLite.new()       # 哪里是平坦的大平原、哪里是缓缓起伏的丘陵
var temp_noise := FastNoiseLite.new()       # 群系：温度
var humid_noise := FastNoiseLite.new()      # 群系：湿度
var dune_noise := FastNoiseLite.new()       # 沙漠里的沙丘
var ice_noise := FastNoiseLite.new()        # 冰原上哪里是冰面
var warp_noise := FastNoiseLite.new()       # 把群系边界扭成弯弯曲曲的形状（不是一条顺滑的线）

var POND_CENTER := Vector2(1e6, 1e6)        # 离玩家最近的池塘（没有就在很远的地方）；ambience.gd 也会读
var water_level := -1000.0
var flower_centers: Array[Vector3] = []     # 已加载的花丛中心，life.gd 的蝴蝶用
var tree_positions: Array[Vector2] = []     # 已加载的树的 xz 位置，ambience.gd 用它算树叶沙沙声
var spawn := Vector3.ZERO
var biome_name := ""                        # 玩家现在所在的群系（中文名），进入新群系时屏幕上提示一次
var _biome_timer := 0.0
var _snow_k := 0.0
var _snow_k_raw := 0.0
var on_ice := false
var trail_img: Image
var trail_tex: ImageTexture
var trail_origin := Vector2i.ZERO   # 贴图左上角对应的世界坐标（单位：像素格）
var _trail_dirty := false
var _trail_foot := 1.0              # 左右脚交替
var drift_mesh: ArrayMesh
var _puffs: Array[CPUParticles3D] = []    # 踩雪溅起的雪沫（轮流用）
var _puff_i := 0
var _breaths: Array[CPUParticles3D] = []  # 雪原里呼出的白气
var _breath_i := 0
var _breath_t := 2.0
var _winter := 0.0
var _sink := 0.0
var drift_mat: ShaderMaterial

var chunks := {}        # Vector2i -> 地形区块记录
var gchunks := {}       # Vector2i -> 草区块记录
var _pond_cache := {}   # Vector2i -> Vector4(x, z, 岸的高度, 有没有)
var _task_ids := {}
var _job_seq := 0
var _jobs := 0
var _max_jobs := 4
var _quitting := false
var _stream_timer := 0.0
var _lod_timer := 0.0
var _hud_timer := 0.0
var _pond_timer := 0.0
var _lists_dirty := false
var _push_pos := PackedVector3Array()
var _push_age := PackedFloat32Array()
var _push_last := Vector3.ZERO
var _push_i := 0
var _walktest := false
var _wt := 0.0

# 共用的网格和材质（只做一份，每个区块引用）
var terrain_mat: ShaderMaterial
var grass_mat: ShaderMaterial
var flower_mat: ShaderMaterial
var water_mat: ShaderMaterial
var pond_mats: Array[ShaderMaterial] = []
var blade_mesh: ArrayMesh
var flower_mesh: ArrayMesh
var trunk_mesh: CylinderMesh
var trunk_mat: ShaderMaterial
var core_mesh: ArrayMesh
var core_mat: ShaderMaterial
var card_mesh: ArrayMesh
var card_mat: ShaderMaterial
var rock_mat: ShaderMaterial
var rock_mats: Array[ShaderMaterial] = []   # 0 普通 / 1 雪地（顶上积雪）/ 2 沙漠砂岩
var ice_mat: ShaderMaterial
var cactus_mat: ShaderMaterial
var cactus_mesh: CapsuleMesh
var pebble_mat: ShaderMaterial
var rock_variants: Array[ArrayMesh] = []
var rock_points: Array[PackedVector3Array] = []

var player: CharacterBody3D
var hud_label: Label
var day_night
var life
var ambience

const GREENS: Array[Color] = [
	Color(0.36, 0.66, 0.26), Color(0.30, 0.60, 0.28), Color(0.46, 0.72, 0.28),
	Color(0.26, 0.56, 0.32), Color(0.52, 0.74, 0.30),
]
const BLOSSOMS: Array[Color] = [Color(1.0, 0.68, 0.78), Color(1.0, 0.80, 0.86)]
const SAKURA: Array[Color] = [Color(1.0, 0.72, 0.82), Color(1.0, 0.82, 0.88), Color(0.98, 0.64, 0.76), Color(1.0, 0.90, 0.93)]
const AUTUMN: Array[Color] = [
	Color(0.95, 0.52, 0.20), Color(0.90, 0.36, 0.18), Color(0.98, 0.72, 0.26),
	Color(0.80, 0.28, 0.20), Color(0.92, 0.62, 0.22),
]
const PINES: Array[Color] = [Color(0.16, 0.38, 0.34), Color(0.20, 0.42, 0.32), Color(0.14, 0.34, 0.36)]
const BIOME_NAMES := ["草原", "雪原", "沙漠", "秋林", "樱花林", "冰原"]
const FLOWER_COLORS: Array[Color] = [
	Color(1.0, 1.0, 1.0), Color(1.0, 0.88, 0.30), Color(1.0, 0.62, 0.76),
	Color(0.62, 0.78, 1.0), Color(0.80, 0.62, 1.0), Color(1.0, 0.50, 0.42),
]


func _ready() -> void:
	if random_seed:
		world_seed = randi() % 2000000000
	print("世界种子: ", world_seed, "（想再生成同一个世界：把 random_seed 关掉，world_seed 填这个数）")
	_walktest = OS.get_cmdline_user_args().has("--walktest")
	_max_jobs = clampi(OS.get_processor_count() - 2, 2, 8)
	_setup_noise()
	_init_assets()

	day_night = (load("res://scripts/day_night.gd") as GDScript).new()
	day_night.name = "DayNight"
	add_child(day_night)

	# 出生点：从原点往外找一块不在山里、不在池塘里的草地
	var sp := _find_spawn()
	spawn = Vector3(sp.x, 0.0, sp.y)
	# 出生点周围 3x3 个区块当场算好（要有地面可站），其余的交给后台线程
	var pc := _chunk_key(spawn)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := pc + Vector2i(dx, dz)
			_new_chunk(key, 0)
			_apply_terrain(key, 0, _compute_terrain(key, 0))
	spawn.y = get_height(spawn.x, spawn.z) + 0.05
	_spawn_player()
	_stream(spawn)

	life = (load("res://scripts/life.gd") as GDScript).new()
	life.name = "Life"
	add_child(life)
	life.setup(self)

	ambience = (load("res://scripts/ambience.gd") as GDScript).new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(self)

	var critters := Node3D.new()
	critters.name = "Critters"
	critters.set_script(load("res://scripts/critters.gd"))
	add_child(critters)
	critters.setup(self)

	_build_hud()


func _process(delta: float) -> void:
	if player == null:
		return
	var p := player.global_position
	_update_pushers(p, delta)

	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = 0.2
		_stream(p)
	if _lists_dirty:
		_lists_dirty = false
		_rebuild_lists()

	# 离玩家最近的池塘（蹚水、水声都用它）
	_pond_timer -= delta
	if _pond_timer <= 0.0:
		_pond_timer = 0.5
		var pond := pond_at(p.x, p.z)
		if pond.w > 0.5 and pond.w < 1.5:
			POND_CENTER = Vector2(pond.x, pond.y)
			water_level = pond.z - 0.3
		else:
			POND_CENTER = Vector2(p.x + 1e5, p.z + 1e5)
			water_level = -1000.0
		if ambience and ambience.get("water") != null:
			(ambience.water as Node3D).global_position = Vector3(POND_CENTER.x, water_level, POND_CENTER.y)
		# 万一走得比生成还快掉到了地面下面，把人放回地面
		var ground := height_raw(p.x, p.z)
		if p.y < ground - 4.0:
			player.global_position.y = ground + 0.5
			player.velocity = Vector3.ZERO

	# 在池塘里蹚水走得慢
	var wading := p.y < water_level - 0.03 and Vector2(p.x, p.z).distance_to(POND_CENTER) < POND_RADIUS + 1.0
	# 深雪里走得慢一点，脚陷进雪里几厘米；雪原里光线和雾变冷
	player.set("move_scale", 0.6 if wading else lerpf(1.0, 0.82, _snow_k))
	_sink = lerpf(_sink, 0.07 * _snow_k if player.is_on_floor() else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	player.set("sink", _sink)
	_winter = lerpf(_winter, _snow_k_raw, clampf(delta * 0.4, 0.0, 1.0))
	day_night.winter = _winter
	_update_breath(delta)
	_trail_update(p)

	# 冰面上很滑：加速和刹车都变慢；顺便看看是不是走进了新的群系
	_biome_timer -= delta
	if _biome_timer <= 0.0:
		_biome_timer = 0.25
		on_ice = ice_at(p.x, p.z) > 0.5 and player.is_on_floor()
		player.set("traction", 0.12 if on_ice else 1.0)
		_snow_k_raw = biome_w(p.x, p.z).r
		_snow_k = _snow_k_raw * (0.0 if on_ice else 1.0)
		var bi := biome_at(p.x, p.z)
		var nm: String = BIOME_NAMES[int(bi.x)]
		if bi.y > 0.7 and nm != biome_name:
			var first := biome_name == ""
			biome_name = nm
			var nt := get_tree().get_first_node_in_group("notice")
			if not first and nt and player.get("active") != false:
				nt.say(nm, 2.4)
	for m in pond_mats:
		m.set_shader_parameter("light_tint", day_night.light_tint)

	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_lod_timer = 0.15
		_update_grass_lod(p)

	_hud_timer -= delta
	if _hud_timer <= 0.0:
		_hud_timer = 0.5
		hud_label.text = day_night.clock_text()

	if _walktest:
		_run_walktest(delta)


## 草/花的碰撞：[0] 是玩家脚下，后面是一串刚走过的脚印，力度随时间衰减，草被踩倒后慢慢弹回来
func _update_pushers(p: Vector3, delta: float) -> void:
	if _push_pos.is_empty():
		_push_pos.resize(PUSH_N)
		_push_age.resize(PUSH_N)
		_push_age.fill(100.0)
		_push_last = p
	for i in range(1, PUSH_N):
		_push_age[i] += delta
	if player.is_on_floor() and Vector2(p.x - _push_last.x, p.z - _push_last.z).length() > PUSH_SPACING:
		_push_i = _push_i % (PUSH_N - 1) + 1
		# 脚印记在当前位置（这里的草正被玩家压着），从这一刻开始计时回弹，所以不会有跳变
		_push_pos[_push_i] = p
		_push_age[_push_i] = 0.0
		_push_last = p
	var arr := PackedVector4Array()
	arr.resize(PUSH_N)
	arr[0] = Vector4(p.x, p.y, p.z, 0.0)
	for i in range(1, PUSH_N):
		var q := _push_pos[i]
		arr[i] = Vector4(q.x, q.y, q.z, _push_age[i])   # w = 松开后过了几秒，回弹曲线在着色器里算
	grass_mat.set_shader_parameter("pushers", arr)
	flower_mat.set_shader_parameter("pushers", arr)


func _setup_noise() -> void:
	hill_noise.seed = world_seed
	hill_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hill_noise.frequency = 0.011
	hill_noise.fractal_octaves = 3
	detail_noise.seed = world_seed + 1
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	detail_noise.frequency = 0.045
	patch_noise.seed = world_seed + 2
	patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	patch_noise.frequency = 0.03
	# 山区的分布：很大的尺度，一片山区大约一公里宽，中间是开阔的草原
	range_noise.seed = world_seed + 6
	range_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	range_noise.frequency = 0.0011
	range_noise.fractal_octaves = 2
	# 山区内部：大轮廓决定哪里是高峰哪里是垭口，脊线噪声刻出山脊和山谷
	mountain_noise.seed = world_seed + 3
	mountain_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	mountain_noise.frequency = 0.0017
	ridge_noise.seed = world_seed + 4
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge_noise.fractal_octaves = 4
	ridge_noise.fractal_gain = 0.34
	ridge_noise.frequency = 0.0016
	dirt_noise.seed = world_seed + 5
	dirt_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dirt_noise.frequency = 0.05
	path_noise.seed = world_seed + 7
	path_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	path_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	path_noise.frequency = 0.0035
	flat_noise.seed = world_seed + 8
	flat_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	flat_noise.frequency = 0.0016
	temp_noise.seed = world_seed + 9
	temp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	temp_noise.frequency = 0.00032
	temp_noise.fractal_octaves = 3
	temp_noise.fractal_gain = 0.4
	humid_noise.seed = world_seed + 10
	humid_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	humid_noise.frequency = 0.00042
	humid_noise.fractal_octaves = 3
	humid_noise.fractal_gain = 0.4
	dune_noise.seed = world_seed + 12
	dune_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	dune_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	dune_noise.frequency = 0.011
	warp_noise.seed = world_seed + 14
	warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_noise.frequency = 0.009
	warp_noise.fractal_octaves = 3
	warp_noise.fractal_gain = 0.5
	ice_noise.seed = world_seed + 13
	ice_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ice_noise.frequency = 0.012
	ice_noise.fractal_octaves = 2


# ───────────────────────── 世界的"公式"：只由种子和坐标决定 ─────────────────────────
# 这一节的函数会在后台线程里被调用，所以只读噪声和常量，不碰场景树和字典

## 0 = 草原，1 = 山区深处
func mountain_mask(x: float, z: float) -> float:
	return smoothstep(0.05, 0.6, range_noise.get_noise_2d(x, z))


## 群系权重：r = 雪原，g = 沙漠，b = 秋林，a = 樱花林；剩下的（1 - 四个之和）就是普通草原。
## 由温度和湿度两张很大尺度的噪声决定（一片群系大约 1-2 公里），边界只有 30-50 米的渐变（地面颜色和草的颜色过渡用）。
## 树、花、灌木、石头这些东西不按权重混，只看 biome_at() 的那一个群系，各群系的东西不会跑到别的群系里
func biome_w(x: float, z: float) -> Color:
	var c := _climate(x, z)
	var t := c.x
	var w := c.y
	var snow := smoothstep(-0.28, -0.34, t)
	var desert := smoothstep(0.28, 0.34, t) * smoothstep(0.03, -0.03, w)
	var autumn := smoothstep(-0.06, -0.12, t) * (1.0 - snow)
	var cherry := smoothstep(0.17, 0.23, w) * (1.0 - snow) * (1.0 - autumn) * (1.0 - desert)
	return Color(snow, desert, autumn, cherry)


## 温度和湿度。采样位置先被 warp_noise 推开几十米，边界就变得弯弯曲曲、有凸出的岬角和凹进去的湾
func _climate(x: float, z: float) -> Vector2:
	var wx := x + warp_noise.get_noise_2d(x, z) * 45.0
	var wz := z + warp_noise.get_noise_2d(x + 913.0, z - 377.0) * 45.0
	return Vector2(temp_noise.get_noise_2d(wx, wz) * 1.7, humid_noise.get_noise_2d(wx, wz) * 1.7)


## 冰原（雪原里比较湿的地方）：0..1
func ice_w(x: float, z: float) -> float:
	var c := _climate(x, z)
	var t := c.x
	var w := c.y
	return smoothstep(-0.36, -0.42, t) * smoothstep(0.07, 0.13, w)


## 群系编号（0 草原 1 雪原 2 沙漠 3 秋林 4 樱花林 5 冰原）和它的权重
func biome_at(x: float, z: float) -> Vector2:
	var b := biome_w(x, z)
	var ice := ice_w(x, z)
	var best := 0
	var bw := 1.0 - b.r - b.g - b.b - b.a
	var ws := [b.r - ice, b.g, b.b, b.a, ice]
	for i in ws.size():
		if ws[i] > bw:
			bw = ws[i]
			best = i + 1
	return Vector2(best, bw)


## 冰原上的冰面（0..1）：一片片结冰的浅洼地
func _ice_sheet(x: float, z: float, ice: float) -> float:
	if ice <= 0.0:
		return 0.0
	return smoothstep(0.02, 0.12, ice_noise.get_noise_2d(x, z) + (ice - 1.0) * 0.6)


## 不含池塘的地面高度
## 平原：大尺度（约 400 米一个起伏）的缓坡 + 少量小坡；flat_noise 决定哪里是几乎全平的大平原、哪里是丘陵。
## 真实的平原几百米内只差一两米，起伏都集中在山区
func _land(x: float, z: float) -> float:
	var flat := smoothstep(-0.25, 0.35, flat_noise.get_noise_2d(x, z))       # 1 = 大平原
	var h := hill_noise.get_noise_2d(x * 0.22, z * 0.22) * lerpf(7.0, 3.0, flat)
	h += hill_noise.get_noise_2d(x + 517.0, z - 303.0) * lerpf(2.4, 0.35, flat)
	h += detail_noise.get_noise_2d(x, z) * 0.22
	var b := biome_w(x, z)
	if b.g > 0.0:
		# 沙丘：沿风向排列的一道道沙脊，迎风面缓、背风面陡
		var dn := dune_noise.get_noise_2d(x * 0.55 + z * 0.25, z * 1.1 - x * 0.2)
		var crest := 1.0 - absf(dn)
		h += b.g * (pow(crest, 3.0) * 5.5 + hill_noise.get_noise_2d(x * 0.6, z * 0.6) * 1.2)
	var ice := ice_w(x, z)
	if ice > 0.0:
		# 冰原很平，冰面是比周围略低的浅洼
		h = lerpf(h, h * 0.3, ice) - _ice_sheet(x, z, ice) * 0.35
	var m := mountain_mask(x, z)
	if m <= 0.0:
		return h
	var big := mountain_noise.get_noise_2d(x, z) * 0.5 + 0.5          # 0..1 高峰/垭口
	var ridge := ridge_noise.get_noise_2d(x, z) * 0.5 + 0.5           # 0..1 山脊
	# 山脚先是缓坡（m 的 1.8 次方），越往里越陡；最高的峰大约 250 米。
	# 坡度大多在 25-40 度之间，能走上去；山脊两侧会有需要手脚并用爬的陡坡
	var peak := 60.0 + big * 190.0
	return h + pow(m, 1.8) * peak * (0.22 + 0.78 * ridge) + m * m * 9.0 * hill_noise.get_noise_2d(x * 0.5 + 900.0, z * 0.5)


## 某个 320 米格子里的池塘：Vector4(x, z, 岸的高度, 1)；没有池塘时 w = 0
func _pond_for_cell(cx: int, cz: int) -> Vector4:
	var h1 := hash(Vector3i(world_seed + 11, cx, cz))
	if (h1 >> 20) % 100 >= 55:
		return Vector4.ZERO
	var fx := float(h1 & 0x3FF) / 1023.0
	var fz := float((h1 >> 10) & 0x3FF) / 1023.0
	var x := (cx + 0.15 + 0.7 * fx) * POND_CELL
	var z := (cz + 0.15 + 0.7 * fz) * POND_CELL
	# 只放在平坦的草原上
	for off: Vector2 in [Vector2.ZERO, Vector2(35, 0), Vector2(-35, 0), Vector2(0, 35), Vector2(0, -35)]:
		if mountain_mask(x + off.x, z + off.y) > 0.0:
			return Vector4.ZERO
	# 沙漠里没有池塘；雪原和冰原里的池塘是结冰的（w = 2：不挖坑、不放水面，地面画成冰）
	var b := biome_w(x, z)
	if b.g > 0.25:
		return Vector4.ZERO
	return Vector4(x, z, _land(x, z), 2.0 if b.r > 0.5 else 1.0)


## 一块矩形范围附近的所有池塘（线程里每个区块只算一次，之后每个采样点直接用）
func _ponds_near(x0: float, z0: float, x1: float, z1: float) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var m := POND_RADIUS + 12.0
	for cz in range(floori((z0 - m) / POND_CELL), floori((z1 + m) / POND_CELL) + 1):
		for cx in range(floori((x0 - m) / POND_CELL), floori((x1 + m) / POND_CELL) + 1):
			var p := _pond_for_cell(cx, cz)
			if p.w > 0.5:
				out.append(p)
	return out


func _height_p(x: float, z: float, ponds: Array[Vector4]) -> float:
	var h := _land(x, z)
	for p in ponds:
		var pd := Vector2(x - p.x, z - p.y).length()
		# 压平范围要比水面大出两格以上（地形每格 2 米），否则格子插值会让岸边低于水面、露出水面边缘
		if pd < POND_RADIUS + 11.0:
			h = lerpf(h, p.z, smoothstep(POND_RADIUS + 11.0, POND_RADIUS + 4.5, pd))
			if p.w < 1.5:
				h -= POND_DEPTH * smoothstep(POND_RADIUS, POND_RADIUS * 0.3, pd)
			else:
				h -= 0.3 * smoothstep(POND_RADIUS + 1.5, POND_RADIUS - 0.5, pd)
	return h


## 到最近一条小路中心线的距离
func _path_dist(x: float, z: float) -> float:
	var n := path_noise.get_noise_2d(x, z)
	var gx := path_noise.get_noise_2d(x + 1.5, z) - n
	var gz := path_noise.get_noise_2d(x, z + 1.5) - n
	return absf(n) / maxf(sqrt(gx * gx + gz * gz) / 1.5, 0.0004)


## x = 小路和泥土斑块，y = 池塘边的沙，z = 冰面（冰原的冰、结冰的池塘）（0..1）。草/花/树的摆放和地面颜色用的是同一份
func _bare(x: float, z: float, ponds: Array[Vector4]) -> Vector3:
	var edge := detail_noise.get_noise_2d(x * 3.0, z * 3.0)
	var m := mountain_mask(x, z)
	var path := (1.0 - smoothstep(0.9, 1.9, _path_dist(x, z) + edge * 0.5)) * (1.0 - smoothstep(0.15, 0.4, m))
	var patch := smoothstep(0.50, 0.64, dirt_noise.get_noise_2d(x, z)) * 0.9
	var sand := 0.0
	var ice := _ice_sheet(x, z, ice_w(x, z))
	for p in ponds:
		var pd := Vector2(x - p.x, z - p.y).length()
		var disc := 1.0 - smoothstep(POND_RADIUS - 2.5, POND_RADIUS + 0.5, pd + edge * 1.2)
		if p.w > 1.5:
			ice = maxf(ice, 1.0 - smoothstep(POND_RADIUS - 0.5, POND_RADIUS + 1.0, pd + edge * 0.8))
		else:
			sand = maxf(sand, disc)
	# 雪原里小路和泥土斑块被雪盖住；沙漠里本来就是沙，不画泥土斑块
	var b := biome_w(x, z)
	patch *= (1.0 - b.r) * (1.0 - b.g)
	path *= 1.0 - b.r * 0.85
	return Vector3(maxf(path, patch), sand, ice)


## 这里是不是树林（0..1）：大尺度决定一片片林子，小尺度让林子边缘参差
func _grove(x: float, z: float) -> float:
	return patch_noise.get_noise_2d(x * 0.3 + 300.0, z * 0.3 - 200.0) * 0.7 + patch_noise.get_noise_2d(x + 300.0, z - 200.0) * 0.3


## 一片区域的高度表：(n+1) x (n+1) 个点，间距 CELL，和最精细地形的顶点完全重合
func _height_grid(ox: float, oz: float, n: int, ponds: Array[Vector4]) -> PackedFloat32Array:
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			hs[iz * (n + 1) + ix] = _height_p(ox + ix * CELL, oz + iz * CELL, ponds)
	return hs


## 从高度表里查高度：和地形三角面完全一致的插值，草和花才不会悬空
func _grid_h(hs: PackedFloat32Array, n: int, ox: float, oz: float, x: float, z: float) -> float:
	var fx := clampf((x - ox) / CELL, 0.0, n - 0.001)
	var fz := clampf((z - oz) / CELL, 0.0, n - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	fx -= ix
	fz -= iz
	var w := n + 1
	var ha := hs[iz * w + ix]
	var hb := hs[iz * w + ix + 1]
	var hc := hs[(iz + 1) * w + ix]
	var hd := hs[(iz + 1) * w + ix + 1]
	if fx >= fz:
		return ha + (hb - ha) * fx + (hd - hb) * fz
	return ha + (hd - hc) * fx + (hc - ha) * fz


## 坡度（每走 1 米升高多少米）：0.58 ≈ 30 度，1.0 = 45 度
func _grid_slope(hs: PackedFloat32Array, n: int, ox: float, oz: float, x: float, z: float) -> float:
	var ix := clampi(int((x - ox) / CELL), 0, n - 1)
	var iz := clampi(int((z - oz) / CELL), 0, n - 1)
	var w := n + 1
	var ha := hs[iz * w + ix]
	var dx := (hs[iz * w + ix + 1] - ha) / CELL
	var dz := (hs[(iz + 1) * w + ix] - ha) / CELL
	return sqrt(dx * dx + dz * dz)


# ───────────────────────── 主线程用的查询 ─────────────────────────

## 这个位置所在格子里的池塘：Vector4(x, z, 岸的高度, 1)；没有时 w = 0
func pond_at(x: float, z: float) -> Vector4:
	var key := Vector2i(floori(x / POND_CELL), floori(z / POND_CELL))
	if not _pond_cache.has(key):
		_pond_cache[key] = _pond_for_cell(key.x, key.y)
	return _pond_cache[key]


func _ponds_at(x: float, z: float) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var p := pond_at(x, z)
	if p.w > 0.5:
		out.append(p)
	return out


## 公式算出的精确高度（快，但和地形三角面有一点点出入）
func height_raw(x: float, z: float) -> float:
	return _height_p(x, z, _ponds_at(x, z))


## 和地形三角面完全一致的高度
func get_height(x: float, z: float) -> float:
	var ox := floorf(x / CELL) * CELL
	var oz := floorf(z / CELL) * CELL
	return _grid_h(_height_grid(ox, oz, 1, _ponds_at(x, z)), 1, ox, oz, x, z)


func bare_at(x: float, z: float) -> float:
	var b := _bare(x, z, _ponds_at(x, z))
	return maxf(maxf(b.x, b.y), b.z)


func ice_at(x: float, z: float) -> float:
	return _bare(x, z, _ponds_at(x, z)).z


## 这里有没有树干 / 石头 / 冰山 / 仙人掌 / 灌木（已加载区块里的障碍物），动物走路前用它检查
func blocked_at(x: float, z: float, rad := 0.3) -> bool:
	var k := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var ck := k + Vector2i(dx, dz)
			if not chunks.has(ck):
				continue
			if _blocked_r(chunks[ck].blockers, x, z, rad):
				return true
	return false


## 动物（兔子、小鹿、地上的小鸟）只住在草原、秋林、樱花林；雪原、冰原、沙漠里没有
func animal_biome_ok(x: float, z: float) -> bool:
	var b := int(biome_at(x, z).x)
	return b == 0 or b == 3 or b == 4


func in_pond(x: float, z: float) -> bool:
	var p := pond_at(x, z)
	return p.w > 0.5 and p.w < 1.5 and Vector2(x - p.x, z - p.y).length() < POND_RADIUS + 1.0 and height_raw(x, z) < p.z - 0.26


func _chunk_key(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))


func _find_spawn() -> Vector2:
	for ring in 80:
		for k in 8:
			var a := TAU * k / 8.0 + ring * 0.4
			var p := Vector2(cos(a), sin(a)) * ring * 45.0
			var ok := true
			for off: Vector2 in [Vector2.ZERO, Vector2(50, 0), Vector2(-50, 0), Vector2(0, 50), Vector2(0, -50)]:
				if mountain_mask(p.x + off.x, p.y + off.y) > 0.0:
					ok = false
					break
			var bw := biome_w(p.x, p.y)
			if bw.r + bw.g + bw.b + bw.a > 0.15:
				ok = false
			var pond := pond_at(p.x, p.y)
			if ok and (pond.w < 0.5 or Vector2(pond.x, pond.y).distance_to(p) > POND_RADIUS + 25.0):
				return p
	return Vector2.ZERO


# ───────────────────────── 工具 ─────────────────────────

func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path) as Shader
	return m


func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


func _make_multimesh(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color] = [], customs: Array[Color] = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.use_custom_data = not customs.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
		if mm.use_custom_data:
			mm.set_instance_custom_data(i, customs[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


## 把球体顶点用噪声挤压变形。flat=true 得到棱角分明的石头，false 得到圆润的树冠
func _make_blob_mesh(radial: int, rings: int, amount: float, freq: float, flat: bool, seed_offset: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = radial
	sphere.rings = rings
	var arrays: Array = sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var n := FastNoiseLite.new()
	n.seed = world_seed + seed_offset
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX
	n.frequency = freq
	if flat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_smooth_group(-1)
		for idx in indices:
			var d := verts[idx].normalized()
			st.add_vertex(d * (1.0 + n.get_noise_3d(d.x, d.y, d.z) * amount))
		st.generate_normals()
		return st.commit()
	# 圆润版本：直接用球面方向当法线，明暗过渡成干净的大色块
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for v in verts:
		var d := v.normalized()
		out_v.append(d * (1.0 + n.get_noise_3d(d.x, d.y, d.z) * amount))
		out_n.append(d)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = out_v
	out[Mesh.ARRAY_NORMAL] = out_n
	out[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh


## toon 材质 + 描边（描边挂在 next_pass 上）
func _toon_with_outline(albedo: Color, radial: bool) -> ShaderMaterial:
	var m := _shader_mat("res://shaders/toon.gdshader")
	m.set_shader_parameter("albedo", albedo)
	var o := _shader_mat("res://shaders/outline.gdshader")
	o.set_shader_parameter("radial", radial)
	m.next_pass = o
	return m


## 所有区块共用的网格和材质，只在启动时做一次
func _init_assets() -> void:
	terrain_mat = _shader_mat("res://shaders/terrain.gdshader")
	terrain_mat.set_shader_parameter("fade_start", GRASS_FADE_START)
	terrain_mat.set_shader_parameter("fade_end", GRASS_FADE_END)
	terrain_mat.set_shader_parameter("wind_dir", WIND_DIR)

	water_mat = _shader_mat("res://shaders/water.gdshader")

	grass_mat = _shader_mat("res://shaders/grass.gdshader")
	grass_mat.set_shader_parameter("wind_dir", WIND_DIR)
	grass_mat.set_shader_parameter("fade_start", GRASS_FADE_START)
	grass_mat.set_shader_parameter("fade_end", GRASS_FADE_END)
	grass_mat.set_shader_parameter("min_density", GRASS_MIN_DENSITY)
	grass_mat.set_shader_parameter("view_end", grass_view_distance)
	blade_mesh = _make_blade_mesh()

	flower_mat = _shader_mat("res://shaders/flower.gdshader")
	flower_mat.set_shader_parameter("wind_dir", WIND_DIR)
	flower_mesh = _make_flower_mesh()

	trunk_mesh = CylinderMesh.new()
	trunk_mesh.top_radius = 0.5
	trunk_mesh.bottom_radius = 1.0
	trunk_mesh.height = 1.0
	trunk_mesh.radial_segments = 8
	trunk_mesh.rings = 1
	trunk_mat = _toon_with_outline(Color(0.45, 0.30, 0.22), false)
	trunk_mat.set_shader_parameter("rim_strength", 0.15)

	# 树冠 = 里面一团深色的"芯"（挡住透光）+ 外面一层朝向镜头的叶片面片
	core_mesh = _make_blob_mesh(14, 8, 0.2, 1.0, false, 100)
	core_mat = _shader_mat("res://shaders/leaves.gdshader")
	core_mat.set_shader_parameter("wind_dir", WIND_DIR)
	card_mat = _shader_mat("res://shaders/foliage.gdshader")
	card_mat.set_shader_parameter("leaf_tex", _make_leaf_texture())
	card_mat.set_shader_parameter("wind_dir", WIND_DIR)
	# 面片网格：四个顶点都在原点，着色器按 UV 把它展开成朝向镜头的方片
	card_mesh = ArrayMesh.new()
	var qa := []
	qa.resize(Mesh.ARRAY_MAX)
	qa[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	qa[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	qa[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	qa[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	card_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, qa)
	card_mesh.custom_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))

	rock_mat = _toon_with_outline(Color(0.62, 0.63, 0.68), true)
	rock_mat.set_shader_parameter("moss_amount", 0.75)
	rock_mat.set_shader_parameter("band_threshold", 0.15)
	var snow_rock := _toon_with_outline(Color(0.58, 0.60, 0.68), true)
	snow_rock.set_shader_parameter("moss_color", Color(0.96, 0.97, 1.0))
	snow_rock.set_shader_parameter("moss_amount", 0.95)
	snow_rock.set_shader_parameter("band_threshold", 0.15)
	var sand_rock := _toon_with_outline(Color(0.86, 0.60, 0.42), true)
	sand_rock.set_shader_parameter("band_threshold", 0.15)
	rock_mats = [rock_mat, snow_rock, sand_rock]
	# 雪堆：树根和石头底下、空地上一个个圆鼓鼓的积雪，让雪看起来有厚度
	drift_mesh = _make_blob_mesh(16, 8, 0.12, 1.2, false, 300)
	drift_mat = _shader_mat("res://shaders/toon.gdshader")
	drift_mat.set_shader_parameter("albedo", Color(0.95, 0.97, 1.0))
	drift_mat.set_shader_parameter("band_threshold", -0.2)
	drift_mat.set_shader_parameter("band_softness", 0.25)
	drift_mat.set_shader_parameter("rim_strength", 0.35)
	_build_snow_fx()
	trail_img = Image.create(TRAIL_RES, TRAIL_RES, false, Image.FORMAT_L8)
	trail_tex = ImageTexture.create_from_image(trail_img)
	terrain_mat.set_shader_parameter("trail_tex", trail_tex)
	terrain_mat.set_shader_parameter("trail_size", TRAIL_RES * TRAIL_PX)
	ice_mat = _toon_with_outline(Color(0.66, 0.86, 0.98), true)
	ice_mat.set_shader_parameter("moss_color", Color(0.94, 0.98, 1.0))
	ice_mat.set_shader_parameter("moss_amount", 0.6)
	ice_mat.set_shader_parameter("band_threshold", 0.05)
	ice_mat.set_shader_parameter("rim_strength", 0.6)
	cactus_mat = _toon_with_outline(Color(0.34, 0.58, 0.32), true)
	cactus_mat.set_shader_parameter("rim_strength", 0.3)
	cactus_mesh = CapsuleMesh.new()
	cactus_mesh.radius = 0.5
	cactus_mesh.height = 2.0
	cactus_mesh.radial_segments = 10
	cactus_mesh.rings = 3
	# 小石子太小，不描边
	pebble_mat = _shader_mat("res://shaders/toon.gdshader")
	pebble_mat.set_shader_parameter("albedo", Color(0.46, 0.47, 0.50))     # 以前太亮，晚上看起来像一片片白点
	pebble_mat.set_shader_parameter("band_threshold", 0.15)
	for v in 5:
		var m := _make_blob_mesh(7, 4, 0.42, 0.9, true, 200 + v * 13)
		rock_variants.append(m)
		# 去重后的顶点用来生成凸包碰撞
		var uniq := {}
		for p: Vector3 in m.get_faces():
			uniq[p.snappedf(0.001)] = true
		var pts := PackedVector3Array()
		for k: Vector3 in uniq:
			pts.append(k)
		rock_points.append(pts)


# ───────────────────────── 区块调度 ─────────────────────────

## 离玩家几个区块以内用哪一档精度：0 = 2 米一格（带碰撞），1 = 4 米，2 = 8 米，3 = 16 米
func _lod_for(d: int) -> int:
	if d <= 1:
		return 0
	if d <= 3:
		return 1
	if d <= 6:
		return 2
	return 3


func _new_chunk(key: Vector2i, want: int) -> Dictionary:
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [key.x, key.y]
	add_child(root)
	var ch := {
		"root": root, "mesh": null, "body": null, "lod": -1, "want": want, "pending": -1,
		"deco": null, "deco_state": 0, "blockers": PackedVector3Array(), "trees": [], "flowers": [],
	}
	chunks[key] = ch
	# 这个区块里有池塘的话，放一片水面
	var c := Vector2((key.x + 0.5) * CHUNK, (key.y + 0.5) * CHUNK)
	var pond := pond_at(c.x, c.y)
	if pond.w > 0.5 and floori(pond.x / CHUNK) == key.x and floori(pond.y / CHUNK) == key.y:
		_add_pond(root, pond, ch)
	return ch


func _add_pond(root: Node3D, pond: Vector4, ch: Dictionary) -> void:
	var mat := water_mat.duplicate() as ShaderMaterial
	# 水面网格是方的，着色器里裁成圆形，四个角不会伸到岸外
	mat.set_shader_parameter("pond_center", Vector2(pond.x, pond.y))
	mat.set_shader_parameter("pond_radius", POND_RADIUS + 1.2)
	var plane := PlaneMesh.new()
	plane.size = Vector2(POND_RADIUS * 2.0 + 2.0, POND_RADIUS * 2.0 + 2.0)
	var mi := MeshInstance3D.new()
	mi.name = "Pond"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3(pond.x, pond.z - 0.3, pond.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	pond_mats.append(mat)
	ch["pond_mat"] = mat


func _free_chunk(key: Vector2i) -> void:
	var ch: Dictionary = chunks[key]
	if ch.has("pond_mat"):
		pond_mats.erase(ch.pond_mat)
	(ch.root as Node3D).queue_free()
	if ch.deco != null:
		(ch.deco as Node3D).queue_free()
		_lists_dirty = true
	chunks.erase(key)


## 每 0.2 秒跑一次：决定哪些区块该生成 / 换精度 / 卸掉，然后把最近的几件事交给后台线程
func _stream(p: Vector3) -> void:
	var pc := _chunk_key(p)
	var me := Vector2(p.x, p.z)

	# 该卸的先卸
	for key: Vector2i in chunks.keys():
		var d := maxi(absi(key.x - pc.x), absi(key.y - pc.y))
		if d > VIEW_CHUNKS + 1:
			_free_chunk(key)
		elif d > DECO_CHUNKS + 1 and chunks[key].deco_state == 2:
			var ch: Dictionary = chunks[key]
			(ch.deco as Node3D).queue_free()
			ch.deco = null
			ch.deco_state = 0
			ch.trees = []
			ch.flowers = []
			ch.blockers = PackedVector3Array()
			_lists_dirty = true
	var g_far := grass_view_distance + 55.0
	for gkey: Vector2i in gchunks.keys():
		var g: Dictionary = gchunks[gkey]
		if not g.has("pending") and _rect_dist(gkey, me) > g_far:
			if g.node != null:
				(g.node as Node3D).queue_free()
			gchunks.erase(gkey)

	if _jobs >= _max_jobs:
		return

	# 要做的事，按离玩家的远近排队：[优先级, 类型, 位置, 精度]
	var todo: Array = []
	for dz in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
		for dx in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
			var key := pc + Vector2i(dx, dz)
			var d := maxi(absi(dx), absi(dz))
			var want := _lod_for(d)
			var ch: Dictionary = chunks[key] if chunks.has(key) else _new_chunk(key, want)
			ch.want = want
			if ch.pending < 0 and ch.lod != want:
				# 还没有地面的区块最优先；只是换精度的可以晚一点
				todo.append([d + (0.0 if ch.lod < 0 else 2.5), 0, key, want])
			if d <= DECO_CHUNKS and ch.deco_state == 0:
				todo.append([d + 0.6, 1, key, 0])
	var g_near := grass_view_distance + 12.0
	var gr := int(ceil(g_near / GCHUNK)) + 1
	var gc := Vector2i(floori(p.x / GCHUNK), floori(p.z / GCHUNK))
	for dz in range(-gr, gr + 1):
		for dx in range(-gr, gr + 1):
			var gkey := gc + Vector2i(dx, dz)
			if gchunks.has(gkey):
				continue
			var dist := _rect_dist(gkey, me)
			if dist > g_near:
				continue
			# 草要等所在区块的树和石头摆好（它们脚下不长草）
			var parent := Vector2i(floori((gkey.x + 0.5) * GCHUNK / CHUNK), floori((gkey.y + 0.5) * GCHUNK / CHUNK))
			if chunks.has(parent) and chunks[parent].deco_state == 2:
				todo.append([dist / CHUNK + 0.3, 2, gkey, 0])

	todo.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for job: Array in todo:
		if _jobs >= _max_jobs:
			break
		_job_seq += 1
		_jobs += 1
		var key: Vector2i = job[2]
		match job[1]:
			0:
				chunks[key].pending = job[3]
				_task_ids[_job_seq] = WorkerThreadPool.add_task(_job_terrain.bind(key, job[3], _job_seq))
			1:
				chunks[key].deco_state = 1
				_task_ids[_job_seq] = WorkerThreadPool.add_task(_job_deco.bind(key, _job_seq))
			2:
				gchunks[key] = {"pending": true}
				var parent := Vector2i(floori((key.x + 0.5) * GCHUNK / CHUNK), floori((key.y + 0.5) * GCHUNK / CHUNK))
				var blockers: PackedVector3Array = chunks[parent].blockers
				_task_ids[_job_seq] = WorkerThreadPool.add_task(_job_grass.bind(key, blockers.duplicate(), _job_seq))


## 加载进度 0..1（loading.gd 用）：玩家周围该有的地形、树石花、草生成了多少。
## 按耗时加权：地形 1、树石花 2、草 2
func load_progress() -> float:
	if player == null:
		return 0.0
	var p := player.global_position
	var pc := _chunk_key(p)
	var me := Vector2(p.x, p.z)
	var total := 0.0
	var done := 0.0
	for dz in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
		for dx in range(-VIEW_CHUNKS, VIEW_CHUNKS + 1):
			var key := pc + Vector2i(dx, dz)
			var ch: Dictionary = chunks.get(key, {})
			total += 1.0
			if not ch.is_empty() and ch.lod >= 0:
				done += 1.0
			if maxi(absi(dx), absi(dz)) <= DECO_CHUNKS:
				total += 2.0
				if not ch.is_empty() and ch.deco_state == 2:
					done += 2.0
	var g_near := grass_view_distance + 12.0
	var gr := int(ceil(g_near / GCHUNK)) + 1
	var gc := Vector2i(floori(p.x / GCHUNK), floori(p.z / GCHUNK))
	for dz in range(-gr, gr + 1):
		for dx in range(-gr, gr + 1):
			var gkey := gc + Vector2i(dx, dz)
			if _rect_dist(gkey, me) > g_near:
				continue
			total += 2.0
			if gchunks.has(gkey) and not gchunks[gkey].has("pending"):
				done += 2.0
	return done / maxf(total, 1.0)


func _rect_dist(gkey: Vector2i, p: Vector2) -> float:
	var o := Vector2(gkey.x, gkey.y) * GCHUNK
	return Vector2(clampf(p.x, o.x, o.x + GCHUNK), clampf(p.y, o.y, o.y + GCHUNK)).distance_to(p)


func _job_done(tok: int) -> void:
	_jobs -= 1
	if _task_ids.has(tok):
		WorkerThreadPool.wait_for_task_completion(_task_ids[tok])
		_task_ids.erase(tok)
	_stream_timer = 0.0     # 有空位了，下一帧马上再派活


## 关游戏时先让后台线程停下来，不然它们会读到已经释放的数据
func _exit_tree() -> void:
	_quitting = true
	for id: int in _task_ids.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_task_ids.clear()


func _rebuild_lists() -> void:
	tree_positions = []
	flower_centers = []
	for ch: Dictionary in chunks.values():
		if ch.deco_state == 2:
			tree_positions.append_array(ch.trees)
			flower_centers.append_array(ch.flowers)


# ───────────────────────── 地形 ─────────────────────────

func _job_terrain(key: Vector2i, lod: int, tok: int) -> void:
	var d := _compute_terrain(key, lod)
	if not _quitting:
		_terrain_ready.call_deferred(key, lod, d, tok)


## 算出一个区块的地形网格数据。顶点色：R = 泥土/小路，G = 沙，B = 树林（远处用来把山坡染成林子的颜色）
func _compute_terrain(key: Vector2i, lod: int) -> Dictionary:
	var cell := CELL * float(1 << lod)
	var n := int(round(CHUNK / cell))
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var ponds := _ponds_near(ox - cell, oz - cell, ox + CHUNK + cell, oz + CHUNK + cell)
	# 高度多算一圈，这样法线在区块接缝处两边一致
	var w := n + 3
	var hs := PackedFloat32Array()
	hs.resize(w * w)
	for iz in w:
		if _quitting:
			return {}
		for ix in w:
			hs[iz * w + ix] = _height_p(ox + (ix - 1) * cell, oz + (iz - 1) * cell, ponds)

	var vn := n + 1
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(vn * vn + vn * 4)
	normals.resize(vn * vn + vn * 4)
	colors.resize(vn * vn + vn * 4)
	var custom := PackedFloat32Array()
	custom.resize((vn * vn + vn * 4) * 4)
	for iz in vn:
		for ix in vn:
			var i := iz * vn + ix
			var hi := (iz + 1) * w + ix + 1
			var x := ox + ix * cell
			var z := oz + iz * cell
			var h := hs[hi]
			verts[i] = Vector3(x, h, z)
			normals[i] = Vector3(hs[hi - 1] - hs[hi + 1], 2.0 * cell, hs[hi - w] - hs[hi + w]).normalized()
			var b := _bare(x, z, ponds)
			var forest := smoothstep(-0.12, 0.08, _grove(x, z)) * (1.0 - smoothstep(TREE_LINE - 20.0, TREE_LINE, h))
			var bw := biome_w(x, z)
			forest *= 1.0 - bw.g * 0.9
			colors[i] = Color(b.x, b.y, forest, b.z)
			custom[i * 4] = bw.r
			custom[i * 4 + 1] = bw.g
			custom[i * 4 + 2] = bw.b
			custom[i * 4 + 3] = bw.a

	var indices := PackedInt32Array()
	var faces := PackedVector3Array()
	for iz in n:
		for ix in n:
			var a := iz * vn + ix
			var b := a + 1
			var c := a + vn
			var d := c + 1
			indices.append_array([a, b, d, a, d, c])
			if lod == 0:
				faces.append_array([verts[a], verts[b], verts[d], verts[a], verts[d], verts[c]])

	# 裙边：区块四周往下垂一圈，盖住相邻区块精度不同时出现的缝
	var drop := cell * 3.0 + 2.0
	var s := vn * vn
	for e in 4:
		for k in vn:
			var src := k
			if e == 1:
				src = n * vn + k
			elif e == 2:
				src = k * vn
			elif e == 3:
				src = k * vn + n
			var di := s + e * vn + k
			verts[di] = verts[src] - Vector3(0.0, drop, 0.0)
			normals[di] = normals[src]
			colors[di] = colors[src]
			for q in 4:
				custom[di * 4 + q] = custom[src * 4 + q]
			if k > 0:
				var a := src - (1 if e < 2 else vn)
				var a2 := di - 1
				indices.append_array([a, src, di, a, di, a2, a, di, src, a, a2, di])
	return {"verts": verts, "normals": normals, "colors": colors, "custom": custom, "indices": indices, "faces": faces}


func _terrain_ready(key: Vector2i, lod: int, d: Dictionary, tok: int) -> void:
	_job_done(tok)
	if not chunks.has(key):
		return
	chunks[key].pending = -1
	_apply_terrain(key, lod, d)


func _apply_terrain(key: Vector2i, lod: int, d: Dictionary) -> void:
	if d.is_empty():
		return
	var ch: Dictionary = chunks[key]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = d.verts
	arrays[Mesh.ARRAY_NORMAL] = d.normals
	arrays[Mesh.ARRAY_COLOR] = d.colors
	arrays[Mesh.ARRAY_CUSTOM0] = d.custom
	arrays[Mesh.ARRAY_INDEX] = d.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = terrain_mat
	var root: Node3D = ch.root
	root.add_child(mi)
	if ch.mesh != null:
		(ch.mesh as Node3D).queue_free()
	ch.mesh = mi
	if ch.body != null:
		(ch.body as Node3D).queue_free()
		ch.body = null
	# 只有玩家脚下和旁边一圈的区块需要碰撞
	if lod == 0:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(d.faces)
		var col := CollisionShape3D.new()
		col.shape = shape
		var body := StaticBody3D.new()
		body.add_child(col)
		root.add_child(body)
		ch.body = body
	ch.lod = lod


# ───────────────────────── 树、灌木、石头、花（每个区块一份） ─────────────────────────

## 叶簇贴图：一圈尖叶子，白底 + 透明通道，运行时画出来，不需要图片文件
func _make_leaf_texture() -> ImageTexture:
	var size := 128
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var lr := RandomNumberGenerator.new()
	lr.seed = 7
	var leaves := 9
	for l in leaves:
		var ang := TAU * l / leaves + lr.randf_range(-0.2, 0.2)
		var length := lr.randf_range(0.37, 0.47)
		var width := lr.randf_range(0.10, 0.14)
		var shade := lr.randf_range(0.72, 1.0)
		var dir := Vector2(cos(ang), sin(ang))
		var nrm := Vector2(-dir.y, dir.x)
		for py in size:
			for px in size:
				var p := Vector2((px + 0.5) / size - 0.5, (py + 0.5) / size - 0.5)
				var u := p.dot(dir) / length
				if u < 0.0 or u > 1.0:
					continue
				var v := absf(p.dot(nrm))
				var w := width * pow(sin(PI * u), 0.75) * (1.15 - 0.5 * u)
				if v <= w:
					var s := shade * (0.88 if v < 0.008 else 1.0)
					img.set_pixel(px, py, Color(s, s, s, 1.0))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## 在一团树冠表面撒叶片面片。center = 这团的中心，canopy = 整棵树冠的中心（用来算法线）
## min_y：叶片方向最低能朝下多少（-1 = 正下方）。贴地的灌木用较大的值，免得叶片撒到地底下
func _add_leaf_cards(r: RandomNumberGenerator, center: Vector3, radius: Vector3, canopy: Vector3, col: Color, count: int,
		card_x: Array[Transform3D], card_c: Array[Color], card_d: Array[Color], min_y := -0.9, snow := 0.0, size_k := 1.0) -> void:
	for i in count:
		# 底部也要撒叶片，否则从下往上看会露出里面的芯
		var dir := Vector3(r.randf_range(-1.0, 1.0), r.randf_range(min_y, 1.0), r.randf_range(-1.0, 1.0)).normalized()
		var pos := center + dir * radius * r.randf_range(0.82, 1.05)
		var size := minf(radius.x * r.randf_range(0.85, 1.25) * size_k, 3.9)
		var lc := col.lightened(r.randf_range(-0.05, 0.1))
		if snow > 0.0 and dir.y > 0.25 and r.randf() < snow:
			lc = lc.lerp(Color(0.95, 0.97, 1.0), r.randf_range(0.75, 0.95))     # 朝上的叶簇积了雪
		var c := _lin(lc)
		c.a = size / 4.0       # 面片大小存在颜色的 alpha 里（着色器里再乘回 4）
		card_x.append(Transform3D(Basis(), pos))
		card_c.append(c)
		card_d.append(Color(canopy.x, canopy.y, canopy.z, r.randf()))


## 松树：细高的树干 + 一层层往上变小的扁树冠（像宝塔），雪原里朝上的叶簇积雪
func _add_pine(r: RandomNumberGenerator, x: float, h: float, z: float, snow: float, trunk_x: Array[Transform3D], tree_cols: Array,
		blockers: PackedVector3Array, core_x: Array[Transform3D], core_c: Array[Color],
		card_x: Array[Transform3D], card_c: Array[Color], card_d: Array[Color], crowns: PackedVector3Array) -> void:
	var tall := r.randf_range(0.85, 1.3)
	var th := 2.2 * tall
	var tr := r.randf_range(0.22, 0.3)
	trunk_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(tr, th + 0.4, tr)), Vector3(x, h - 0.4 + (th + 0.4) * 0.5, z)))
	blockers.append(Vector3(x, z, tr + 0.25))
	tree_cols.append([x, h, z, tr * 0.85, th + 3.0])
	var col: Color = PINES[r.randi() % PINES.size()]
	var core_col := _lin(col.darkened(0.12))
	var layers := r.randi_range(4, 5)
	var canopy := Vector3(x, h + th + 3.0 * tall, z)
	# 最下面一层树枝的下沿要高过角色的头（约 1.1 米），否则走到树下身体会插进树枝里
	var y := h + 1.75 * tall + 0.45
	var y0 := y
	var rr0 := 2.1 * tall
	for k in layers:
		var f := float(k) / float(layers - 1)
		var rr := lerpf(2.1, 0.55, f) * tall
		var c := Vector3(x, y, z)
		var rad := Vector3(rr, rr * 0.36, rr)
		# 芯比叶片层小一圈、厚一点：扁的芯边缘会从叶片之间露出来，近看像一片片深色的圆盘
		if f < 0.5:     # 上面几层小，叶片就盖得住，不放芯（放了会从稀疏的叶片间露出深色的一块）
			core_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(rr * 0.62, rr * 0.36, rr * 0.62) * CORE_SCALE), c + Vector3(0, rr * 0.05, 0)))
			core_c.append(core_col)
		# 叶片小一些、多一些，才看得出一层层的轮廓；下摆往下垂
		_add_leaf_cards(r, c, rad, canopy, col, int(lerpf(34.0, 16.0, f)), card_x, card_c, card_d, -0.3 if k == 0 else -0.55, snow * 0.85, 0.5 + f * 0.15)
		if k < layers - 1:
			y += lerpf(1.25, 0.8, f) * tall
	# 尖顶：紧贴在最上面一层的顶上（以前多往上加了一层的间距，尖顶悬在空中）
	var tip := Vector3(x, y + 0.28 * tall, z)
	_add_leaf_cards(r, tip, Vector3(0.4, 0.55, 0.4) * tall, canopy, col, 8, card_x, card_c, card_d, -0.5, snow, 0.8)
	# 树冠的碰撞：人从树枝底下走得过去，但镜头会被它挡住拉近，不会钻进树冠里
	var cb := y0 - 0.25 * tall
	tree_cols.append([x, cb, z, rr0 * 0.8, tip.y + 0.4 - cb])
	crowns.append(Vector3(x, z, rr0 * 1.1))


## 雪堆：压扁的圆团，大半埋在地下，只露出一个鼓包（没有碰撞，踩上去会陷进去）
func _add_drift(r: RandomNumberGenerator, drift_x: Array[Transform3D], x: float, h: float, z: float, size: float) -> void:
	var sc := Vector3(size * r.randf_range(1.0, 1.4), size * r.randf_range(0.22, 0.32), size * r.randf_range(0.8, 1.1))
	drift_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(sc), Vector3(x, h - sc.y * 0.45, z)))


## 仙人掌：一根主干 + 0-2 条向上弯的手臂（胶囊拼出来）
func _add_cactus(r: RandomNumberGenerator, x: float, h: float, z: float, cactus_x: Array[Transform3D], cactus_cols: Array, blockers: PackedVector3Array) -> void:
	var th := r.randf_range(2.0, 3.6)
	var rad := r.randf_range(0.32, 0.42)
	var yaw := Basis(Vector3.UP, r.randf() * TAU)
	cactus_x.append(Transform3D(yaw * Basis.from_scale(Vector3(rad * 2.0, th * 0.5, rad * 2.0)), Vector3(x, h + th * 0.5 - 0.2, z)))
	blockers.append(Vector3(x, z, rad + 0.3))
	cactus_cols.append([x, h, z, rad, th])
	var arms := r.randi_range(0, 2)
	var side := 1.0 if r.randf() < 0.5 else -1.0
	for a in arms:
		var ay := h + th * r.randf_range(0.35, 0.6)
		var out := rad * 2.0 + 0.25
		var arm_len := r.randf_range(0.7, 1.2)
		var ar := rad * 0.7
		var dir := yaw * Vector3(side, 0.0, 0.0)
		# 横着伸出去的一小段
		var hb := yaw * Basis(Vector3(0, 0, 1), PI * 0.5) * Basis.from_scale(Vector3(ar * 2.0, out * 0.5, ar * 2.0))
		cactus_x.append(Transform3D(hb, Vector3(x, ay, z) + dir * out * 0.5))
		# 往上竖起来的一段
		cactus_x.append(Transform3D(yaw * Basis.from_scale(Vector3(ar * 2.0, arm_len * 0.5, ar * 2.0)), Vector3(x, ay + arm_len * 0.5 - ar, z) + dir * out))
		side = -side


## 半径为 rad 的东西放在 (x, z) 会不会碰到 blockers 里的任何一个
func _blocked_r(blockers: PackedVector3Array, x: float, z: float, rad: float) -> bool:
	for b in blockers:
		var dx := x - b.x
		var dz := z - b.y
		var rr := b.z + rad
		if dx * dx + dz * dz <= rr * rr:
			return true
	return false


func _blocked(blockers: PackedVector3Array, x: float, z: float) -> bool:
	for b in blockers:
		var dx := x - b.x
		var dz := z - b.y
		if dx * dx + dz * dz <= b.z * b.z:
			return true
	return false


func _job_deco(key: Vector2i, tok: int) -> void:
	var d := _compute_deco(key)
	if not _quitting:
		_deco_ready.call_deferred(key, d, tok)


## 在后台线程里算出一个区块里所有摆设的位置（只算数据，不建节点）
func _compute_deco(key: Vector2i) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector3i(world_seed, key.x, key.y))
	var ox := key.x * CHUNK
	var oz := key.y * CHUNK
	var n := int(CHUNK / CELL)
	var ponds := _ponds_near(ox, oz, ox + CHUNK, oz + CHUNK)
	var hs := _height_grid(ox, oz, n, ponds)
	var area := CHUNK * CHUNK / (160.0 * 160.0)
	var mid_m := mountain_mask(ox + CHUNK * 0.5, oz + CHUNK * 0.5)
	var sp := Vector2(spawn.x, spawn.z)
	var mid_b := biome_w(ox + CHUNK * 0.5, oz + CHUNK * 0.5)
	var mid_ice := ice_w(ox + CHUNK * 0.5, oz + CHUNK * 0.5)

	var blockers := PackedVector3Array()
	var trunk_x: Array[Transform3D] = []
	var tree_cols: Array = []       # [x, y, z, 半径, 高]
	var core_x: Array[Transform3D] = []
	var core_c: Array[Color] = []
	var card_x: Array[Transform3D] = []
	var card_c: Array[Color] = []
	var card_d: Array[Color] = []
	var placed: Array[Vector2] = []
	var cactus_x: Array[Transform3D] = []
	var cactus_at: Array[Vector2] = []
	var crowns := PackedVector3Array()  # 树冠的范围 (x, z, 半径)：冰山不能戳进树冠  # 仙人掌也占了 placed 里的位置（保持间距），但不算树（没有树叶声）
	var cactus_cols: Array = []     # [x, y, z, 半径, 高]
	var ice_x: Array = []           # [Transform3D, 第几种形状]
	var drift_x: Array[Transform3D] = []

	# ── 树：成片聚成树林，中间留出开阔草地；太陡、太高、小路上、池塘边都不长 ──
	# 每个群系的树种不同：雪原是积雪的松树，秋林是红黄的树，樱花林几乎都是粉色；沙漠里换成仙人掌，冰原上几乎没有树
	var want := int(round(tree_count * area * (1.0 - mid_b.g * 0.85 - mid_ice * 0.8 + mid_b.a * 0.15)))
	var tries := 0
	while placed.size() < want and tries < want * 14:
		tries += 1
		if _quitting:
			return {}
		var x := ox + r.randf_range(4.0, CHUNK - 4.0)
		var z := oz + r.randf_range(4.0, CHUNK - 4.0)
		var p := Vector2(x, z)
		var bw := biome_w(x, z)
		if _grove(x, z) < -0.05 and r.randf() < 0.85 - bw.a * 0.3:
			continue
		var h := _grid_h(hs, n, ox, oz, x, z)
		if h > TREE_LINE - r.randf() * 20.0 or _grid_slope(hs, n, ox, oz, x, z) > 0.6:
			continue
		if p.distance_to(sp) < 7.0 or not _clear(x, z, ponds) or _path_dist(x, z) < 3.0:
			continue
		var ok := true
		for q in placed:
			if q.distance_to(p) < 6.5:
				ok = false
				break
		if not ok:
			continue
		placed.append(p)

		var bid := int(biome_at(x, z).x)
		if bid == 2:
			_add_cactus(r, x, h, z, cactus_x, cactus_cols, blockers)
			cactus_at.append(p)
			continue
		if bid == 1 or bid == 5:
			_add_pine(r, x, h, z, 1.0, trunk_x, tree_cols, blockers, core_x, core_c, card_x, card_c, card_d, crowns)
			_add_drift(r, drift_x, x, h, z, r.randf_range(0.9, 1.3))
			continue

		var th := r.randf_range(3.0, 4.6)
		var tr := r.randf_range(0.30, 0.42)
		trunk_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(tr, th + 0.4, tr)), Vector3(x, h - 0.4 + (th + 0.4) * 0.5, z)))
		blockers.append(Vector3(x, z, tr + 0.25))
		tree_cols.append([x, h, z, tr * 0.85, th])

		var base_col: Color = BLOSSOMS[r.randi() % BLOSSOMS.size()] if r.randf() < 0.14 else GREENS[r.randi() % GREENS.size()]
		if bid == 3:
			base_col = AUTUMN[r.randi() % AUTUMN.size()]
		elif bid == 4:
			base_col = SAKURA[r.randi() % SAKURA.size()] if r.randf() < 0.9 else GREENS[r.randi() % GREENS.size()]
		var core_col := _lin(base_col.darkened(0.1))     # 芯和叶片背光面差不多颜色，从缝里看到的只是更深一点的树叶
		var big := r.randf_range(2.0, 2.8)
		var top := Vector3(x, h + th + big * 0.35, z)
		var canopy := top - Vector3(0.0, big * 0.45, 0.0)
		var rad := Vector3(big, big * 0.82, big)
		core_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(rad * CORE_SCALE), top))
		core_c.append(core_col)
		crowns.append(Vector3(x, z, big * 1.9))
		_add_leaf_cards(r, top, rad, canopy, base_col, 66, card_x, card_c, card_d)
		var side_n := r.randi_range(4, 6)
		var a0 := r.randf() * TAU
		for s in side_n:
			var ang := a0 + TAU * s / side_n + r.randf_range(-0.3, 0.3)
			var sr := big * r.randf_range(0.55, 0.75)
			var off := Vector3(cos(ang), 0.0, sin(ang)) * big * r.randf_range(0.65, 0.85)
			off.y = -big * r.randf_range(0.2, 0.5)
			var srad := Vector3(sr, sr * 0.85, sr)
			core_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(srad * CORE_SCALE), top + off))
			core_c.append(core_col)
			_add_leaf_cards(r, top + off, srad, canopy, base_col, 34, card_x, card_c, card_d)

	var trunk_block := blockers.duplicate()    # 到这里为止 blockers 里只有树干：石头只避开树干，石头之间可以挨着堆
	# ── 灌木：贴地的小团树叶 ──
	for i in int(round(bush_count * area)):
		var x := ox + r.randf_range(3.0, CHUNK - 3.0)
		var z := oz + r.randf_range(3.0, CHUNK - 3.0)
		var h := _grid_h(hs, n, ox, oz, x, z)
		if h > TREE_LINE or _grid_slope(hs, n, ox, oz, x, z) > 0.7:
			continue
		if Vector2(x, z).distance_to(sp) < 5.0 or _blocked(blockers, x, z) or not _clear(x, z, ponds):
			continue
		var bbid := int(biome_at(x, z).x)
		if bbid == 1 or bbid == 5 or (bbid == 2 and r.randf() < 0.8):
			continue        # 雪原、冰原没有灌木；沙漠里只有零星的干灌木
		var bb := Color(0, 0, 0, 0)
		var bc: Color = GREENS[r.randi() % GREENS.size()].darkened(0.06)
		if bbid == 3:
			bc = AUTUMN[r.randi() % AUTUMN.size()].darkened(0.1)
		elif bbid == 2:
			bc = Color(0.58, 0.56, 0.30)        # 沙漠里的干灌木
		var bush_center := Vector3(x, h - 0.3, z)
		for s in r.randi_range(2, 4):
			var br := r.randf_range(0.5, 0.95)
			var bx := x + r.randf_range(-0.7, 0.7)
			var bz := z + r.randf_range(-0.7, 0.7)
			var c := Vector3(bx, _grid_h(hs, n, ox, oz, bx, bz) + br * 0.45, bz)
			# 灌木不放深色的芯：它一半埋在地里，下半部没有叶片遮挡，芯的圆边会贴着地面露出来。
			# 灌木够小，光靠叶片面片就能挡严实
			_add_leaf_cards(r, c, Vector3(br, br * 0.8, br), bush_center, bc, 26, card_x, card_c, card_d, -0.35, bb.r)
			blockers.append(Vector3(bx, bz, br * 0.7))

	# ── 石头：山里更多、更大 ──
	var rocks: Array = []       # [Transform3D, 第几种形状]
	for g in int(round(rock_group_count * area * (1.0 + 3.0 * mid_m))):
		var gx := ox + r.randf_range(5.0, CHUNK - 5.0)
		var gz := oz + r.randf_range(5.0, CHUNK - 5.0)
		if Vector2(gx, gz).distance_to(sp) < 7.0 or not _clear(gx, gz, ponds) or _path_dist(gx, gz) < 4.0:
			continue
		var big_k := 1.0 + mid_m * 0.8 + mid_b.g * 0.6
		var gid := int(biome_at(gx, gz).x)
		var rmat := 1 if (gid == 1 or gid == 5) else (2 if gid == 2 else 0)
		for i in r.randi_range(1, 4):
			var s := (r.randf_range(0.7, 2.3) if i == 0 else r.randf_range(0.4, 1.1)) * big_k
			var x := gx if i == 0 else gx + r.randf_range(-3.5, 3.5)
			var z := gz if i == 0 else gz + r.randf_range(-3.5, 3.5)
			var scl := Vector3(s * r.randf_range(0.85, 1.25), s * r.randf_range(0.6, 0.95), s * r.randf_range(0.85, 1.25))
			if _blocked_r(trunk_block, x, z, maxf(scl.x, scl.z)):
				continue        # 不能长在树干里
			var rid := int(biome_at(x, z).x)
			rmat = 1 if (rid == 1 or rid == 5) else (2 if rid == 2 else 0)   # 每块石头按自己所在的群系
			var b := Basis.from_euler(Vector3(r.randf_range(-0.25, 0.25), r.randf() * TAU, r.randf_range(-0.25, 0.25))) * Basis.from_scale(scl)
			rocks.append([Transform3D(b, Vector3(x, _grid_h(hs, n, ox, oz, x, z) + scl.y * 0.3, z)), r.randi() % 5, rmat])
			if rmat == 1:
				_add_drift(r, drift_x, x, _grid_h(hs, n, ox, oz, x, z), z, maxf(scl.x, scl.z) * 1.05)
			blockers.append(Vector3(x, z, maxf(scl.x, scl.z) * 0.9))

	# ── 冰山：冰原上一簇簇冰蓝色的尖冰，大的有十几米高 ──
	if mid_ice > 0.05:
		for g in int(round(9.0 * area * 4.0 * mid_ice)):
			var gx := ox + r.randf_range(6.0, CHUNK - 6.0)
			var gz := oz + r.randf_range(6.0, CHUNK - 6.0)
			var gi := ice_w(gx, gz)
			if r.randf() > gi or Vector2(gx, gz).distance_to(sp) < 12.0:
				continue
			var base := r.randf_range(1.2, 3.2) * (0.6 + gi * 0.6)
			for i in r.randi_range(2, 6):
				var s := base * (1.0 if i == 0 else r.randf_range(0.35, 0.75))
				var x := gx if i == 0 else gx + r.randf_range(-1.6, 1.6) * base
				var z := gz if i == 0 else gz + r.randf_range(-1.6, 1.6) * base
				var tall := r.randf_range(2.2, 4.2) if i == 0 else r.randf_range(1.4, 3.0)
				var scl := Vector3(s * r.randf_range(0.8, 1.1), s * tall, s * r.randf_range(0.8, 1.1))
				# 尖冰会歪，顶部最多偏出 高度 × 0.25：要离树冠和别的东西足够远
				var reach := maxf(scl.x, scl.z) + scl.y * 0.25
				if _blocked_r(crowns, x, z, reach) or _blocked_r(blockers, x, z, maxf(scl.x, scl.z)):
					continue
				var lean := Vector3(r.randf_range(-0.22, 0.22), r.randf() * TAU, r.randf_range(-0.22, 0.22))
				var b := Basis.from_euler(lean) * Basis.from_scale(scl)
				var y := _grid_h(hs, n, ox, oz, clampf(x, ox, ox + CHUNK - 0.1), clampf(z, oz, oz + CHUNK - 0.1))
				ice_x.append([Transform3D(b, Vector3(x, y + scl.y * 0.35, z)), r.randi() % 5])
				blockers.append(Vector3(x, z, maxf(scl.x, scl.z) * 0.9))

	# ── 散落的小石子（没有碰撞）：小路、池塘边和山坡上多一些 ──
	var pebble_x: Array[Transform3D] = []
	for i in int(round(pebble_count * area)):
		var x := ox + r.randf() * CHUNK
		var z := oz + r.randf() * CHUNK
		var b := _bare(x, z, ponds)
		if maxf(b.x, b.y) < 0.3 and r.randf() < 0.6 - 0.4 * mid_m:
			continue
		var pid := int(biome_at(x, z).x)
		if pid == 1 or pid == 5 or b.z > 0.1:
			continue        # 雪地和冰面上没有小石子
		var s := r.randf_range(0.06, 0.24)
		var pb := Basis.from_euler(Vector3(r.randf() * TAU, r.randf() * TAU, 0.0)) * Basis.from_scale(Vector3(s, s * 0.7, s))
		pebble_x.append(Transform3D(pb, Vector3(x, _grid_h(hs, n, ox, oz, x, z) + s * 0.2, z)))

	# ── 花：一丛一丛的，只长在草原上 ──
	var flower_x: Array[Transform3D] = []
	var flower_c: Array[Color] = []
	var centers: Array[Vector3] = []
	var per := int(float(flower_count) / 70.0)
	for ci in int(round(70.0 * area)):
		var cx := ox + r.randf_range(4.0, CHUNK - 4.0)
		var cz := oz + r.randf_range(4.0, CHUNK - 4.0)
		var radius := r.randf_range(2.5, 7.0)
		var col: Color = FLOWER_COLORS[r.randi() % FLOWER_COLORS.size()]
		var col2: Color = FLOWER_COLORS[r.randi() % FLOWER_COLORS.size()]
		if mountain_mask(cx, cz) > 0.3:
			continue
		var fba := biome_at(cx, cz)
		var fid := int(fba.x)
		var edge_check := fba.y < 0.995      # 靠近群系边界的花丛：每朵花单独检查，不让花越过边界
		if fid == 1 or fid == 2 or fid == 5:
			continue        # 雪原、沙漠、冰原不长花
		if fid == 4:
			col = [Color(1.0, 0.70, 0.82), Color(1.0, 1.0, 1.0), Color(1.0, 0.86, 0.92)][r.randi() % 3]
			col2 = Color(1.0, 0.62, 0.76)
		elif fid == 3:
			col = [Color(1.0, 0.88, 0.30), Color(1.0, 0.62, 0.26), Color(1.0, 1.0, 1.0)][r.randi() % 3]
			col2 = Color(0.80, 0.62, 1.0)
		var before := flower_x.size()
		for i in per:
			var ang := r.randf() * TAU
			var d := sqrt(r.randf()) * radius
			var x := clampf(cx + cos(ang) * d, ox, ox + CHUNK - 0.01)
			var z := clampf(cz + sin(ang) * d, oz, oz + CHUNK - 0.01)
			if _blocked(blockers, x, z):
				continue
			if edge_check and int(biome_at(x, z).x) != fid:
				continue
			var b := _bare(x, z, ponds)
			if maxf(maxf(b.x, b.y), b.z) > 0.3 or _grid_slope(hs, n, ox, oz, x, z) > 0.6:
				continue
			var s := r.randf_range(0.8, 1.35)
			flower_x.append(Transform3D(Basis(Vector3.UP, r.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, _grid_h(hs, n, ox, oz, x, z) - 0.02, z)))
			flower_c.append(_lin(col if r.randf() < 0.8 else col2))
		if flower_x.size() - before > per / 3:
			centers.append(Vector3(cx, _grid_h(hs, n, ox, oz, cx, cz), cz))

	var ymin := INF
	var ymax := -INF
	for h in hs:
		ymin = minf(ymin, h)
		ymax = maxf(ymax, h)
	return {
		"blockers": blockers, "trees": placed.filter(func(q): return not cactus_at.has(q)), "tree_cols": tree_cols, "trunk_x": trunk_x,
		"core_x": core_x, "core_c": core_c, "card_x": card_x, "card_c": card_c, "card_d": card_d,
		"rocks": rocks, "pebble_x": pebble_x, "cactus_x": cactus_x, "drift_x": drift_x, "cactus_cols": cactus_cols, "ice_x": ice_x, "flower_x": flower_x, "flower_c": flower_c,
		"centers": centers, "ymin": ymin, "ymax": ymax,
	}


## 这个位置能不能放树/石头/灌木：不在小路、泥地、池塘上
func _clear(x: float, z: float, ponds: Array[Vector4]) -> bool:
	var b := _bare(x, z, ponds)
	if maxf(maxf(b.x, b.y), b.z) > 0.15:
		return false
	for p in ponds:
		if Vector2(x - p.x, z - p.y).length() < POND_RADIUS + 3.0:
			return false
	return true


## 回到主线程：把算好的数据变成节点
func _deco_ready(key: Vector2i, d: Dictionary, tok: int) -> void:
	_job_done(tok)
	if not chunks.has(key):
		return
	var ch: Dictionary = chunks[key]
	if d.is_empty() or ch.deco_state != 1:
		ch.deco_state = 0
		return
	var deco := Node3D.new()
	deco.name = "Deco_%d_%d" % [key.x, key.y]
	add_child(deco)
	var body := StaticBody3D.new()
	deco.add_child(body)
	var bounds := AABB(Vector3(key.x * CHUNK - 6.0, d.ymin - 4.0, key.y * CHUNK - 6.0), Vector3(CHUNK + 12.0, d.ymax - d.ymin + 20.0, CHUNK + 12.0))

	if not d.trunk_x.is_empty():
		var trunks := _make_multimesh(trunk_mesh, d.trunk_x)
		trunks.material_override = trunk_mat
		deco.add_child(trunks)
		var cores := _make_multimesh(core_mesh, d.core_x, d.core_c)
		cores.material_override = core_mat
		# 芯是光滑的球，投影会变成地上几个圆；只让叶片面片投影，树荫边缘才是碎叶形状
		cores.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		deco.add_child(cores)
		for t: Array in d.tree_cols:
			var cyl := CylinderShape3D.new()
			cyl.radius = t[3]
			cyl.height = t[4]
			var tcol := CollisionShape3D.new()
			tcol.shape = cyl
			tcol.position = Vector3(t[0], t[1] + t[4] * 0.5, t[2])
			body.add_child(tcol)
	if not d.card_x.is_empty():
		var cards := _make_multimesh(card_mesh, d.card_x, d.card_c, d.card_d)
		cards.material_override = card_mat
		cards.custom_aabb = bounds
		deco.add_child(cards)

	for rk: Array in d.rocks:
		var xf: Transform3D = rk[0]
		var vi: int = rk[1]
		var mi := MeshInstance3D.new()
		mi.mesh = rock_variants[vi]
		mi.material_override = rock_mats[rk[2]]
		mi.transform = xf
		deco.add_child(mi)
		var pts := PackedVector3Array()
		for p in rock_points[vi]:
			pts.append(xf * p)
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)

	for ik: Array in d.ice_x:
		var xf: Transform3D = ik[0]
		var vi: int = ik[1]
		var mi := MeshInstance3D.new()
		mi.mesh = rock_variants[vi]
		mi.material_override = ice_mat
		mi.transform = xf
		deco.add_child(mi)
		var pts := PackedVector3Array()
		for p in rock_points[vi]:
			pts.append(xf * p)
		var shape := ConvexPolygonShape3D.new()
		shape.points = pts
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)

	if not d.drift_x.is_empty():
		var drifts := _make_multimesh(drift_mesh, d.drift_x)
		drifts.material_override = drift_mat
		drifts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		drifts.visibility_range_end = 220.0
		deco.add_child(drifts)

	if not d.cactus_x.is_empty():
		var cacti := _make_multimesh(cactus_mesh, d.cactus_x)
		cacti.material_override = cactus_mat
		deco.add_child(cacti)
		for t: Array in d.cactus_cols:
			var cyl := CylinderShape3D.new()
			cyl.radius = t[3]
			cyl.height = t[4]
			var ccol := CollisionShape3D.new()
			ccol.shape = cyl
			ccol.position = Vector3(t[0], t[1] + t[4] * 0.5, t[2])
			body.add_child(ccol)

	if not d.pebble_x.is_empty():
		var pebbles := _make_multimesh(rock_variants[0], d.pebble_x)
		pebbles.material_override = pebble_mat
		pebbles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pebbles.visibility_range_end = 110.0
		deco.add_child(pebbles)
	if not d.flower_x.is_empty():
		var flowers := _make_multimesh(flower_mesh, d.flower_x, [], d.flower_c)
		flowers.material_override = flower_mat
		flowers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flowers.visibility_range_end = 150.0
		deco.add_child(flowers)

	ch.deco = deco
	ch.deco_state = 2
	ch.blockers = d.blockers
	ch.trees = d.trees
	ch.flowers = d.centers
	_lists_dirty = true


# ───────────────────────── 草 ─────────────────────────

func _make_blade_mesh() -> ArrayMesh:
	var w := 0.07
	var h := 0.55
	var verts := PackedVector3Array([
		Vector3(-w, 0.0, 0.0), Vector3(w, 0.0, 0.0),
		Vector3(-w * 0.72, h * 0.5, 0.03), Vector3(w * 0.72, h * 0.5, 0.03),
		Vector3(0.0, h, 0.10),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, 0.5), Vector2(1.0, 0.5), Vector2(0.5, 1.0),
	])
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 3, 0, 3, 2, 2, 3, 4])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _job_grass(gkey: Vector2i, blockers: PackedVector3Array, tok: int) -> void:
	var d := _compute_grass(gkey, blockers)
	if not _quitting:
		_grass_ready.call_deferred(gkey, d, tok)


## 在工作线程里运行：只读数据 + 填一个浮点数组，不碰场景树
## 每片草 20 个浮点：12 个是变换矩阵，4 个是颜色（群系权重），4 个是自定义数据（高度倍率 / 抽稀序号 / 随机数 / 空）
func _compute_grass(gkey: Vector2i, all_blockers: PackedVector3Array) -> Dictionary:
	var ox := gkey.x * GCHUNK
	var oz := gkey.y * GCHUNK
	var gn := int(GCHUNK / CELL)
	var ponds := _ponds_near(ox, oz, ox + GCHUNK, oz + GCHUNK)
	var hs := _height_grid(ox, oz, gn, ponds)
	# 每半米一格，先把"这里是不是泥土/沙"算成一张表，每片草直接查
	var bn := int(GCHUNK * 2.0)
	var bg := PackedFloat32Array()
	bg.resize(bn * bn)
	for bz in bn:
		if _quitting:
			return {}
		for bx in bn:
			var b := _bare(ox + (bx + 0.5) * 0.5, oz + (bz + 0.5) * 0.5, ponds)
			bg[bz * bn + bx] = maxf(maxf(b.x, b.y), b.z)
	# 只留下碰得到这一块的树和石头
	var blockers := PackedVector3Array()
	for b in all_blockers:
		if b.x > ox - b.z and b.x < ox + GCHUNK + b.z and b.y > oz - b.z and b.y < oz + GCHUNK + b.z:
			blockers.append(b)

	# 群系每 2 米算一个点（和地形顶点一样密），草的颜色和疏密才能和地面对得上
	var bgw: Array[Color] = []
	bgw.resize((gn + 1) * (gn + 1))
	for iz in gn + 1:
		for ix in gn + 1:
			bgw[iz * (gn + 1) + ix] = biome_w(ox + ix * CELL, oz + iz * CELL)

	var r := RandomNumberGenerator.new()
	r.seed = hash(Vector3i(world_seed + 991, gkey.x, gkey.y))
	var buf := PackedFloat32Array()
	const STRIDE := 20      # 12 变换 + 4 颜色 + 4 自定义数据
	buf.resize(grass_per_chunk * STRIDE)
	var n := 0
	var ymin := INF
	var ymax := -INF
	var inv := 1.0 / float(grass_per_chunk)
	for i in grass_per_chunk:
		if _quitting:
			return {}
		var x := ox + r.randf() * GCHUNK
		var z := oz + r.randf() * GCHUNK
		var b := bg[mini(int((z - oz) * 2.0), bn - 1) * bn + mini(int((x - ox) * 2.0), bn - 1)]
		if b > 0.5 or _blocked(blockers, x, z):
			continue
		var fx := (x - ox) / CELL
		var fz := (z - oz) / CELL
		var gx0 := mini(int(fx), gn - 1)
		var gz0 := mini(int(fz), gn - 1)
		fx -= gx0
		fz -= gz0
		var gi := gz0 * (gn + 1) + gx0
		var bw: Color = bgw[gi].lerp(bgw[gi + 1], fx).lerp(bgw[gi + gn + 1].lerp(bgw[gi + gn + 2], fx), fz)
		# 雪原只有零星露出雪面的草尖，沙漠只有稀疏的干草丛
		if bw.r > 0.45 or r.randf() < bw.r * 2.0 + bw.g * 0.82:
			continue
		var y := _grid_h(hs, gn, ox, oz, x, z)
		# 陡坡是岩石，高处是岩石和雪：坡越陡、越高，草越稀
		if _grid_slope(hs, gn, ox, oz, x, z) > 0.5 + r.randf() * 0.35 or y > GRASS_LINE + r.randf() * 45.0:
			continue
		var wet := false
		for p in ponds:
			if y < p.z - 0.26 and Vector2(x - p.x, z - p.y).length() < POND_RADIUS + 1.0:
				wet = true
		if wet:
			continue
		# 用噪声让草有高有矮、成片变化；靠近小路的草矮一些
		var tall := (0.75 + patch_noise.get_noise_2d(x, z) * 0.45) * (1.0 - b * 1.2) * (1.0 - bw.r * 0.45 - bw.g * 0.2 + bw.b * 0.15)
		var sy := tall * r.randf_range(0.7, 1.3)
		var sw := r.randf_range(0.8, 1.35)
		var ang := r.randf() * TAU
		var c := cos(ang) * sw
		var s := sin(ang) * sw
		var o := n * STRIDE
		buf[o] = c
		buf[o + 1] = 0.0
		buf[o + 2] = s
		buf[o + 3] = x
		buf[o + 4] = 0.0
		buf[o + 5] = sy
		buf[o + 6] = 0.0
		buf[o + 7] = y - 0.02
		buf[o + 8] = -s
		buf[o + 9] = 0.0
		buf[o + 10] = c
		buf[o + 11] = z
		buf[o + 16] = sy
		buf[o + 17] = n * inv
		buf[o + 18] = r.randf()
		buf[o + 19] = 0.0
		# 实例颜色 = 群系权重（雪原 / 沙漠 / 秋林 / 樱花林），草的颜色在着色器里按它混合
		buf[o + 12] = bw.r
		buf[o + 13] = bw.g
		buf[o + 14] = bw.b
		buf[o + 15] = bw.a
		ymin = minf(ymin, y)
		ymax = maxf(ymax, y)
		n += 1
	buf.resize(n * STRIDE)
	return {"buf": buf, "n": n, "ymin": ymin, "ymax": ymax}


func _grass_ready(gkey: Vector2i, d: Dictionary, tok: int) -> void:
	_job_done(tok)
	if not gchunks.has(gkey):
		return
	if d.is_empty():
		gchunks.erase(gkey)
		return
	var origin := Vector2(gkey.x, gkey.y) * GCHUNK
	var rec := {"mm": null, "n": 0, "rect": Rect2(origin, Vector2(GCHUNK, GCHUNK)), "node": null}
	gchunks[gkey] = rec
	var n: int = d.n
	if n == 0:
		return      # 这一块全是岩石 / 水 / 路：记下来，免得反复重算
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = blade_mesh
	mm.instance_count = n
	mm.buffer = d.buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = grass_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(origin.x - 1.0, d.ymin - 0.5, origin.y - 1.0), Vector3(GCHUNK + 2.0, d.ymax - d.ymin + 2.0, GCHUNK + 2.0))
	mmi.visibility_range_end = grass_view_distance + GCHUNK * 0.75
	mmi.visibility_range_end_margin = 6.0
	add_child(mmi)
	rec.mm = mm
	rec.n = n
	rec.node = mmi
	if player:
		_update_grass_lod(player.global_position)


## 远处的草块只画一部分草叶（和着色器里的抽稀用同一条曲线，所以看不出跳变）
func _update_grass_lod(cam: Vector3) -> void:
	var p := Vector2(cam.x, cam.z)
	for g: Dictionary in gchunks.values():
		if g.has("pending") or g.mm == null:
			continue
		var rect: Rect2 = g.rect
		var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
		var d := q.distance_to(p)
		var dens := lerpf(1.0, GRASS_MIN_DENSITY, smoothstep(GRASS_FADE_START, GRASS_FADE_END, d)) + 0.07
		var count := mini(g.n, int(ceil(dens * grass_per_chunk)))
		if d > grass_view_distance:
			count = 0
		var mm: MultiMesh = g.mm
		if mm.visible_instance_count != count:
			mm.visible_instance_count = count


# ───────────────────────── 花的网格 ─────────────────────────

func _make_flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var stem_h := 0.62
	var sw := 0.012
	# UV2 当遮罩：x = 花瓣，y = 花心，都是 0 = 茎
	st.set_uv2(Vector2(0, 0))
	for axis in 2:
		var side := Vector3(sw, 0, 0) if axis == 0 else Vector3(0, 0, sw)
		var quad: Array[Vector3] = [-side, side, side + Vector3(0, stem_h, 0), -side + Vector3(0, stem_h, 0)]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_uv(Vector2(0.5, quad[idx].y / stem_h))
			st.add_vertex(quad[idx])
	# 花瓣：5 片菱形，稍微上翘
	st.set_uv(Vector2(0.5, 1.0))
	var petals := 5
	var pr := 0.12
	var c := Vector3(0, stem_h, 0)
	for i in petals:
		var a := TAU * i / petals
		var half := TAU / petals * 0.48
		var tip := c + Vector3(cos(a), 0.22, sin(a)) * pr
		var l := c + Vector3(cos(a - half), 0.08, sin(a - half)) * pr * 0.62
		var r := c + Vector3(cos(a + half), 0.08, sin(a + half)) * pr * 0.62
		st.set_uv2(Vector2(1, 0))
		for v: Vector3 in [c, l, tip, c, tip, r]:
			st.add_vertex(v)
	# 花心
	st.set_uv2(Vector2(0, 1))
	var cc := c + Vector3(0, 0.012, 0)
	for i in 6:
		var a0 := TAU * i / 6.0
		var a1 := TAU * (i + 1) / 6.0
		st.add_vertex(cc)
		st.add_vertex(cc + Vector3(cos(a0), 0, sin(a0)) * 0.035)
		st.add_vertex(cc + Vector3(cos(a1), 0, sin(a1)) * 0.035)
	return st.commit()


# ───────────────────────── 玩家 & 提示 ─────────────────────────

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	hud_label = Label.new()
	hud_label.position = Vector2(16, 12)
	hud_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	hud_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	hud_label.add_theme_font_size_override("font_size", 18)
	layer.add_child(hud_label)
	add_child(layer)
	var map := Control.new()
	map.set_script(load("res://scripts/minimap.gd"))
	layer.add_child(map)
	map.setup(self)


func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(load("res://scripts/player.gd"))
	player.set("bound", 1.0e9)     # 无限地图，没有边界
	player.set("spawn_point", spawn)
	player.position = spawn
	add_child(player)
	player.connect("stepped", _on_player_stepped)


func _on_player_stepped(landing: bool) -> void:
	var p := player.global_position
	_stamp_footprint(p, landing)
	var surface := "grass"
	if p.y < water_level - 0.03 and Vector2(p.x, p.z).distance_to(POND_CENTER) < POND_RADIUS + 1.0:
		surface = "water"
	elif ice_at(p.x, p.z) > 0.5:
		surface = "ice"
	elif bare_at(p.x, p.z) > 0.5:
		surface = "dirt"
	else:
		var bw := biome_w(p.x, p.z)
		if bw.r > 0.5:
			surface = "snow"
		elif bw.g > 0.5:
			surface = "sand"
	if ambience:
		ambience.play_step(surface, landing)


# ───────────────────────── 雪地 / 沙地脚印 ─────────────────────────

## 玩家离贴图中心太远时整张图平移，让玩家回到中心
func _trail_update(p: Vector3) -> void:
	var cx := int(floor(p.x / TRAIL_PX)) - TRAIL_RES / 2
	var cz := int(floor(p.z / TRAIL_PX)) - TRAIL_RES / 2
	var shift := Vector2i(cx, cz) - trail_origin
	if absi(shift.x) > 250 or absi(shift.y) > 250:
		var img := Image.create(TRAIL_RES, TRAIL_RES, false, Image.FORMAT_L8)
		if absi(shift.x) < TRAIL_RES and absi(shift.y) < TRAIL_RES:
			img.blit_rect(trail_img, Rect2i(shift, Vector2i(TRAIL_RES, TRAIL_RES)), Vector2i.ZERO)
		trail_img = img
		trail_origin = Vector2i(cx, cz)
		_trail_dirty = true
	if _trail_dirty:
		_trail_dirty = false
		trail_tex.update(trail_img)
		terrain_mat.set_shader_parameter("trail_origin", Vector2(trail_origin) * TRAIL_PX)


## 柔和的圆点贴图（雪沫、白气共用）
func _soft_dot() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func _fade_curve(peak: float) -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(peak, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c


func _build_snow_fx() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var alpha_ramp := Gradient.new()
	alpha_ramp.set_color(0, Color(1, 1, 1, 1.0))
	alpha_ramp.set_color(1, Color(1, 1, 1, 0.0))
	for i in 6:
		var q := QuadMesh.new()
		q.size = Vector2(0.13, 0.13)
		q.material = mat
		var ps := CPUParticles3D.new()
		ps.mesh = q
		ps.emitting = false
		ps.one_shot = true
		ps.amount = 14
		ps.lifetime = 0.7
		ps.explosiveness = 0.95
		ps.direction = Vector3(0, 1, 0)
		ps.spread = 70.0
		ps.initial_velocity_min = 0.5
		ps.initial_velocity_max = 1.4
		ps.gravity = Vector3(0, -3.5, 0)
		ps.damping_min = 1.5
		ps.damping_max = 3.0
		ps.scale_amount_min = 0.6
		ps.scale_amount_max = 1.6
		ps.color_ramp = alpha_ramp
		ps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		ps.emission_sphere_radius = 0.06
		ps.local_coords = false
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ps)
		_puffs.append(ps)
	var breath_ramp := Gradient.new()
	breath_ramp.set_color(0, Color(1, 1, 1, 0.0))
	breath_ramp.set_color(1, Color(1, 1, 1, 0.0))
	breath_ramp.add_point(0.15, Color(1, 1, 1, 0.6))
	for i in 3:
		var q := QuadMesh.new()
		q.size = Vector2(0.22, 0.22)
		q.material = mat
		var ps := CPUParticles3D.new()
		ps.mesh = q
		ps.emitting = false
		ps.one_shot = true
		ps.amount = 10
		ps.lifetime = 1.4
		ps.explosiveness = 0.6
		ps.spread = 18.0
		ps.initial_velocity_min = 0.25
		ps.initial_velocity_max = 0.5
		ps.gravity = Vector3(0, 0.12, 0)
		ps.damping_min = 0.3
		ps.damping_max = 0.6
		ps.scale_amount_min = 0.6
		ps.scale_amount_max = 1.0
		ps.scale_amount_curve = _grow_curve()
		ps.color_ramp = breath_ramp
		ps.local_coords = false
		ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ps)
		_breaths.append(ps)


func _grow_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.4))
	c.add_point(Vector2(1.0, 2.2))
	return c


## 脚边溅起一小团雪沫（沙漠里是黄色的沙尘，少一点）
func _puff(at: Vector3, vel: Vector3, landing: bool, snow: bool) -> void:
	var ps := _puffs[_puff_i]
	_puff_i = (_puff_i + 1) % _puffs.size()
	ps.global_position = at
	ps.color = Color(0.93, 0.96, 1.0) if snow else Color(0.92, 0.82, 0.60)     # 雪沫带一点点蓝，在亮的雪地上才看得出
	ps.amount = (28 if landing else 16) if snow else (10 if landing else 5)
	ps.initial_velocity_max = (2.0 if landing else 1.2) + vel.length() * 0.25
	ps.direction = (Vector3.UP + vel * 0.15).normalized()
	ps.restart()


## 雪原里每隔几秒在脸前面呼出一小团白气（跑起来更频繁）；晚上也有
func _update_breath(delta: float) -> void:
	if _snow_k_raw < 0.5 or _breaths.is_empty():
		return
	_breath_t -= delta
	if _breath_t > 0.0:
		return
	var hero = player.get("hero")
	if hero == null or hero.get("face") == null:
		return
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	_breath_t = randf_range(1.2, 1.8) if speed > 4.0 else randf_range(2.6, 4.0)
	var face: Node3D = hero.face
	var fwd: Vector3 = (hero as Node3D).global_basis.z.normalized()
	var ps := _breaths[_breath_i]
	_breath_i = (_breath_i + 1) % _breaths.size()
	ps.global_position = face.global_position + fwd * 0.22 - Vector3(0, 0.05, 0)
	ps.direction = (fwd + Vector3(0, 0.15, 0)).normalized()
	ps.initial_velocity_max = 0.5 + speed * 0.15
	ps.restart()


## 在脚下印一个椭圆形的脚印（左右脚交替；落地时两只脚一起）。只在雪原和沙漠印
func _stamp_footprint(p: Vector3, landing: bool) -> void:
	var bw := biome_w(p.x, p.z)
	if bw.r + bw.g < 0.25 or not player.is_on_floor():
		return
	var v := Vector2(player.velocity.x, player.velocity.z)
	var fwd := v.normalized() if v.length() > 0.3 else Vector2(0.0, 1.0)
	var hero = player.get("hero")
	if v.length() <= 0.3 and hero:
		var hz: Vector3 = (hero as Node3D).global_basis.z
		fwd = Vector2(hz.x, hz.z).normalized()
	var side := Vector2(-fwd.y, fwd.x)
	var feet := [-1.0, 1.0] if landing else [_trail_foot]
	_trail_foot = -_trail_foot
	for f: float in feet:
		var c := Vector2(p.x, p.z) + side * f * 0.13 + fwd * 0.05
		_stamp(c, fwd, 0.16, 0.10, 1.0 if landing else 0.85)
		_puff(Vector3(c.x, p.y + 0.03, c.y), Vector3(fwd.x, 0.0, fwd.y) * v.length(), landing, bw.r > bw.g)
	_trail_dirty = true


func _stamp(c: Vector2, fwd: Vector2, half_len: float, half_w: float, depth: float) -> void:
	var side := Vector2(-fwd.y, fwd.x)
	var rpx := int(ceil(half_len / TRAIL_PX)) + 2
	var cx := int(floor(c.x / TRAIL_PX)) - trail_origin.x
	var cz := int(floor(c.y / TRAIL_PX)) - trail_origin.y
	for dz in range(-rpx, rpx + 1):
		var iz := cz + dz
		if iz < 0 or iz >= TRAIL_RES:
			continue
		for dx in range(-rpx, rpx + 1):
			var ix := cx + dx
			if ix < 0 or ix >= TRAIL_RES:
				continue
			var q := Vector2((ix + trail_origin.x + 0.5) * TRAIL_PX, (iz + trail_origin.y + 0.5) * TRAIL_PX) - c
			var a := q.dot(fwd) / half_len
			var b := q.dot(side) / half_w
			var e := a * a + b * b
			if e >= 1.0:
				continue
			var val := depth * (1.0 - smoothstep(0.55, 1.0, e))
			var old := trail_img.get_pixel(ix, iz).r
			if val > old:
				trail_img.set_pixel(ix, iz, Color(val, val, val))


# ───────────────────────── 自测（开发用） ─────────────────────────
## `godot --path . -- --walktest`：把玩家快速拖过 1.6 公里，检查区块的生成和卸载不报错，然后退出

func _run_walktest(delta: float) -> void:
	_wt += delta
	if _wt < 6.0:
		return
	if _wt < 22.0:
		var a := _wt * 0.2
		player.global_position += Vector3(cos(a), 0.0, sin(a)) * 100.0 * delta
		player.global_position.y = height_raw(player.global_position.x, player.global_position.z) + 1.0
		player.velocity = Vector3.ZERO
		return
	if _wt > 30.0:
		var loaded := 0
		var lod0 := 0
		var deco := 0
		for ch: Dictionary in chunks.values():
			if ch.lod >= 0:
				loaded += 1
			if ch.lod == 0:
				lod0 += 1
			if ch.deco_state == 2:
				deco += 1
		var grass := 0
		for g: Dictionary in gchunks.values():
			if not g.has("pending") and g.mm != null:
				grass += 1
		var p := player.global_position
		print("WALKTEST pos=(%d, %d, %d) chunks=%d/%d lod0=%d deco=%d grass=%d trees=%d jobs=%d fps=%d" % [
			int(p.x), int(p.y), int(p.z), loaded, chunks.size(), lod0, deco, grass, tree_positions.size(), _jobs, int(Engine.get_frames_per_second())])
		# 山区的坡度统计：随机取点，看有多少能走、多少要爬、多少是峭壁
		var rr := RandomNumberGenerator.new()
		rr.seed = 1
		var mtn := 0
		var walk := 0
		var climb := 0
		var cliff := 0
		var top := 0.0
		var total := 20000
		for i in total:
			var x := rr.randf_range(-4000.0, 4000.0)
			var z := rr.randf_range(-4000.0, 4000.0)
			var h := _land(x, z)
			top = maxf(top, h)
			if mountain_mask(x, z) < 0.3:
				continue
			mtn += 1
			var sl := Vector2(_land(x + 2.0, z) - h, _land(x, z + 2.0) - h).length() / 2.0
			var deg := rad_to_deg(atan(sl))
			if deg < 46.0:
				walk += 1
			elif deg < 78.0:
				climb += 1
			else:
				cliff += 1
		print("TERRAIN mountain_area=%d%% highest=%dm | in mountains: walkable=%d%% climb=%d%% cliff=%d%%" % [
			mtn * 100 / total, int(top), walk * 100 / maxi(mtn, 1), climb * 100 / maxi(mtn, 1), cliff * 100 / maxi(mtn, 1)])
		# 群系面积和平原的平坦程度
		var counts := [0, 0, 0, 0, 0, 0]
		var plain := 0
		var flat_n := 0
		var relief := 0.0
		for i in 6000:
			var x := rr.randf_range(-6000.0, 6000.0)
			var z := rr.randf_range(-6000.0, 6000.0)
			counts[int(biome_at(x, z).x)] += 1
			if mountain_mask(x, z) > 0.0:
				continue
			plain += 1
			var h0 := _land(x, z)
			var sl := Vector2(_land(x + 2.0, z) - h0, _land(x, z + 2.0) - h0).length() / 2.0
			if rad_to_deg(atan(sl)) < 5.0:
				flat_n += 1
			relief += absf(_land(x + 100.0, z) - h0)
		var bs := ""
		for i in 6:
			bs += "%s=%d%% " % [BIOME_NAMES[i], counts[i] * 100 / 6000]
		print("BIOMES ", bs)
		print("PLAINS slope<5deg=%d%% avg height change over 100m=%.1fm" % [flat_n * 100 / maxi(plain, 1), relief / maxi(plain, 1)])
		_walktest = false
		get_tree().quit()
