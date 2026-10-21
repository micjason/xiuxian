# 旧表单覆盖保护（2026-10-21，后台小版本，不发 APK）

方案见 `docs/changes/next/stale-save-protection.md`（负责人已批准）。起因：20:36 两个窗口 1 秒内先后保存同一关，后到的旧表单把先到的整行盖掉，服务器没提示。

## 服务器
- 新模块 `backend/src/modules/content/revisions.ts`：
  - 版本号 = 这一行库里内容（含 `updated_at`）的 md5。用整行哈希而不是只看 `updated_at`：弹窗类型表没有 `updated_at`，个别保存路径不一定更新它，整行哈希都能兜住；有 `updated_at` 的表，它变了哈希一定变。
  - `GET /admin/draft/revisions?kind=stage|globals|item|skill|skillCategory|realm|chapter|gearSet|puppet|popupType` → `{ 主键: 版本号 }`（需要管理员登录）。
  - 受保护的保存接口（`/admin/...` 和 `/api/v1/admin/...` 都算）：关卡 `PUT stages/:id`；全局（同一行 `content_globals`）`config-overview / tuning / rules / enhance / boss-rules / gear-params / gear-qualities`；`gear/:id`、`gear/manual/:id`、`items/:id`、`gear-sets/:id`、`skills/:id`、`skill-categories/:id`、`realms/:code`、`chapters/:id`、`puppets/:id`、`popup-types/:slug`。
  - 请求带 `If-Match: <版本号>` 且和库里不一致 → `409 STALE_REVISION`，`details` 里有现在的版本号、最后保存时间和管理员名，不写库。
  - 保存成功的响应头 `X-Revision` = 新版本号（同一个表单接着改再存不会误报）。
  - **不带 `If-Match` 的请求照旧放行**（脚本、测试、旧缓存页面）；后台网页的保存全部会带。检查排在登录校验之后。
- 测试 `revisions.test.ts`：关卡 409 + 用 409 返回的版本号「仍然覆盖」成功 + 同一窗口连续保存不误报；全局：一页保存后另一页旧版本号 409、`/api/v1` 前缀同样受保护、不带版本号照旧成功；章节 409、kind 校验、未登录 401。

## 后台
- `composables/revisions.ts`：每个页面自己一份版本号（不和其他页签共享）。页面读数据前先取版本号（先取再读：最多误报、不会漏报）。
- `api()` 新参数 `guard`：自动带 `If-Match`、成功后记下 `X-Revision`；遇到 409 弹出 `ConflictDialog`：
  - **重新读取**：丢掉这次改动，页面重读；列表页的抽屉自动用最新内容重新打开。
  - **查看差异**：表格对比「服务器上现在的值」和「你要保存的值」（只列你这次要保存、且两边不同的字段）。
  - **仍然覆盖**：带上服务器现在的版本号再发一次（期间又有人保存会再弹）。
  - **取消**：表单保持不动。
- 已接入：关卡与 Boss 抽屉；配置概览、装备强化、战斗公式（全局一行）、装备生成参数；装备（公式装备 / 手动装备 / 套装）；物品；功法、功法分类；境界；章节；试打木桩；弹窗类型。
- 没接：旧的「洞府建筑」页（还走老接口 `/admin/content/buildings`，不在草稿体系里）；新建 / 删除 / 恢复默认等单击操作（不是「旧表单」）。

## 已知限制
- 检查和写库不是同一个事务：两个请求在同一毫秒内到达仍可能都通过（窗口极小；真正的问题「表单开着很久」已覆盖）。
- 全局参数是一整行：A 页改公式、B 页改强化，B 保存也会提示冲突（「查看差异」会显示没有字段冲突，可以放心「仍然覆盖」）。
