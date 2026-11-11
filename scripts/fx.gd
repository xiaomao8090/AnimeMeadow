extends RefCounted
## 互动特效（静态函数，直接 Fx.hearts(...) 调用）：
##   hearts      一串小爱心飘起来
##   heart_pop   一颗大爱心“啵”地弹出来，慢慢升起、轻轻摇摆后消失
##   sparkles    四角星闪光
##   crumbs      喂东西时掉的碎屑
##   dizzy_stars 头顶转圈的小星星
## 贴图全部运行时画：贴纸风格（粉色渐变 + 右下卡通阴影 + 左上高光 + 奶油白描边），不受光照，晚上也看得清。

const PINK_TOP := Color(1.0, 0.64, 0.75)
const PINK_BOT := Color(0.95, 0.36, 0.55)
const PINK_SHADE := Color(0.84, 0.25, 0.46)
const RIM := Color(1.0, 0.975, 0.94)
const GOLD := Color(1.0, 0.86, 0.55)

static var _heart_tex: ImageTexture
static var _spark_tex: ImageTexture
static var _dot_tex: ImageTexture
static var _mats := {}


# ───────────────────────── 贴图 ─────────────────────────

static func _sd_heart(p: Vector2) -> float:
	p.x = absf(p.x)
	if p.y + p.x > 1.0:
		return (p - Vector2(0.25, 0.75)).length() - sqrt(2.0) / 4.0
	var a := (p - Vector2(0.0, 1.0)).length_squared()
	var b := (p - Vector2.ONE * 0.5 * maxf(p.x + p.y, 0.0)).length_squared()
	return sqrt(minf(a, b)) * signf(p.x - p.y)


static func heart_texture() -> ImageTexture:
	if _heart_tex:
		return _heart_tex
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var pix := 1.5 / n
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n * 1.5 - 0.75, (1.0 - (y + 0.5) / n) * 1.5 - 0.2)
			var d := _sd_heart(p)
			var outer := 1.0 - smoothstep(-pix, pix, d - 0.075)
			if outer <= 0.0:
				img.set_pixel(x, y, Color(RIM, 0.0))
				continue
			var inner := 1.0 - smoothstep(-pix, pix, d)
			var col := PINK_BOT.lerp(PINK_TOP, clampf((p.y - 0.05) / 1.0, 0.0, 1.0))
			# 卡通阴影：把爱心往左上挪一点，原来的爱心里多出来的那一条月牙就是右下的阴影
			var ds := _sd_heart(p + Vector2(0.075, -0.075))
			col = col.lerp(PINK_SHADE, smoothstep(-pix, pix, ds) * 0.85)
			# 高光：左上一个斜的小椭圆 + 一个小圆点
			var q := (p - Vector2(-0.3, 0.8)).rotated(0.75)
			var hl := 1.0 - smoothstep(0.85, 1.0, (q.x / 0.13) ** 2 + (q.y / 0.065) ** 2)
			hl = maxf(hl, 1.0 - smoothstep(0.03, 0.04, (p - Vector2(-0.14, 0.93)).length()))
			col = col.lerp(Color(1, 1, 1), hl * 0.92)
			img.set_pixel(x, y, Color(RIM.lerp(col, inner), outer))
	img.generate_mipmaps()
	_heart_tex = ImageTexture.create_from_image(img)
	return _heart_tex


static func spark_texture() -> ImageTexture:
	if _spark_tex:
		return _spark_tex
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5) * 2.0
			var ax := absf(p.x)
			var ay := absf(p.y)
			# 四角星：两条细长的光芒 + 中间一团柔光
			var star := maxf(exp(-ax * 22.0) * exp(-ay * 3.2), exp(-ay * 22.0) * exp(-ax * 3.2))
			var glow := exp(-p.length() * 6.0) * 0.7
			var a := clampf(star * 1.3 + glow, 0.0, 1.0) * (1.0 - smoothstep(0.85, 1.0, maxf(ax, ay)))
			var col := Color(1, 1, 1).lerp(GOLD, clampf(p.length() * 1.6, 0.0, 1.0))
			img.set_pixel(x, y, Color(col, a))
	img.generate_mipmaps()
	_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


static func dot_texture() -> ImageTexture:
	if _dot_tex:
		return _dot_tex
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var r := Vector2((x + 0.5) / n - 0.5, (y + 0.5) / n - 0.5).length() * 2.0
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 - smoothstep(0.7, 1.0, r)))
	img.generate_mipmaps()
	_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex


static func _material(tex: Texture2D, particles: bool) -> StandardMaterial3D:
	var key := str(tex.get_instance_id()) + ("p" if particles else "s")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.vertex_color_use_as_albedo = true
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if particles else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	m.disable_fog = true
	m.render_priority = 2
	_mats[key] = m
	return m


# ───────────────────────── 粒子 ─────────────────────────

static func _curve(points: Array) -> Curve:
	var c := Curve.new()
	for pt in points:
		c.add_point(pt)
	return c


