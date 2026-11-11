// 地面 + 山脉：草地 / 小路和泥土 / 池塘边的沙 / 陡坡岩石 / 山顶积雪
// 远处没有草叶的地方，地面会换成"草尖"的颜色并带上风的亮带，和近处的草无缝衔接
shader_type spatial;
render_mode world_vertex_coords;

uniform vec3 color_a : source_color = vec3(0.12, 0.34, 0.16);
uniform vec3 color_b : source_color = vec3(0.20, 0.44, 0.19);
uniform vec3 far_tip : source_color = vec3(0.38, 0.62, 0.24);
uniform vec3 far_dry : source_color = vec3(0.52, 0.64, 0.26);
uniform vec3 gust_color : source_color = vec3(0.70, 0.82, 0.42);
uniform vec3 hill_grass : source_color = vec3(0.30, 0.52, 0.24);
uniform vec3 dirt_a : source_color = vec3(0.52, 0.39, 0.26);
uniform vec3 dirt_b : source_color = vec3(0.63, 0.49, 0.33);
uniform vec3 sand_color : source_color = vec3(0.80, 0.72, 0.52);
uniform vec3 rock_dark : source_color = vec3(0.36, 0.38, 0.50);
uniform vec3 rock_light : source_color = vec3(0.62, 0.64, 0.74);
uniform vec3 snow_color : source_color = vec3(0.95, 0.97, 1.0);
uniform vec3 forest_color : source_color = vec3(0.16, 0.36, 0.17);
// 群系（world.gd 把权重存在 CUSTOM0：r 雪原 / g 沙漠 / b 秋林 / a 樱花林；冰面在顶点色的 A）
uniform vec3 snow_shadow : source_color = vec3(0.74, 0.82, 0.95);
uniform vec3 sand_a : source_color = vec3(0.88, 0.76, 0.52);
uniform vec3 sand_b : source_color = vec3(0.95, 0.84, 0.60);
uniform vec3 fall_ground : source_color = vec3(0.42, 0.34, 0.14);
uniform vec3 fall_far : source_color = vec3(0.80, 0.56, 0.22);
uniform vec3 sakura_ground : source_color = vec3(0.20, 0.44, 0.22);
uniform vec3 petal_color : source_color = vec3(1.0, 0.76, 0.85);
uniform vec3 ice_a : source_color = vec3(0.62, 0.84, 0.96);
uniform vec3 ice_b : source_color = vec3(0.82, 0.94, 1.0);
uniform vec3 forest_fall : source_color = vec3(0.70, 0.36, 0.16);
uniform vec3 forest_pine : source_color = vec3(0.14, 0.30, 0.30);
uniform vec3 forest_sakura : source_color = vec3(0.95, 0.66, 0.78);
// 脚印（world.gd 每一步在这张图上印一个椭圆，图跟着玩家平移）
uniform sampler2D trail_tex : filter_linear, repeat_disable;
uniform vec2 trail_origin = vec2(-100000.0);
uniform float trail_size = 61.44;
uniform vec3 print_deep : source_color = vec3(0.66, 0.74, 0.92);
uniform float rock_slope = 0.80;      // 法线 y 小于这个值（约 37 度）开始露岩石
uniform float rock_height = 125.0;    // 高过这里，缓坡也逐渐变成碎石
uniform float snow_height = 165.0;    // 雪线高度
// 泥土/小路、沙、树林这三样由 world.gd 算好存在顶点色里（R / G / B），无限地图不需要一张固定的贴图
uniform float fade_start = 28.0;
uniform float fade_end = 72.0;
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind_speed = 1.0;

varying vec3 v_pos;
varying vec3 v_n;
varying vec3 v_col;
varying vec4 v_biome;
varying float v_ice;

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

void vertex() {
	v_pos = VERTEX;
	v_n = NORMAL;
	v_col = COLOR.rgb;
	v_ice = COLOR.a;
	v_biome = CUSTOM0;
}

