# 数值方案一 · 第一阶段：战斗与战力 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把战斗伤害换成「攻击 × 攻击 ÷ (攻击 + k × 对方防御)」，规则页去掉两个防御比例和两个最少伤害、加上 k 和推荐战力倍数，服务器自动算出每个关卡的推荐战力，并在发布时检查推荐战力随境界递增。

**Architecture:** 伤害公式和 Boss 战力是 `backend/src/modules/combat/` 里的纯函数。新文件 `backend/src/modules/content/stage-power.ts` 把规则、境界和关卡拼起来算推荐战力，同时被发布检查（`validate.ts`）和后台关卡列表（`ops-content.ts`）使用。规则仍存在 `content_globals.combat` 这个 jsonb 里，不改表结构，不写迁移。

**Tech Stack:** TypeScript、Fastify、Drizzle ORM、PostgreSQL、vitest；后台 Vue 3 + Element Plus。

**设计依据:** `docs/superpowers/specs/2026-10-12-numeric-scheme-design.md`（方案一，用户已确认）。

---

## 全局约束（每个任务都要遵守）

- 所有回复、注释、界面文字用简体中文。
- **工作区里有大量用户没提交的改动，包括本计划要改的文件。** 在现有内容上修改，不要 `git stash`、`git checkout --`、`git reset`，不要还原任何不是本计划写的改动。**整个计划执行过程中不要 `git commit`**，最后交给用户决定怎么提交。
- 不加兜底。规则没填就直接报错「请先在后台填写：…」，不要在代码里写默认值（见 `.cursor/rules/no-hidden-fallbacks.mdc`）。
- 第一版不做境界压制，不做战力压制。
- 功法百分比、装备模板、掉落改动属于第二到第四阶段，本计划不碰。`combatStats` 里功法的算法保持原样。
- 后端命令都在 `backend/` 目录下执行：
  - 测试：`npm test`（脚本已设置 `DATABASE_URL=postgres://xiuxian:xiuxian@127.0.0.1:5432/xiuxian_test`，需要本机 PostgreSQL 在跑）
  - 单个测试文件：`npm test -- src/modules/combat/battle.test.ts`
  - 类型检查：`npm run typecheck`
  - 代码检查：`npm run lint`
- 后台命令在 `admin/` 目录下执行：`npm run build`（含 `vue-tsc` 类型检查）、`npm run lint`。
- 不改 Godot 客户端。客户端不在本地算伤害（已确认 `game/` 下没有伤害公式）。

## 本阶段改完后的规则字段

规则页（`content_globals.combat` + `powerWeights`）最终字段，全部必填：

| 键 | 中文名 | 允许 0 | 第一版要填的值 |
|---|---|---|---|
| `challengeCooldownSeconds` | 挑战冷却 | 是 | 保持现值 |
| `timeLimitSeconds` | 单场时限 | 否 | 20 |
| `defenseConstant` | 防御常数 k | 否 | 1 |
| `minInterval` | 最短出手间隔 | 否 | 0.5 |
| `speedBase` | 速度基数 | 否 | 100 |
| `attackWeight` / `defenseWeight` / `hpWeight` / `speedWeight` | 战力权重 | 是 | 4.7 / 1.6 / 0.95 / 2.6 |
| `recommendedPowerMargin` | 推荐战力倍数 | 否 | 1.05 |
| `bagCapacity` / `offlineCapSeconds` | 行囊容量 / 离线上限 | 否 | 保持现值 |

删除：`playerDefenseFactor`、`bossDefenseFactor`、`playerDamageFloor`、`bossDamageFloor`。

库里已有的 `combat` jsonb 不用迁移。旧键留在里面不会被读取；管理员在规则页点一次保存，整个 `combat` 会被新内容覆盖。保存之前，游戏会报「请先在后台填写：防御常数 k、推荐战力倍数」，这是预期行为。

## 涉及的文件

| 文件 | 动作 | 职责 |
|---|---|---|
| `backend/src/modules/combat/battle.ts` | 改 | 新伤害公式，`BattleConfig` 只剩时限和 k |
| `backend/src/modules/combat/battle.test.ts` | 改 | 伤害公式和战斗过程测试 |
| `backend/src/modules/combat/stats.ts` | 改 | 新增 `bossPower` |
| `backend/src/modules/combat/stats.test.ts` | 改 | `bossPower` 测试 |
| `backend/src/modules/content/rules.ts` | 改 | 规则字段增删 |
| `backend/src/modules/content/rules.test.ts` | 新建 | 规则字段测试 |
| `backend/src/db/schema.ts` | 改 | `contentGlobals.combat` 的 TypeScript 类型 |
| `backend/src/modules/content/validate.ts` | 改 | `ContentSnapshot` 类型；发布检查调用推荐战力检查 |
| `backend/src/modules/content/validate.test.ts` | 改 | 发布检查测试 |
| `backend/src/modules/content/stage-power.ts` | 新建 | 关卡推荐战力和递增检查 |
| `backend/src/modules/content/stage-power.test.ts` | 新建 | 上面的测试 |
| `backend/src/modules/loop/actions.ts` | 改 | `battleConfigOf` |
| `backend/src/modules/content/trial.ts` | 改 | 试打用新公式 |
| `backend/src/modules/content/ops-content.ts` | 改 | 关卡列表带推荐战力 |
| `backend/src/modules/content/stage-list-power.test.ts` | 新建 | 关卡列表推荐战力测试 |
| 7 个测试文件的规则夹具 | 改 | 换成新字段（见任务 3） |
| `admin/src/views/RulesView.vue` | 改 | 规则页字段和说明 |
| `admin/src/views/StagesView.vue` | 改 | 关卡列表显示推荐战力；试打文案 |
| `docs/roadmap/02-target-architecture.md` | 改 | 伤害公式说明 |
| `docs/changes/2026-10-12/combat-power-phase1.md` | 新建 | 修改记录 |

---

### Task 0: 基线

**Files:** 无改动

- [ ] **Step 1: 读设计文档**

