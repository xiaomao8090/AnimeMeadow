// 浅水塘：按水深从浅青到深蓝，岸边一圈白色泡沫，水面有卡通感的亮斑
shader_type spatial;
render_mode unshaded;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 shallow_color : source_color = vec3(0.50, 0.88, 0.86);
uniform vec3 deep_color : source_color = vec3(0.18, 0.52, 0.80);
uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 light_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform vec2 pond_center = vec2(0.0);
uniform float pond_radius = 11.0;   // 超出这个半径的部分不画（水面网格是方的）

varying vec3 v_world;

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
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 用深度图算出"水面到水底"的厚度
	float depth = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 vpos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vpos.xyz /= vpos.w;
	float thickness = max(VERTEX.z - vpos.z, 0.0);

	if (distance(v_world.xz, pond_center) > pond_radius) {
		discard;
	}

	vec2 p = v_world.xz;
	float t = TIME;
	float n1 = vnoise(p * 1.6 + vec2(t * 0.25, t * 0.18));
	float n2 = vnoise(p * 2.3 - vec2(t * 0.20, t * 0.30));
	float ripple = n1 * n2;

	float depth_f = smoothstep(0.0, 1.3, thickness);
	vec3 c = mix(shallow_color, deep_color, depth_f);
	c = mix(c, c * 1.2 + 0.1, step(0.38, ripple) * 0.7);
	float foam = 1.0 - smoothstep(0.0, 0.10 + 0.12 * n1, thickness);
	c = mix(c, foam_color, foam);

	ALBEDO = c * light_tint;
	ALPHA = clamp(0.6 + depth_f * 0.3 + foam, 0.0, 1.0);
}
