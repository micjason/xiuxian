# 洞府 8h 最小美术包 · MANIFEST

> **8h 最小包 · 可糙 · 后续可精修替换同名文件**  
> 日期：2026-10-31（Asia/Shanghai）  
> 范围：负责人 P0 收窄版 —— 仅 **7 张**（傀儡 1 + 三设施×2 档景差）  
> 根目录：`/workspace/q_design/dongfu_8h_min/`

色板：`#CDEFEA` `#FFF8EC` `#6B4A3A` `#FF9F43` · Q 风简笔 · 全 RGBA 透明底 PNG

---

## 文件清单（必接 7）

| # | 文件名 | 绝对路径 | 尺寸 | 用途 | 客户端建议挂点 |
|---|--------|----------|------|------|----------------|
| 1 | `icon_kuilei_256.png` | `/workspace/q_design/dongfu_8h_min/icon_kuilei_256.png` | 256×256 | **傀儡**统一图标（闲/忙同图；替换灵仆叙事） | 顶栏「傀儡」胶囊；分配条头像；雇佣入口默认图 |
| 2 | `spot_garden_lv1.png` | `/workspace/q_design/dongfu_8h_min/spot_garden_lv1.png` | 192×192 | 药园 **Lv1** 景差（疏畦少苗） | L0 药园热点中心贴图 / 设施卡缩略 |
| 3 | `spot_garden_lv2.png` | `/workspace/q_design/dongfu_8h_min/spot_garden_lv2.png` | 192×192 | 药园 **Lv2** 景差（密畦+花果） | 同上；设施等级 ≥2 时替换 lv1 |
| 4 | `spot_alchemy_lv1.png` | `/workspace/q_design/dongfu_8h_min/spot_alchemy_lv1.png` | 192×192 | 炼丹 **Lv1** 景差（小炉微烟） | L0 炼丹热点中心贴图 / 设施卡缩略 |
| 5 | `spot_alchemy_lv2.png` | `/workspace/q_design/dongfu_8h_min/spot_alchemy_lv2.png` | 192×192 | 炼丹 **Lv2** 景差（旺火+烟团） | 同上；等级 ≥2 替换 |
| 6 | `spot_forge_lv1.png` | `/workspace/q_design/dongfu_8h_min/spot_forge_lv1.png` | 192×192 | 强化/炼器 **Lv1** 景差（锻台+锤） | L0 强化热点中心贴图 / 设施卡缩略 |
| 7 | `spot_forge_lv2.png` | `/workspace/q_design/dongfu_8h_min/spot_forge_lv2.png` | 192×192 | 强化/炼器 **Lv2** 景差（炽芯+火花+侧架） | 同上；等级 ≥2 替换 |

---

## 与旧资源关系

| 旧 | 新 | 说明 |
|----|----|------|
| `/workspace/q_design/assets/icon_lingpu.png` | `icon_kuilei_256.png` | **叙事替换**：灵仆→傀儡。尺寸同 256²。可先只换文案+图标；分配逻辑不变。旧 lingpu 保留作回退。 |
| L0/L1 整屏 keyart（`q_dongfu_*`） | 本包 spot_* | **不重画整屏**。spot 叠在现有 L0 热点上或作设施卡图标即可出「升级有景差」。 |
| `icon_lingmu.png` | — | 本包不动；灵木资源图标继续用旧的。 |

---

## 硬接建议（先接这 3 类）

1. **`icon_kuilei_256.png`** → 顶栏/分配条立刻换名换图（文案「傀儡」）。  
2. **三设施 spot_lv1** → 挂 L0 三个热点中心（药园/炼丹/强化），替代纯色占位。  
3. **三设施 spot_lv2** → 设施 `level >= 2` 时换图，一眼看出升级景差。

阵法 / 地块五态 / hire·rest 态 / 对照条：**本包未出**（P0 已砍）。

---

## 替换约定

精修时 **同名覆盖** 本目录文件即可；客户端路径不必改。