读 `docs/superpowers/specs/2026-10-12-numeric-scheme-design.md` 的「战斗」「战力」「关卡与 Boss」「后台」四节。

- [ ] **Step 2: 跑一遍现有检查，记下基线**

```bash
cd backend && npm test; npm run typecheck; npm run lint
```

把失败的测试名记下来。之后的任务里，只要求「不新增失败」。如果基线就有失败，在最终汇报里列出，不要去修与本计划无关的失败。

---

### Task 1: 新伤害公式

**Files:**
- Modify: `backend/src/modules/combat/battle.ts`
- Test: `backend/src/modules/combat/battle.test.ts`

- [ ] **Step 1: 把测试文件整个换成下面的内容**

```ts
import { describe, expect, it } from "vitest";
import { hitDamage, simulateBattle } from "./battle.js";

const config = { timeLimitSeconds: 60, defenseConstant: 1 };

describe("hitDamage", () => {
  it("blocks half the damage when attack equals defense", () => {
    expect(hitDamage(100, 100, 1)).toBe(50);
  });

  it("doubles the damage when both sides double", () => {
    expect(hitDamage(200, 200, 1)).toBe(2 * hitDamage(100, 100, 1));
  });

  it("deals full attack against zero defense", () => {
    expect(hitDamage(100, 0, 1)).toBe(100);
  });

  it("deals nothing with zero attack", () => {
    expect(hitDamage(0, 0, 1)).toBe(0);
    expect(hitDamage(0, 50, 1)).toBe(0);
  });

  it("never drops to a cliff when defense is far above attack", () => {
    expect(hitDamage(10, 1000, 1)).toBeGreaterThan(0);
  });
});

describe("simulateBattle", () => {
  it("times out when the boss cannot be finished in time", () => {
    const result = simulateBattle(
      { attack: 1, defense: 0, hp: 100, interval: 10 },
      { attack: 0, defense: 0, hp: 10000, interval: 10 },
      { ...config, timeLimitSeconds: 5 },
    );
    expect(result).toMatchObject({ win: false, reason: "timeout" });
  });

  it("lets the player strike first when both act at the same time", () => {
    const result = simulateBattle(
      { attack: 10, defense: 10, hp: 20, interval: 2 },
      { attack: 10, defense: 0, hp: 10, interval: 2 },
      config,
    );
    expect(result.win).toBe(true);
    expect(result.log[0]?.side).toBe("player");
    expect(result.durationSeconds).toBe(2);
  });

  it("finishes a same-level boss in about nine seconds", () => {
    const side = { attack: 100, defense: 100, hp: 333, interval: 1.25 };
    const result = simulateBattle(side, side, { ...config, timeLimitSeconds: 20 });
    expect(result).toMatchObject({ win: true, reason: "win" });
    expect(result.durationSeconds).toBeCloseTo(8.75, 6);
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd backend && npm test -- src/modules/combat/battle.test.ts
```

预期：`hitDamage(100, 100, 1)` 得到 0 而不是 50 等断言失败（旧公式是 `攻击 − 防御 × 比例`）。

- [ ] **Step 3: 改 `battle.ts`**

把 `BattleConfig`、`hitDamage` 和 `simulateBattle` 开头两行换成：

```ts
export type BattleConfig = {
  timeLimitSeconds: number;
  defenseConstant: number;
};
```

```ts
export function hitDamage(attack: number, defense: number, defenseConstant: number): number {
  if (attack <= 0) {
    return 0;
  }
  return (attack * attack) / (attack + defenseConstant * Math.max(defense, 0));
}
```

```ts
export function simulateBattle(player: BattleSide, boss: BattleSide, config: BattleConfig): BattleResult {
  const playerDamage = hitDamage(player.attack, boss.defense, config.defenseConstant);
  const bossDamage = hitDamage(boss.attack, player.defense, config.defenseConstant);
```

`simulateBattle` 其余部分、`BattleSide`、`BattleEvent`、`BattleResult`、`trimLog` 都不动。

- [ ] **Step 4: 跑测试，确认通过**

```bash
cd backend && npm test -- src/modules/combat/battle.test.ts
```

预期：全部通过。此时 `npm run typecheck` 会在 `actions.ts`、`trial.ts` 报错，任务 3 处理。

---

### Task 2: 规则字段

**Files:**
- Modify: `backend/src/modules/content/rules.ts`
- Modify: `backend/src/db/schema.ts`（`contentGlobals.combat` 的类型）
- Modify: `backend/src/modules/content/validate.ts`（`ContentSnapshot.globals.combat` 的类型）
- Create: `backend/src/modules/content/rules.test.ts`

- [ ] **Step 1: 写失败测试 `backend/src/modules/content/rules.test.ts`**

```ts
import { describe, expect, it } from "vitest";
import { readGameRules, rulesFromInput } from "./rules.js";
import type { ContentSnapshot } from "./validate.js";

const input = {
  offlineCapSeconds: 3600,
  bagCapacity: 20,
  attackWeight: 4.7,
  defenseWeight: 1.6,
  hpWeight: 0.95,
  speedWeight: 2.6,
  minInterval: 0.5,
  challengeCooldownSeconds: 0,
  timeLimitSeconds: 20,
  defenseConstant: 1,
  speedBase: 100,
  recommendedPowerMargin: 1.05,
};

function world(combat: Record<string, number>): ContentSnapshot {
  return {
    globals: {
      startingRealmSlug: "mortal",
      starterItems: [],
      offlineCapSeconds: 3600,
      bagCapacity: 20,
      powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
      combat,
    },
    realms: [],
    stages: [],
    dropTables: [],
    items: [],
    skills: [],
  };
}

describe("game rules", () => {
  it("keeps k and the recommended power margin and drops the old factors", () => {
    const rules = rulesFromInput(input);
    expect(rules.defenseConstant).toBe(1);
    expect(rules.recommendedPowerMargin).toBe(1.05);
    expect(Object.keys(rules)).not.toContain("playerDefenseFactor");
    expect(Object.keys(rules)).not.toContain("bossDamageFloor");
  });

  it("refuses zero k and zero margin", () => {
    expect(() => rulesFromInput({ ...input, defenseConstant: 0 })).toThrow("防御常数 k必须大于 0");
    expect(() => rulesFromInput({ ...input, recommendedPowerMargin: 0 })).toThrow("推荐战力倍数必须大于 0");
  });

  it("asks the admin to fill the new fields on an old world", () => {
    const old = world({ minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 20, speedBase: 100, playerDefenseFactor: 0.4 });
    expect(() => readGameRules(old)).toThrow("请先在后台填写：防御常数 k、推荐战力倍数");
  });

  it("reads a complete world", () => {
    const rules = readGameRules(
      world({ minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 20, defenseConstant: 1, speedBase: 100, recommendedPowerMargin: 1.05 }),
    );
    expect(rules).toMatchObject({ defenseConstant: 1, recommendedPowerMargin: 1.05, speedBase: 100, timeLimitSeconds: 20 });
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd backend && npm test -- src/modules/content/rules.test.ts
```

