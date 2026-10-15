#!/usr/bin/env python3
"""把下载的第三方素材加工成游戏用图。

输入（不进仓库，见 game/assets/ASSETS_LICENSES.md 里的下载地址）：
  $ASSET_SRC/gameicons/   —— github.com/game-icons/icons 的克隆（CC BY 3.0）
  $ASSET_SRC/paintings/   —— 维基共享资源上的四幅古画原图（公有领域）
输出：game/assets/art/icons/*.png（白色剪影，运行时上色）、game/assets/art/bg/*.webp
用法：ASSET_SRC=/path python3 tools/assets/build_icons_and_backgrounds.py <game/assets/art 目录>
"""
import os
import re
import sys

import cairosvg
import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

SRC = os.environ["ASSET_SRC"]
OUT = sys.argv[1]
Image.MAX_IMAGE_PIXELS = None

# 图标名 → game-icons 的 作者/文件名。作者与许可见 ASSETS_LICENSES.md。
ICONS = {
    # 装备部位
    "slot_weapon": "lorc/broadsword",
    "slot_helmet": "delapouite/jewel-crown",
    "slot_clothes": "lorc/robe",
    "slot_gloves": "delapouite/bracer",
    "slot_shoes": "darkzaitzev/tabi-boot",
    "slot_accessory": "lorc/gem-pendant",
    "slot_artifact": "delapouite/dragon-orb",
    "slot_pet": "lorc/fox-head",
    # 物品类别
    "cat_equipment": "lorc/broadsword",
    "cat_material": "lorc/crystal-cluster",
    "cat_pill": "lorc/pill",
    "cat_book": "delapouite/spell-book",
    "cat_scroll": "lorc/scroll-unfurled",
    "cat_herb": "delapouite/mushrooms",
    "cat_other": "lorc/gems",
    # 底部页签
    "tab_cultivate": "lorc/lotus",
    "tab_adventure": "lorc/crossed-swords",
    "tab_character": "lorc/beams-aura",
    "tab_bag": "lorc/knapsack",
    "tab_skill": "delapouite/secret-book",
    # 资源 / 状态
    "res_cultivation": "lorc/magic-swirl",
    "res_power": "lorc/muscle-up",
    "res_enhance": "lorc/anvil",
    "res_bag": "lorc/knapsack",
    "res_stone": "lorc/crystal-shine",
    "ui_enhance": "delapouite/upgrade",
    "ui_decompose": "lorc/cauldron",
    "ui_lock": "lorc/padlock",
    "ui_settings": "lorc/cog",
    "ui_report": "lorc/tied-scroll",
    "ui_credits": "lorc/ringing-bell",
    "ui_sparkle": "delapouite/sparkles",
    "ui_yinyang": "delapouite/yin-yang",
    "ui_sun": "lorc/sun",
    "ui_moon": "lorc/moon",
    "ui_mountain": "lorc/mountains",
    "ui_pagoda": "delapouite/pagoda",
    "ui_gate": "delapouite/heaven-gate",
    "ui_chest": "delapouite/chest",
    "ui_crane": "delapouite/crane",
    # 主角与首领头像
    "avatar_meditate": "lorc/meditation",
    "boss_dragon": "lorc/dragon-head",
    "boss_tiger": "delapouite/tiger-head",
    "boss_fox": "lorc/fox-head",
    "boss_wolf": "lorc/wolf-head",
    "boss_snake": "lorc/snake",
    "boss_scorpion": "lorc/scorpion",
    "boss_reptile": "delapouite/horned-reptile",
    "boss_werewolf": "lorc/werewolf",
    "boss_ghost": "lorc/ghost",
    "boss_skull": "lorc/skull-crack",
    "boss_lizard": "lorc/lizardman",
    "boss_turtle": "lorc/turtle-shell",
    "boss_unicorn": "delapouite/unicorn",
    "boss_twin_dragon": "lorc/double-dragon",
}


def build_icons():
    d = os.path.join(OUT, "icons")
    os.makedirs(d, exist_ok=True)
    for name, ref in ICONS.items():
        path = os.path.join(SRC, "gameicons", ref + ".svg")
        svg = open(path).read()
        svg = re.sub(r'<path d="M0 0h512v512H0z"/>', "", svg)  # 去掉黑底，只留白色剪影
        png = cairosvg.svg2png(bytestring=svg.encode(), output_width=160, output_height=160)
        with open(os.path.join(d, name + ".png"), "wb") as f:
            f.write(png)
    print("icons", len(ICONS))


