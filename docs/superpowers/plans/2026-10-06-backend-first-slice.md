# 后端第一批 Implementation Plan

> 已被 `docs/roadmap/` 取代，不再执行。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本机做出玩家登录、结算、突破、战力、配置发布、操作记录查询和修复入口，并用测试证明。

**Architecture:** 一个 Fastify 进程加本机 PostgreSQL。登录、玩家进度、配置发布、操作记录、修复分成五块。结算、突破和战力是纯函数。会改进度的成功写入与操作记录在同一个事务里。

**Tech Stack:** Node.js、TypeScript、Fastify 5、Drizzle ORM、PostgreSQL 16、Vitest、argon2id。

## Global Constraints

- 不连接 `101.132.74.32`，不部署，不做后台页面，不改手机客户端。
- 修为、境界、战力、突破由服务器计算。请求里带来的这些数不能写入进度。
- 登录、结算、突破、发布、修复，成功和失败都写入操作记录。密码、明文会话和令牌不进记录，也不进 `backend/var/crash.log`。
- 进度和对应的成功记录在同一次事务里写入。事务失败则两边都不留。
- 修旧数据只走具名修复程序：先预览，确认名单编号后写入。同一玩家对同一个修复程序只生效一次。
- 玩家会话不能调用发布、查询记录、预览修复和确认修复。
- 同时只有一份草稿和一份当前已发布版本。
- 战力公式与客户端一致：`attack + defense * 0.8 + speed * 1.5 + hp * 0.04`。
- 第一个管理员用本机命令创建，没有公开的管理员注册接口。
- 第一批不预置真实修复程序。

---

### Task 1: 项目骨架、规则、技能和战力纯函数

**Files:**
- Create: `backend/package.json`
- Create: `backend/tsconfig.json`
- Create: `backend/vitest.config.ts`
- Create: `backend/docker-compose.yml`
- Create: `backend/.gitignore`
- Create: `backend/src/modules/player/power.ts`
- Create: `backend/src/modules/player/power.test.ts`
- Create: `.cursor/rules/backend-authority.mdc`
- Create: `.cursor/skills/implement-backend/SKILL.md`
- Modify: `backend/README.md`

**Interfaces:**
- Consumes: 无
- Produces: `piecePower(stats: { attack: number; defense: number; hp: number; speed: number }): number`

- [ ] **Step 1: 写失败测试**

```ts
import { describe, expect, it } from "vitest";
import { piecePower } from "./power.js";

describe("piecePower", () => {
  it("matches the client formula", () => {
    expect(piecePower({ attack: 10, defense: 10, hp: 100, speed: 10 })).toBe(
      10 + 8 + 15 + 4,
    );
  });
});
```

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && npm test -- src/modules/player/power.test.ts`
Expected: FAIL，找不到 `./power.js` 或 `piecePower`

- [ ] **Step 3: 写最小实现和骨架**

`power.ts`：

```ts
export function piecePower(stats: {
  attack: number;
  defense: number;
  hp: number;
  speed: number;
}): number {
  return stats.attack + stats.defense * 0.8 + stats.speed * 1.5 + stats.hp * 0.04;
}
```

`package.json` 的 scripts：`test` 为 `vitest run`，`dev` 为 `tsx src/server.ts`，`db:generate` 为 `drizzle-kit generate`，`db:migrate` 为 `tsx src/db/migrate.ts`，`admin:create` 为 `tsx src/scripts/create-admin.ts`。dependencies：`argon2`、`drizzle-orm`、`fastify`、`postgres`。devDependencies：`drizzle-kit`、`tsx`、`typescript`、`vitest`、`@types/node`。`"type": "module"`。

`tsconfig.json`：`strict`、`module`/`moduleResolution` 为 `NodeNext`、`outDir` 为 `dist`、`rootDir` 为 `src`。测试文件放在 `src` 旁，vitest 直接跑 TypeScript，不要求先编译测试。

`docker-compose.yml`：服务名 `postgres`，镜像 `postgres:16`，端口 `5432:5432`，用户/密码/库都是 `xiuxian`，数据卷 `pgdata`。

`backend/.gitignore`：`node_modules/`、`dist/`、`var/`、`.env`。

规则 `.cursor/rules/backend-authority.mdc` 的 `alwaysApply` 为 true，正文使用设计文档「规则和技能」里的五条。技能 `.cursor/skills/implement-backend/SKILL.md` 的 description 以 “Use when” 开头，正文是设计文档里的五步。

`backend/README.md` 改成：本目录是第一批后端，本机用 Docker 里的 PostgreSQL 跑测试。尚未部署到公网服务器。

- [ ] **Step 4: 安装依赖并确认测试通过**

Run: `cd backend && npm install && npm test -- src/modules/player/power.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend .cursor/rules/backend-authority.mdc .cursor/skills/implement-backend/SKILL.md
git commit -m "$(cat <<'EOF'
feat(backend): add the power rule and project skeleton

