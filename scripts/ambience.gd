extends Node
## 声音：风声（随阵风起伏）、树下的树叶沙沙声、按时段切换的环境声和鸟叫、夜晚虫鸣、池塘水声、脚步声。
## 素材都是 BBC 音效库的真实野外录音，处理时统一了响度（循环 RMS -20 dBFS，单次音效峰值 -3 dBFS）。
##
## 一天的声音：
##   清晨 5-9 点   黎明鸟群合唱（dawn_loop），近处鸟叫最频繁
##   白天 8-18 点  草地环境声（day_loop），正午最安静，鸟叫稀疏
##   黄昏 17-21 点 黄昏鸟鸣 + 渐起的虫声（dusk_loop），换成乌鸫、歌鸫、知更鸟
##   夜晚          树蟋（crickets_loop），没有鸟叫
##
## 群系（按玩家所在位置的权重慢慢过渡）：
##   雪原 / 冰原  呼啸的冷风（snow_wind_loop），没有鸟和虫；冰原上远处偶尔传来冰层"啾——"的声音（ice_ping_N）
##   沙漠        低沉的热风 + 卷沙声（desert_wind_loop），鸟很少，夜里照样有虫鸣
##   脚步声：草 / 泥土 / 水 / 雪 / 沙 / 冰
##   雪、沙、冰的脚步声和冷风、热风、冰层声是代码合成的（tools 里没有，生成脚本见 HANDOFF.md），其余是 BBC 录音

var world
var wind: AudioStreamPlayer
var leaves: AudioStreamPlayer
var dawn_bed: AudioStreamPlayer
var day_bed: AudioStreamPlayer
var dusk_bed: AudioStreamPlayer
var crickets: AudioStreamPlayer
var water: AudioStreamPlayer3D
var snow_wind: AudioStreamPlayer
var desert_wind: AudioStreamPlayer
var ice_player: AudioStreamPlayer3D
var ice_pings: Array[AudioStream] = []
var _ice_timer := 5.0
var _bw := Color(0, 0, 0, 0)     # 群系权重（平滑过的）：r 雪原 / g 沙漠 / b 秋林 / a 樱花林
var _ice := 0.0
var _bw_timer := 0.0
var bird_players: Array[AudioStreamPlayer] = []
var step_players: Array[AudioStreamPlayer] = []
var birds: Array[AudioStream] = []
var steps := {}          # "grass" / "dirt" / "water" -> Array[AudioStream]
var _bird_timer := 2.0
var _step_i := 0
var _t := 0.0
var _canopy := 0.0       # 0 = 开阔草地，1 = 站在树冠下
var _canopy_timer := 0.0
var _rng := RandomNumberGenerator.new()

const STEP_GAIN := {"grass": -9.0, "dirt": -12.0, "water": -7.0, "snow": -10.0, "sand": -12.0, "ice": -13.0}
const STEP_FILES := 8
const BIRD_FILES := 14

# bird_N.ogg 是哪种鸟：1-2 云雀  3-4 黄鹀  5-6 歌鸫  7 苍头燕雀  8-9 知更鸟  10-11 鹪鹩  12-14 乌鸫
const BIRDS_MORNING := [1, 2, 3, 4, 7, 8, 9, 10, 11]
const BIRDS_MIDDAY := [1, 2, 3, 4]
const BIRDS_EVENING := [5, 6, 8, 9, 12, 13, 14]

const LEAVES_RANGE := 7.0    # 离树多远开始听得到树叶声（米）


