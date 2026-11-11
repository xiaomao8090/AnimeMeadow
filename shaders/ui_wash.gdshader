shader_type canvas_item;
// 菜单的调色层：左边一层柔和的暗色（让文字清楚）、底部压暗、四角暗角、一点点胶片颗粒

uniform float wash : hint_range(0.0, 1.0) = 1.0;      // 左侧暗色 + 底部
uniform float vignette : hint_range(0.0, 1.0) = 1.0;
uniform float grain : hint_range(0.0, 0.2) = 0.035;
uniform float aspect = 1.7778;
uniform vec4 ink : source_color = vec4(0.055, 0.085, 0.095, 1.0);
uniform vec4 warm : source_color = vec4(1.0, 0.82, 0.55, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float left = 1.0 - smoothstep(0.0, 0.62, uv.x);
	left = left * left * 0.62;
	float bottom = smoothstep(0.72, 1.0, uv.y) * 0.30;
	vec2 d = (uv - 0.5) * vec2(aspect, 1.0) / aspect * 1.6;
	float vig = smoothstep(0.45, 1.05, length(d)) * 0.55;
	float a = clamp((left + bottom) * wash + vig * vignette, 0.0, 0.88);

	// 右上角（天空那边）一层很淡的暖光，像夕阳的光晕
	float glow = (1.0 - smoothstep(0.0, 0.75, distance(uv * vec2(aspect, 1.0), vec2(aspect * 0.86, 0.08)))) * 0.10 * wash;

	float n = hash(floor(FRAGCOORD.xy) + fract(TIME * 7.0) * 113.0) - 0.5;
	vec3 col = mix(ink.rgb, warm.rgb, glow / max(a + glow, 0.001));
	COLOR = vec4(col + n * grain, clamp(a + glow + n * grain * (wash + vignette) * 0.5, 0.0, 1.0));
}
