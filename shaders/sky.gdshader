// 天空：渐变 + 太阳/光晕 + 月亮 + 星星 + 体积云（光线步进）。颜色由 day_night.gd 按时间设置
shader_type sky;
render_mode use_half_res_pass;

uniform vec3 top_color : source_color = vec3(0.24, 0.50, 0.95);
uniform vec3 horizon_color : source_color = vec3(0.68, 0.86, 1.0);
uniform vec3 sun_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 cloud_light : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_dark : source_color = vec3(0.72, 0.80, 0.95);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float night = 0.0;
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.46;
uniform float cloud_scale = 0.0008;          // 越小云团越大
uniform float cloud_base = 550.0;            // 云底高度（米）
uniform float cloud_thickness = 1200.0;      // 云层厚度（最高的云顶 = 云底 + 这个值）
uniform float cloud_density_scale = 0.012;   // 越大云越实、越不透
uniform vec2 cloud_wind = vec2(9.0, 3.0);    // 云飘动的速度（米/秒）

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(13.7, 7.1);
		a *= 0.5;
	}
	return v;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(i), hash3(i + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 0.0)), hash3(i + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0.0, 0.0, 1.0)), hash3(i + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(i + vec3(0.0, 1.0, 1.0)), hash3(i + vec3(1.0, 1.0, 1.0)), f.x), f.y),
		f.z);
}

// 天空按一个球面来算（半径比真实地球小，弯得明显一点），远处的云会自然沉到地平线下面，
// 不需要在某个距离一刀切断
const float PLANET_R = 200000.0;

// 一个点离"地面"的高度
float cloud_alt(vec3 p) {
	return p.y + dot(p.xz, p.xz) / (2.0 * PLANET_R);
}

// 从相机出发沿 d 方向，走多远到达高度为 h 的球壳
float shell_dist(float dy, float h) {
	float b = PLANET_R * dy;
	return -b + sqrt(b * b + 2.0 * PLANET_R * h + h * h);
}

// 云在空间里某一点的密度 0..1。云层是 cloud_base 到 cloud_base + cloud_thickness 之间的一层
// detail = false 时少算细节（给光照采样用，省性能）
float cloud_density(vec3 p, bool detail) {
	float hgt = (cloud_alt(p) - cloud_base) / cloud_thickness;
	if (hgt < 0.0 || hgt > 1.0) {
		return 0.0;
	}
	vec3 q = p + vec3(cloud_wind.x, 0.0, cloud_wind.y) * TIME;
	// 俯视图上哪里有云（一朵一朵分开的）。cov > 0 才在云的范围里
	float cov = fbm(q.xz * cloud_scale) - (1.0 - cloud_cover);
	if (cov <= 0.0) {
		return 0.0;
	}
	// 每朵云是一个鼓起来的包：边上矮、中间高，底面也有点高低不平，而不是一整层等厚的板
	float top = 0.14 + 0.86 * (1.0 - exp(-cov * 7.0));
	float bot = 0.07 * vnoise(q.xz * cloud_scale * 6.0);
	float v = (hgt - bot) / (top - bot);
	if (v <= 0.0 || v >= 1.0) {
		return 0.0;
	}
	float dn = min(cov * 5.0, 0.6) * smoothstep(0.0, 0.16, v) * smoothstep(1.0, 0.5, v);
	// 大块的三维起伏：在云的侧面和顶上挖出一个个鼓包和凹陷
	dn -= vnoise3(q * cloud_scale * 2.6 + vec3(0.0, TIME * 0.01, 0.0)) * 0.26;
	if (dn <= 0.0) {
		return 0.0;
	}
	// 细节：一团一团的小鼓包（越往上啃得越多，顶部像菜花）
	vec3 e = q * cloud_scale * 7.0 + vec3(0.0, TIME * 0.02, 0.0);
	float n = 1.0 - abs(vnoise3(e) * 2.0 - 1.0);
	if (detail) {
		n = n * 0.62 + (1.0 - abs(vnoise3(e * 2.4 + 11.0) * 2.0 - 1.0)) * 0.26 + vnoise3(e * 5.3 + 23.0) * 0.12;
	}
	dn -= n * (0.10 + 0.14 * v);
	return clamp(dn * 4.5, 0.0, 1.0);
}