EOF
)"
```

### Task 2: 结算和突破纯规则

**Files:**
- Create: `backend/src/modules/player/progress-rules.ts`
- Create: `backend/src/modules/player/progress-rules.test.ts`

**Interfaces:**
- Consumes: 无
- Produces:
  - `settleCultivation(input: { cultivation: number; elapsedSeconds: number; gainPerSecond: number; offlineCapSeconds: number }): { cultivation: number; countedSeconds: number; gained: number }`
  - `breakthrough(input: { cultivation: number; cost: number; nextSlug: string | null }): { ok: true; cultivation: number; nextSlug: string } | { ok: false; reason: "not_enough" | "max_realm" }`

- [ ] **Step 1: 写失败测试**

```ts
import { describe, expect, it } from "vitest";
import { breakthrough, settleCultivation } from "./progress-rules.js";

describe("settleCultivation", () => {
  it("caps elapsed time and adds cultivation", () => {
    const result = settleCultivation({
      cultivation: 10,
      elapsedSeconds: 100,
      gainPerSecond: 2,
      offlineCapSeconds: 40,
    });
    expect(result).toEqual({ cultivation: 90, countedSeconds: 40, gained: 80 });
  });

  it("treats negative elapsed time as zero", () => {
    const result = settleCultivation({
      cultivation: 10,
      elapsedSeconds: -5,
      gainPerSecond: 2,
      offlineCapSeconds: 40,
    });
    expect(result.gained).toBe(0);
    expect(result.cultivation).toBe(10);
  });
});

describe("breakthrough", () => {
  it("spends cultivation and moves to the next realm", () => {
    expect(breakthrough({ cultivation: 400, cost: 360, nextSlug: "qi_early" })).toEqual({
      ok: true,
      cultivation: 40,
      nextSlug: "qi_early",
    });
  });

  it("rejects a realm with no next slug", () => {
    expect(breakthrough({ cultivation: 999, cost: 1, nextSlug: null })).toEqual({
      ok: false,
      reason: "max_realm",
    });
  });

  it("rejects when cultivation is short", () => {
    expect(breakthrough({ cultivation: 10, cost: 360, nextSlug: "qi_early" })).toEqual({
      ok: false,
      reason: "not_enough",
    });
  });
});
```

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && npm test -- src/modules/player/progress-rules.test.ts`
Expected: FAIL，模块不存在

- [ ] **Step 3: 写最小实现**

`countedSeconds` 为 `max(0, min(elapsedSeconds, offlineCapSeconds))`。`gained` 为 `countedSeconds * gainPerSecond`。`nextSlug === null` 时返回 `max_realm`，先于余额检查。余额不足返回 `not_enough`。成功时修为减去 cost。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && npm test -- src/modules/player/progress-rules.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/player/progress-rules.ts backend/src/modules/player/progress-rules.test.ts
git commit -m "$(cat <<'EOF'
feat(backend): add cultivation settle and breakthrough rules

