# 内容发布与弹窗队列 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 制作后台用同一份草稿发布境界、关卡、物品、技能和掉落；游戏端用一条弹窗队列显示服务器下发的通知。

**Architecture:** 发布检查和掉落掷点是纯函数。草稿仍沿用现有的境界、技能、物品表，关卡和掉落放在 adventure 文档里。通知由 `GET /me` 返回，客户端一个弹窗层按优先级逐个显示。

**Tech Stack:** TypeScript, Fastify, Drizzle, PostgreSQL, Vue 3, Element Plus, Godot 4.7 GDScript.

## Global Constraints

- 制作后台不把物品发给某个玩家。
- 一次发布整份草稿。失败则线上版本不变。
- 掉落概率是 0 到 100 的整数，数量不小于 1。各自掷点。
- 已发布编号不能删除。
- 手机这一版不打 Boss、不学技能。历练、行囊、功法仍不开放。
- 系统弹窗同一时间只显示一扇。未知模板丢弃。

---

### Task 1: 发布检查与掉落掷点

- [ ] 为境界链、技能环、技能书、掉落范围、已发布编号写失败测试。
- [ ] 实现纯函数并让测试通过。
- [ ] 发布时调用检查，保存掉落时拒绝非法概率和数量。

### Task 2: 草稿字段

- [ ] 技能增加前置技能。物品增加技能书指向和「可由游戏发放」。
- [ ] 关卡保存一个 Boss 的四项属性，掉落按 Boss 加物品合并成一条。
- [ ] 后台页面能编辑这些字段。

### Task 3: 通知

- [ ] `GET /me` 按弹窗优先级返回版本更新、公告和收益。
- [ ] 关闭通知后不再返回。离开满 60 秒且有修为才产生收益。
- [ ] 后台可改优先级和启用，可写公告。

### Task 4: 游戏端弹窗层

- [ ] 一个队列，优先级小的先显示，关掉才显示下一扇。
- [ ] 三种模板各自布局，不再使用会叠在一起的引擎窗口。
- [ ] 登录后的系统弹窗只来自 `GET /me`。
