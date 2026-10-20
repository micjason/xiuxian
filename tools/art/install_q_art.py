#!/usr/bin/env python3
"""Q 版美术入库（2026-10-20 美术交付 /workspace/art_out_q/）。

用法：python3 tools/art/install_q_art.py [--from /workspace/art_out_q]

做的事：
1. ui/ 下的切图（九宫格、按钮、控件、数字字体 .fnt+.png）原名拷到 game/assets/art/q/ui/；
   九宫格边距从 checklist_q.csv 生成 game/scripts/ui/art/q_nine.gd（ArtLib.Q_NINE 读它），并校验
   宽 > 左+右、高 > 上+下（不满足的列进 q/CHECK.txt 并退出码 1）。
2. 图标 / 物品 / 精灵 / 背景按 ArtLib 的 id 改名拷入 q/{icons,items,sprites,bg}（对应表 MAP）。
   背景只用 webp（PNG 版太大），dot_tile / scene_fade 是小 png。
3. 美术的逐文件授权表 license_q.csv 拷到 game/assets/art_q_license_list.csv（ASSETS_LICENSES.md 第 8 节引用）。
4. 美术没交的 id 用设计稿临时切图（/workspace/q_src/cut、/workspace/q_design/src）顶上，记在 q/PLACEHOLDERS.txt。
5. 主角静态图 sprites/hero_meditate 由角色拆层拼合图（anim_layers/char/_assembled_closed.png，双手搭膝）
   裁出设计稿角色框（画布 0,0–1288,1259 = 设计稿 706×690）生成（GENERATED）。
6. 动画特效（2026-10-20 动画交付 /workspace/anim_out_q/，--anim 指定）：5 个文件夹原样拷到 game/anim_q/
   （场景里的 res://anim_q/... 路径不变）；不拷 .import（Godot 重新导入）。每个文件夹自带的 TTF 字体不拷
   （3 份 8 MB 的庆科黄油体 + 3 份 1.5 MB 的快乐体），场景里的字体改指向 assets/fonts/ 的子集字体：
   快乐体用已有的 ZCOOLKuaiLe-Regular.subset.woff2，庆科黄油体按快乐体子集的字表 + ASCII 子集化成
   ZCOOLQingKeHuangYou-Regular.subset.woff2。
"""
import argparse, csv, os, shutil, sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, 'game/assets/art/q')
NINE_GD = os.path.join(REPO, 'game/scripts/ui/art/q_nine.gd')
LICENSE_OUT = os.path.join(REPO, 'game/assets/art_q_license_list.csv')
CUT = '/workspace/q_src/cut'