EOF
)"
```

### Task 3: 表结构和迁移

**Files:**
- Create: `backend/src/db/schema.ts`
- Create: `backend/src/db/client.ts`
- Create: `backend/src/db/migrate.ts`
- Create: `backend/drizzle.config.ts`
- Create: `backend/src/db/schema.test.ts`
- Create: `backend/drizzle/` 下由 drizzle-kit 生成的 SQL

**Interfaces:**
- Consumes: 无
- Produces: 表 `players`、`admins`、`sessions`、`content_releases`、`realms`、`skills`、`items`、`player_states`、`operation_records`、`repair_previews`、`repair_applications`。`getDb()` 返回 drizzle 客户端。`migrate()` 执行 `backend/drizzle` 里的 SQL。

表的必填列：

- `players` / `admins`：`id` uuid 主键，`username` 唯一，`password_hash`，`created_at`
- `sessions`：`id` uuid，`token_hash` 唯一，`actor_type`（`player` 或 `admin`），`actor_id`，`expires_at`
- `content_releases`：`id`，`status`（`draft`、`published`、`archived`），`offline_cap_seconds`，`published_at` 可空，`note` 可空
- `realms`：`release_id`，`slug`，`display_name`，`sort_order`，`gain_per_second`，`breakthrough_cost`，`next_slug` 可空，`attack`，`defense`，`hp`，`speed`。同一 `release_id + slug` 唯一
- `skills`：`release_id`，`slug`，`display_name`，`description`，`role`，`attack`，`defense`，`hp`，`speed`，`cultivate_bonus`，`min_realm_order`
- `items`：`release_id`，`slug`，`display_name`，`description`，`kind`，`quality`，`slot` 可空，`attack`，`defense`，`hp`，`speed`
- `player_states`：`player_id` 主键，`cultivation`，`realm_slug`，`last_settled_at`
- `operation_records`：`id`，`at`，`actor_type`，`actor_id` 可空，`actor_name`，`action`，`result`，`reason` 可空，`content_release_id` 可空，`summary` jsonb
- `repair_previews`：`id`，`repair_name`，`entries` jsonb，`created_at`，`state_token`
- `repair_applications`：`repair_name`，`player_id`，`preview_id`，`applied_at`。`repair_name + player_id` 唯一

- [ ] **Step 1: 写失败测试**

```ts
import { describe, expect, it } from "vitest";
import * as schema from "./schema.js";

const tableNames = [
  "players",
  "admins",
  "sessions",
  "contentReleases",
  "realms",
  "skills",
  "items",
  "playerStates",
  "operationRecords",
  "repairPreviews",
  "repairApplications",
];

describe("schema", () => {
  it("exports every first-slice table", () => {
    for (const name of tableNames) {
      expect(schema).toHaveProperty(name);
    }
  });
});
```

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && npm test -- src/db/schema.test.ts`
Expected: FAIL

- [ ] **Step 3: 写 schema、drizzle 配置和 migrate**

`getDb()` 读取 `DATABASE_URL`，缺失时抛出 `DATABASE_URL is required`。`migrate()` 对 drizzle 生成目录调用 `migrate()`。然后运行 `npm run db:generate`，把 SQL 留在 `backend/drizzle/`。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && npm test -- src/db/schema.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/db backend/drizzle backend/drizzle.config.ts
git commit -m "$(cat <<'EOF'
feat(backend): add the postgres schema

EOF
)"
```

### Task 4: 操作记录

**Files:**
- Create: `backend/src/modules/operations/record.ts`
- Create: `backend/src/modules/operations/record.test.ts`
- Create: `backend/src/test/db.ts`

**Interfaces:**
- Consumes: `getDb()`、`operation_records`
- Produces:
  - `writeOperation(tx, input: { at: Date; actorType: "player" | "admin"; actorId: string | null; actorName: string; action: "login" | "settle" | "breakthrough" | "publish" | "repair"; result: "success" | "failure"; reason?: string; contentReleaseId?: string; summary: Record<string, unknown> }): Promise<void>`
  - `listOperations(db, query: { name?: string; action?: string; from: Date; to: Date })`
  - `writeCrash(error: unknown, filePath: string): void`

`writeOperation` 在写入前删除 summary 和 reason 里的 `password`、`token`、`passwordHash` 键。`listOperations` 按 `at` 升序。有 `name` 时匹配 `actor_name`。没有 `name` 时不按人过滤。

- [ ] **Step 1: 写失败测试**

一个测试调用 `writeOperation` 写入带 `password` 键的 summary，再 `listOperations`，断言行存在且 summary 里没有 `password`。另一个测试把 `{ password: "secret", message: "boom" }` 交给 `writeCrash`，读文件断言不含 `secret`，含 `boom`。数据库测试使用 `DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian`。每个测试包在事务里，结束时回滚。

- [ ] **Step 2: 启动数据库并确认测试失败**

Run: `cd backend && docker compose up -d && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm run db:migrate && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/operations/record.test.ts`
Expected: FAIL，函数不存在

- [ ] **Step 3: 写最小实现**

按接口实现。`writeCrash` 向 `filePath` 追加一行 JSON。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/operations/record.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/operations backend/src/test/db.ts
git commit -m "$(cat <<'EOF'
feat(backend): record operations without secrets

EOF
)"
```