预期：`rules.defenseConstant` 为 `undefined`，或缺字段报「请先在后台填写：玩家攻击时的防御比例…」。

- [ ] **Step 3: 改 `rules.ts`**

按下面逐处修改（其余函数 `numberOf`、`readRules` 不动）：

`GameRules` 换成：

```ts
export type GameRules = {
  offlineCapSeconds: number;
  bagCapacity: number;
  powerWeights: { attack: number; defense: number; hp: number; speed: number };
  minInterval: number;
  challengeCooldownSeconds: number;
  timeLimitSeconds: number;
  defenseConstant: number;
  speedBase: number;
  recommendedPowerMargin: number;
};
```

`RulesInput` 换成：

```ts
export type RulesInput = {
  offlineCapSeconds?: number;
  bagCapacity?: number;
  attackWeight?: number;
  defenseWeight?: number;
  hpWeight?: number;
  speedWeight?: number;
  minInterval?: number;
  challengeCooldownSeconds?: number;
  timeLimitSeconds?: number;
  defenseConstant?: number;
  speedBase?: number;
  recommendedPowerMargin?: number;
};
```

`fields` 换成（顺序决定「请先在后台填写」里名字的顺序）：

```ts
const fields = [
  ["offlineCapSeconds", "离线上限", false],
  ["bagCapacity", "行囊容量", false],
  ["attackWeight", "攻击权重", true],
  ["defenseWeight", "防御权重", true],
  ["hpWeight", "气血权重", true],
  ["speedWeight", "速度权重", true],
  ["minInterval", "最短出手间隔", false],
  ["challengeCooldownSeconds", "挑战冷却", true],
  ["timeLimitSeconds", "单场时限", false],
  ["defenseConstant", "防御常数 k", false],
  ["speedBase", "速度基数", false],
  ["recommendedPowerMargin", "推荐战力倍数", false],
] as const;
```

`rulesFromInput` 的 `return` 换成：

```ts
  return {
    offlineCapSeconds: values.offlineCapSeconds,
    bagCapacity: values.bagCapacity,
    powerWeights: {
      attack: values.attackWeight,
      defense: values.defenseWeight,
      hp: values.hpWeight,
      speed: values.speedWeight,
    },
    minInterval: values.minInterval,
    challengeCooldownSeconds: values.challengeCooldownSeconds,
    timeLimitSeconds: values.timeLimitSeconds,
    defenseConstant: values.defenseConstant,
    speedBase: values.speedBase,
    recommendedPowerMargin: values.recommendedPowerMargin,
  };
```

`rulesInputOf` 的 `return` 换成：

```ts
  return {
    offlineCapSeconds: world.globals.offlineCapSeconds,
    bagCapacity: world.globals.bagCapacity,
    attackWeight: weights?.attack,
    defenseWeight: weights?.defense,
    hpWeight: weights?.hp,
    speedWeight: weights?.speed,
    minInterval: combat?.minInterval,
    challengeCooldownSeconds: combat?.challengeCooldownSeconds,
    timeLimitSeconds: combat?.timeLimitSeconds,
    defenseConstant: combat?.defenseConstant,
    speedBase: combat?.speedBase,
    recommendedPowerMargin: combat?.recommendedPowerMargin,
  };
```

`rulesView` 的 `return` 换成：

```ts
  return {
    offlineCapSeconds: row?.offlineCapSeconds ?? null,
    bagCapacity: row?.bagCapacity ?? null,
    attackWeight: weights?.attack ?? null,
    defenseWeight: weights?.defense ?? null,
    hpWeight: weights?.hp ?? null,
    speedWeight: weights?.speed ?? null,
    minInterval: combat?.minInterval ?? null,
    challengeCooldownSeconds: combat?.challengeCooldownSeconds ?? null,
    timeLimitSeconds: combat?.timeLimitSeconds ?? null,
    defenseConstant: combat?.defenseConstant ?? null,
    speedBase: combat?.speedBase ?? null,
    recommendedPowerMargin: combat?.recommendedPowerMargin ?? null,
  };
```

`saveRules` 里 `combat:` 对象换成：

```ts
    combat: {
      minInterval: rules.minInterval,
      challengeCooldownSeconds: rules.challengeCooldownSeconds,
      timeLimitSeconds: rules.timeLimitSeconds,
      defenseConstant: rules.defenseConstant,
      speedBase: rules.speedBase,
      recommendedPowerMargin: rules.recommendedPowerMargin,
    },
```

- [ ] **Step 4: 改两处类型**

`backend/src/db/schema.ts` 里 `contentGlobals` 的 `combat: jsonb("combat").$type<{...}>()`，泛型换成：

```ts
  combat: jsonb("combat").$type<{
    minInterval?: number;
    challengeCooldownSeconds?: number;
    timeLimitSeconds?: number;
    defenseConstant?: number;
    speedBase?: number;
    recommendedPowerMargin?: number;
  }>(),
```

