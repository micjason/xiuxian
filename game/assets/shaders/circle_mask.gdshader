shader_type canvas_item;
// 圆形裁切（Q 版头像）：圆外透明，边缘 1.5% 羽化。
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float d = distance(UV, vec2(0.5));
	c.a *= 1.0 - smoothstep(0.485, 0.5, d);
	COLOR = c;
}
