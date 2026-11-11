// 树叶面片：每个实例是一张永远朝向镜头的叶簇贴图，法线取"从树冠中心向外"，
// 所以整棵树的明暗是一整块干净的卡通色块，边缘是碎叶的轮廓
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;

uniform sampler2D leaf_tex : filter_linear_mipmap, repeat_disable, hint_default_white;
uniform vec2 wind_dir = vec2(1.0, 0.35);
uniform float sway = 0.12;
uniform float wind_speed = 1.0;
uniform vec3 shade_tint : source_color = vec3(0.55, 0.72, 0.80);

varying vec3 v_wn;
varying vec3 v_col;

void vertex() {
	// 网格的四个顶点都在原点，所以这里的 VERTEX 就是这张面片的世界坐标中心
	vec3 center = VERTEX;
	vec3 canopy = INSTANCE_CUSTOM.xyz;
	float rnd = INSTANCE_CUSTOM.w;
	float size = COLOR.a * 4.0;

	vec2 d = normalize(wind_dir);
	float t = TIME * wind_speed;
	float s = sin(t * 1.3 + center.x * 0.35 + center.z * 0.3)
			+ 0.3 * sin(t * 3.4 + center.x * 1.9 + center.y * 1.6 + center.z * 1.3);
	center.xz += d * s * sway;
	center.y += 0.25 * sway * sin(t * 2.1 + center.x * 1.2 + center.z * 1.5);

	// 叶片自身的轻微转动 = 沙沙抖动
	float roll = rnd * TAU + sin(t * 2.6 + rnd * 40.0) * 0.14;
	vec2 c = UV - 0.5;
	vec2 r = vec2(c.x * cos(roll) - c.y * sin(roll), c.x * sin(roll) + c.y * cos(roll));
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	VERTEX = center + (right * r.x + up * r.y) * size;

	v_wn = normalize(normalize(center - canopy) + vec3(0.0, 0.25, 0.0));
	v_col = COLOR.rgb;
}

void fragment() {
	vec4 tex = texture(leaf_tex, UV);
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.4;
	float g = smoothstep(-0.6, 0.8, v_wn.y);
	vec3 c = mix(v_col * shade_tint * 0.85, v_col, g) * mix(0.8, 1.0, tex.r);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(v_wn, 0.0)).xyz);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-0.12, -0.04, ndl);
	DIFFUSE_LIGHT += lit * ATTENUATION * LIGHT_COLOR / PI;
}
