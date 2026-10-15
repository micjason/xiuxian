#!/usr/bin/env python3
"""程序化绘制游戏端 UI 框体（九宫格）、稀有度框、进度条、图标底板、法阵、云雾、标题 Logo。

没有任何第三方素材，全部由代码画出，所以没有授权问题；换成正式美术时，只要同名 PNG 覆盖
game/assets/art/ui/ 里的文件即可（九宫格边距写在 game/scripts/ui/art/art_lib.gd）。
用法：python3 tools/assets/build_ui_frames.py <输出目录，默认 game/assets/art/ui>
依赖：Pillow、numpy。
"""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "../../game/assets/art/ui")
FONT = os.environ.get("TITLE_FONT", "")  # 马善政（OFL），用于烘焙标题 Logo
S = 4  # 超采样倍数

GOLD = (219, 189, 112)
GOLD_L = (244, 222, 150)
GOLD_D = (133, 106, 46)
JADE = (117, 173, 133)
JADE_D = (79, 128, 105)
JADE_L = (173, 214, 184)
INK = (9, 12, 14)
SURF = (22, 33, 31)
SURF_D = (12, 20, 19)
CIN = (178, 58, 46)
CIN_L = (238, 125, 112)
RARITY = [(188, 196, 191), (102, 196, 138), (98, 167, 234), (184, 144, 242), (242, 162, 76), (242, 107, 92)]


def canvas(w, h):
    return Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))


def down(img, w, h):
    return img.resize((w, h), Image.LANCZOS)


def poly_chamfer(x0, y0, x1, y1, cut):
    c = cut
    return [(x0 + c, y0), (x1 - c, y0), (x1, y0 + c), (x1, y1 - c), (x1 - c, y1), (x0 + c, y1), (x0, y1 - c), (x0, y0 + c)]


def gradient(w, h, top, bot, alpha_top=255, alpha_bot=255):
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    t = np.linspace(0, 1, h)[:, None]
    for i in range(3):
        arr[:, :, i] = (top[i] * (1 - t) + bot[i] * t).astype(np.uint8)
    arr[:, :, 3] = (alpha_top * (1 - t) + alpha_bot * t).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def frame(w, h, fill=(SURF, SURF_D), fill_alpha=(235, 235), border=GOLD_D, bw=3, cut=14, pad=2, inner=None, inner_gap=7, inner_w=1.5,
          corner=None, corner_len=26, highlight=None, glow=None, glow_r=6):
    img = canvas(w, h)
    W, H = w * S, h * S
    p = pad * S
    pts = poly_chamfer(p, p, W - p, H - p, cut * S)
    if glow:
        g = canvas(w, h)
        gd = ImageDraw.Draw(g)
        gd.polygon(pts, outline=glow + (150,), width=int(bw * S * 2.2))
        g = g.filter(ImageFilter.GaussianBlur(glow_r * S))
        img = Image.alpha_composite(img, g)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    fillimg = gradient(W, H, fill[0], fill[1], fill_alpha[0], fill_alpha[1])
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    layer.paste(fillimg, (0, 0), mask)
    if highlight:  # 顶部高光渐变
        hl = gradient(W, H // 2, highlight, highlight, 70, 0)
        full = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        full.paste(hl, (0, 0))
        full.putalpha(ImageChops.multiply(full.getchannel("A"), mask))
        layer = Image.alpha_composite(layer, full)
    img = Image.alpha_composite(img, layer)
    d = ImageDraw.Draw(img)
    d.polygon(pts, outline=border + (255,), width=int(bw * S))
    if inner:
        ip = (pad + bw + inner_gap) * S
        ipts = poly_chamfer(ip, ip, W - ip, H - ip, max(2, (cut - 4)) * S)
        d.polygon(ipts, outline=inner + (200,), width=max(1, int(inner_w * S)))
    if corner:
        # 四角金色折角：沿边延伸的 L 形 + 切角处菱形点
        o = (pad + bw / 2) * S
        L = corner_len * S
        lw = int((bw + 1.5) * S)
        for (cx, cy, sx, sy) in [(o, o, 1, 1), (W - o, o, -1, 1), (o, H - o, 1, -1), (W - o, H - o, -1, -1)]:
            c = cut * S
            d.line([(cx + sx * c, cy), (cx + sx * (c + L), cy)], fill=corner + (255,), width=lw)
            d.line([(cx, cy + sy * c), (cx, cy + sy * (c + L))], fill=corner + (255,), width=lw)
            r = 3.2 * S
            px, py = cx + sx * (c * 0.5 + 1.5 * S), cy + sy * (c * 0.5 + 1.5 * S)
            d.polygon([(px, py - r), (px + r, py), (px, py + r), (px - r, py)], fill=corner + (255,))
    return down(img, w, h)


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    img.save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)


