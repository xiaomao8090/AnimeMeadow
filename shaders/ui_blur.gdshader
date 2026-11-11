shader_type canvas_item;
// 毛玻璃：读屏幕画面的模糊版本（mipmap + 多次采样），盖一层淡淡的墨绿色。
// side_only = 1 时只模糊左边一块（主菜单里的设置面板），右边保持清楚

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float side_only : hint_range(0.0, 1.0) = 0.0;
uniform float edge = 0.43;
uniform vec4 tint : source_color = vec4(0.07, 0.11, 0.12, 1.0);

void fragment() {
	float m = mix(1.0, 1.0 - smoothstep(edge - 0.05, edge + 0.07, UV.x), side_only);
	float a = amount * m;
	if (a < 0.002) {
		COLOR = vec4(0.0);
	} else {
		float lod = 4.2 * a;
		vec2 px = SCREEN_PIXEL_SIZE * 14.0 * a;
		vec3 c = textureLod(screen_tex, SCREEN_UV, lod).rgb * 0.2;
		c += textureLod(screen_tex, SCREEN_UV + vec2( px.x, 0.0), lod).rgb * 0.1;
		c += textureLod(screen_tex, SCREEN_UV + vec2(-px.x, 0.0), lod).rgb * 0.1;
		c += textureLod(screen_tex, SCREEN_UV + vec2(0.0,  px.y), lod).rgb * 0.1;
		c += textureLod(screen_tex, SCREEN_UV + vec2(0.0, -px.y), lod).rgb * 0.1;
		c += textureLod(screen_tex, SCREEN_UV + px * vec2( 0.7,  0.7), lod).rgb * 0.1;
		c += textureLod(screen_tex, SCREEN_UV + px * vec2(-0.7,  0.7), lod).rgb * 0.1;
		c += textureLod(screen_tex, SCREEN_UV + px * vec2( 0.7, -0.7), lod).rgb * 0.1;
		c += textureLod(screen_tex, SCREEN_UV + px * vec2(-0.7, -0.7), lod).rgb * 0.1;
		c = mix(c, tint.rgb, 0.42);
		COLOR = vec4(c, a);
	}
}
