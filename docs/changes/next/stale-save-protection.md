# 旧表单覆盖保护（下一个小版本，方案）

## 问题（2026-10-21 dev2 实际发生）
20:36:34 Chengpeng 保存了「赤炎火山·三」，20:36:35 另一个窗口用 1 分钟前打开的抽屉又保存了一次。
`PUT /admin/draft/stages/:id` 收的是**整关表单**（基础信息、普通怪、掉落、首领、指定掉落），后到的请求用旧数据把先到的整行盖掉，服务器不提示。
同一个账号多窗口 / 多人同时改都会遇到；多标签页 + keep-alive 让「打开很久的旧表单」更常见。

## 受影响的接口（都是整份覆盖）
| 接口 | 后台表单 |
|---|---|
| `PUT /admin/draft/stages/:id` | 关卡与 Boss 抽屉（风险最大：字段最多、最常改） |
| `PUT /admin/draft/config-overview`、`/tuning`、`/rules`、`/enhance`、`/boss-rules`、`/gear-params`、`/gear-qualities` | 配置概览、战斗公式、装备强化、首领规则（都写 `content_globals` 同一行，彼此还会互相覆盖） |
| `PUT /admin/draft/gear/:id`、`/gear/manual/:id`、`/gear-sets/:id` | 装备配置抽屉、套装 |
| `PUT /admin/draft/items/:id`、`/skills/:id`、`/skill-categories/:id`、`/realms/:code`、`/chapters/:id`、`/puppets/:id` | 物品、功法、境界、章节、试打木桩 |
| `PUT /admin/popup-types/:slug`、公告 | 运营 |
| 旧的 `/admin/content/*` PUT | 已不在后台使用，可只读或删掉 |

## 两种做法
1. **只提交改动的字段（PATCH）**：前端拿「打开时的快照」和当前表单做 diff，只发改过的路径。
   能减少冲突，但改的正好是同一字段时仍会静默覆盖；嵌套数组（首领、普通怪、指定掉落）要定义合并规则，前后端都要大改。
2. **乐观并发（推荐）**：每行已有 `updated_at`（`content_globals` 也有）。
   - GET 返回 `revision`（= `updated_at` 的毫秒数）；表单保存时带 `If-Match: <revision>`（或 body `revision`）。
   - 服务端 `UPDATE … WHERE slug = $1 AND updated_at = $rev`，0 行 → `409 STALE_REVISION`，附当前最新值和最后保存时间。
   - 后台 `api()` 统一处理 409：弹窗「这条在你打开后被别人改过（x 分钟前）」→「重新读取（丢掉我的改动）/ 查看差异 / 仍然覆盖（带 force=1）」。
   - 不带 revision 的旧客户端照旧（兼容），下一版后台全部带上后可改为必填。

## 建议
做 **方案 2**，先覆盖关卡抽屉和 `content_globals` 系列（配置概览 / 首领规则 / 强化 / 公式），再推到装备、物品、功法、境界、章节。
可以和已有的「全局数据版本号」配合：切回页签时数据已自动重读，冲突主要剩下「抽屉开着很久」这种情况，正好由 409 兜住。

## 估算
- 服务端：通用 `assertRevision()` + 各 PUT 接上、返回 409、测试 ≈ 0.5 天
- 后台：`api()` 统一 409 弹窗、表单保存带 revision、关卡抽屉 / 配置概览先接 ≈ 0.5 天
- 其余页面逐个接 + 联调截图 ≈ 0.5 天
合计约 **1.5 天**，不涉及客户端、不发 APK、不改库结构（用现有 `updated_at`）。
