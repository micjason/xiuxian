shader_type canvas_item;
// 水墨云雾：两层可平铺的噪声云缓慢反向飘动，叠在背景画上。
// mist_tex 是 assets/art/ui/mist.png（可平铺，云量在 alpha 通道）。

uniform sampler2D mist_tex : repeat_enable, filter_linear;
uniform float speed = 0.010;
uniform float strength = 0.55;
uniform vec4 tint : source_color = vec4(0.78, 0.9, 0.88, 1.0);

void fragment() {
	vec2 uv = UV * vec2(1.4, 3.2);
	float near = texture(mist_tex, uv + vec2(TIME * speed, 0.0)).a;
	float far = texture(mist_tex, uv * vec2(0.65, 0.8) + vec2(0.37 - TIME * speed * 0.55, 0.21)).a;
	float cloud = clamp(near * 0.6 + far * 0.55 - 0.18, 0.0, 1.0);
	// 云主要出现在画面中下部，顶部和底部留干净，避免盖住文字区。
	float band = smoothstep(0.12, 0.38, UV.y) * (1.0 - smoothstep(0.62, 0.95, UV.y));
	COLOR = vec4(tint.rgb, cloud * strength * band);
}
