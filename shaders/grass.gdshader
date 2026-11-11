// 草叶：随风摆动 + 阵风高光 + 玩家踩踏压弯
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform vec3 base_color : source_color = vec3(0.12, 0.34, 0.16);
uniform vec3 tip_color : source_color = vec3(0.38, 0.62, 0.24);
uniform vec3 dry_tip_color : source_color = vec3(0.52, 0.64, 0.26);
uniform vec3 gust_color : source_color = vec3(0.70, 0.82, 0.42);
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind_strength = 0.38;
uniform float wind_speed = 1.0;
#include "res://shaders/push.gdshaderinc"
// 远近过渡：远处的草逐渐变稀、变矮，最后缩回地面（数值由 world.gd 统一设置）
uniform float fade_start = 28.0;
uniform float fade_end = 72.0;
uniform float min_density = 0.3;
uniform float view_end = 85.0;

varying float v_h;
varying float v_gust;
varying float v_patch;
varying vec4 v_biome;   // 实例颜色 = 群系权重：r 雪原 / g 沙漠 / b 秋林 / a 樱花林

// 各群系的草根色和草尖色（terrain.gdshader 里远处的地面用同一套颜色）
const vec3 SNOW_BASE = vec3(0.30, 0.42, 0.40);
const vec3 SNOW_TIP = vec3(0.60, 0.66, 0.56);    // 雪原边上冒出雪面的枯草（以前接近白色，看起来像一地白点）
const vec3 SAND_BASE = vec3(0.50, 0.42, 0.22);
const vec3 SAND_TIP = vec3(0.86, 0.76, 0.44);
const vec3 FALL_BASE = vec3(0.34, 0.24, 0.10);
const vec3 FALL_TIP = vec3(0.92, 0.64, 0.24);
const vec3 SAKURA_BASE = vec3(0.16, 0.40, 0.20);
const vec3 SAKURA_TIP = vec3(0.56, 0.78, 0.36);

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
	float h = UV.y;
	vec2 p = VERTEX.xz;

	// INSTANCE_CUSTOM: r = 这片草的高度倍率, g = 0..1 的序号（用来按距离抽稀）
	float cam_d = distance(p, CAMERA_POSITION_WORLD.xz);
	float dens = mix(1.0, min_density, smoothstep(fade_start, fade_end, cam_d));
	float keep = 1.0 - smoothstep(dens, dens + 0.06, INSTANCE_CUSTOM.g);
	keep *= 1.0 - smoothstep(view_end * 0.8, view_end, cam_d);
	VERTEX.y -= h * 0.55 * INSTANCE_CUSTOM.r * (1.0 - keep);
	float k = h * h * keep;
	vec2 d = normalize(wind_dir);
	float t = TIME * wind_speed;

	// 大片移动的阵风 + 沿风向传播的波浪 + 细碎抖动
	float gust = vnoise(p * 0.07 - d * t * 0.6);
	float wave = sin(dot(p, d) * 0.9 - t * 2.4 + gust * 4.0) * 0.5 + 0.5;
	float flutter = sin(t * 5.3 + p.x * 3.1 + p.y * 2.3) * 0.18;
	float bend = (0.12 + gust * 0.88) * (0.55 + 0.45 * wave) + flutter * (0.2 + gust);

	// 玩家碰到的草：整片叶子绕根部倒下去（按草根位置算，同一片草的顶点方向一致，不会被拉宽拉长）
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 pb = vec3(1.0, 0.0, 0.0);
	if (cam_d < 14.0) {
		pb = push_bend(root);
	} else {
		pb.z = 0.0;
	}

	// 被压住的草几乎不随风摆
	float wk = k * (1.0 - clamp(pb.z, 0.0, 1.0) * 0.8);
	VERTEX.xz += d * bend * wind_strength * wk;
	VERTEX.y -= abs(bend) * wind_strength * wk * 0.35;

	if (abs(pb.z) > 0.001) {
		VERTEX = push_apply(VERTEX, root, h, pb, 1.3);
	}

	v_h = h;
	v_gust = gust * wave;
	v_patch = vnoise(p * 0.13 + vec2(17.0, 5.0));
	v_biome = COLOR;
}

void fragment() {
	vec3 tip = mix(tip_color, dry_tip_color, v_patch);
	vec3 base = base_color;
	vec4 b = v_biome;
	base = mix(base, SAKURA_BASE, b.a);
	tip = mix(tip, SAKURA_TIP, b.a);
	base = mix(base, FALL_BASE, b.b);
	tip = mix(tip, mix(FALL_TIP, vec3(0.80, 0.40, 0.18), v_patch * 0.6), b.b);
	base = mix(base, SAND_BASE, b.g);
	tip = mix(tip, SAND_TIP, b.g);
	base = mix(base, SNOW_BASE, b.r);
	tip = mix(tip, SNOW_TIP, b.r);
	vec3 c = mix(base, tip, v_h);
	c = mix(c, gust_color, v_gust * v_h * v_h * 0.45);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// 法线统一朝上，草地受光干净、不会一片亮一片暗
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = smoothstep(0.0, 0.25, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