def mix(a, b, t):
    return tuple(int(a[i] * (1 - t) + b[i] * t) for i in range(3))


def build_panels():
    # 卡片：墨绿半透明底 + 暗金细边 + 内描线
    save(frame(96, 96, fill=((26, 40, 37), (14, 24, 22)), fill_alpha=(232, 232), border=GOLD_D, bw=2.5, cut=12, inner=(94, 120, 98), highlight=JADE_L), "panel_card.png")
    # 弹窗：更厚的金框 + 角饰
    save(frame(128, 128, fill=((30, 46, 42), (14, 24, 22)), fill_alpha=(248, 248), border=GOLD, bw=3.5, cut=18, inner=GOLD_D, inner_gap=8, corner=GOLD_L, corner_len=30, highlight=JADE_L), "panel_popup.png")
    # 内嵌区：更暗，细线
    save(frame(64, 64, fill=((8, 14, 14), (10, 17, 16)), fill_alpha=(220, 220), border=(60, 82, 72), bw=2, cut=8, pad=1), "panel_inset.png")
    # 页面顶部标题带
    save(frame(256, 96, fill=((46, 38, 22), (24, 20, 12)), fill_alpha=(240, 240), border=GOLD, bw=3, cut=22, inner=GOLD_D, inner_gap=6, corner=GOLD_L, corner_len=24), "ribbon_title.png")
    # 资源胶囊
    save(frame(128, 64, fill=((20, 30, 28), (10, 17, 16)), fill_alpha=(235, 235), border=GOLD_D, bw=2.5, cut=22, pad=2), "chip.png")
    # Toast / 提示
    save(frame(128, 96, fill=((12, 18, 18), (12, 18, 18)), fill_alpha=(235, 235), border=GOLD_D, bw=2, cut=14), "toast.png")
    # 战报行底
    save(frame(64, 64, fill=((16, 26, 24), (16, 26, 24)), fill_alpha=(120, 120), border=(70, 92, 80), bw=1.5, cut=6, pad=1), "row_bg.png")
    # 选中行
    save(frame(64, 64, fill=((60, 52, 28), (36, 32, 18)), fill_alpha=(220, 220), border=GOLD, bw=2.5, cut=8, pad=1, glow=GOLD, glow_r=3), "row_selected.png")


def build_buttons():
    spec = {
        "primary": dict(fill=(GOLD_L, GOLD_D), border=(255, 240, 190), inner=(255, 244, 205), hl=(255, 255, 255)),
        "secondary": dict(fill=((40, 62, 56), (18, 32, 29)), border=GOLD_D, inner=(120, 150, 120), hl=JADE_L),
        "danger": dict(fill=((205, 82, 66), (120, 34, 28)), border=(250, 190, 170), inner=(255, 210, 190), hl=(255, 255, 255)),
        "jade": dict(fill=((110, 168, 130), (46, 92, 74)), border=JADE_L, inner=(220, 245, 225), hl=(255, 255, 255)),
        "ghost": dict(fill=((20, 30, 28), (12, 19, 18)), border=(70, 92, 82), inner=None, hl=None),
    }
    for name, s in spec.items():
        for state in ("normal", "pressed", "disabled"):
            fill = s["fill"]
            border = s["border"]
            alpha = (255, 255)
            if state == "pressed":
                fill = (mix(fill[1], (0, 0, 0), 0.05), mix(fill[0], (0, 0, 0), 0.35))
                border = mix(border, (0, 0, 0), 0.25)
            if state == "disabled":
                fill = ((52, 58, 56), (36, 42, 40))
                border = (84, 92, 88)
                alpha = (255, 255)
            img = frame(96, 96, fill=fill, fill_alpha=alpha, border=border, bw=3, cut=15,
                        inner=s["inner"] if state == "normal" and s["inner"] else None, inner_gap=6, inner_w=1.2,
                        highlight=s["hl"] if state == "normal" else None)
            save(img, f"btn_{name}_{state}.png")
    # 底部页签：选中底（金色上缘 + 发光）
    save(frame(96, 160, fill=((52, 46, 26), (20, 20, 14)), fill_alpha=(0, 220), border=GOLD, bw=0.1, cut=6, pad=0), "tab_selected_bg.png")