# ---- 背景：古画裁切 + 国风调色（压暗、偏青、暗角），统一为竖屏 9:16 ----
W, H = 810, 1440


def grade(im, dark=0.55, tint=(0.80, 0.98, 0.95), sat=0.78, contrast=1.05, top_fade=0.0, bottom_fade=0.55):
    im = im.convert("RGB")
    im = ImageEnhance.Color(im).enhance(sat)
    im = ImageEnhance.Contrast(im).enhance(contrast)
    a = np.asarray(im).astype(np.float32) / 255.0
    a = a * np.array(tint, dtype=np.float32)[None, None, :]
    a = np.clip(a * dark, 0, 1) ** 1.25
    h, w, _ = a.shape
    yy = np.linspace(0, 1, h)[:, None, None]
    xx = np.linspace(-1, 1, w)[None, :, None]
    vign = 1 - 0.38 * (xx ** 2) * 0.9
    a = a * vign
    ink = np.array([0.03, 0.045, 0.05], dtype=np.float32)[None, None, :]
    if bottom_fade > 0:
        k = np.clip((yy - 0.55) / 0.45, 0, 1) ** 1.4 * bottom_fade
        a = a * (1 - k) + ink * k
    if top_fade > 0:
        k = np.clip((0.18 - yy) / 0.18, 0, 1) * top_fade
        a = a * (1 - k) + ink * k
    return Image.fromarray(np.clip(a * 255, 0, 255).astype(np.uint8))


def crop_portrait(im, cx, cy, width, scale=None):
    """以 (cx, cy) 为中心裁出 9:16 的竖图，width 为裁剪宽度（原图像素）。"""
    h = int(width * 16 / 9)
    x0 = int(cx - width / 2)
    y0 = int(cy - h / 2)
    x0 = max(0, min(im.width - width, x0))
    y0 = max(0, min(im.height - h, y0))
    return im.crop((x0, y0, x0 + width, y0 + h)).resize((W, H), Image.LANCZOS)


def save_bg(img, name, quality=74):
    d = os.path.join(OUT, "bg")
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, name + ".webp")
    img.save(p, "WEBP", quality=quality, method=6)
    print("bg", name, os.path.getsize(p) // 1024, "KB")


def build_backgrounds():
    p = os.path.join(SRC, "paintings")
    wx = Image.open(os.path.join(p, "wang_ximeng.jpg"))
    fk = Image.open(os.path.join(p, "fan_kuan.jpg"))
    gx = Image.open(os.path.join(p, "guo_xi.jpg"))
    qy = Image.open(os.path.join(p, "qiu_ying.jpg"))
    sx = (wx.width - 900) / 39

    def wx_crop(i, cy=800, width=900):
        return crop_portrait(wx, i * sx + 450, cy, width)

    # 登录：范宽《溪山行旅图》上段巨岳（水墨，偏冷）
    save_bg(grade(crop_portrait(fk, 1400, 1900, 2400), dark=1.25, tint=(0.80, 0.97, 1.0), sat=0.35, contrast=1.15, bottom_fade=0.75), "login")
    # 修炼主页：王希孟《千里江山图》高耸主峰（青绿）
    save_bg(grade(wx_crop(15), dark=1.0, tint=(0.64, 0.94, 1.06), sat=1.0, contrast=1.1, bottom_fade=0.55), "home")
    # 历练章节：六段不同山水
    for n, idx in enumerate([9, 19, 24, 26, 31, 35], start=1):
        save_bg(grade(wx_crop(idx), dark=0.95, tint=(0.64, 0.93, 1.06), sat=1.0, contrast=1.1, bottom_fade=0.6), f"stage_{n}")
    # 角色：郭熙《早春图》水墨，墨色最重
    save_bg(grade(crop_portrait(gx, 980, 1100, 1500), dark=0.8, tint=(0.78, 0.97, 1.0), sat=0.35, contrast=1.2, bottom_fade=0.8), "character")
    # 行囊：郭熙下段
    save_bg(grade(crop_portrait(gx, 980, 1850, 1500), dark=0.72, tint=(0.78, 0.97, 1.0), sat=0.35, contrast=1.2, bottom_fade=0.8), "bag")
    # 功法：仇英《桃源仙境图》（青绿楼阁）压暗
    save_bg(grade(crop_portrait(qy, 400, 640, 760), dark=0.85, tint=(0.72, 0.98, 1.04), sat=0.95, contrast=1.1, bottom_fade=0.8), "skill")


if __name__ == "__main__":
    build_icons()
    build_backgrounds()
