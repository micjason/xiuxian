/**
 * 美术编号清单（第三批：怪物 / 首领立绘、章节背景、章节首领特效改成后台字段，不再按名字猜图）。
 * 和客户端资源一一对应，art-keys.test.ts 会对照 game/assets/art/q/sprites/ 里的文件，客户端加图忘了加这里会报错。
 * - 立绘：artKey = wolf → 客户端 res://assets/art/q/sprites/mon_wolf.png；精英 / 章末首领的描边、光圈由客户端按 tier 处理。
 * - 章节背景：bgKey = heifeng → 客户端 bg/bg_heifeng_1080x960.webp（SPEC_Q §16，图还没进仓库，客户端那批一起拷）。
 * - 章节首领特效：bossFx = default | chiyan（SPEC_Q §14.7，客户端以后做）。
 */
export const MONSTER_ART_KEYS = [
  { key: "wolf", name: "青鬃狼" },
  { key: "fox", name: "赤眼狐妖" },
  { key: "snake", name: "毒牙蟒" },
  { key: "bear", name: "黑风熊王" },
  { key: "ghost", name: "游魂" },
  { key: "bone_golem", name: "骨傀" },
  { key: "bat", name: "血蝠" },
  { key: "ghost_elder", name: "噬魂老鬼" },
  { key: "lava_lizard", name: "炎鳞蜥" },
  { key: "fire_crow", name: "火鸦" },
  { key: "lava_golem", name: "熔岩傀" },
  { key: "fire_jiao", name: "赤焰蛟" },
] as const;

export const CHAPTER_BG_KEYS = [
  { key: "heifeng", name: "黑风岭" },
  { key: "youming", name: "幽冥古道" },
  { key: "chiyan", name: "赤炎火山" },
] as const;

export const CHAPTER_BOSS_FX = [
  { key: "default", name: "默认" },
  { key: "chiyan", name: "赤炎（火焰）" },
] as const;

export const MONSTER_ART_KEY_SET: ReadonlySet<string> = new Set(MONSTER_ART_KEYS.map((row) => row.key));
export const CHAPTER_BG_KEY_SET: ReadonlySet<string> = new Set(CHAPTER_BG_KEYS.map((row) => row.key));
export const CHAPTER_BOSS_FX_SET: ReadonlySet<string> = new Set(CHAPTER_BOSS_FX.map((row) => row.key));

/** 后台下拉用：立绘、背景、首领特效的可选项（缩略图路径是客户端资源路径，后台自己决定怎么显示）。 */
export function artKeyCatalog() {
  return {
    monsters: MONSTER_ART_KEYS.map((row) => ({ key: row.key, name: row.name, sprite: `sprites/mon_${row.key}.png` })),
    chapterBackgrounds: CHAPTER_BG_KEYS.map((row) => ({ key: row.key, name: row.name, image: `bg/bg_${row.key}_1080x960.webp` })),
    bossFx: CHAPTER_BOSS_FX.map((row) => ({ key: row.key, name: row.name })),
  };
}