### Task 5: 玩家和管理员登录

**Files:**
- Create: `backend/src/modules/auth/service.ts`
- Create: `backend/src/modules/auth/routes.ts`
- Create: `backend/src/modules/auth/service.test.ts`
- Create: `backend/src/scripts/create-admin.ts`

**Interfaces:**
- Consumes: `players`、`admins`、`sessions`、`writeOperation`
- Produces:
  - `registerPlayer(db, input: { username: string; password: string; now: Date }): Promise<{ playerId: string; token: string }>`
  - `loginPlayer(db, input: { username: string; password: string; now: Date }): Promise<{ ok: true; playerId: string; token: string } | { ok: false; reason: "unknown" | "bad_password" }>`
  - `loginAdmin(db, input: { username: string; password: string; now: Date }): Promise<{ ok: true; adminId: string; token: string } | { ok: false; reason: "unknown" | "bad_password" }>`
  - `createAdmin(db, input: { username: string; password: string }): Promise<void>`
  - `readSession(db, token: string, now: Date): Promise<{ actorType: "player" | "admin"; actorId: string; actorName: string } | null>`

明文 token 只在返回值里出现一次。数据库保存 sha256。会话有效期 30 天。注册时创建 `player_states`：修为 0，境界 `mortal`，`last_settled_at` 为 `now`。成功和失败登录都写操作记录。失败记录的 summary 只有 `username` 和 `reason`。

路由：`POST /auth/register`、`POST /auth/login`、`POST /admin/auth/login`。没有 `POST /admin/auth/register`。

- [ ] **Step 1: 写失败测试**

覆盖：注册后能用会话认出玩家；错误密码返回 `bad_password` 且记录里没有密码明文；`createAdmin` 之后 `loginAdmin` 成功；玩家 token 调用 `readSession` 的 `actorType` 为 `player`。

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/auth/service.test.ts`
Expected: FAIL

- [ ] **Step 3: 写最小实现**

用 `argon2.hash` / `argon2.verify`。`create-admin.ts` 从环境变量 `ADMIN_USERNAME` 和 `ADMIN_PASSWORD` 读取，缺一即退出码 1，不把密码打印出来。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/auth/service.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/auth backend/src/scripts/create-admin.ts
git commit -m "$(cat <<'EOF'
feat(backend): add player and admin sessions

EOF
)"
```

### Task 6: 配置草稿和发布

**Files:**
- Create: `backend/src/modules/content/service.ts`
- Create: `backend/src/modules/content/routes.ts`
- Create: `backend/src/modules/content/service.test.ts`

**Interfaces:**
- Consumes: `content_releases`、`realms`、`skills`、`items`、`writeOperation`、`readSession`
- Produces:
  - `ensureDraft(db): Promise<string>`
  - `saveRealm(db, adminId: string, input: RealmInput): Promise<void>`
  - `publish(db, admin: { id: string; name: string }, now: Date): Promise<{ releaseId: string }>`
  - `getPublishedRealm(db, slug: string): Promise<RealmRow | null>`

`RealmInput` 含 `slug`、`displayName`、`sortOrder`、`gainPerSecond`、`breakthroughCost`、`nextSlug`、`attack`、`defense`、`hp`、`speed`。`saveRealm` 只写草稿。`publish` 在一个事务里复制草稿的境界、技能、物品到新版本，新版本改为 `published`，旧的 `published` 改为 `archived`，草稿保留且内容与新版本相同。名称为空或同一草稿里 slug 重复时，`publish` 抛出错误且不改变已发布版本。成功发布写操作记录，summary 含 `previousReleaseId` 和 `releaseId`。

