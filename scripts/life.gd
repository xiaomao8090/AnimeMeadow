extends Node3D
## 氛围：飘落的花瓣、空中的光点（晚上变成萤火虫）、在花丛间飞的蝴蝶

var world
var petals: GPUParticles3D
var leaves: GPUParticles3D      # 秋林：飘落的红黄叶子
var snowfall: GPUParticles3D    # 雪原 / 冰原：下雪
var _bw := Color(0, 0, 0, 0)    # 玩家所在位置的群系权重（平滑过的）
var _bw_t := 0.0
var motes: GPUParticles3D
var petal_mat: ShaderMaterial
var mote_mat: ShaderMaterial
var butterfly_mat: ShaderMaterial
var butterflies: MultiMeshInstance3D
var _bf: Array[Dictionary] = []
var _t := 0.0
var _rehome_t := 1.0


func _fade_ramp() -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.12, Color(1, 1, 1, 1))
	g.add_point(0.85, Color(1, 1, 1, 1))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _shader_mat(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path) as Shader
	return m


func setup(w) -> void:
	world = w
	var wind := Vector3(world.WIND_DIR.x, 0.0, world.WIND_DIR.y).normalized()

	# ── 花瓣 ──
	petal_mat = _shader_mat("res://shaders/petal.gdshader")
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24.0, 5.0, 24.0)
	pm.direction = Vector3(wind.x, -0.35, wind.z)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(wind.x * 0.5, -0.45, wind.z * 0.5)
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 4.0
	pm.color_ramp = _fade_ramp()
	var pg := Gradient.new()
	pg.set_color(0, Color(1.0, 0.72, 0.82))
	pg.set_color(1, Color(1.0, 0.96, 0.97))
	var pgt := GradientTexture1D.new()
	pgt.gradient = pg
	pm.color_initial_ramp = pgt
	var pq := QuadMesh.new()
	pq.size = Vector2(0.10, 0.13)
	pq.material = petal_mat
	petals = GPUParticles3D.new()
	petals.amount = 300             # 樱花林里全开；普通草原只放一部分（amount_ratio）
	petals.lifetime = 9.0
	petals.preprocess = 9.0
	petals.local_coords = false
	petals.process_material = pm
	petals.draw_pass_1 = pq
	petals.visibility_aabb = AABB(Vector3(-60, -30, -60), Vector3(120, 60, 120))
	petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(petals)

	# ── 光点 / 萤火虫 ──
	mote_mat = _shader_mat("res://shaders/mote.gdshader")
	var mm := ParticleProcessMaterial.new()
	mm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mm.emission_box_extents = Vector3(18.0, 2.2, 18.0)
	mm.direction = Vector3(0, 1, 0)
	mm.spread = 180.0
	mm.initial_velocity_min = 0.1
	mm.initial_velocity_max = 0.45
	mm.gravity = Vector3(wind.x * 0.08, 0.03, wind.z * 0.08)
	mm.scale_min = 0.5
	mm.scale_max = 1.2
	mm.turbulence_enabled = true
	mm.turbulence_noise_strength = 0.35
	mm.turbulence_noise_scale = 3.0
	mm.color_ramp = _fade_ramp()
	var mq := QuadMesh.new()
	mq.size = Vector2(0.09, 0.09)
	mq.material = mote_mat
	motes = GPUParticles3D.new()
	motes.amount = 80
	motes.lifetime = 6.0
	motes.preprocess = 6.0
	motes.local_coords = false
	motes.process_material = mm
	motes.draw_pass_1 = mq
	motes.visibility_aabb = AABB(Vector3(-50, -20, -50), Vector3(100, 40, 100))
	motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(motes)

	leaves = _make_fall([Color(0.95, 0.50, 0.18), Color(0.98, 0.74, 0.26), Color(0.85, 0.30, 0.18)],
		Vector2(0.17, 0.22), 140, 8.0, Vector3(wind.x * 0.4, -0.6, wind.z * 0.4), 1.6)
	snowfall = _make_fall([Color(1, 1, 1), Color(0.92, 0.96, 1.0)],
		Vector2(0.065, 0.065), 700, 10.0, Vector3(wind.x * 0.25, -0.9, wind.z * 0.25), 0.5)
	(snowfall.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(30.0, 6.0, 30.0)
	_set_ratio(petals, 0.35)
	_set_ratio(leaves, 0.0)
	_set_ratio(snowfall, 0.0)

	_build_butterflies()


## 一种飘落的东西（花瓣 / 叶子 / 雪）：和花瓣同一个着色器，颜色和大小不同
func _make_fall(cols: Array, size: Vector2, amount: int, life: float, gravity: Vector3, speed: float) -> GPUParticles3D:
	var wind := Vector3(world.WIND_DIR.x, 0.0, world.WIND_DIR.y).normalized()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(24.0, 5.0, 24.0)
	pm.direction = Vector3(wind.x, -0.5, wind.z)
	pm.spread = 35.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = gravity
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.5
	pm.turbulence_noise_scale = 4.0
	pm.color_ramp = _fade_ramp()
	var g := Gradient.new()
	g.set_color(0, cols[0])
	g.set_color(1, cols[1])
	if cols.size() > 2:
		g.add_point(0.5, cols[2])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_initial_ramp = gt
	var q := QuadMesh.new()
	q.size = size
	q.material = petal_mat
	var ps := GPUParticles3D.new()
	ps.amount = amount
	ps.lifetime = life
	ps.preprocess = life
	ps.local_coords = false
	ps.process_material = pm
	ps.draw_pass_1 = q
	ps.visibility_aabb = AABB(Vector3(-60, -30, -60), Vector3(120, 60, 120))
	ps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ps)
	return ps


