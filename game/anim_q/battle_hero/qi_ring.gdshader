shader_type canvas_item;
render_mode blend_add;
// 脚下聚气环（大招蓄力）：贴图只当画布（任意白图），全部在 shader 里画。节点 scale.y 压扁成地面椭圆。
// fill 0..1 顺时针（从后方 12 点开始）填满；ready = 接近蓄满时的脉动（0..1）；flare = 释放瞬间整环闪亮。
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float ready : hint_range(0.0, 1.0) = 0.0;
uniform float flare : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_k = 0.8;
// 1 = 只画前半圈（靠近镜头，盖在脚上），-1 = 只画后半圈（在身体后面），0 = 整圈
uniform float half_mode = 0.0;
uniform vec4 c_low : source_color = vec4(0.45, 0.95, 1.0, 1.0);
uniform vec4 c_full : source_color = vec4(1.0, 0.86, 0.35, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	float ang = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);   // 0 = 上（远处），顺时针
	float band = smoothstep(0.70, 0.76, r) * (1.0 - smoothstep(0.90, 0.97, r));
	float core = smoothstep(0.78, 0.83, r) * (1.0 - smoothstep(0.86, 0.91, r));
	float on = 1.0 - smoothstep(fill - 0.004, fill + 0.004, ang);
	if (fill >= 0.999) { on = 1.0; }
	float head = exp(-pow((ang - fill) * 40.0, 2.0)) * step(0.01, fill) * step(fill, 0.999);
	vec3 col = mix(c_low.rgb, c_full.rgb, smoothstep(0.75, 1.0, fill));
	float pulse = 0.5 + 0.5 * sin(TIME * 12.0);
	// 底轨（暗）+ 已蓄部分（亮）+ 蓄力头部亮点
	float track = band * 0.18;
	float lit = band * on * (0.45 + 0.35 * fill) + core * on * 0.6 + head * band * 1.2;
	// 12 个刻度点
	float tick = smoothstep(0.85, 1.0, cos(ang * 6.2831853 * 12.0)) * smoothstep(0.92, 0.95, r) * (1.0 - smoothstep(0.98, 1.0, r));
	lit += tick * on * 0.6;
	// 环内淡淡的气场
	float inner = (1.0 - smoothstep(0.0, 0.75, r)) * 0.22 * fill * fill;
	float a = track + lit * (1.0 + ready * (0.35 + 0.5 * pulse)) + inner * (1.0 + ready * pulse);
	a += flare * (band * 1.4 + (1.0 - smoothstep(0.0, 0.9, r)) * 0.5);
	vec3 rgb = mix(col, vec3(1.0, 0.97, 0.8), flare * 0.4 + head * 0.3);
	float keep = half_mode > 0.5 ? smoothstep(-0.04, 0.04, p.y) : (half_mode < -0.5 ? 1.0 - smoothstep(-0.04, 0.04, p.y) : 1.0);
	COLOR = vec4(rgb * a * alpha_k * keep, 1.0);
}