def build_bars():
    # 进度条外框（深色槽 + 金边 + 圆切角）
    save(frame(192, 56, fill=((6, 10, 10), (12, 20, 19)), fill_alpha=(255, 255), border=GOLD_D, bw=3, cut=18, pad=2, inner=(70, 60, 34), inner_gap=2, inner_w=1), "bar_frame.png")
    for name, (a, b) in {"jade": (JADE_L, JADE_D), "gold": (GOLD_L, GOLD_D), "cin": (CIN_L, CIN), "blue": ((150, 200, 240), (60, 110, 170))}.items():
        img = canvas(128, 56)
        W, H = 128 * S, 56 * S
        pad = 8 * S
        pts = poly_chamfer(pad, pad, W - pad, H - pad, 12 * S)
        mask = Image.new("L", (W, H), 0)
        ImageDraw.Draw(mask).polygon(pts, fill=255)
        g = gradient(W, H, a, b)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        layer.paste(g, (0, 0), mask)
        # 顶部高光条
        d = ImageDraw.Draw(layer)
        d.line([(pad + 14 * S, pad + 4 * S), (W - pad - 14 * S, pad + 4 * S)], fill=(255, 255, 255, 110), width=3 * S)
        save(down(layer, 128, 56), f"bar_fill_{name}.png")