`backend/src/modules/content/validate.ts` 里 `ContentSnapshot.globals.combat` 换成：

```ts
    combat?: {
      minInterval?: number;
      challengeCooldownSeconds?: number;
      timeLimitSeconds?: number;
      defenseConstant?: number;
      speedBase?: number;
      recommendedPowerMargin?: number;
    };
```

只改类型，不生成迁移（`combat` 本来就是 jsonb）。

- [ ] **Step 5: 跑测试，确认通过**

```bash
cd backend && npm test -- src/modules/content/rules.test.ts
```

预期：4 个测试通过。

---

### Task 3: 战斗调用方和测试夹具

**Files:**
- Modify: `backend/src/modules/loop/actions.ts`（`battleConfigOf`）
- Modify: `backend/src/modules/content/trial.ts`
- Modify 夹具：`backend/src/e2e/core-loop.test.ts`、`backend/src/plugins/client-version.test.ts`、`backend/src/modules/loop/equip.test.ts`、`backend/src/modules/loop/skill-level.test.ts`、`backend/src/modules/loop/power-explain.test.ts`、`backend/src/modules/content/puppet.test.ts`

- [ ] **Step 1: 改 `actions.ts` 的 `battleConfigOf`**

```ts
export function battleConfigOf(world: ContentSnapshot) {
  const rules = readGameRules(world);
  return {
    timeLimitSeconds: rules.timeLimitSeconds,
    defenseConstant: rules.defenseConstant,
  };
}
```

`challengeStage` 里调用 `simulateBattle(..., battleConfigOf(world))` 的地方不用改。

- [ ] **Step 2: 改 `trial.ts`**

把原来算 `playerHit`、`bossHit`、`playerHits` 的三行：

```ts
    const playerHit = hitDamage(player.attack, boss.defense, config.playerDefenseFactor, 1, config.playerDamageFloor);
    const bossHit = hitDamage(boss.attack, player.defense, config.bossDefenseFactor, 1, config.bossDamageFloor);
    const playerHits = Math.ceil(boss.hp / playerHit);
```

换成：

```ts
    const playerHit = hitDamage(player.attack, boss.defense, config.defenseConstant);
    const bossHit = hitDamage(boss.attack, player.defense, config.defenseConstant);
    const playerHits = playerHit > 0 ? Math.ceil(boss.hp / playerHit) : null;
```

再把返回对象里的 `playerKillSeconds: playerHits * player.interval,` 换成：

```ts
      playerKillSeconds: playerHits == null ? null : playerHits * player.interval,
```

`TrialPuppetResult` 里 `playerHits`、`playerKillSeconds` 本来就是 `number | null`，类型不用改。

- [ ] **Step 3: 改 6 个测试文件里的规则夹具**

每个文件里 `combat: { ... }` 对象中有这四行（数值可能不同）：

```ts
          playerDefenseFactor: 0.4,
          bossDefenseFactor: 0.5,
          playerDamageFloor: 1,
          bossDamageFloor: 0,
```

删掉这四行，在同一个 `combat` 对象里加上：

```ts
          defenseConstant: 1,
          recommendedPowerMargin: 1.05,
```

其余字段（`minInterval`、`challengeCooldownSeconds`、`timeLimitSeconds`、`speedBase`）和 `powerWeights` 原样保留。改完用下面的命令确认后端里已经没有旧字段：

```bash
cd backend && rg -n "DefenseFactor|DamageFloor" src
```

预期：没有输出。

- [ ] **Step 4: 跑受影响的测试**

```bash
cd backend && npm test -- src/modules/content/puppet.test.ts src/e2e/core-loop.test.ts src/plugins/client-version.test.ts src/modules/loop
```

预期：全部通过。`puppet.test.ts` 里的首领防御是 0，新旧公式在防御为 0 时伤害相同，所以 `playerKillSeconds: 45, bossKillSeconds: 7.5` 和胜负断言不用改。如果这里有失败，先读失败信息，不要改断言去凑结果；断言确实要改时，在最终汇报里写明原因。

- [ ] **Step 5: 类型检查**

```bash
cd backend && npm run typecheck
```

预期：没有错误。

---

### Task 4: Boss 战力

**Files:**
- Modify: `backend/src/modules/combat/stats.ts`
- Test: `backend/src/modules/combat/stats.test.ts`

- [ ] **Step 1: 在 `stats.test.ts` 里加测试**

第 2 行的 import 改成：

```ts
import { bossPower, computePower, sumReachedRealmStats } from "./stats.js";
```

在文件末尾的 `});` 之前（`describe("combat power", ...)` 内部）加：

```ts
  it("turns the boss interval into an equivalent speed", () => {
    const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
    const boss = { attack: 100, defense: 100, hp: 333, interval: 1.25 };
    expect(bossPower(boss, { baseInterval: 1.5, speedBase: 100, weights })).toBeCloseTo(998.35, 6);
  });

  it("treats a boss slower than the realm interval as zero speed", () => {
    const weights = { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 };
    const boss = { attack: 100, defense: 100, hp: 333, interval: 2 };
    expect(bossPower(boss, { baseInterval: 1.5, speedBase: 100, weights })).toBeCloseTo(946.35, 6);
  });
```

算式：等效速度 = 100 × (1.5 ÷ 1.25 − 1) = 20；战力 = 100×4.7 + 100×1.6 + 333×0.95 + 20×2.6 = 998.35。

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd backend && npm test -- src/modules/combat/stats.test.ts
```

预期：`bossPower` 不存在，导入失败。

- [ ] **Step 3: 在 `stats.ts` 的 `computePower` 后面加**

```ts
export function bossPower(
  boss: { attack: number; defense: number; hp: number; interval: number },
  input: { baseInterval: number; speedBase: number; weights: { attack: number; defense: number; hp: number; speed: number } },
): number {
  const speed = Math.max(0, input.speedBase * (input.baseInterval / boss.interval - 1));
  const weights = input.weights;
  return boss.attack * weights.attack + boss.defense * weights.defense + boss.hp * weights.hp + speed * weights.speed;
}
```

这里返回不取整的值，取整在乘完推荐战力倍数之后做。

- [ ] **Step 4: 跑测试，确认通过**

```bash
cd backend && npm test -- src/modules/combat/stats.test.ts
```

---

### Task 5: 关卡推荐战力

**Files:**
- Create: `backend/src/modules/content/stage-power.ts`
- Create: `backend/src/modules/content/stage-power.test.ts`

- [ ] **Step 1: 写失败测试 `stage-power.test.ts`**

```ts
import { describe, expect, it } from "vitest";
import { stagePowerErrors, stageRecommendedPower } from "./stage-power.js";
import type { ContentSnapshot } from "./validate.js";