路由都要求管理员会话：`PUT /admin/content/realms/:slug`、`PUT /admin/content/skills/:slug`、`PUT /admin/content/items/:slug`、`POST /admin/content/publish`。

- [ ] **Step 1: 写失败测试**

先发布一版凡人境界，每秒修为 2，名字「凡人」。再把草稿名字改成「凡人改」并保存，断言 `getPublishedRealm` 仍返回「凡人」。再发布，断言已发布名字为「凡人改」，slug 仍是 `mortal`。另测空名字发布会失败，已发布名字不变。玩家会话调用 `publish` 被拒绝。

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/content/service.test.ts`
Expected: FAIL

- [ ] **Step 3: 写最小实现**

技能和物品的保存字段与 schema 列一致。第一批测试以境界为主，技能和物品各有一个保存后能随发布复制的测试。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/content/service.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/content
git commit -m "$(cat <<'EOF'
feat(backend): publish content from a single draft

EOF
)"
```

### Task 7: 打开游戏时结算和突破

**Files:**
- Create: `backend/src/modules/player/service.ts`
- Create: `backend/src/modules/player/routes.ts`
- Create: `backend/src/modules/player/service.test.ts`

**Interfaces:**
- Consumes: `settleCultivation`、`breakthrough`、`piecePower`、`getPublishedRealm`、`writeOperation`、`player_states`
- Produces:
  - `openProgress(db, playerId: string, now: Date): Promise<{ realmSlug: string; realmName: string; cultivation: number; gained: number; power: number }>`
  - `tryBreakthrough(db, playerId: string, now: Date): Promise<{ ok: true; realmSlug: string; cultivation: number } | { ok: false; reason: "not_enough" | "max_realm" }>`

`openProgress` 使用 `SELECT ... FOR UPDATE` 锁住进度行。经过秒数是 `now - last_settled_at`，上限来自已发布版本的 `offline_cap_seconds`。战力用已发布境界的攻防气血速度计算，不写入 `player_states`。成功时进度和操作记录同一个事务。`tryBreakthrough` 失败时进度的境界和修为不变，并有失败记录。请求体里的 `cultivation` 字段被忽略。

路由：`GET /me`、`POST /me/breakthrough`，都要求玩家会话。

- [ ] **Step 1: 写失败测试**

已发布凡人每秒修为 2、离线上限 28800、攻 10 防 6 血 50 速 0、突破消耗 360、下一境界 `qi_early`。玩家上次结算在 50 秒前，修为 0。`openProgress` 返回修为 100、gained 100、境界名「凡人」、power 为 `piecePower({ attack: 10, defense: 6, hp: 50, speed: 0 })`。再调用一次、`now` 相同，修为仍是 100。两个并行的 `openProgress` 也只增加一次。没有已发布配置时，`openProgress` 不改修为，并留下失败记录。修为 100 时 `tryBreakthrough` 返回 `not_enough`，修为仍是 100。把修为先结算到不少于 360 后，`tryBreakthrough` 返回 `qi_early`，操作记录里有突破前后境界。请求体里的 `cultivation` 不改变结果。

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/player/service.test.ts`
Expected: FAIL

- [ ] **Step 3: 写最小实现**

并发测试用两个并行的 `openProgress`，`now` 相同，最终修为只增加一次。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/player/service.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/player/service.ts backend/src/modules/player/routes.ts backend/src/modules/player/service.test.ts
git commit -m "$(cat <<'EOF'
feat(backend): settle cultivation on the server

EOF
)"
```

### Task 8: 按玩家和时间查询操作记录

**Files:**
- Create: `backend/src/modules/operations/routes.ts`
- Create: `backend/src/modules/operations/routes.test.ts`

**Interfaces:**
- Consumes: `listOperations`、`readSession`
- Produces: `GET /admin/operations?name=&from=&to=&action=`

