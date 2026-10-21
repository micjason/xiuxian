shader_type canvas_item;
// 精英 / 章末首领用的怪物着色器 = 美术 shaders/boss_outline.gdshader（SPEC_Q §14.2 描边 + 暗边 + 外光呼吸）
// + 通用怪物着色器 monster_fx.gdshader（受击闪白 flash、从头往下溶解 dissolve）合在一起，一次绘制。
// 参数名 flash / dissolve / noise_tex 和 monster_fx 一样，所以 monster_rig 的动作代码不用区分。
// 和美术原版的区别（为了低端机）：
//   - 24 方向 → 16 方向；本身不透明的像素（怪物身体内部）直接跳过采样（大约省一半）。
//   - 输出乘了节点的 modulate（原版忽略），淡入淡出、染色照常生效。
//   - 四边形外扩按 VERTEX 的正负号算，Sprite2D 必须 centered=true、offset=(0,0)；flip_h 也没问题。
// px 参数是贴图像素；monster_rig 会按怪物的缩放换算，保证屏幕上的粗细和 SPEC 一致。
uniform vec4 outline_color : source_color = vec4(1.0, 0.788, 0.235, 1.0);
uniform vec4 outline_top : source_color = vec4(1.0, 0.965, 0.722, 1.0);
uniform vec4 edge_color : source_color = vec4(0.722, 0.431, 0.063, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.878, 0.29, 0.9);
uniform float outline_px = 5.8;
uniform float edge_px = 1.7;
uniform float glow_px = 20.0;
uniform float pad_px = 40.0;
uniform float pulse_speed = 2.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_edge : source_color = vec4(0.62, 0.95, 1.0, 1.0);
uniform sampler2D noise_tex : filter_linear, repeat_enable;

varying vec4 v_mod;

float inb(vec2 uv) {
	vec2 b = step(vec2(0.0), uv) * step(uv, vec2(1.0));
	return b.x * b.y;
}
// TEXTURE 不能当参数传给函数（Godot 4 会报 custom_samplers 错），所以用宏
#define A_AT(uv) (texture(TEXTURE, (uv)).a * inb(uv))

void vertex() {
	v_mod = COLOR;
	vec2 ts = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 duv = UV * 2.0 - 1.0;
	VERTEX += sign(VERTEX) * pad_px;
	UV = (UV * ts + duv * pad_px) / ts;
}

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	float inside = (UV.x >= 0.0 && UV.y >= 0.0 && UV.x <= 1.0 && UV.y <= 1.0) ? 1.0 : 0.0;
	vec4 base = texture(TEXTURE, clamp(UV, vec2(0.0), vec2(1.0))) * inside;
	vec4 col = base;
	if (base.a < 0.99) {
		float ring = 0.0;
		float outer = 0.0;
		float glow = 0.0;
		for (int i = 0; i < 16; i++) {
			float an = 6.2831853 * float(i) / 16.0;
			vec2 d = vec2(cos(an), sin(an)) * px;
			ring = max(ring, max(A_AT(UV + d * outline_px), A_AT(UV + d * outline_px * 0.5)));
			outer = max(outer, A_AT(UV + d * (outline_px + edge_px)));
			glow += A_AT(UV + d * (outline_px + glow_px * 0.35)) + A_AT(UV + d * (outline_px + glow_px * 0.7)) + A_AT(UV + d * (outline_px + glow_px));
		}
		glow = clamp(glow / 48.0 * 2.4, 0.0, 1.0);
		float pulse = pulse_speed > 0.0 ? 0.875 + 0.125 * sin(TIME * pulse_speed) : 1.0;
		vec3 ringc = mix(outline_top.rgb, outline_color.rgb, clamp(UV.y, 0.0, 1.0));
		col = vec4(glow_color.rgb, glow_color.a * glow * pulse);
		col = mix(col, vec4(edge_color.rgb, 1.0), outer);
		col = mix(col, vec4(mix(ringc, flash_color.rgb, flash * 0.5), 1.0), ring);
		col.rgb = mix(col.rgb, base.rgb, base.a);
		col.a = max(col.a, base.a);
	}
	// 受击闪白：只闪怪物本体（描边只提亮一半）
	col.rgb = mix(col.rgb, flash_color.rgb, flash * base.a);
	if (dissolve > 0.0) {
		vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
		float n = texture(noise_tex, UV * 1.6).r;
		float f = n * 0.55 + (1.0 - uv.y) * 0.45;
		float t = 1.02 - dissolve * 1.12;
		float keep = step(f, t);
		float edge = smoothstep(t - 0.08, t, f) * keep;
		col.rgb = mix(col.rgb, dissolve_edge.rgb, clamp(edge * 1.4 + dissolve * 0.35, 0.0, 1.0));
		col.a *= keep;
	}
	COLOR = col * v_mod;
}