type Boss = { attack: number; defense: number; hp: number; interval: number };

function realm(slug: string, displayName: string, sortOrder: number, baseInterval: number | undefined) {
  return {
    slug,
    displayName,
    sortOrder,
    nextRealmSlug: null,
    tickSeconds: 1,
    gainPerTick: 1,
    breakthroughCost: 10,
    minRateBp: 10000,
    baseRateBp: 10000,
    maxRateBp: 10000,
    requiredStageSlug: null,
    recommendedPower: 0,
    baseInterval,
    enabled: true,
  };
}

function stage(slug: string, displayName: string, requiredRealmOrder: number, boss: Boss | null) {
  return {
    slug,
    displayName,
    requiredRealmOrder,
    nextStageSlug: null,
    bossDropTableSlug: "d",
    idleDropTableSlug: "d",
    firstClearDropTableSlug: "d",
    bossHp: 1,
    bossInterval: 1,
    bosses: boss ? [{ name: "首领", ...boss, drops: [] }] : [],
    recommendedPower: 0,
    enabled: true,
  };
}

const weak = { attack: 100, defense: 100, hp: 333, interval: 1.25 };
const strong = { attack: 120, defense: 120, hp: 400, interval: 1.25 };

function world(patch: Partial<ContentSnapshot> = {}): ContentSnapshot {
  return {
    globals: {
      startingRealmSlug: "qi",
      starterItems: [],
      offlineCapSeconds: 3600,
      bagCapacity: 20,
      powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
      combat: { minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 20, defenseConstant: 1, speedBase: 100, recommendedPowerMargin: 1.05 },
    },
    realms: [realm("qi", "炼气", 1, 1.5), realm("zhuji", "筑基", 2, 1.5)],
    stages: [stage("stage_a", "后山", 1, weak), stage("stage_b", "山门", 2, strong)],
    dropTables: [],
    items: [],
    skills: [],
    ...patch,
  };
}

describe("stage recommended power", () => {
  it("multiplies the first boss power by the margin", () => {
    const current = world();
    expect(stageRecommendedPower(current, current.stages[0]!)).toBe(1048);
    expect(stageRecommendedPower(current, current.stages[1]!)).toBe(1247);
  });

  it("accepts power that rises with the realm", () => {
    expect(stagePowerErrors(world())).toEqual([]);
  });

  it("rejects a higher realm stage that is not stronger", () => {
    const errors = stagePowerErrors(world({ stages: [stage("stage_a", "后山", 1, weak), stage("stage_b", "山门", 2, weak)] }));
    expect(errors).toEqual([{ slug: "stage_b", message: "推荐战力 1048 不高于低一个境界的关卡「后山」的 1048" }]);
  });

  it("does not compare stages on the same realm", () => {
    expect(stagePowerErrors(world({ stages: [stage("stage_a", "后山", 1, strong), stage("stage_b", "山门", 1, weak)] }))).toEqual([]);
  });

  it("skips stages without a boss", () => {
    expect(stagePowerErrors(world({ stages: [stage("stage_a", "后山", 1, null)] }))).toEqual([]);
  });

  it("reports a realm without a base interval", () => {
    const errors = stagePowerErrors(world({ realms: [realm("qi", "炼气", 1, undefined), realm("zhuji", "筑基", 2, 1.5)] }));
    expect(errors).toEqual([{ slug: "stage_a", message: "请先在后台填写境界「炼气」的基础出手间隔" }]);
  });

  it("reports a stage whose realm is gone", () => {
    const errors = stagePowerErrors(world({ stages: [stage("stage_a", "后山", 9, weak)] }));
    expect(errors).toEqual([{ slug: "stage_a", message: "关卡「后山」的境界不存在" }]);
  });

  it("reports missing rules instead of guessing", () => {
    const current = world();
    const errors = stagePowerErrors({ ...current, globals: { ...current.globals, combat: undefined } });
    expect(errors[0]?.message.startsWith("请先在后台填写：")).toBe(true);
  });
});
```

算式：后山 998.35 × 1.05 = 1048.27 → 1048；山门 = 120×4.7 + 120×1.6 + 400×0.95 + 20×2.6 = 1188，× 1.05 = 1247.4 → 1247。

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd backend && npm test -- src/modules/content/stage-power.test.ts
```

预期：模块不存在。

- [ ] **Step 3: 新建 `stage-power.ts`**

