# 洞府药园 / 炼丹不再显示物品 slug

客户端 `CaveView.item_name` 原先在 `content.items` 缺 `displayName` 时直接回落成 slug，药园地块、选种和炼丹配方标题会露出 `seed_lingcao`、`pill_cultivate` 这类编号。

- 先用 `content.items` 里的 `displayName`（空字符串或等于 slug 视为没有）。
- 没有时用内置中文名：灵草种子、清心草种子、灵草、清心草、修为丹、攻击临时丹、防御临时丹、灵木。
- 仍没有时显示「未知物品」，不把原始 slug 当界面文案。`recipeSlug` 只用于节点名和炼制请求。
- `ProtoMock.content()`（截图脚本用的演示内容）补上这些物品的中文名。旧导出里已有正式名的不覆盖。

没有存档迁移，也没有线上灌库。
