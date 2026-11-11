// 花：UV2 当遮罩（x=花瓣 y=花心 其余=茎），花瓣颜色来自实例 custom data
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform vec3 stem_color : source_color = vec3(0.20, 0.48, 0.20);
uniform vec3 center_color : source_color = vec3(1.0, 0.80, 0.20);
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float wind_strength = 0.22;
uniform float wind_speed = 1.0;
#include "res://shaders/push.gdshaderinc"

varying vec3 v_petal;
varying vec2 v_mask;

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
	float k = h * h;
	vec2 p = VERTEX.xz;
	vec2 d = normalize(wind_dir);
	float t = TIME * wind_speed;

	float gust = vnoise(p * 0.07 - d * t * 0.6);
	float wave = sin(dot(p, d) * 0.9 - t * 2.4 + gust * 4.0) * 0.5 + 0.5;
	float flutter = sin(t * 4.1 + p.x * 2.7 + p.y * 1.9) * 0.2;
	float bend = (0.12 + gust * 0.88) * (0.55 + 0.45 * wave) + flutter * (0.2 + gust);
	// 玩家碰到的花：整株绕根部倒下去
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 pb = vec3(1.0, 0.0, 0.0);
	if (distance(p, CAMERA_POSITION_WORLD.xz) < 14.0) {
		pb = push_bend(root);
	} else {
		pb.z = 0.0;
	}
	VERTEX.xz += d * bend * wind_strength * k * (1.0 - clamp(pb.z, 0.0, 1.0) * 0.8);
	if (abs(pb.z) > 0.001) {
		VERTEX = push_apply(VERTEX, root, h, pb, 1.1);
	}

	v_petal = INSTANCE_CUSTOM.rgb;
	v_mask = UV2;
}

void fragment() {
	vec3 c = stem_color;
	c = mix(c, v_petal, v_mask.x);
	c = mix(c, center_color, v_mask.y);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float lit = smoothstep(0.0, 0.25, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