只允许管理员。`from` 和 `to` 是 ISO 时间。`name` 和 `action` 可空。发布记录在不传 `name`、`action=publish` 时返回。

- [ ] **Step 1: 写失败测试**

写入一条玩家「甲」的失败结算，管理员查询 `name=甲&action=settle` 能看到 `reason`。玩家 token 请求该接口返回 403。

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/operations/routes.test.ts`
Expected: FAIL

- [ ] **Step 3: 写最小实现**

用 Fastify 注入测试里的 db 和 now，不绑定真实端口。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/operations/routes.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/operations
git commit -m "$(cat <<'EOF'
feat(backend): let admins query operation records

EOF
)"
```

### Task 9: 修复入口

**Files:**
- Create: `backend/src/modules/repairs/service.ts`
- Create: `backend/src/modules/repairs/routes.ts`
- Create: `backend/src/modules/repairs/service.test.ts`

**Interfaces:**
- Consumes: `player_states`、`repair_previews`、`repair_applications`、`writeOperation`
- Produces:
  - `registerRepair(repair: { name: string; plan(db, player: { id: string; cultivation: number }): Promise<{ cultivation: number } | null> }): void`
  - `previewRepair(db, name: string): Promise<{ previewId: string; entries: Array<{ playerId: string; before: number; after: number; status: "pending" | "already" }> }>`
  - `applyRepair(db, admin: { id: string; name: string }, previewId: string, now: Date): Promise<{ applied: number }>`

`plan` 返回 null 表示这个玩家不受影响。预览不写 `player_states`。确认时比较当前修为和名单里的 `before`，不一致则整次失败且不写入。一致则把修为写成 `after`，插入 `repair_applications`，写一行修复记录。再次确认同一预览，已有 `repair_applications` 的玩家被跳过，修为不再变化。未知名字抛出 `unknown repair`。测试只注册名为 `double-cultivation` 的假程序，把修为乘 2。生产代码的注册表默认为空。

路由：`POST /admin/repairs/preview`、`POST /admin/repairs/apply`，只允许管理员。

- [ ] **Step 1: 写失败测试**

按上面的假程序覆盖：预览不改修为、确认后修为翻倍、再次确认修为不变、预览之后修为被别人改过则确认失败、玩家 token 返回 403、未知名字失败。

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/repairs/service.test.ts`
Expected: FAIL

- [ ] **Step 3: 写最小实现**

`state_token` 保存预览时每个玩家的修为，确认时逐个比较。

- [ ] **Step 4: 运行并确认通过**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/modules/repairs/service.test.ts`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/modules/repairs
git commit -m "$(cat <<'EOF'
feat(backend): preview and apply named data repairs

EOF
)"
```

### Task 10: 组装进程

**Files:**
- Create: `backend/src/app.ts`
- Create: `backend/src/server.ts`
- Create: `backend/src/app.test.ts`
- Modify: `backend/README.md`

**Interfaces:**
- Consumes: 各模块的 `routes`
- Produces: `buildApp(db): FastifyInstance`。`server.ts` 读 `DATABASE_URL` 和 `PORT`，默认端口 8080。未捕获异常调用 `writeCrash`，文件为 `backend/var/crash.log`。

- [ ] **Step 1: 写失败测试**

用 `buildApp` 走完：创建管理员不可经 HTTP 完成；玩家注册、登录、管理员发布境界、玩家 `GET /me` 得到已发布境界名。玩家请求 `POST /admin/content/publish` 返回 403。

- [ ] **Step 2: 运行并确认失败**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test -- src/app.test.ts`
Expected: FAIL

- [ ] **Step 3: 写最小实现**

路由按模块注册。README 写上本机启动需要的 `docker compose up -d`、`DATABASE_URL`、`npm run db:migrate`、`ADMIN_USERNAME` / `ADMIN_PASSWORD` 和 `npm run admin:create`。写明公网服务器不在这一批。

- [ ] **Step 4: 运行全部测试**

Run: `cd backend && DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian npm test`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add backend/src/app.ts backend/src/server.ts backend/src/app.test.ts backend/README.md
git commit -m "$(cat <<'EOF'
feat(backend): serve the first player and admin API

EOF
)"
```
