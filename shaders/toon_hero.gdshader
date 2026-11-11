// 角色身体专用的卡通着色：和 toon.gdshader 一样，多一个 squash_y——
// 第一人称时把高过这个高度的顶点压平到这个高度（头被压成脖子处的一个平面），
// 这样镜头不会穿进自己的头里，低头看又不会看到一个空洞
shader_type spatial;
render_mode world_vertex_coords;

uniform vec3 albedo : source_color = vec3(0.6, 0.6, 0.6);
uniform float band_threshold : hint_range(-1.0, 1.0) = 0.0;
uniform float band_softness : hint_range(0.001, 0.5) = 0.04;
uniform float rim_strength : hint_range(0.0, 1.0) = 0.18;
uniform float squash_y = 100000.0;
uniform vec3 cap_color : source_color = vec3(0.35, 0.14, 0.09);   // 压平后的切面：涂成衣领里面的深色
varying float v_cap;

void vertex() {
	v_cap = 0.0;
	if (VERTEX.y > squash_y) {
		VERTEX.y = squash_y;
		NORMAL = vec3(0.0, 1.0, 0.0);
		v_cap = 1.0;
	}
}

void fragment() {
	ALBEDO = mix(albedo, cap_color, step(0.5, v_cap));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	EMISSION = albedo * rim * rim_strength;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(band_threshold - band_softness, band_threshold + band_softness, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