void fragment() {
	vec2 p = v_pos.xz;
	float patch = vnoise(p * 0.13 + vec2(17.0, 5.0));
	float n = patch * 0.65 + vnoise(p * 0.6) * 0.35;
	float n2 = vnoise(p * 0.05 + vec2(3.0, 41.0));
	float up = normalize(v_n).y;

	// 近处：草根的深色；远处：草尖的颜色 + 阵风亮带（和 grass.gdshader 同一套公式）
	vec3 near_grass = mix(color_a, color_b, n);
	vec2 d = normalize(wind_dir);
	float t = TIME * wind_speed;
	float gust = vnoise(p * 0.07 - d * t * 0.6);
	float wave = sin(dot(p, d) * 0.9 - t * 2.4 + gust * 4.0) * 0.5 + 0.5;
	vec3 far_grass = mix(color_a, mix(far_tip, far_dry, patch), 0.72);
	far_grass = mix(far_grass, gust_color, gust * wave * 0.28);
	float cam_d = distance(p, CAMERA_POSITION_WORLD.xz);
	vec3 grass = mix(near_grass, far_grass, smoothstep(fade_start * 0.6, fade_end, cam_d));
	grass = mix(grass, hill_grass, smoothstep(14.0, 36.0, v_pos.y));
	float far_k = smoothstep(fade_start * 0.6, fade_end, cam_d);
	vec4 bw = v_biome;

	// 樱花林：草地更嫩，地上落了一片片花瓣
	vec3 sak = mix(sakura_ground, mix(color_a, vec3(0.56, 0.78, 0.36), 0.72), far_k);
	float petals = step(0.84, vnoise(p * 3.6 + vec2(4.0, 9.0))) * step(0.3, patch);
	sak = mix(sak, petal_color, petals * 0.85);
	grass = mix(grass, sak, bw.a);
	// 秋林：枯黄的草地
	vec3 fall = mix(fall_ground * (0.9 + 0.2 * n), mix(fall_ground, mix(fall_far, vec3(0.80, 0.40, 0.18), patch * 0.6), 0.72), far_k);
	grass = mix(grass, fall, bw.b);
	// 沙漠：沙地，沙丘顶部亮、背阴面暗一点，加一些风吹出的沙纹
	float ripple = sin(dot(p, vec2(0.83, 0.55)) * 3.2 + vnoise(p * 0.4) * 6.0) * 0.5 + 0.5;
	vec3 sand_col = mix(sand_a, sand_b, n * 0.7 + ripple * 0.12);
	grass = mix(grass, sand_col, bw.g);
	// 雪原：雪地，背光一侧偏蓝；风吹出的一道道细雪纹（顺着风向）+ 大片很淡的起伏明暗
	vec2 wd = normalize(wind_dir);
	vec2 wp = vec2(dot(p, wd), dot(p, vec2(-wd.y, wd.x)));
	float streak = vnoise(vec2(wp.x * 0.35, wp.y * 3.2)) * vnoise(vec2(wp.x * 0.12 + 7.0, wp.y * 1.1));
	vec3 snow_col = mix(snow_shadow, snow_color, smoothstep(0.6, 0.95, up) * 0.6 + n * 0.4);
	snow_col = mix(snow_col, snow_shadow, smoothstep(0.25, 0.6, streak) * 0.22 + (n2 - 0.5) * 0.12);
	// 雪线不是平滑渐变：边上一块块的残雪，中间露出草地
	float edge_n = (vnoise(p * 0.18 + vec2(31.0, 7.0)) * 0.7 + vnoise(p * 0.9) * 0.3 - 0.5);
	float snow_k = clamp(bw.r + edge_n * 1.6 * bw.r * (1.0 - bw.r) * 4.0, 0.0, 1.0);
	snow_k = smoothstep(0.3, 0.7, snow_k);
	grass = mix(grass, snow_col, snow_k);

	// 远处看不到一棵棵树，把有树林的山坡染成林子的颜色（近处有真的树，不染）
	vec3 fc = forest_color;
	fc = mix(fc, forest_sakura, bw.a * 0.7);
	fc = mix(fc, forest_fall, bw.b);
	fc = mix(fc, forest_pine, bw.r);
	grass = mix(grass, fc * (0.85 + 0.3 * patch), v_col.b * smoothstep(180.0, 330.0, cam_d) * 0.85);

	// 小路 / 泥土 / 沙
	vec2 gm = v_col.rg;
	float dirt = smoothstep(0.35, 0.6, gm.r + (vnoise(p * 2.5) - 0.5) * 0.25);
	float sand = smoothstep(0.35, 0.6, gm.g + (vnoise(p * 2.0) - 0.5) * 0.2);
	vec3 dirt_col = mix(dirt_a, dirt_b, step(0.5, vnoise(p * 0.9 + vec2(9.0, 2.0))) * 0.6 + vnoise(p * 3.0) * 0.4);
	vec3 c = mix(grass, dirt_col, dirt);
	c = mix(c, sand_color * (0.92 + 0.08 * vnoise(p * 3.0)), sand);

	// 冰面：浅蓝 + 白色的裂纹和气泡
	float ice = smoothstep(0.4, 0.6, v_ice + (vnoise(p * 1.5) - 0.5) * 0.15);
	float crack = 1.0 - smoothstep(0.0, 0.035, abs(vnoise(p * 0.35 + vec2(7.0, 3.0)) - 0.5));
	crack = max(crack, 1.0 - smoothstep(0.0, 0.025, abs(vnoise(p * 0.9 + vec2(1.0, 8.0)) - 0.5)));
	vec3 ice_col = mix(ice_a, ice_b, n * 0.6 + crack * 0.7);
	c = mix(c, ice_col, ice);

	// 岩石：硬边的色块，高处更浅
	float rock_mask = 1.0 - smoothstep(rock_slope - 0.05, rock_slope + 0.02, up + (n2 - 0.5) * 0.12);
	rock_mask = max(rock_mask, smoothstep(rock_height - 15.0, rock_height + 20.0, v_pos.y + n2 * 25.0));
	rock_mask *= smoothstep(8.0, 16.0, v_pos.y);    // 平地草原上不露岩石
	float strata = step(0.5, fract(v_pos.y * 0.09 + n2 * 0.8));
	vec3 rock = mix(rock_dark, rock_light, smoothstep(40.0, 190.0, v_pos.y) * 0.7 + strata * 0.18);

	// 雪：只落在不太陡的山顶
	float snow = smoothstep(snow_height - 2.0, snow_height + 2.0, v_pos.y + (n2 - 0.5) * 16.0) * smoothstep(0.45, 0.6, up);

	c = mix(c, rock, rock_mask);
	c = mix(c, snow_color, snow);

	// 脚印：雪地里深（底部偏蓝的阴影 + 边缘被挤出来的一圈亮边），沙地里浅
	vec2 tuv = (p - trail_origin) / trail_size;
	float fp_k = clamp(bw.r + bw.g * 0.6, 0.0, 1.0) * (1.0 - ice) * (1.0 - rock_mask);
	if (fp_k > 0.01 && tuv.x > 0.0 && tuv.y > 0.0 && tuv.x < 1.0 && tuv.y < 1.0) {
		float tx = 1.0 / 1024.0;
		float fp = texture(trail_tex, tuv).r;
		float fx = texture(trail_tex, tuv + vec2(tx, 0.0)).r - texture(trail_tex, tuv - vec2(tx, 0.0)).r;
		float fz = texture(trail_tex, tuv + vec2(0.0, tx)).r - texture(trail_tex, tuv - vec2(0.0, tx)).r;
		float ring = texture(trail_tex, tuv + vec2(2.5 * tx, 0.0)).r + texture(trail_tex, tuv - vec2(2.5 * tx, 0.0)).r
			+ texture(trail_tex, tuv + vec2(0.0, 2.5 * tx)).r + texture(trail_tex, tuv - vec2(0.0, 2.5 * tx)).r;
		float rim = clamp(ring * 0.25 - fp, 0.0, 1.0);      // 脚印外面一圈
		vec3 deep = mix(print_deep, sand_a * 0.78, bw.g / max(bw.r + bw.g, 0.001));
		c = mix(c, deep, smoothstep(0.1, 0.7, fp) * 0.65 * fp_k);
		c = mix(c, vec3(1.0), rim * 0.5 * fp_k * bw.r);
		// 假的凹陷：按脚印深度的坡度把法线往里掰，受光一侧亮、背光一侧暗
		vec3 nw = normalize(v_n + vec3(fx, 0.0, fz) * 9.0 * fp_k);
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}

	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = smoothstep(0.0, 0.25, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