```ts
import { AppError } from "../../shared/errors.js";
import { bossPower } from "../combat/stats.js";
import { readGameRules } from "./rules.js";
import type { ContentSnapshot } from "./validate.js";

type Stage = ContentSnapshot["stages"][number];

function priceStage(world: ContentSnapshot, stage: Stage): { realmOrder: number; power: number } {
  const boss = stage.bosses?.[0];
  if (!boss) {
    throw new AppError("INVALID_INPUT", "这个关卡还没有首领");
  }
  const name = stage.displayName ?? stage.slug;
  const realm = world.realms.find((row) => row.sortOrder === stage.requiredRealmOrder);
  if (!realm || realm.sortOrder === undefined) {
    throw new AppError("INVALID_INPUT", `关卡「${name}」的境界不存在`);
  }
  if (realm.baseInterval === undefined || realm.baseInterval <= 0) {
    throw new AppError("INVALID_INPUT", `请先在后台填写境界「${realm.displayName ?? realm.slug}」的基础出手间隔`);
  }
  const rules = readGameRules(world);
  const raw = bossPower(boss, { baseInterval: realm.baseInterval, speedBase: rules.speedBase, weights: rules.powerWeights });
  return { realmOrder: realm.sortOrder, power: Math.round(raw * rules.recommendedPowerMargin) };
}

export function stageRecommendedPower(world: ContentSnapshot, stage: Stage): number {
  return priceStage(world, stage).power;
}

export function stagePowerErrors(world: ContentSnapshot): { slug: string; message: string }[] {
  const errors: { slug: string; message: string }[] = [];
  const priced: { stage: Stage; realmOrder: number; power: number }[] = [];
  for (const stage of world.stages) {
    if (!stage.bosses?.[0]) {
      continue;
    }
    try {
      priced.push({ stage, ...priceStage(world, stage) });
    } catch (cause) {
      if (!(cause instanceof AppError)) {
        throw cause;
      }
      errors.push({ slug: stage.slug, message: cause.message });
    }
  }
  const orders = [...new Set(priced.map((row) => row.realmOrder))].sort((left, right) => left - right);
  for (let index = 1; index < orders.length; index += 1) {
    const lower = priced.filter((row) => row.realmOrder === orders[index - 1]);
    const strongest = lower.reduce((best, row) => (row.power > best.power ? row : best));
    for (const row of priced.filter((candidate) => candidate.realmOrder === orders[index])) {
      if (row.power <= strongest.power) {
        errors.push({
          slug: row.stage.slug,
          message: `推荐战力 ${row.power} 不高于低一个境界的关卡「${strongest.stage.displayName ?? strongest.stage.slug}」的 ${strongest.power}`,
        });
      }
    }
  }
  return errors;
}
```

说明：
- 没有首领的关卡在递增检查里跳过，因为挑战时会单独报「这个关卡还没有首领」。
- 「低一个境界」指的是有关卡的、order 更小的相邻境界，中间没有关卡的境界不算。
- `priceStage` 里的 `catch` 只把错误收集成发布检查的报错文字，不吞错误，不换成默认值。

- [ ] **Step 4: 跑测试，确认通过**

```bash
cd backend && npm test -- src/modules/content/stage-power.test.ts
```

预期：8 个测试通过。如果 `AppError` 的 `message` 不是传入的中文文字，读 `backend/src/shared/errors.ts` 确认构造参数，按实际签名调整，不要改测试里的文字。

---

### Task 6: 发布检查

**Files:**
- Modify: `backend/src/modules/content/validate.ts`
- Test: `backend/src/modules/content/validate.test.ts`

- [ ] **Step 1: 在 `validate.test.ts` 末尾的 `describe` 里加测试**

```ts
  it("rejects a higher realm stage whose recommended power is not higher", () => {
    const base = draft().realms[0]!;
    const boss = { name: "首领", attack: 100, defense: 100, hp: 333, interval: 1.25, drops: [] };
    const stageOf = (slug: string, next: string | null, order: number) => ({
      slug,
      displayName: slug,
      nextStageSlug: next,
      requiredRealmOrder: order,
      bossDropTableSlug: "drop_a",
      idleDropTableSlug: "drop_a",
      firstClearDropTableSlug: "drop_a",
      bossHp: 1,
      bossInterval: 1,
      bosses: [boss],
      recommendedPower: 0,
      enabled: true,
    });
    const result = validateContent(
      draft({
        globals: {
          startingRealmSlug: "mortal",
          starterItems: [],
          offlineCapSeconds: 3600,
          bagCapacity: 20,
          powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
          combat: { minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 20, defenseConstant: 1, speedBase: 100, recommendedPowerMargin: 1.05 },
        },
        realms: [
          { ...base, slug: "mortal", sortOrder: 1, nextRealmSlug: "qi", baseInterval: 1.5 },
          { ...base, slug: "qi", sortOrder: 2, nextRealmSlug: null, baseInterval: 1.5 },
        ],
        stages: [stageOf("stage_a", "stage_b", 1), stageOf("stage_b", null, 2)],
        dropTables: [{ slug: "drop_a", entries: [] }],
      }),
    );
    expect(result.errors).toEqual([
      { kind: "stage", slug: "stage_b", field: "bosses", message: "推荐战力 1048 不高于低一个境界的关卡「stage_a」的 1048" },
    ]);
  });
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd backend && npm test -- src/modules/content/validate.test.ts
```

预期：新测试失败，`errors` 是空数组。

- [ ] **Step 3: 改 `validate.ts`**

文件顶部加导入：

```ts
import { stagePowerErrors } from "./stage-power.js";
```

在 `for (const stage of draft.stages) { ... }` 那个循环（检查掉落表、Boss 气血和出手间隔）结束之后，紧接着加：

```ts
  for (const problem of stagePowerErrors(draft)) {
    push("stage", problem.slug, "bosses", problem.message);
  }
```

`stage-power.ts` 对 `validate.ts` 只做类型导入（`import type`），不会形成运行时循环依赖。

- [ ] **Step 4: 跑测试，确认通过**

```bash
cd backend && npm test -- src/modules/content/validate.test.ts src/modules/content/snapshot.test.ts src/e2e/core-loop.test.ts src/plugins/client-version.test.ts
```

预期：全部通过。`snapshot.test.ts` 和原有 `validate.test.ts` 用例里的关卡没有首领，会被跳过；`core-loop.test.ts` 只有一个带首领的关卡，不触发递增比较。

---

### Task 7: 后台关卡列表显示推荐战力

**Files:**
- Modify: `backend/src/modules/content/ops-content.ts`
- Create: `backend/src/modules/content/stage-list-power.test.ts`

- [ ] **Step 1: 写失败测试 `stage-list-power.test.ts`**

