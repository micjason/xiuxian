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
        # 美术没出头像图（只有 ui/avatar_frame + avatar_mask），用角色分层里的整张脸
        'avatar': 'anim_layers/char/face_full_closed.png',
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
        'hero_meditate': 'sprites/char_meditate.png',
        'mon_wolf': 'sprites/mon_wolf.png', 'mon_fox': 'sprites/mon_fox.png',
        'mon_snake': 'sprites/mon_snake.png', 'mon_bear': 'sprites/mon_bear.png',
        'bd_field': 'sprites/bd_field.png', 'bd_alchemy': 'sprites/bd_alchemy.png',
        'bd_array': 'sprites/bd_array.png', 'bd_hut': 'sprites/bd_hut.png',
        'chest_closed': 'sprites/chest_closed.png', 'lotus_platform': 'sprites/lotus_platform.png',
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


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--from', dest='art', default='/workspace/art_out_q')
    art = ap.parse_args().art
    placeholders, problems = [], []
    # 旧的占位目录整个重建，避免留下美术已改名的旧文件
    for folder in ('icons', 'items', 'sprites', 'bg', 'ui'):
        path = os.path.join(OUT, folder)
        if os.path.isdir(path):
            shutil.rmtree(path)
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
    # ui/：原名全拷（含 .fnt）
    ui_src = os.path.join(art, 'ui')
    for name in sorted(os.listdir(ui_src)):
        if name.endswith(('.png', '.fnt')):
            copy(os.path.join(ui_src, name), os.path.join(OUT, 'ui', name))
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
    with open(LICENSE_OUT + '.import', 'w') as fh:  # 别让 Godot 当翻译表导入
        fh.write('[remap]\n\nimporter="keep"\n')
    with open(os.path.join(OUT, 'PLACEHOLDERS.txt'), 'w') as fh:
        fh.write('# 美术没有交付、暂用设计稿临时切图的文件（重跑 tools/art/install_q_art.py 会刷新）\n')
        fh.write('\n'.join(placeholders) + ('\n' if placeholders else ''))
    with open(os.path.join(OUT, 'CHECK.txt'), 'w') as fh:
        fh.write('# 入库检查（缺文件 / 尺寸不符 / 九宫格边距过大）\n')
        fh.write('\n'.join(problems) + ('\n' if problems else '无问题\n'))
    print(f'installed into {OUT}; nine-slice {len(nine)}; placeholders {len(placeholders)}; problems {len(problems)}')
    for p in problems:
        print('  !', p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
