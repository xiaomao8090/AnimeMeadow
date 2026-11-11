// 描边：把模型沿法线在屏幕空间外扩几个像素，只画背面（挂在 toon 材质的 next_pass 上）
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec3 outline_color : source_color = vec3(0.10, 0.09, 0.17);
uniform float width_px = 2.2;
uniform bool radial = false;   // 石头是硬边模型，用"从中心向外"的方向外扩才不会裂开

void vertex() {
	vec3 dir = radial ? normalize(VERTEX) : NORMAL;
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec3 n_view = mat3(MODELVIEW_MATRIX) * dir;
	vec2 n_px = (PROJECTION_MATRIX * vec4(n_view, 0.0)).xy * VIEWPORT_SIZE;
	n_px = normalize(n_px + vec2(0.00001));
	// 远处的描边细一点，不会糊成一团黑
	float w = width_px * clamp(35.0 / max(clip.w, 0.001), 0.3, 1.0);
	clip.xy += n_px / VIEWPORT_SIZE * 2.0 * w * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color;
}
