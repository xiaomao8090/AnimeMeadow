// 空中的光点（粒子用）：朝向镜头的柔光小圆点，白天是花粉，晚上是萤火虫
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.6);
uniform float intensity = 1.0;

void vertex() {
	mat4 bb = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	bb = bb * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * bb;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float a = clamp(1.0 - d, 0.0, 1.0);
	a = a * a;
	float core = smoothstep(0.45, 0.0, d);
	ALBEDO = tint * intensity * (0.6 + core);
	ALPHA = a * COLOR.a;
}
