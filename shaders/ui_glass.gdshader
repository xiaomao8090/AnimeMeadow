shader_type canvas_item;
// 毛玻璃圆角块（物品栏格子、背包面板）：模糊身后的画面 + 一层墨绿色调 + 顶部淡淡的光泽 + 细白描边；
// glow 的 alpha > 0 时加一圈金色描边和外发光（选中的格子）。
// 节点要比 rect_size 大 pad*2，外发光画在 pad 里面。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec2 rect_size = vec2(64.0, 64.0);
uniform float pad = 12.0;
uniform float radius = 16.0;
uniform float blur = 3.2;
uniform vec4 tint : source_color = vec4(0.07, 0.11, 0.12, 0.42);
uniform vec4 border : source_color = vec4(1.0, 1.0, 1.0, 0.22);
uniform vec4 glow : source_color = vec4(0.925, 0.78, 0.50, 0.0);
uniform float alpha = 1.0;

float sd_round(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 full = rect_size + vec2(pad * 2.0);
	vec2 p = (UV - 0.5) * full;
	float d = sd_round(p, rect_size * 0.5, radius);
	float inside = 1.0 - smoothstep(-0.8, 0.4, d);

	vec2 px = SCREEN_PIXEL_SIZE * 7.0;
	vec3 bg = textureLod(screen_tex, SCREEN_UV, blur).rgb * 0.36;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(px.x, px.y), blur).rgb * 0.16;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, px.y), blur).rgb * 0.16;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(px.x, -px.y), blur).rgb * 0.16;
	bg += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, -px.y), blur).rgb * 0.16;
	vec3 col = mix(bg, tint.rgb, tint.a);
	// 顶部的光泽：上面亮一点，往下渐暗
	float ty = clamp((p.y + rect_size.y * 0.5) / rect_size.y, 0.0, 1.0);
	col += vec3(1.0) * 0.07 * (1.0 - smoothstep(0.0, 0.55, ty));

	// 细白描边（内侧 1 像素）
	float ring = 1.0 - smoothstep(0.6, 1.4, abs(d + 1.0));
	col = mix(col, border.rgb, border.a * ring);
	// 选中：金色描边加粗
	float gring = 1.0 - smoothstep(1.0, 2.2, abs(d + 1.2));
	col = mix(col, glow.rgb, glow.a * gring);

	// 外发光（只在格子外面）
	float halo = glow.a * 0.55 * exp(-max(d, 0.0) / 4.5) * step(0.0, d);
	float a = max(inside, halo);
	vec3 outc = mix(glow.rgb, col, inside);
	COLOR = vec4(outc, a * alpha);
}
