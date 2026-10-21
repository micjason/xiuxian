shader_type canvas_item;
// 主角战斗姿势（单帧 player_fight.png）专用：
//  · 待机摆动：上身绕脚底轻微摆（剪切），衣袖 / 衣摆 / 发梢（离身体中线越远越明显）随波飘动，剑身基本不动
//  · 受击闪白 flash、失败变灰 gray
//  · 大招蓄力外光 charge_glow（只在透明 / 半透明像素上采样，身体内部不采样）
// 精灵必须 centered=true、offset=0（四角往外扩 pad_px，给摆动和外光留空间）。
uniform float pad_px = 24.0;
uniform float sway = 0.0;          // 上身摆动（uv 单位，正 = 往右），由脚本按时间给
uniform float flutter_amp = 0.006; // 飘动幅度（uv 单位）
uniform float flutter_speed = 3.1;
uniform float flutter_freq = 9.0;
uniform float flutter_on = 1.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float gray : hint_range(0.0, 1.0) = 0.0;
uniform float charge_glow : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(0.59, 0.96, 1.0, 1.0);
uniform float glow_px = 14.0;
// 剑身（不飘）：uv 矩形 x0,y0,x1,y1（朝右的图）
uniform vec4 rigid_rect = vec4(0.56, 0.36, 1.0, 0.56);

varying vec4 v_mod;

void vertex() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 grow = vec2(pad_px) / tex_size;
	VERTEX += sign(VERTEX) * pad_px;
	UV = (UV - 0.5) * (1.0 + 2.0 * grow) + 0.5;
	v_mod = COLOR;
}

float inb(vec2 uv) {
	return step(0.0, uv.x) * step(0.0, uv.y) * step(uv.x, 1.0) * step(uv.y, 1.0);
}
#define A_AT(uv) (texture(TEXTURE, (uv)).a * inb(uv))

void fragment() {
	vec2 uv = UV;
	float h = clamp(1.0 - uv.y, 0.0, 1.0);          // 0 = 脚底
	float side = clamp(abs(uv.x - 0.47) * 2.2, 0.0, 1.0);
	vec2 rr = step(rigid_rect.xy, uv) * step(uv, rigid_rect.zw);
	float rigid = rr.x * rr.y;
	float fl = sin(TIME * flutter_speed + uv.y * flutter_freq + uv.x * 3.0) * flutter_amp
		* smoothstep(0.2, 0.95, side) * smoothstep(0.03, 0.35, h) * flutter_on * (1.0 - rigid * 0.85);
	float fy = cos(TIME * flutter_speed * 0.8 + uv.x * 7.0) * flutter_amp * 0.35 * smoothstep(0.3, 1.0, side) * flutter_on * (1.0 - rigid);
	uv.x -= sway * h * h + fl;
	uv.y -= fy;
	vec4 c = texture(TEXTURE, uv) * inb(uv);
	// 外光：只在没有完全不透明的像素上算（身体内部跳过）
	if (charge_glow > 0.004 && c.a < 0.99) {
		vec2 px = TEXTURE_PIXEL_SIZE * glow_px;
		float m = 0.0;
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 0.5235988;
			vec2 d = vec2(cos(a), sin(a));
			m = max(m, A_AT(uv + d * px) * 0.55);
			m = max(m, A_AT(uv + d * px * 0.5));
		}
		float g = m * (1.0 - c.a) * charge_glow;
		c.rgb = mix(glow_color.rgb, c.rgb, c.a / max(c.a + g, 0.0001));
		c.a = c.a + g * glow_color.a;
	}
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, vec3(lum) * vec3(0.82, 0.84, 0.9), gray);
	c.rgb = mix(c.rgb, flash_color.rgb, flash * 0.85);
	COLOR = c * v_mod;
}
