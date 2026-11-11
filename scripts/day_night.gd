extends Node
## 昼夜循环：转动太阳/月亮，并按时间调整天空、灯光、环境光和雾的颜色。
## 按住 T 可以让时间快进。

@export var day_length_minutes := 10.0   # 游戏里一整天 = 现实多少分钟
@export var time_of_day := 9.0           # 开始时间（0-24）
@export var fast_forward := 40.0         # 按住 T 时的倍速

var sun: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial

var day := 1.0                 # 1 = 白天
var night := 0.0               # 1 = 深夜
var light_tint := Color.WHITE  # 给不受光照的材质（水、花瓣、蝴蝶）用的整体色调
var winter := 0.0              # world.gd 设置：玩家在雪原里 = 1。光偏冷、环境光更亮（雪地反光）、远处起一层发白的雾

const SKY_TOP := [Color(0.24, 0.50, 0.95), Color(0.30, 0.32, 0.62), Color(0.015, 0.03, 0.10)]
const SKY_HORIZON := [Color(0.68, 0.86, 1.0), Color(1.0, 0.62, 0.42), Color(0.06, 0.10, 0.22)]
const SUN_COL := [Color(1.0, 0.96, 0.88), Color(1.0, 0.58, 0.32), Color(0.55, 0.68, 1.0)]
const AMBIENT := [Color(0.56, 0.68, 0.95), Color(0.70, 0.55, 0.70), Color(0.24, 0.32, 0.64)]
const AMBIENT_ENERGY := [0.9, 0.75, 0.7]
const CLOUD_LIGHT := [Color(1.0, 1.0, 1.0), Color(1.0, 0.76, 0.60), Color(0.20, 0.25, 0.42)]
const CLOUD_DARK := [Color(0.72, 0.80, 0.95), Color(0.55, 0.40, 0.56), Color(0.07, 0.09, 0.20)]
const TINT := [Color(1.0, 1.0, 1.0), Color(1.0, 0.80, 0.70), Color(0.30, 0.37, 0.62)]


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader") as Shader
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# 带颜色的环境光 = 动漫风里偏蓝的阴影
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.fog_enabled = true
	env.fog_density = 0.0021     # 一公里外的地形基本融进天色里，看不到世界的"边"
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	env.adjustment_contrast = 1.03
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	sun.shadow_blur = 1.5
	add_child(sun)
	_apply()


func _process(delta: float) -> void:
	var speed := 24.0 / maxf(day_length_minutes * 60.0, 1.0)
	if Input.is_physical_key_pressed(KEY_T):
		speed *= fast_forward
	time_of_day = fposmod(time_of_day + delta * speed, 24.0)
	_apply()


func clock_text() -> String:
	var h := int(time_of_day)
	var m := int((time_of_day - h) * 60.0)
	return "%02d:%02d" % [h, m]


func _mix(c: Array, dusk: float) -> Color:
	var a: Color = c[0]
	var b: Color = c[1]
	var n: Color = c[2]
	return a * day + b * dusk + n * night


func _apply() -> void:
	# 6 点日出、12 点正午、18 点日落；轨道倾斜 35°，正午太阳不会在头顶正上方
	var a := (time_of_day - 6.0) / 24.0 * TAU
	var tilt := deg_to_rad(35.0)
	var sun_dir := Vector3(cos(a), sin(a) * cos(tilt), sin(a) * sin(tilt)).normalized()
	var moon_dir := -sun_dir
	var e := sun_dir.y

	day = smoothstep(0.05, 0.35, e)
	night = smoothstep(-0.02, -0.3, e)
	var dusk := clampf(1.0 - day - night, 0.0, 1.0)

	# 同一盏平行光白天当太阳、晚上当月亮；经过地平线时亮度是 0，切换看不出来
	var is_day := e > 0.0
	var ldir := sun_dir if is_day else moon_dir
	sun.basis = Basis.looking_at(-ldir, Vector3.UP)
	if is_day:
		sun.light_energy = 0.75 * smoothstep(0.0, 0.2, e)
		sun.light_color = (SUN_COL[1] as Color).lerp(SUN_COL[0], day)
	else:
		sun.light_energy = 0.24 * smoothstep(0.0, 0.2, -e)
		sun.light_color = SUN_COL[2]

	var top := _mix(SKY_TOP, dusk)
	var horizon := _mix(SKY_HORIZON, dusk)
	var w := winter
	# 雪原：太阳光偏冷白，环境光更亮、偏蓝（雪地把光反射到阴影里），天边发白，远处起一层雾，颜色稍微淡一点
	if w > 0.001:
		if is_day:
			sun.light_color = sun.light_color.lerp(Color(0.96, 0.97, 1.0), w * 0.6 * day)
		horizon = horizon.lerp(horizon.lerp(Color(0.90, 0.94, 1.0), day), w * 0.55)
		top = top.lerp(top.lerp(Color(0.52, 0.66, 0.90), day), w * 0.35)
	env.ambient_light_color = _mix(AMBIENT, dusk).lerp(Color(0.72, 0.80, 1.0), w * 0.5)
	# 极光：雪原的夜里出现，雪地被映上一点点绿
	var aur := w * night
	env.ambient_light_color = env.ambient_light_color.lerp(Color(0.42, 0.95, 0.66), aur * 0.14)
	env.ambient_light_energy = (AMBIENT_ENERGY[0] * day + AMBIENT_ENERGY[1] * dusk + AMBIENT_ENERGY[2] * night) * (1.0 + 0.25 * w)
	env.fog_density = 0.0021 + 0.0042 * w
	env.adjustment_saturation = 1.15 - 0.12 * w
	env.fog_light_color = horizon
	light_tint = _mix(TINT, dusk)

	sky_mat.set_shader_parameter("top_color", top)
	sky_mat.set_shader_parameter("horizon_color", horizon)
	sky_mat.set_shader_parameter("sun_color", (SUN_COL[1] as Color).lerp(SUN_COL[0], day))
	sky_mat.set_shader_parameter("cloud_light", _mix(CLOUD_LIGHT, dusk))
	sky_mat.set_shader_parameter("cloud_dark", _mix(CLOUD_DARK, dusk))
	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("night", night)
	sky_mat.set_shader_parameter("aurora", aur)