func _set_ratio(ps: GPUParticles3D, k: float) -> void:
	ps.amount_ratio = clampf(k, 0.0, 1.0)
	ps.emitting = k > 0.01


func _make_butterfly_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for side: float in [-1.0, 1.0]:
		var rf := Vector3(0.0, 0.0, -0.05)
		var rb := Vector3(0.0, 0.0, 0.06)
		var tf := Vector3(0.14 * side, 0.0, -0.11)
		var tb := Vector3(0.12 * side, 0.0, 0.04)
		var hind := Vector3(0.075 * side, 0.0, 0.12)
		for v: Vector3 in [rf, tf, tb, rf, tb, rb, rb, tb, hind]:
			st.set_uv(Vector2(absf(v.x) / 0.14, (v.z + 0.11) / 0.23))
			st.add_vertex(v)
	return st.commit()


func _build_butterflies() -> void:
	# 无限地图：花丛是边走边生成的，启动时可能一丛都还没有。蝴蝶先放在出生点，
	# 之后由 _rehome() 把离玩家太远的蝴蝶搬到附近的花丛去
	var centers: Array = world.flower_centers
	var rng := RandomNumberGenerator.new()
	rng.seed = world.world_seed + 77
	var palette: Array[Color] = [
		Color(1.0, 0.62, 0.15), Color(1.0, 0.90, 0.30), Color(1.0, 1.0, 1.0),
		Color(0.45, 0.72, 1.0), Color(1.0, 0.60, 0.80), Color(0.72, 0.55, 1.0),
	]
	var count := 16
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = _make_butterfly_mesh()
	mm.instance_count = count
	for i in count:
		var home: Vector3 = world.spawn + Vector3(0.0, -500.0, 0.0) if centers.is_empty() else centers[rng.randi() % centers.size()]
		_bf.append({
			"home": home,
			"r1": rng.randf_range(1.5, 4.5), "r2": rng.randf_range(1.5, 4.5),
			"a": rng.randf_range(0.25, 0.5), "b": rng.randf_range(0.6, 1.1), "c": rng.randf_range(0.3, 0.55),
			"ph": rng.randf() * 20.0,
		})
		mm.set_instance_color(i, palette[rng.randi() % palette.size()].srgb_to_linear())
		mm.set_instance_custom_data(i, Color(rng.randf(), 0, 0, 0))
		mm.set_instance_transform(i, Transform3D(Basis(), home))
	butterfly_mat = _shader_mat("res://shaders/butterfly.gdshader")
	butterflies = MultiMeshInstance3D.new()
	butterflies.name = "Butterflies"
	butterflies.multimesh = mm
	butterflies.material_override = butterfly_mat
	butterflies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	butterflies.custom_aabb = AABB(Vector3(-1e7, -1e4, -1e7), Vector3(2e7, 2e4, 2e7))
	add_child(butterflies)


