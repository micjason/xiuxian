shader_type canvas_item;
// 怪物通用着色器：整只闪白(flash) + 从头往下溶解成灵气(dissolve)。单张怪图即可，不需要拆层。
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 edge_color : source_color = vec4(0.62, 0.95, 1.0, 1.0);
uniform sampler2D noise_tex : filter_linear, repeat_enable;

void fragment() {
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, flash_color.rgb, flash);
	if (dissolve > 0.0) {
		float n = texture(noise_tex, UV * 1.6).r;
		float f = n * 0.55 + (1.0 - UV.y) * 0.45;      // 头顶先散
		float t = 1.02 - dissolve * 1.12;
		float keep = step(f, t);
		float edge = smoothstep(t - 0.08, t, f) * keep;
		c.rgb = mix(c.rgb, edge_color.rgb, clamp(edge * 1.4 + dissolve * 0.35, 0.0, 1.0));
		c.a *= keep;
	}
	COLOR = c;
}