```ts
import { describe, expect, it } from "vitest";
import { contentGlobals, contentRealms } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { createOpsStage, listOpsStages } from "./ops-content.js";

describe("stage list recommended power", () => {
  it("shows the computed power or the reason it cannot be computed", async () => {
    await withDb(async (db) => {
      await db.insert(contentRealms).values({ slug: "2", displayName: "练气", sortOrder: 2, nextRealmSlug: null, baseInterval: 1.5 });
      const armed = await createOpsStage(
        db,
        { displayName: "后山", realmCode: 2, bosses: [{ name: "木傀", attack: 100, defense: 100, hp: 333, interval: 1.25, drops: [] }] },
        null,
      );
      const empty = await createOpsStage(db, { displayName: "山门", realmCode: 2, bosses: [] }, null);

      const before = await listOpsStages(db);
      expect(before.find((row) => row.id === armed.id)).toMatchObject({ recommendedPower: null });
      expect(before.find((row) => row.id === armed.id)?.powerProblem?.startsWith("请先在后台填写：")).toBe(true);

      await db.insert(contentGlobals).values({
        id: 1,
        startingRealmSlug: "2",
        offlineCapSeconds: 3600,
        bagCapacity: 20,
        powerWeights: { attack: 4.7, defense: 1.6, hp: 0.95, speed: 2.6 },
        combat: { minInterval: 0.5, challengeCooldownSeconds: 0, timeLimitSeconds: 20, defenseConstant: 1, speedBase: 100, recommendedPowerMargin: 1.05 },
      });
      const after = await listOpsStages(db);
      expect(after.find((row) => row.id === armed.id)).toMatchObject({ recommendedPower: 1048, powerProblem: null });
      expect(after.find((row) => row.id === empty.id)).toMatchObject({ recommendedPower: null, powerProblem: "这个关卡还没有首领" });
    });
  });
});
```

- [ ] **Step 2: 跑测试，确认失败**

```bash
cd backend && npm test -- src/modules/content/stage-list-power.test.ts
```

预期：`recommendedPower` 为 `undefined`。

- [ ] **Step 3: 改 `ops-content.ts`**

顶部加导入：

```ts
import { loadDraftSnapshot } from "./snapshot.js";
import { stageRecommendedPower } from "./stage-power.js";
import type { ContentSnapshot } from "./validate.js";
```

在 `stageView` 函数前面加：

```ts
function stagePowerOf(world: ContentSnapshot, slug: string): { recommendedPower: number | null; powerProblem: string | null } {
  const stage = world.stages.find((candidate) => candidate.slug === slug);
  if (!stage) {
    throw new AppError("INTERNAL");
  }
  try {
    return { recommendedPower: stageRecommendedPower(world, stage), powerProblem: null };
  } catch (cause) {
    if (cause instanceof AppError) {
      return { recommendedPower: null, powerProblem: cause.message };
    }
    throw cause;
  }
}
```

`stageView` 增加第五个参数，并在返回对象里展开：

```ts
function stageView(
  row: typeof contentStages.$inferSelect,
  realms: { slug: string; displayName: string; sortOrder: number }[],
  items: { slug: string; displayName: string }[],
  skills: { slug: string; displayName: string }[],
  power: { recommendedPower: number | null; powerProblem: string | null },
) {
```

```ts
  return {
    id: row.slug,
    displayName: row.displayName,
    realmCode: row.requiredRealmOrder,
    realmName: realm?.displayName ?? "",
    realmMissing: realm == null,
    bosses,
    ...power,
  };
```

`listOpsStages` 改成：

```ts
export async function listOpsStages(db: Db) {
  const [stages, realms, items, skills, world] = await Promise.all([
    db.select().from(contentStages),
    db.select().from(contentRealms),
    db.select().from(contentItems),
    db.select().from(contentSkills),
    loadDraftSnapshot(db),
  ]);
  return stages
    .sort((left, right) => left.requiredRealmOrder - right.requiredRealmOrder || left.displayName.localeCompare(right.displayName, "zh"))
    .map((row) => stageView(row, realms, items, skills, stagePowerOf(world, row.slug)));
}
```

如果 `stageView` 在文件里还有别的调用处，用 `rg -n "stageView\(" backend/src` 找出来，同样传入 `stagePowerOf(...)` 的结果。

- [ ] **Step 4: 跑测试，确认通过**

```bash
cd backend && npm test -- src/modules/content/stage-list-power.test.ts src/modules/content/ops-content.test.ts
```

预期：全部通过。

---

### Task 8: 后台页面

**Files:**
- Modify: `admin/src/views/RulesView.vue`
- Modify: `admin/src/views/StagesView.vue`

- [ ] **Step 1: 规则页说明文字**

`RulesView.vue` 顶部 `<p>` 的内容换成：

```html
    <p>
      这里的数会直接被游戏使用。没填的话，对应功能会失败，不会再用代码里的数顶上。出手间隔 = 境界的基础出手间隔 × 速度基数 ÷（速度基数 + 速度），再和最短出手间隔比，取更大的。每下伤害 = 攻击 × 攻击 ÷（攻击 + k × 对方防御），攻击和防御一样时挡掉一半。战力 = 攻击×权重 + 防御×权重 + 气血×权重 + 速度×权重。关卡推荐战力 = 第一个首领的战力 × 推荐战力倍数，首领的出手间隔先换成等效速度再算。
    </p>
```

- [ ] **Step 2: 规则页表单项**

删除「玩家攻击时的防御比例」「首领攻击时的防御比例」「玩家每下最少伤害」「首领每下最少伤害」四个 `<el-form-item>`。

在「单场时限（秒）」后面加：

```html
      <el-form-item label="防御常数 k">
        <el-input-number v-model="form.defenseConstant" :min="0" :step="0.1" :controls="false" />
      </el-form-item>
```

在「战力里速度的权重」后面加：

```html
      <el-form-item label="推荐战力倍数">
        <el-input-number v-model="form.recommendedPowerMargin" :min="0" :step="0.01" :controls="false" />
      </el-form-item>
```

- [ ] **Step 3: 规则页脚本**