// 沿视线穿过云层步进。返回 rgb = 预乘颜色，a = 不透明度
vec4 march_clouds(vec3 d, vec2 screen_uv) {
	if (d.y < -0.05) {
		return vec4(0.0);
	}
	float t0 = shell_dist(d.y, cloud_base);
	float t1 = shell_dist(d.y, cloud_base + cloud_thickness);
	// 空的地方大步走；碰到云就退回一步改用小步细走，这样云的边缘不会被大步"切"出一层层的断面
	float dt_far = (t1 - t0) / 40.0;
	float dt_near = dt_far * 0.25;
	// 每个像素起点错开一点，把分层的条纹打散（用规则的抖动图案，比纯随机的颗粒感轻）
	vec2 pix = floor(screen_uv * vec2(800.0, 450.0));
	float jitter = fract(52.9829189 * fract(dot(pix, vec2(0.06711056, 0.00583715))));
	float t = t0 + dt_far * jitter;

	vec3 ld = sun_dir.y > -0.05 ? sun_dir : moon_dir;
	float sd = max(dot(d, sun_dir), 0.0);
	float horizon_fade = smoothstep(-0.05, 0.0, d.y);

	vec3 acc = vec3(0.0);
	float trans = 1.0;
	bool fine = false;
	int empty = 0;
	for (int i = 0; i < 180; i++) {
		if (t > t1) {
			break;
		}
		vec3 p = d * t;
		float dens = cloud_density(p, true);
		if (!fine) {
			if (dens > 0.0) {
				// 刚进云：退回上一步的位置，从那里开始细走
				fine = true;
				empty = 0;
				t = max(t - dt_far, t0) + dt_near * jitter;
				continue;
			}
			t += dt_far;
			continue;
		}
		float dt = dt_near;
		if (dens <= 0.0) {
			empty++;
			if (empty > 6) {
				fine = false;
			}
		} else {
			empty = 0;
		}
		// 很远的云慢慢淡出，而不是到某个距离突然没了
		dens *= 1.0 - smoothstep(13000.0, 24000.0, t);
		if (dens > 0.005) {
			// 朝光源方向采 4 个点，前面挡着的云越多这里越暗
			float od = 0.0;
			od += cloud_density(p + ld * 50.0, false) * 70.0;
			od += cloud_density(p + ld * 130.0, false) * 100.0;
			od += cloud_density(p + ld * 260.0, false) * 150.0;
			od += cloud_density(p + ld * 460.0, false) * 220.0;
			// 直射光 + 在云里多次散射后剩下的柔光（没有这一项，背光面会死黑一片、看着是平的）
			float beer = exp(-od * 0.007) * 0.7 + exp(-od * 0.0018) * 0.3;
			float hgt = clamp((cloud_alt(p) - cloud_base) / cloud_thickness, 0.0, 1.0);
			// 天光：云的上半部更亮，底部更暗；薄的边缘透光更亮 → 从下面看也有鼓起来的体积感
			float sky_light = mix(0.0, 0.3, hgt) + (1.0 - dens) * 0.22;
			float lit = clamp(smoothstep(0.03, 0.75, beer) * 0.85 + sky_light, 0.0, 1.0);
			vec3 cc = mix(cloud_dark * 0.9, cloud_light, lit);
			// 太阳在云后面时，薄的地方透光
			cc += sun_color * pow(sd, 14.0) * beer * 0.55 * (1.0 - night);
			// 远处的云融进地平线的颜色
			cc = mix(horizon_color, cc, exp(-t * 0.00009));

			float a = 1.0 - exp(-dens * dt * cloud_density_scale);
			acc += trans * a * cc;
			trans *= 1.0 - a;
			if (trans < 0.03) {
				trans = 0.0;
				break;
			}
		}
		t += dt;
	}
	float alpha = (1.0 - trans) * horizon_fade;
	return vec4(acc * horizon_fade, alpha);
}

