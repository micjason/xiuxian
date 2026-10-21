import { and, eq, gt, sql } from "drizzle-orm";
import { withTransaction, type Tx } from "../../db/tx.js";
import { enhanceExpMigrations, playerStates } from "../../db/schema.js";
import { essenceRules, migratedEssence, readEnhanceRules } from "../content/enhance.js";
import type { ContentSnapshot } from "../content/validate.js";
import type { Db } from "../operations/record.js";
import { addStack } from "./bag.js";

/**
 * 第五批：一次性把玩家剩余的「强化经验」换成「炼器精粹」（SPEC_Q §17.3）。
 * - 比例在后台「装备强化 · 炼器精粹」里配（migrationRatioBp，默认 7000 = 0.7，向上取整；为什么不会让人变弱见
 *   content/enhance.ts STARTING_ESSENCE_RULES 和 docs/changes/2026-10-22/salvage-essence.md）。
 * - 幂等：enhance_exp_migrations 以 player_id 为主键，每人只迁一次；迁移和扣经验、加精粹在同一个事务里。
 * - 什么时候做：玩家下一次结算（任何 /me/* 请求）时顺手做；后台也可以一键给所有人做完。
 * - 已强化装备的等级不变（不动 player_items.enhance_level）。
 */
export async function migratePlayerEnhanceExp(
  tx: Tx,
  world: ContentSnapshot,
  playerId: string,
  state: { enhanceExp: number },
  now: Date,
): Promise<{ enhanceExp: number; essence: number } | null> {
  if (!(state.enhanceExp > 0)) {
    return null;
  }
  let rules;
  try {
    rules = readEnhanceRules(world);
    essenceRules(rules);
  } catch {
    // 还没配精粹规则：先不迁（经验原样留着，配好后下次结算再迁）
    return null;
  }
  const essence = migratedEssence(rules, state.enhanceExp);
  const itemSlug = essenceRules(rules).itemSlug;
  if (!world.items.some((item) => item.slug === itemSlug)) {
    return null;
  }
  const [logged] = await tx
    .insert(enhanceExpMigrations)
    .values({ playerId, enhanceExp: state.enhanceExp, essence, ratioBp: essenceRules(rules).migrationRatioBp, itemSlug, migratedAt: now })
    .onConflictDoNothing({ target: enhanceExpMigrations.playerId })
    .returning({ playerId: enhanceExpMigrations.playerId });
  if (!logged) {
    // 已经迁过（不会再有新的强化经验进来；万一有，原样留着，不重复发精粹）
    return null;
  }
  await addStack(tx, playerId, itemSlug, essence, "migrate:enhance_exp", now);
  await tx.update(playerStates).set({ enhanceExp: 0 }).where(eq(playerStates.playerId, playerId));
  return { enhanceExp: state.enhanceExp, essence };
}

/** 后台一键：给所有还有强化经验、没迁过的玩家做迁移（每人一个事务，可重复点）。 */
export async function migrateAllEnhanceExp(db: Db, world: ContentSnapshot, now: Date) {
  const pending = await db
    .select({ playerId: playerStates.playerId })
    .from(playerStates)
    .where(and(gt(playerStates.enhanceExp, 0), sql`not exists (select 1 from ${enhanceExpMigrations} m where m.player_id = ${playerStates.playerId})`));
  let migrated = 0;
  for (const row of pending) {
    const done = await withTransaction(db, async (tx) => {
      const [state] = await tx.select({ enhanceExp: playerStates.enhanceExp }).from(playerStates).where(eq(playerStates.playerId, row.playerId)).for("update").limit(1);
      return state ? migratePlayerEnhanceExp(tx, world, row.playerId, state, now) : null;
    });
    if (done) {
      migrated += 1;
    }
  }
  return { migrated, ...(await enhanceExpMigrationStatus(db)) };
}

/** 迁移情况（后台「装备强化」页显示）。 */
export async function enhanceExpMigrationStatus(db: Db) {
  const [done] = await db
    .select({ players: sql<number>`count(*)::int`, enhanceExp: sql<number>`coalesce(sum(${enhanceExpMigrations.enhanceExp}), 0)::bigint`, essence: sql<number>`coalesce(sum(${enhanceExpMigrations.essence}), 0)::bigint` })
    .from(enhanceExpMigrations);
  const [left] = await db
    .select({ players: sql<number>`count(*)::int` })
    .from(playerStates)
    .where(and(gt(playerStates.enhanceExp, 0), sql`not exists (select 1 from ${enhanceExpMigrations} m where m.player_id = ${playerStates.playerId})`));
  return {
    migratedPlayers: Number(done?.players ?? 0),
    migratedEnhanceExp: Number(done?.enhanceExp ?? 0),
    migratedEssence: Number(done?.essence ?? 0),
    pendingPlayers: Number(left?.players ?? 0),
  };
}
