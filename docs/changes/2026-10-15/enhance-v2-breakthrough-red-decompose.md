# 装备强化 v2：突破节点、红色、已穿戴不能分解、经验池无上限

## 决定（客户已确认）

1. 满级属性加成保留（橙 +15 约 ×1.9），但一切可在后台配置：每个品质的等级上限、经验倍数、经验增长倍数、每级属性加成、分解基础经验，加通用值。
2. 已穿戴的装备禁止分解。
3. 强化经验池没有上限。
4. 红色（仙品）可以强化，有自己的规则。
5. 要突破节点：每个品质可配置若干节点，装备强化到节点等级后需要额外材料才能继续，不失败。

详细规则、起始值、风险和待回答的问题见 `docs/design/enhance_rules_proposal.md`（v2）。

## 改动位置

- 数据库：迁移 `0017_enhance_red_and_breakthrough.sql`：`player_items.break_level`；创建 3 个起始材料物品（`enh_stone_low/mid/high`，不覆盖同名物品）；给草稿的强化规则补红色和突破节点（只补缺的，不覆盖后台已改的数字）；如果草稿里有「方案首领掉落」表，加三种突破石的起始掉落。
- 后端：`content/enhance.ts`（红色、品质覆盖、突破节点、材料校验、保存时创建起始材料）、`content/validate.ts`（发布时校验节点和材料）、`loop/actions.ts`（`enhanceItem` 遇节点停下并报 `BREAKTHROUGH_REQUIRED`；新增 `breakthroughItem`；分解已穿戴装备报 `EQUIPPED_CANNOT_DECOMPOSE`；方案首领也会掷后台掉落表）、`loop/routes.ts`（`POST /me/items/:id/breakthrough`）、`shared/errors.ts`（3 个新错误码）、`content/numeric-scheme.ts`、`scripts/apply-numeric-scheme.ts`、`scripts/import-legacy.ts`、`db/schema.ts`。
- 后台：`views/config/EnhanceView.vue`（6 个品质、每品质覆盖项、突破节点表、批量补齐节点、曲线里标出突破等级和升满所需材料、去掉「满级加成偏高」提醒）、`nav.ts`、`mock/server.mjs`。
- 游戏端：`model/enhance_model.gd`（红色、覆盖项、节点；没有任何玩法数字）、`model/bag_model.gd`（突破信息、材料现有数量、`decompose_block_reason`）、`ui/pages/item_detail.gd`（强化卡的突破块、分解不可用原因）、`ui/play_screen.gd`（突破请求、批量分解跳过已穿戴、红点包含「材料齐了可突破」）、`bag_page.gd`、`character_page.gd`、`home_page.gd`、`model/ui_mock.gd`。

## 没做 / 要注意

- 已发布的快照里没有红色和突破规则：需要重新发布一次。老快照里红色装备不能强化（其他品质不受影响）。
- 红色装备目前只能在后台「物品」里手工建（品质 `red`）；自动生成装备仍只有白到橙五档。
- 突破材料的掉落只是起始占位，没有设计过；分解不返还突破材料。
- 没有真机验证；强化与突破数值都没有平衡过。