// ───────────── 极光 ─────────────
// 每一道极光是一张竖着的"帘子"：在俯视图上是一条东西走向、弯弯曲曲的线（z = aur_curve(x)），
// 从离地 aurora_bottom 起往上延伸。视线和帘子的交点处取颜色：
//   底边最亮的绿色（氧原子 557.7nm，约 100-150 公里高），往上逐渐变暗，顶部转成淡红（氧原子 630nm，200 公里以上），
//   活动强的时候底边会镶一圈紫红（氮分子）。
// 帘子上的竖条纹（射线）只随东西方向变化、不随高度变化，透视下自然往天顶汇聚；
// 帘子被侧着看（褶皱转过来）的地方，视线在里面走得更长，所以更亮 —— 这是真实极光"亮褶"的来源。
// 地图里 -z 是北，极光都在北边，活动越强越往南扩、越往头顶上来。
uniform float aurora = 0.0;                  // day_night.gd 设置：雪原权重 × 夜晚
const vec3 AUR_GREEN = vec3(0.16, 1.0, 0.45);
const vec3 AUR_RED = vec3(0.90, 0.12, 0.26);
const vec3 AUR_PURPLE = vec3(0.55, 0.18, 0.95);

float aur_curve(float x, float base, float seed, float tm) {
	return base
		+ 5200.0 * sin(x * 0.000045 + seed * 3.1 + tm * 0.010)
		+ 2200.0 * sin(x * 0.00013 - tm * 0.023 + seed * 7.0)
		+ 1500.0 * (vnoise(vec2(x * 0.00025 + tm * 0.006, seed * 13.0)) - 0.5);
}

vec3 aur_curtain(vec3 d, float base, float seed, float tm, float act) {
	if (d.z > -0.02 || d.y < -0.02) {
		return vec3(0.0);
	}
	// 视线在俯视图上是 x = s·z 这条线，用牛顿法找它和帘子曲线的交点
	float s = d.x / d.z;
	float z = base;
	for (int i = 0; i < 5; i++) {
		float xi = s * z;
		float c = aur_curve(xi, base, seed, tm);
		float dc = (aur_curve(xi + 40.0, base, seed, tm) - c) / 40.0;
		float hp = 1.0 - s * dc;
		hp = (hp < 0.0 ? -1.0 : 1.0) * max(abs(hp), 0.3);
		z -= clamp((z - c) / hp, -12000.0, 12000.0);
	}
	float x = s * z;
	float c = aur_curve(x, base, seed, tm);
	if (abs(z - c) > 500.0 || z > -500.0) {
		return vec3(0.0);
	}
	float dc = (aur_curve(x + 40.0, base, seed, tm) - c) / 40.0;
	float t = z / d.z;
	float h = cloud_alt(d * t);

	// 底边高度沿着帘子起伏
	float bottom = 3600.0 + 1000.0 * vnoise(vec2(x * 0.0004 + tm * 0.01, seed * 4.0));
	float hh = (h - bottom) / 9000.0;
	if (hh < -0.06 || hh > 1.3) {
		return vec3(0.0);
	}

	// 竖条纹：沿着帘子慢慢流动，活动强时流得快；每根射线顶端高低不同
	float ax = x + tm * 35.0 * (0.4 + act);
	float r1 = vnoise(vec2(ax * 0.0021, seed * 5.0));
	float r2 = vnoise(vec2(ax * 0.0090, seed * 9.0 + 3.0));
	float fine = 1.0 - smoothstep(25000.0, 60000.0, t);      // 太远的细条纹会闪，淡掉
	float rays = 0.22 + 1.1 * (r1 * r1 * 0.65 + r2 * r2 * 0.35 * fine);
	float ray_top = mix(0.30, 1.0, vnoise(vec2(ax * 0.0013, seed * 2.0 + 5.0)));

	// 高度上的颜色分布
	float hc = max(hh, 0.0);
	float green = smoothstep(-0.05, 0.015, hh) * exp(-hc * 3.0 / ray_top);
	float red = smoothstep(0.12, 0.55, hh) * exp(-max(hh - 0.5, 0.0) * 2.2) * 0.30 * ray_top;
	float purple = exp(-abs(hh) * 45.0) * smoothstep(0.45, 0.9, act) * 0.55;

	// 沿帘子一块亮一块暗，慢慢变化
	float patchy = 0.30 + 0.70 * smoothstep(0.25, 0.75, vnoise(vec2(x * 0.00012 - tm * 0.02, seed * 3.0)));

	// 视线穿过帘子的路径长度：越是侧着看越长越亮
	vec2 n = normalize(vec2(-dc, 1.0));
	float path = min(1.0 / max(abs(dot(n, d.xz)), 0.08), 4.5);

	vec3 e = (AUR_GREEN * green + AUR_RED * red + AUR_PURPLE * purple) * rays * patchy * path;
	// 很远的极光被大气吃掉一部分
	return e * exp(-t / 70000.0);
}