def build_slots():
    for i, c in enumerate(RARITY):
        tint = mix(SURF_D, c, 0.16)
        save(frame(96, 96, fill=(mix(SURF, c, 0.22), tint), fill_alpha=(245, 245), border=c, bw=3 + (1 if i >= 4 else 0), cut=10, pad=2,
                   inner=mix(c, (255, 255, 255), 0.35) if i >= 2 else None, inner_gap=4, inner_w=1.2,
                   corner=mix(c, (255, 255, 255), 0.4) if i >= 3 else None, corner_len=14,
                   glow=c if i >= 3 else None, glow_r=3),
             f"slot_r{i}.png")
    save(frame(96, 96, fill=((12, 20, 19), (8, 14, 13)), fill_alpha=(200, 200), border=(66, 84, 76), bw=2, cut=10, pad=2), "slot_empty.png")
    save(frame(96, 96, fill=((12, 20, 19), (8, 14, 13)), fill_alpha=(170, 170), border=(46, 58, 54), bw=2, cut=10, pad=2), "slot_locked.png")
    save(frame(96, 96, fill=((0, 0, 0), (0, 0, 0)), fill_alpha=(0, 0), border=GOLD_L, bw=4, cut=10, pad=2, glow=GOLD, glow_r=5, corner=GOLD_L, corner_len=16), "slot_selected.png")
    # 圆形物品底板（径向渐变，白色，运行时按稀有度上色）
    n = 256
    yy, xx = np.mgrid[0:n, 0:n]
    r = np.sqrt((xx - n / 2) ** 2 + (yy - n / 2) ** 2) / (n / 2)
    a = np.clip(1 - r, 0, 1) ** 1.6
    arr = np.zeros((n, n, 4), dtype=np.uint8)
    arr[:, :, :3] = 255
    arr[:, :, 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(arr, "RGBA"), "glow_soft.png")
    # 红点
    img = canvas(40, 40)
    d = ImageDraw.Draw(img)
    d.ellipse([3 * S, 3 * S, 37 * S, 37 * S], fill=CIN + (255,), outline=(255, 220, 205, 255), width=3 * S)
    d.ellipse([10 * S, 8 * S, 22 * S, 16 * S], fill=(255, 255, 255, 90))
    save(down(img, 40, 40), "reddot.png")
    # 横向纹饰分隔线
    img = canvas(512, 24)
    d = ImageDraw.Draw(img)
    W, H = 512 * S, 24 * S
    cy = H // 2
    for x0, x1 in [(10 * S, W // 2 - 26 * S), (W // 2 + 26 * S, W - 10 * S)]:
        for k in range(x0, x1, 2):
            t = (k - x0) / max(1, x1 - x0)
            alpha = int(220 * (t if x0 < W // 2 else 1 - t) ** 0.6)
            d.line([(k, cy), (k + 2, cy)], fill=GOLD + (alpha,), width=int(1.5 * S))
    cx = W // 2
    for rr, col in [(9 * S, GOLD_D), (6 * S, GOLD)]:
        d.polygon([(cx, cy - rr), (cx + rr, cy), (cx, cy + rr), (cx - rr, cy)], fill=col + (255,))
    d.polygon([(cx, cy - 3 * S), (cx + 3 * S, cy), (cx, cy + 3 * S), (cx - 3 * S, cy)], fill=INK + (255,))
    for dx in (-18 * S, 18 * S):
        r2 = 2.5 * S
        d.ellipse([cx + dx - r2, cy - r2, cx + dx + r2, cy + r2], fill=GOLD + (255,))
    save(down(img, 512, 24), "divider.png")


def build_dock():
    # 底部导航：深色渐变 + 顶部金线 + 极淡云纹
    w, h = 1080, 200
    img = gradient(w, h, (16, 26, 24), (6, 10, 10), 232, 252)
    d = ImageDraw.Draw(img)
    d.line([(0, 1), (w, 1)], fill=GOLD_D + (255,), width=3)
    d.line([(0, 6), (w, 6)], fill=(70, 60, 34, 160), width=1)
    save(img, "dock_bg.png")
    # 顶栏：自上而下渐隐
    h2 = 200
    top = gradient(w, h2, (4, 7, 8), (4, 7, 8), 235, 0)
    save(top, "topbar_fade.png")
    # 底部渐隐（盖在背景图下方，提升文字对比）
    save(gradient(w, 600, (6, 9, 10), (6, 9, 10), 0, 240), "fade_bottom.png")
    save(gradient(w, 600, (6, 9, 10), (6, 9, 10), 240, 0), "fade_top.png")


def build_formation():
    """修炼法阵：同心圆 + 八卦爻线 + 刻度。透明底，金/玉色。"""
    n = 1024
    img = Image.new("RGBA", (n * 2, n * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = n
    def ring(r, w, col, a=255):
        d.ellipse([c - r, c - r, c + r, c + r], outline=col + (a,), width=w)
    ring(960, 6, GOLD, 230)
    ring(930, 2, GOLD_D, 200)
    ring(720, 4, GOLD_D, 220)
    ring(700, 2, GOLD, 160)
    ring(440, 3, JADE, 150)
    ring(430, 1, JADE_L, 120)
    ring(300, 2, GOLD_D, 140)
    for k in range(120):
        ang = k * 2 * math.pi / 120
        r0, r1 = (900, 930) if k % 5 else (880, 930)
        d.line([(c + r0 * math.cos(ang), c + r0 * math.sin(ang)), (c + r1 * math.cos(ang), c + r1 * math.sin(ang))], fill=GOLD_D + (200,), width=3 if k % 5 else 5)
    # 八卦：三条爻线（阳爻连、阴爻断）
    trig = [(1, 1, 1), (0, 1, 1), (1, 0, 1), (0, 0, 1), (1, 1, 0), (0, 1, 0), (1, 0, 0), (0, 0, 0)]
    for i, t in enumerate(trig):
        ang = i * math.pi / 4 - math.pi / 2
        for j, yang in enumerate(t):
            rr = 770 + j * 44
            half = 22  # 弧度的一半（度）
            a0, a1 = math.degrees(ang) - half, math.degrees(ang) + half
            if yang:
                d.arc([c - rr, c - rr, c + rr, c + rr], a0, a1, fill=GOLD + (255,), width=18)
            else:
                d.arc([c - rr, c - rr, c + rr, c + rr], a0, a0 + half * 0.8, fill=GOLD + (255,), width=18)
                d.arc([c - rr, c - rr, c + rr, c + rr], a1 - half * 0.8, a1, fill=GOLD + (255,), width=18)
    # 内圈八角星
    pts = []
    for k in range(16):
        ang = k * math.pi / 8 - math.pi / 2
        r = 440 if k % 2 == 0 else 230
        pts.append((c + r * math.cos(ang), c + r * math.sin(ang)))
    d.polygon(pts, outline=JADE_L + (170,), width=3)
    glow = img.filter(ImageFilter.GaussianBlur(14))
    img = Image.alpha_composite(glow, img)
    save(img.resize((768, 768), Image.LANCZOS), "formation.png")


def fbm(shape, seed, octaves=5):
    rng = np.random.default_rng(seed)
    h, w = shape
    out = np.zeros(shape)
    amp = 1.0
    tot = 0.0
    for o in range(octaves):
        f = 2 ** (o + 1)
        base = rng.random((f, f))
        # 周期插值：先在 tile 上做双三次，保证左右、上下无缝
        big = Image.fromarray((base * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        # 无缝处理：把图像镜像拼接后再取原尺寸（简单起见使用 wrap 采样）
        arr = np.asarray(big).astype(float) / 255
        out += arr * amp
        tot += amp
        amp *= 0.55
    return out / tot


def build_mist():
    h, w = 256, 1024
    # 用周期噪声：在傅里叶域生成 1/f 噪声，天然无缝
    rng = np.random.default_rng(7)
    fx = np.fft.fftfreq(w)[None, :]
    fy = np.fft.fftfreq(h)[:, None]
    f = np.sqrt(fx ** 2 + fy ** 2)
    f[0, 0] = 1
    spec = (rng.normal(size=(h, w)) + 1j * rng.normal(size=(h, w))) / (f ** 1.9)
    spec[0, 0] = 0
    field = np.real(np.fft.ifft2(spec))
    field = (field - field.min()) / (field.max() - field.min())
    field = np.clip((field - 0.42) * 2.4, 0, 1) ** 1.3
    # 上下边缘淡出
    ramp = np.sin(np.linspace(0, math.pi, h))[:, None] ** 1.2
    a = field * ramp
    arr = np.zeros((h, w, 4), dtype=np.uint8)
    arr[:, :, 0] = 214
    arr[:, :, 1] = 232
    arr[:, :, 2] = 226
    arr[:, :, 3] = (a * 255).astype(np.uint8)
    save(Image.fromarray(arr, "RGBA"), "mist.png")


def build_logo():
    if not FONT or not os.path.exists(FONT):
        print("skip logo (TITLE_FONT 未设置)")
        return
    W, H = 900, 420
    img = Image.new("RGBA", (W * 2, H * 2), (0, 0, 0, 0))
    f_big = ImageFont.truetype(FONT, 300)
    f_small = ImageFont.truetype(FONT, 64)
    d = ImageDraw.Draw(img)
    text = "修仙"
    bbox = d.textbbox((0, 0), text, font=f_big)
    tw = bbox[2] - bbox[0]
    x = (W * 2 - tw) // 2 - bbox[0]
    y = 60
    # 阴影/外发光
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).text((x, y + 10), text, font=f_big, fill=(0, 0, 0, 220))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(14)))
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((x, y), text, font=f_big, fill=GOLD + (200,), stroke_width=10, stroke_fill=GOLD + (200,))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(22)))
    # 金色渐变字
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).text((x, y), text, font=f_big, fill=255, stroke_width=2, stroke_fill=255)
    g = gradient(img.size[0], img.size[1], (255, 244, 205), (176, 134, 56))
    fill = Image.new("RGBA", img.size, (0, 0, 0, 0))
    fill.paste(g, (0, 0), mask)
    outline = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(outline).text((x, y), text, font=f_big, fill=(60, 40, 12, 255), stroke_width=8, stroke_fill=(60, 40, 12, 255))
    img = Image.alpha_composite(img, outline)
    img = Image.alpha_composite(img, fill)
    d = ImageDraw.Draw(img)
    sub = "问 道 长 生"
    sb = d.textbbox((0, 0), sub, font=f_small)
    sx = (W * 2 - (sb[2] - sb[0])) // 2 - sb[0]
    d.text((sx, 400), sub, font=f_small, fill=JADE_L + (255,))
    # 两侧细线
    ly = 400 + (sb[3] - sb[1]) // 2 + 12
    for x0, x1 in [(120, sx - 40), (sx + (sb[2] - sb[0]) + 40, W * 2 - 120)]:
        d.line([(x0, ly), (x1, ly)], fill=GOLD_D + (230,), width=3)
    save(img.resize((W, H), Image.LANCZOS), "logo_title.png")


if __name__ == "__main__":
    build_panels()
    build_buttons()
    build_bars()
    build_slots()
    build_dock()
    build_formation()
    build_mist()
    build_logo()
