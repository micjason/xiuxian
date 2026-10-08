# 数据库迁移

只改 `backend/src/db/schema.ts`，然后在 `backend/` 执行 `npm run db:generate`。检查生成的 SQL，提交它。不要手写迁移，也不要改已经执行过的迁移文件。

本机：`npm run db:migrate` 作用在 `.env` 里的库。测试：`npm test` 使用 `xiuxian_test`。

正式服和测试服的备份、重建要等项目负责人确认后再做。备案完成前不要把线上从 HTTP 换成 HTTPS。