vec3 aurora_color(vec3 d) {
	float tm = TIME;
	// 活动强度：几分钟一个起落，偶尔爆发；再叠一点很慢的脉动
	float act = smoothstep(0.25, 0.8, vnoise(vec2(tm * 0.006, 1.3)));
	act = clamp(act * 0.85 + 0.15 + 0.06 * sin(tm * 0.7) * act, 0.0, 1.0);

	vec3 col = vec3(0.0);
	// 主弧：活动越强越往南（越高）
	col += aur_curtain(d, mix(-32000.0, -15000.0, act), 1.0, tm, act);
	// 远处低空的一道
	col += aur_curtain(d, -52000.0, 2.0, tm * 1.15, act) * 0.6;
	// 活动强的时候头顶上也会出现
	float hi = smoothstep(0.55, 0.9, act);
	if (hi > 0.0) {
		col += aur_curtain(d, mix(-12000.0, -5000.0, hi), 3.0, tm * 0.9, act) * 0.85 * hi;
	}
	// 北边低空一层淡淡的弥散绿光
	col += AUR_GREEN * 0.04 * act * exp(-max(d.y, 0.0) * 6.0)
		* smoothstep(0.1, -0.6, d.z) * smoothstep(-0.02, 0.05, d.y);

	// 地平线附近穿过的大气更厚，压暗
	col *= smoothstep(-0.02, 0.06, d.y);
	return col * (0.35 + 0.35 * act);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	if (AT_HALF_RES_PASS) {
		vec4 cl = AT_CUBEMAP_PASS ? vec4(0.0) : march_clouds(d, SCREEN_UV);
		COLOR = cl.rgb;
		ALPHA = cl.a;
	} else {
	float h = clamp(d.y, 0.0, 1.0);
	vec3 col = mix(horizon_color, top_color, pow(h, 0.5));
	col = mix(col, horizon_color * 0.8, smoothstep(0.0, -0.3, d.y));

	// 太阳周围的光晕
	float sd = max(dot(d, sun_dir), 0.0);
	col += sun_color * (pow(sd, 6.0) * 0.16 + pow(sd, 60.0) * 0.45) * (1.0 - night);

	// 星星
	if (night > 0.01 && d.y > 0.0) {
		vec2 suv = d.xz / (d.y + 0.4) * 38.0;
		vec2 cell = floor(suv);
		vec2 f = fract(suv) - 0.5;
		float r = hash(cell);
		vec2 off = (vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5) * 0.6;
		float star = step(0.90, r) * smoothstep(0.11, 0.0, length(f - off));
		float tw = 0.6 + 0.4 * sin(TIME * (1.0 + r * 3.0) + r * 100.0);
		col += vec3(0.9, 0.95, 1.0) * star * tw * night * smoothstep(0.0, 0.15, d.y) * 1.6;
	}

	// 太阳和月亮的圆盘
	float disc = smoothstep(0.9992, 0.9995, dot(d, sun_dir));
	col = mix(col, sun_color * 2.2, disc);
	float md = dot(d, moon_dir);
	col += vec3(0.5, 0.62, 1.0) * pow(max(md, 0.0), 40.0) * 0.3 * night;
	col = mix(col, vec3(1.0, 1.0, 0.92) * 1.4, smoothstep(0.9990, 0.9993, md) * night);

	// 极光在星星和月亮前面、云后面
	if (aurora > 0.005 && !AT_CUBEMAP_PASS) {
		col += aurora_color(d) * aurora;
	}

	// 体积云在半分辨率通道里算好（预乘颜色 + 不透明度），这里叠到天空上
	if (!AT_CUBEMAP_PASS) {
		vec4 cl = HALF_RES_COLOR;
		col = col * (1.0 - cl.a) + cl.rgb;
	}
	COLOR = col;
	}
}