func _stream(file: String, loop := false) -> AudioStream:
	var path := "res://audio/" + file
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path) as AudioStream
	if s == null:
		# 还没被编辑器导入时，直接从文件读
		s = AudioStreamOggVorbis.load_from_file(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	return s


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


func _loop_player(file: String) -> AudioStreamPlayer:
	var p := _player(_stream(file, true), -80.0)
	p.play()
	# 各段循环从随机位置开始，避免每次进游戏听到的都一样
	p.seek(_rng.randf() * maxf(p.stream.get_length() - 1.0, 0.0))
	return p


func setup(w) -> void:
	world = w
	_rng.randomize()

	wind = _loop_player("wind_loop.ogg")
	leaves = _loop_player("leaves_loop.ogg")
	dawn_bed = _loop_player("dawn_loop.ogg")
	day_bed = _loop_player("day_loop.ogg")
	dusk_bed = _loop_player("dusk_loop.ogg")
	crickets = _loop_player("crickets_loop.ogg")
	snow_wind = _loop_player("snow_wind_loop.ogg")
	desert_wind = _loop_player("desert_wind_loop.ogg")
	for i in range(1, 5):
		ice_pings.append(_stream("ice_ping_%d.ogg" % i))
	ice_player = AudioStreamPlayer3D.new()
	ice_player.unit_size = 25.0
	ice_player.max_distance = 200.0
	ice_player.attenuation_filter_cutoff_hz = 6000.0
	add_child(ice_player)

	water = AudioStreamPlayer3D.new()
	water.stream = _stream("water_loop.ogg", true)
	water.volume_db = -8.0
	water.unit_size = 4.0
	water.max_distance = 35.0
	add_child(water)
	water.global_position = Vector3(world.POND_CENTER.x, world.water_level, world.POND_CENTER.y)
	water.play()

	for i in range(1, BIRD_FILES + 1):
		birds.append(_stream("bird_%d.ogg" % i))
	for i in 2:
		bird_players.append(_player(null, -10.0))
	for surface in ["grass", "dirt", "water", "snow", "sand", "ice"]:
		var list: Array[AudioStream] = []
		for i in range(1, STEP_FILES + 1):
			list.append(_stream("step_%s_%d.ogg" % [surface, i]))
		steps[surface] = list
	for i in 3:
		step_players.append(_player(null, 0.0))


## t 在 [a, d] 之间时为 1 附近，a→b 淡入，c→d 淡出
func _band(t: float, a: float, b: float, c: float, d: float) -> float:
	return smoothstep(a, b, t) * (1.0 - smoothstep(c, d, t))


## 按权重设置循环的音量；权重为 0 时暂停，省一点 CPU
func _set_bed(p: AudioStreamPlayer, weight: float, db: float) -> void:
	p.stream_paused = weight < 0.01
	p.volume_db = db + linear_to_db(maxf(weight, 0.0001))


## 玩家附近有多少树冠：每棵树按距离做高斯衰减再相加
func _canopy_amount() -> float:
	var p: Vector3 = world.player.global_position
	var me := Vector2(p.x, p.z)
	var sum := 0.0
	for q: Vector2 in world.tree_positions:
		var d2 := me.distance_squared_to(q)
		if d2 < 900.0:
			sum += exp(-d2 / (2.0 * LEAVES_RANGE * LEAVES_RANGE))
	return clampf(sum, 0.0, 1.0)


func _process(delta: float) -> void:
	if world == null:
		return
	_t += delta
	var night: float = world.day_night.night
	var hour: float = world.day_night.time_of_day

	# 所在群系（权重慢慢跟上，走过边界时声音是渐变的）
	_bw_timer -= delta
	if _bw_timer <= 0.0 and world.player:
		_bw_timer = 0.5
		var pp: Vector3 = world.player.global_position
		_bw = _bw.lerp(world.biome_w(pp.x, pp.z), 0.3)
		_ice = lerpf(_ice, world.ice_w(pp.x, pp.z), 0.3)
	var cold := clampf(_bw.r, 0.0, 1.0)
	var hot := clampf(_bw.g, 0.0, 1.0)
	var life_k := (1.0 - cold) * (1.0 - hot * 0.8)     # 鸟叫和草地环境声的多少

	# 风声跟着阵风起伏
	var gust := clampf(0.5 + 0.3 * sin(_t * 0.23) + 0.2 * sin(_t * 0.61 + 1.3), 0.0, 1.0)
	wind.volume_db = lerpf(-15.0, -6.0, gust) - night * 3.0 + linear_to_db(maxf((1.0 - cold) * (1.0 - hot), 0.0001))
	wind.stream_paused = cold + hot > 0.99
	wind.pitch_scale = lerpf(0.97, 1.03, gust)
	_set_bed(snow_wind, cold * lerpf(0.55, 1.0, gust), -6.0 - night * 2.0)
	_set_bed(desert_wind, hot * lerpf(0.5, 1.0, gust), -7.0 - night * 3.0)

	# 冰原：远处冰层偶尔"啾——"一声，方向随机
	_ice_timer -= delta
	if _ice_timer <= 0.0:
		_ice_timer = _rng.randf_range(7.0, 18.0)
		if _ice > 0.4 and world.player and not ice_player.playing:
			var pp: Vector3 = world.player.global_position
			var a := _rng.randf() * TAU
			ice_player.global_position = pp + Vector3(cos(a), -1.0, sin(a)) * _rng.randf_range(25.0, 70.0)
			ice_player.stream = ice_pings[_rng.randi() % ice_pings.size()]
			ice_player.volume_db = _rng.randf_range(-6.0, 0.0) + linear_to_db(_ice)
			ice_player.pitch_scale = _rng.randf_range(0.85, 1.15)
			ice_player.play()

	# 树叶沙沙声：离树越近越响，也跟着阵风起伏；开阔处的风声相应压低一点
	_canopy_timer -= delta
	if _canopy_timer <= 0.0:
		_canopy_timer = 0.2
		var target := _canopy_amount()
		_canopy = lerpf(_canopy, target, 0.35)
	_set_bed(leaves, _canopy * lerpf(0.45, 1.0, gust), -5.0 - night * 3.0)
	wind.volume_db -= _canopy * 3.0

	# 按时段切换的环境声
	var dawn_w := _band(hour, 4.5, 5.5, 7.5, 9.0)
	var day_w := _band(hour, 7.5, 9.0, 17.0, 18.5) * (1.0 - 0.45 * _band(hour, 11.0, 12.5, 14.5, 16.0))
	var dusk_w := _band(hour, 17.0, 18.0, 20.0, 21.0)
	_set_bed(dawn_bed, dawn_w * life_k, -9.0)
	_set_bed(day_bed, day_w * life_k, -8.0)
	_set_bed(dusk_bed, dusk_w * life_k, -11.0)
	_set_bed(crickets, night * (1.0 - cold), -21.0)

	# 近处的单只鸟叫：清晨最密，正午稀疏，黄昏换一批鸟，夜里没有
	_bird_timer -= delta
	if _bird_timer <= 0.0:
		var activity := maxf(dawn_w, maxf(day_w * 0.7, dusk_w * 0.8)) * life_k
		var pool: Array = BIRDS_MORNING
		if hour >= 16.0:
			pool = BIRDS_EVENING
		elif hour >= 10.0:
			pool = BIRDS_MIDDAY
		_bird_timer = _rng.randf_range(4.0, 11.0) / maxf(activity, 0.25)
		if activity > 0.2:
			for p in bird_players:
				if not p.playing:
					p.stream = birds[int(pool[_rng.randi() % pool.size()]) - 1]
					p.volume_db = _rng.randf_range(-20.0, -9.0)
					p.pitch_scale = _rng.randf_range(0.96, 1.04)
					p.play()
					break


## surface: "grass" / "dirt" / "water" / "snow" / "sand" / "ice"
func play_step(surface: String, landing: bool) -> void:
	var list: Array = steps[surface]
	var p := step_players[_step_i]
	_step_i = (_step_i + 1) % step_players.size()
	p.stream = list[_rng.randi() % list.size()]
	var gain: float = STEP_GAIN[surface]
	p.volume_db = gain + _rng.randf_range(-2.0, 1.0) + (3.0 if landing else 0.0)
	p.pitch_scale = _rng.randf_range(0.93, 1.07) * (0.9 if landing else 1.0)
	p.play()