## 每隔几秒检查一次：家离玩家超过 90 米的蝴蝶，搬到玩家附近 70 米内随便一个花丛
func _rehome(p: Vector3) -> void:
	var near: Array[Vector3] = []
	for c: Vector3 in world.flower_centers:
		if Vector2(c.x - p.x, c.z - p.z).length() < 70.0:
			near.append(c)
	if near.is_empty():
		return
	for b in _bf:
		var home: Vector3 = b.home
		if Vector2(home.x - p.x, home.z - p.z).length() > 90.0 or home.y < -400.0:
			b.home = near[randi() % near.size()]


func _bf_pos(b: Dictionary, t: float) -> Vector3:
	var home: Vector3 = b.home
	var tt: float = t + b.ph
	var x: float = home.x + cos(tt * b.a) * b.r1 + sin(tt * b.a * 2.3) * 0.6
	var z: float = home.z + sin(tt * b.c) * b.r2 + cos(tt * b.c * 1.9) * 0.6
	var y: float = world.height_raw(x, z) + 0.95 + sin(tt * b.b) * 0.3 + sin(tt * 9.0) * 0.05
	return Vector3(x, y, z)


func _process(delta: float) -> void:
	if world == null or world.player == null:
		return
	_t += delta
	var p: Vector3 = world.player.global_position
	var dn = world.day_night
	var tint: Color = dn.light_tint
	var night: float = dn.night

	petals.global_position = p + Vector3(0.0, 6.5, 0.0)
	leaves.global_position = p + Vector3(0.0, 6.0, 0.0)
	snowfall.global_position = p + Vector3(0.0, 9.0, 0.0)
	# 按所在群系换飘落的东西（权重慢慢过渡，走过边界时不会突然变）
	_bw_t -= delta
	if _bw_t <= 0.0:
		_bw_t = 0.5
		var target: Color = world.biome_w(p.x, p.z)
		_bw = _bw.lerp(target, 0.35)
		var plain := clampf(1.0 - _bw.r - _bw.g - _bw.b - _bw.a, 0.0, 1.0)
		_set_ratio(petals, plain * 0.35 + _bw.a * 1.0)
		_set_ratio(leaves, _bw.b)
		_set_ratio(snowfall, _bw.r)
	motes.global_position = p + Vector3(0.0, 2.0, 0.0)
	petal_mat.set_shader_parameter("light_tint", tint)
	# 白天是淡淡的花粉，晚上变成发绿光的萤火虫
	mote_mat.set_shader_parameter("intensity", lerpf(0.55, 2.6, night))
	mote_mat.set_shader_parameter("tint", Color(1.0, 0.95, 0.65).lerp(Color(0.75, 1.0, 0.35), night))

	_rehome_t -= delta
	if _rehome_t <= 0.0:
		_rehome_t = 3.0
		_rehome(p)

	if butterflies:
		butterflies.visible = night < 0.6 and _bw.r < 0.5 and _bw.g < 0.6
		if butterflies.visible:
			butterfly_mat.set_shader_parameter("light_tint", tint)
			var mm := butterflies.multimesh
			for i in _bf.size():
				var b := _bf[i]
				if b.get("gone", 0.0) > _t:
					mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ONE * 0.0001), Vector3(0, -1000, 0)))
					continue
				var pos := _bf_pos(b, _t)
				var ahead := _bf_pos(b, _t + 0.1)
				var dir := ahead - pos
				dir.y = 0.0
				var basis := Basis()
				if dir.length_squared() > 0.000001:
					basis = Basis.looking_at(dir.normalized(), Vector3.UP)
				mm.set_instance_transform(i, Transform3D(basis, pos))


## 捕虫网用：pos 周围 radius 米内的蝴蝶被抓走（过一阵子会有新的飞回来），返回抓到几只
func catch_near(pos: Vector3, radius: float) -> int:
	if butterflies == null or not butterflies.visible:
		return 0
	var n := 0
	for b in _bf:
		if b.get("gone", 0.0) > _t:
			continue
		if _bf_pos(b, _t).distance_to(pos) < radius:
			b["gone"] = _t + 25.0
			n += 1
	return n