`type Rules` 里删掉 `playerDefenseFactor`、`bossDefenseFactor`、`playerDamageFloor`、`bossDamageFloor`，加上：

```ts
  defenseConstant: number | null;
  recommendedPowerMargin: number | null;
```

`keys` 数组和 `form` 的初始值里做同样的增删（新增 `"defenseConstant"`、`"recommendedPowerMargin"`，初始值 `undefined`）。

- [ ] **Step 4: 关卡列表加「推荐战力」列**

`StagesView.vue` 表格里「首领」列后面加：

```html
      <el-table-column label="推荐战力" width="220">
        <template #default="{ row }">
          <span v-if="row.powerProblem" class="hint">{{ row.powerProblem }}</span>
          <span v-else>{{ row.recommendedPower }}</span>
        </template>
      </el-table-column>
```

`type Stage` 里加：

```ts
  recommendedPower: number | null;
  powerProblem: string | null;
```

页面顶部说明 `<p>` 末尾补一句：`推荐战力由服务器按第一个首领自动算出，不能手填。`

- [ ] **Step 5: 试打结果文案**

把下面这段：

```html
          <p>
            每下打掉 {{ round(result.playerHit ?? 0) }}，要打 {{ result.playerHits }} 下，约
            {{ round(result.playerKillSeconds ?? 0) }} 秒打死首领
          </p>
          <p v-if="result.bossHits == null">首领破不了这个人偶的防，打不死</p>
```

换成：

```html
          <p v-if="result.playerHits == null">人偶攻击是 0，打不动首领</p>
          <p v-else>
            每下打掉 {{ round(result.playerHit ?? 0) }}，要打 {{ result.playerHits }} 下，约
            {{ round(result.playerKillSeconds ?? 0) }} 秒打死首领
          </p>
          <p v-if="result.bossHits == null">首领攻击是 0，打不动这个人偶</p>
```

- [ ] **Step 6: 后台检查**

```bash
cd admin && npm run build && npm run lint
```

预期：没有错误。再执行 `rg -n "DefenseFactor|DamageFloor" admin/src`，预期没有输出。

---

### Task 9: 文档

**Files:**
- Modify: `docs/roadmap/02-target-architecture.md`
- Create: `docs/changes/2026-10-12/combat-power-phase1.md`

- [ ] **Step 1: 改架构文档的伤害公式**

`docs/roadmap/02-target-architecture.md` 里「挑战流程」第 2 步的代码块（从「玩家每击伤害 = max(1, …」到「常数 0.4 / 0.5 放进全局配置 …」）换成：

```text
每击伤害 = 攻击 × 攻击 ÷ (攻击 + k × 对方防御)，k 是全局配置 combat.defenseConstant
按时间轴推进：双方各按自己的出手间隔出手，先把对方气血打到 0 的一方胜。
同一时刻双方同时出手时，玩家先手。
超过 timeLimitSeconds 仍未分胜负 → 判负（提示“输出不足”）。
```

同一文件里「警告（不阻止发布…）」那条中的「某关卡推荐战力低于前一关」删掉，并在发布检查的错误列表里加一条：「高一个境界的关卡，推荐战力要高于低一个境界的所有关卡（推荐战力按第一个首领自动算出）」。

- [ ] **Step 2: 写修改记录 `docs/changes/2026-10-12/combat-power-phase1.md`**

```markdown
# 数值方案一第一阶段：战斗与战力

## 决定

- 伤害改为「攻击 × 攻击 ÷ (攻击 + k × 对方防御)」，k 在规则页填写，第一版填 1。
- 去掉规则里的玩家/首领防御比例和玩家/首领每下最少伤害。
- 关卡推荐战力由服务器按第一个首领自动算出：首领战力 × 推荐战力倍数。首领的出手间隔按所属境界的基础出手间隔换成等效速度。
- 发布时，高一个境界的关卡推荐战力必须高于低一个境界的关卡。
- 基础出手间隔继续放在境界上，不挪到规则页。

## 改动位置

- 后端：`combat/battle.ts`、`combat/stats.ts`、`content/rules.ts`、`content/stage-power.ts`、`content/validate.ts`、`content/ops-content.ts`、`content/trial.ts`、`loop/actions.ts`。
- 后台：规则页、关卡页。
- 文档：`docs/superpowers/specs/2026-10-12-numeric-scheme-design.md`、`docs/roadmap/02-target-architecture.md`。

## 还没做

- 规则页的新值要管理员手动填写并保存，保存前游戏会提示缺少「防御常数 k、推荐战力倍数」。
- 功法百分比、装备模板、掉落改动在第二到第四阶段。
- 境界表、装备、首领的第一版数值还没填进后台。
```

---

### Task 10: 全量验证

**Files:** 无新改动

- [ ] **Step 1: 后端全量**

```bash
cd backend && npm test && npm run typecheck && npm run lint
```

预期：和 Task 0 的基线相比没有新增失败。

- [ ] **Step 2: 后台**

```bash
cd admin && npm run build && npm run lint
```

- [ ] **Step 3: 检查残留和 diff**

```bash
rg -n "DefenseFactor|DamageFloor|最少伤害|防御比例" backend/src admin/src
git status --short
git diff --stat
```

预期：第一条没有输出。`git status` 里新增的文件只有本计划列出的那些。

- [ ] **Step 4: 手工验证（需要本机后端和后台在跑）**

1. 打开后台规则页，按「本阶段改完后的规则字段」表填值并保存，确认保存成功、刷新后值还在。
2. 打开关卡页，确认每个有首领的关卡显示推荐战力；境界没填基础出手间隔的关卡显示对应提示。
3. 在关卡页对任一首领点「试打」，确认结果能显示，文案没有「破不了防」。
4. 用手机或接口挑战一关，确认能正常打完。

- [ ] **Step 5: 汇报**

汇报里写清楚：改了哪些文件；实际运行了哪些命令、结果如何；基线里原本就失败的测试；哪些手工验证没做。**不要提交**，提醒用户自己检查 diff 后提交（工作区里还有用户自己的未提交改动）。