# id -> 美术交付里的相对路径（无则用 FALLBACK）
MAP = {
    'icons': {
        'tab_cultivate': 'icons/icon_lotus.png', 'tab_adventure': 'icons/icon_sword.png',
        'tab_skill': 'icons/icon_scroll.png', 'tab_bag': 'icons/icon_pouch.png',
        'side_cave': 'icons/icon_dongfu.png', 'side_alchemy': 'icons/icon_gourd.png',
        'chest': 'icons/icon_chest.png', 'res_stone': 'icons/icon_stone.png',
        'res_gourd': 'icons/icon_gourd.png', 'res_lotus': 'icons/icon_lotus.png',
        # 主角头像（美术 2026-10-20 补交，已裁圆、带浅青底；战斗页等用图标 avatar 的地方都用它）
        'avatar': 'ui/avatar_player_round@2x.png',
    },
    'items': {
        'gear_weapon': 'icons/eq_sword.png', 'gear_helmet': 'icons/eq_crown.png',
        'gear_clothes': 'icons/eq_robe.png', 'gear_gloves': 'icons/eq_bracers.png',
        'gear_shoes': 'icons/eq_boots.png', 'gear_accessory': 'icons/eq_pendant.png',
        'mat_stone': 'icons/it_ore.png', 'mat_herb': 'icons/it_herb.png', 'mat_bone': 'icons/it_bone.png',
        'mat_other': 'icons/it_ore.png', 'book_atk': 'icons/it_book_atk.png', 'book_def': 'icons/it_book_def.png',
        'book_hp': 'icons/it_book_hp.png', 'book_other': 'icons/icon_scroll.png',
        'pill_qi': 'icons/it_elixir.png', 'pill_body': 'icons/it_pill.png', 'pill_other': 'icons/it_pill.png',
    },
    'sprites': {
        'mon_wolf': 'sprites/mon_wolf.png', 'mon_fox': 'sprites/mon_fox.png',
        'mon_snake': 'sprites/mon_snake.png', 'mon_bear': 'sprites/mon_bear.png',
        # 幽冥古道 / 赤炎火山（SPEC_Q 12.4，2026-10-20 补交）
        'mon_ghost': 'sprites/mon_ghost.png', 'mon_bone_golem': 'sprites/mon_bone_golem.png',
        'mon_bat': 'sprites/mon_bat.png', 'mon_ghost_elder': 'sprites/mon_ghost_elder.png',
        'mon_lava_lizard': 'sprites/mon_lava_lizard.png', 'mon_fire_crow': 'sprites/mon_fire_crow.png',
        'mon_lava_golem': 'sprites/mon_lava_golem.png', 'mon_fire_jiao': 'sprites/mon_fire_jiao.png',
        'bd_field': 'sprites/bd_field.png', 'bd_alchemy': 'sprites/bd_alchemy.png',
        'bd_array': 'sprites/bd_array.png', 'bd_hut': 'sprites/bd_hut.png',
        'chest_closed': 'sprites/chest_closed.png',
        # 开箱宝箱（SPEC_Q 12.2，2x 图按 0.5 显示）：离线弹窗动画缺失时的静态图
        'chest_open': 'sprites/chest_open.png', 'chest_closed_hd': 'sprites/chest_closed_hd.png',
        'lotus_platform': 'sprites/lotus_platform.png',
        'fx_aura_radial': 'sprites/fx_aura_radial.png', 'fx_ring_solid': 'sprites/fx_ring_solid.png',
        'fx_ring_dashed': 'sprites/fx_ring_dashed.png', 'fx_light_beam': 'sprites/fx_light_beam.png',
        'fx_ground_shadow': 'sprites/fx_ground_shadow.png', 'fx_sunburst': 'sprites/fx_sunburst.png',
        'fx_star': 'sprites/fx_star.png', 'fx_chest_glow': 'sprites/fx_chest_glow.png',
        'fx_card_glow': 'sprites/fx_card_glow.png', 'fx_break_glow': 'sprites/fx_break_glow.png',
        'fx_hit_burst': 'sprites/fx_hit_burst.png', 'fx_teal_vignette': 'sprites/fx_teal_vignette.png',
    },
    'bg': {
        'cultivate.webp': 'bg/bg_cultivate_1080x1368.webp', 'adventure.webp': 'bg/bg_heifeng_1080x960.webp',
        'cave.webp': 'bg/bg_cave_1080x2340.webp', 'dots_tile.png': 'bg/dot_tile_56.png',
        'scene_fade_top.png': 'bg/scene_fade_top.png', 'scene_fade_bottom.png': 'bg/scene_fade_bottom.png',
    },
}
FALLBACK = {'icons/avatar.png': '/workspace/q_design/src/avatar.png'}
# 由美术图加工生成的文件：目标 -> (美术相对路径, 裁切框, 输出尺寸)
GENERATED = {
    'sprites/hero_meditate.png': ('anim_layers/char/_assembled_closed.png', (0, 0, 1288, 1259), (706, 690)),
}

ANIM_OUT = os.path.join(REPO, 'game/anim_q')
ANIM_DIRS = ('hero_meditate', 'ui_fx', 'float_drop', 'breakthrough', 'chest_open')
FONT_DIR = os.path.join(REPO, 'game/assets/fonts')
FONT_MAP = {
    'ZCOOLKuaiLe-Regular.ttf': 'res://assets/fonts/ZCOOLKuaiLe-Regular.subset.woff2',
    'ZCOOLQingKeHuangYou-Regular.ttf': 'res://assets/fonts/ZCOOLQingKeHuangYou-Regular.subset.woff2',
}