static func _burst(parent: Node, pos: Vector3, tex: Texture2D, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _material(tex, true)
	p.mesh = q
	p.amount = maxi(amount, 1)
	p.one_shot = true
	p.lifetime = life
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = pos
	parent.get_tree().create_timer(life + 0.6, false).timeout.connect(p.queue_free)
	return p


## 一串小爱心：从 pos 往上飘，一颗接一颗，弹出来、慢慢变小消失
static func hearts(parent: Node, pos: Vector3, count := 5, size := 1.0) -> void:
	var p := _burst(parent, pos, heart_texture(), count, 1.8)
	p.explosiveness = 0.55
	p.randomness = 0.4
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12
	p.direction = Vector3.UP
	p.spread = 30.0
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.4
	p.gravity = Vector3(0, -0.3, 0)
	p.damping_min = 0.5
	p.damping_max = 0.9
	p.angle_min = -20.0
	p.angle_max = 20.0
	p.angular_velocity_min = -25.0
	p.angular_velocity_max = 25.0
	p.scale_amount_min = 0.12 * size
	p.scale_amount_max = 0.21 * size
	p.scale_amount_curve = _curve([Vector2(0, 0), Vector2(0.1, 1.2), Vector2(0.22, 1.0), Vector2(0.75, 0.9), Vector2(1, 0)])
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.7, Color(1, 1, 1, 1))
	p.color_ramp = g
	var gi := Gradient.new()
	gi.set_color(0, Color(1, 1, 1))
	gi.set_color(1, Color(1.0, 0.86, 0.92))
	p.color_initial_ramp = gi
	p.emitting = true


## 四角星闪光：从 pos 向四周散开、一闪一闪地消失
static func sparkles(parent: Node, pos: Vector3, count := 10, radius := 0.25, size := 1.0) -> void:
	var p := _burst(parent, pos, spark_texture(), count, 0.9)
	p.explosiveness = 0.85
	p.randomness = 0.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.1
	p.gravity = Vector3(0, 0.25, 0)
	p.damping_min = 1.5
	p.damping_max = 2.5
	p.angle_min = 0.0
	p.angle_max = 45.0
	p.scale_amount_min = 0.07 * size
	p.scale_amount_max = 0.15 * size
	p.scale_amount_curve = _curve([Vector2(0, 0), Vector2(0.15, 1.0), Vector2(0.35, 0.55), Vector2(0.5, 0.95), Vector2(1, 0)])
	p.emitting = true


## 碎屑：喂东西时从嘴边掉下来的小颗粒
static func crumbs(parent: Node, pos: Vector3, col: Color, count := 7) -> void:
	var p := _burst(parent, pos, dot_texture(), count, 0.8)
	p.explosiveness = 0.9
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.04
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.0
	p.gravity = Vector3(0, -5.0, 0)
	p.scale_amount_min = 0.025
	p.scale_amount_max = 0.045
	p.scale_amount_curve = _curve([Vector2(0, 1), Vector2(0.7, 1), Vector2(1, 0)])
	p.color = col
	p.emitting = true


# ───────────────────────── 单个的 ─────────────────────────

static func _sprite(parent: Node, pos: Vector3, tex: Texture2D, size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = tex
	s.pixel_size = size / float(tex.get_width())
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.shaded = false
	s.double_sided = true
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	s.render_priority = 3
	s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(s)
	s.global_position = pos
	return s


## 一颗大爱心：先“啵”地弹大（略微过冲），然后慢慢升起、左右轻摇、变淡消失；顺带一圈小闪光
static func heart_pop(parent: Node, pos: Vector3, size := 0.34, with_sparkles := true) -> void:
	var s := _sprite(parent, pos, heart_texture(), size)
	s.scale = Vector3.ONE * 0.01
	var tw := s.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * 1.28, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "scale", Vector3(1.08, 0.92, 1.0), 0.09)
	tw.tween_property(s, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_SINE)
	var rise := s.create_tween()
	rise.tween_property(s, "global_position", pos + Vector3(0, 0.55, 0), 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var sway := s.create_tween().set_loops(2)
	sway.tween_property(s, "offset", Vector2(10, 0), 0.4).set_trans(Tween.TRANS_SINE)
	sway.tween_property(s, "offset", Vector2(-10, 0), 0.4).set_trans(Tween.TRANS_SINE)
	var fade := s.create_tween()
	fade.tween_interval(1.15)
	fade.tween_property(s, "modulate:a", 0.0, 0.45)
	fade.tween_callback(s.queue_free)
	if with_sparkles:
		sparkles(parent, pos, 8, 0.16 * size / 0.34, size / 0.34)


## 头顶转圈的小星星（晕了），跟着 follow 节点走
static func dizzy_stars(follow: Node3D, height: float, duration := 2.6) -> void:
	var ring := Node3D.new()
	follow.add_child(ring)
	ring.position = Vector3(0, height, 0)
	for i in 3:
		var a := TAU * i / 3.0
		var s := Sprite3D.new()
		s.texture = spark_texture()
		s.pixel_size = 0.13 / 64.0
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.render_priority = 3
		s.modulate = Color(1.0, 0.95, 0.75)
		s.position = Vector3(cos(a) * 0.3, sin(a * 2.0) * 0.03, sin(a) * 0.3)
		ring.add_child(s)
	ring.scale = Vector3.ONE * 0.01
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(duration - 0.55, 0.1))
	tw.tween_property(ring, "scale", Vector3.ONE * 0.01, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(ring.queue_free)
	var spin := ring.create_tween()
	spin.tween_property(ring, "rotation:y", TAU * duration * 0.9, duration)
