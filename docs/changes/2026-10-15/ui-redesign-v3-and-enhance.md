# 界面 v3、装备强化与分期

## 决定

- 开发分期：A 阶段只做单人可玩的完整玩法和后台；安全、回滚、封号、补发、邮件礼包兑换码、订单放到 B 阶段。详见 `docs/roadmap/phases.md`。
- 去掉：版本回滚、玩家封禁、补发、邮件、礼包、兑换码、商品与订单（后台页面、路由、演示数据）；物品锁定（客户端）。后端本来没有回滚、封禁、补发接口，所以没有删后端接口，也没有新增。
- 装备部位：6 个核心部位（新增「手部」，服务端键 `gloves`），法宝、灵宠预留。
- 没有货币，没有出售。分解装备得到强化经验，经验给任意装备升强化等级。
- 强化第一版不失败、按品质限制等级，数字在后台配置，规则见 `docs/design/enhance_rules_proposal.md`（v1 是讨论稿，v2 已由客户确认并加了突破节点，见 `enhance-v2-breakthrough-red-decompose.md`）。
- 行囊初始容量 20；保留 `bagCapacity` / `bagBonus` 字段和界面，没有购买入口。
- 游戏端美术：先用公开可下载的素材做占位，美术来源、作者、授权记录在 `game/assets/ASSETS_LICENSES.md`；不能商用或授权不明的素材标明「上线前替换」。

## 改动位置

- 数据库：迁移 `backend/drizzle/0016_enhance_and_hands.sql`（`content_globals.enhance`、`player_items.enhance_level`、`player_states.enhance_exp`、`player_states.bag_bonus`；写入强化起始值）。
- 后端：`content/enhance.ts`、`content/draft-routes.ts`（`GET/PUT /admin/draft/enhance`）、`content/validate.ts`、`content/numeric-scheme.ts` 与 `content/gear.ts`（手部）、`loop/actions.ts` 与 `loop/routes.ts`（`POST /me/items/:id/enhance`、分解返还经验、背包容量）、`scripts/import-legacy.ts`。
- 后台：`nav.ts`、`router.ts`、`layouts/AdminLayout.vue`、`views/config/EnhanceView.vue`（新）、`views/publish/VersionsView.vue`（去掉回滚）、`views/players/PlayersView.vue`（去掉封禁与补发）、`views/system/SettingsView.vue`、`schema/resources.ts`；删除 `views/ops/{Mail,Gifts,Codes,Shop}View.vue`、`components/MockCrudView.vue`、`components/MockBadge.vue`、`composables/mockStore.ts`；`mock/server.mjs` 去掉回滚接口，增加强化与手部。
- 游戏端：`scripts/ui/` 整体重做（`art/`、`shell/`、`pages/`、`kit/`、`main_theme.gd`、`play_screen.gd`、`player_login.gd`）；`scripts/model/`（`enhance_model.gd` 新增，`bag_model.gd`、`slot_config.gd`、`item_flags.gd`、`ui_mock.gd` 修改）；`assets/art/`、`assets/fonts/`、`assets/shaders/`、`assets/credits.json`、`assets/ASSETS_LICENSES.md`；删除 `scripts/ui/bag_art.gd`。
- 工具：`tools/assets/build_ui_frames.py`、`tools/assets/build_icons_and_backgrounds.py`（可重新生成框体、图标、背景）。
- 测试：`game/tests/unit/` 新增 `test_enhance_model.gd`、`test_art_lib.gd`、`test_mock_enhance.gd`，其余按新界面更新；后端新增强化与分解测试。

## 还没做

- 没有真机（Android）验证；界面只在 Xvfb 里用演示数据渲染截图。
- 强化数值、掉率、关卡推荐战力没有平衡过；已部署的内容要重新发布才会带上强化规则和手部装备。
- 占位美术里图标（game-icons.net，CC BY 3.0）必须保留署名；背景画和字体可商用，但整体风格建议上线前换成原创美术。
- 后台 CSV、操作日志等页面没有改动；回滚、封禁、补发、邮件等放到 B 阶段。
- 无头 GUT 里仓库自带的 LFS 指针字体会打印 FreeType 报错，与本次改动无关；运行 GUT 时用不把引擎报错算失败的配置（只统计 `gut` 与 `push_error`）。

## 相关

- ADR：无新增。`docs/decisions/` 里「突破概率」等旧决定不变。