def install_anim(anim: str, problems: list) -> int:
    """动画交付 → game/anim_q/。返回拷贝的文件数。"""
    import re
    _clear_keep_imports(ANIM_OUT)
    count = 0
    qingke = None
    for folder in ANIM_DIRS:
        src_root = os.path.join(anim, folder)
        if not os.path.isdir(src_root):
            problems.append(f'动画交付缺少文件夹 {folder}')
            continue
        for dirpath, _dirs, files in os.walk(src_root):
            rel_dir = os.path.relpath(dirpath, anim)
            for name in sorted(files):
                src = os.path.join(dirpath, name)
                if name.endswith('.import'):
                    continue
                if os.path.basename(dirpath) == 'font':
                    if name.startswith('ZCOOLQingKeHuangYou'):
                        qingke = src
                    continue
                dst = os.path.join(ANIM_OUT, os.path.relpath(src, anim))
                copy(src, dst)
                count += 1
                if name.endswith('.tscn'):
                    text = open(dst, encoding='utf-8').read()
                    def repl(m):
                        font = os.path.basename(m.group(1))
                        if font not in FONT_MAP:
                            problems.append(f'{rel_dir}/{name} 用了没登记的字体 {font}')
                            return m.group(0)
                        return f'path="{FONT_MAP[font]}"'
                    text = re.sub(r'path="(res://anim_q/[^"]+/font/[^"]+)"', repl, text)
                    open(dst, 'w', encoding='utf-8').write(text)
    if qingke:
        _subset_qingke(qingke)
    else:
        problems.append('动画交付里没有 ZCOOLQingKeHuangYou 字体，没法生成子集')
    return count


def _subset_qingke(src: str) -> None:
    from fontTools import subset
    from fontTools.ttLib import TTFont
    kuaile = TTFont(os.path.join(FONT_DIR, 'ZCOOLKuaiLe-Regular.subset.woff2'))
    chars = set(kuaile.getBestCmap().keys()) | set(range(0x20, 0x7F)) | {ord(c) for c in '，、·×÷％＋－万亿修为突破成功'}
    opts = subset.Options()
    opts.flavor = 'woff2'
    opts.layout_features = ['*']
    opts.name_IDs = ['*']  # 保留版权 / OFL 声明
    font = TTFont(src)
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=sorted(chars))
    sub.subset(font)
    subset.save_font(font, os.path.join(FONT_DIR, 'ZCOOLQingKeHuangYou-Regular.subset.woff2'), opts)


def _clear_keep_imports(path):
    for dirpath, _dirs, files in os.walk(path):
        for name in files:
            if not name.endswith('.import'):
                os.remove(os.path.join(dirpath, name))


def _drop_orphan_imports(path):
    for dirpath, _dirs, files in os.walk(path):
        for name in files:
            if name.endswith('.import') and not os.path.exists(os.path.join(dirpath, name[:-7])):
                os.remove(os.path.join(dirpath, name))


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


