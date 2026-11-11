// 软的物品（捕虫网的网兜）：贴图卡通着色 + 离挂点越远晃得越多
// soft_offset 由 hero_rig.gd 的弹簧每帧设置（物品本地坐标），所以挥网、走路、停下时网兜会甩、会荡、会回弹
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform float soft_top = 1.0;         // 这个高度以上不动（网圈）
uniform float soft_len = 0.54;        // 从网圈到网底的长度
uniform vec3 soft_offset = vec3(0.0);
uniform float rim_strength = 0.12;

void vertex() {
	float m = clamp((soft_top - VERTEX.y) / soft_len, 0.0, 1.0);
	VERTEX += soft_offset * m * m;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 4.0);
	EMISSION = c * rim * rim_strength;
}

void light() {
	float ndl = abs(dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += smoothstep(-0.05, 0.05, ndl - 0.05) * ATTENUATION * LIGHT_COLOR / PI;
}
