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

	// 体积云在半分辨率通道里算好（预乘颜色 + 不透明度），这里叠到天空上
	if (!AT_CUBEMAP_PASS) {
		vec4 cl = HALF_RES_COLOR;
		col = col * (1.0 - cl.a) + cl.rgb;
	}
	COLOR = col;
	}
}