# 物品详情弹窗（SPEC_Q 第 13 节，2026-10-20）用到的切图：新交 5 张 + 复用的。缺了记进 CHECK.txt。
POPUP_ITEM_CUTS = [
    'arrow_down_red', 'chip_purple', 'row_gold_74', 'icon_enhance_exp', 'icon_enhance_exp@2x',
    'popup_frame', 'ribbon_title_104', 'btn_close', 'well_apricot', 'row_cream_74', 'plate_gold_r30',
    'chip_grey', 'chip_green', 'chip_blue', 'chip_orange', 'chip_redflat', 'chip_cream', 'chip_mint', 'chip_dark',
    'arrow_up_green', 'bar_bg_40', 'bar_fill_gold_32', 'bar_fill_mint_32', 'check_ok', 'check_no',
    'btn_orange_100_normal', 'btn_orange_100_pressed', 'btn_orange_124_normal', 'btn_orange_124_pressed',
    'btn_mint_100_normal', 'btn_mint_100_pressed', 'btn_mint_124_normal', 'btn_mint_124_pressed',
    'btn_grey_disabled_100', 'btn_grey_disabled_124',
] + [f'slot_{q}' for q in ('white', 'green', 'blue', 'purple', 'orange', 'red')]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--from', dest='art', default='/workspace/art_out_q')
    ap.add_argument('--anim', dest='anim', default='/workspace/anim_out_q')
    args = ap.parse_args()
    art = args.art
    placeholders, problems = [], []
    # 旧的占位目录重建，避免留下美术已改名的旧文件；Godot 的 .import 留着（uid 不变），源文件没了的最后再删
    for folder in ('icons', 'items', 'sprites', 'bg', 'ui'):
        _clear_keep_imports(os.path.join(OUT, folder))
    for folder, table in MAP.items():
        for ident, rel in table.items():
            name = ident if folder == 'bg' else ident + '.png'
            dst = os.path.join(OUT, folder, name)
            src = os.path.join(art, rel)
            if not os.path.isfile(src):
                fb = FALLBACK.get(f'{folder}/{name}')
                if fb and os.path.isfile(fb):
                    placeholders.append(f'{folder}/{name}  <- {fb}（美术未交付 {rel}）')
                    src = fb
                else:
                    problems.append(f'缺少 {rel}（{folder}/{name}）')
                    continue
            copy(src, dst)
    from PIL import Image
    for target, (rel, box, size) in GENERATED.items():
        src = os.path.join(art, rel)
        if not os.path.isfile(src):
            problems.append(f'缺少 {rel}（{target}）')
            continue
        dst = os.path.join(OUT, target)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        Image.open(src).convert('RGBA').crop(box).resize(size, Image.LANCZOS).save(dst, optimize=True)
    # ui/：原名全拷（含 .fnt）
    ui_src = os.path.join(art, 'ui')
    for name in sorted(os.listdir(ui_src)):
        if name.endswith(('.png', '.fnt')):
            copy(os.path.join(ui_src, name), os.path.join(OUT, 'ui', name))
    for cut in POPUP_ITEM_CUTS:
        if not os.path.isfile(os.path.join(OUT, 'ui', cut + '.png')):
            problems.append(f'物品详情弹窗缺切图 ui/{cut}.png（SPEC_Q 13.11）')
    # 九宫格表
    from PIL import Image
    rows = list(csv.DictReader(open(os.path.join(art, 'checklist_q.csv'), encoding='utf-8-sig')))
    nine = {}
    for row in rows:
        rel = row['文件(相对 art_out_q)']
        margins = row['九宫格 patch_margin L/T/R/B'].strip()
        if not margins or not rel.startswith('ui/'):
            continue
        left, top, right, bottom = [int(x) for x in margins.split('/')]
        path = os.path.join(art, rel)
        w, h = Image.open(path).size
        if row['尺寸px'] and row['尺寸px'] != f'{w}x{h}':
            problems.append(f'{rel} 清单写 {row["尺寸px"]}，实际 {w}x{h}')
        if not (w > left + right and h > top + bottom):
            problems.append(f'{rel} {w}x{h} 九宫格边距 {margins} 不满足 宽>左+右、高>上+下')
        nine[os.path.splitext(os.path.basename(rel))[0]] = (left, top, right, bottom, '仅横向' in row['拉伸方向'])
    with open(NINE_GD, 'w') as fh:
        fh.write('class_name QNine\nextends RefCounted\n')
        fh.write('## 由 tools/art/install_q_art.py 从 /workspace/art_out_q/checklist_q.csv 生成，不要手改。\n')
        fh.write('## 切图名 → [左, 上, 右, 下, 仅横向拉伸]（仅横向 = 贴图高度固定，控件高度应等于贴图高度）。\n\n')
        fh.write('const TABLE := {\n')
        for key in sorted(nine):
            l, t, r, b, h_only = nine[key]
            fh.write(f'\t"{key}": [{l}, {t}, {r}, {b}, {"true" if h_only else "false"}],\n')
        fh.write('}\n')
    shutil.copyfile(os.path.join(art, 'license_q.csv'), LICENSE_OUT)
    # 美术清单之外补交、同样入库的文件（清单里没有单列），补一行授权登记
    extra = open(os.path.join(REPO, 'tools/art/q_license_extra.csv'), encoding='utf-8').read()
    with open(LICENSE_OUT, 'a', encoding='utf-8') as fh:
        fh.write(extra if extra.endswith('\n') else extra + '\n')
    with open(LICENSE_OUT + '.import', 'w') as fh:  # 别让 Godot 当翻译表导入
        fh.write('[remap]\n\nimporter="keep"\n')
    with open(os.path.join(OUT, 'PLACEHOLDERS.txt'), 'w') as fh:
        fh.write('# 美术没有交付、暂用设计稿临时切图的文件（重跑 tools/art/install_q_art.py 会刷新）\n')
        fh.write('\n'.join(placeholders) + ('\n' if placeholders else ''))
    anim_count = install_anim(args.anim, problems) if args.anim else 0
    _drop_orphan_imports(OUT)
    _drop_orphan_imports(ANIM_OUT)
    with open(os.path.join(OUT, 'CHECK.txt'), 'w') as fh:
        fh.write('# 入库检查（缺文件 / 尺寸不符 / 九宫格边距过大 / 动画交付）\n')
        fh.write('\n'.join(problems) + ('\n' if problems else '无问题\n'))
    print(f'installed into {OUT}; nine-slice {len(nine)}; placeholders {len(placeholders)}; anim files {anim_count}; problems {len(problems)}')
    for p in problems:
        print('  !', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
