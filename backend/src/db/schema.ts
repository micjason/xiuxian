import type { OptionalRuleValues, StageMonster, MonsterDropOverride, BossRewardEntry, BossRepeatReward, DesignatedDrop, SetTier } from "../modules/content/combat-types.js";
import type { Tuning } from "../modules/content/tuning.js";
import { sql } from "drizzle-orm";
import {
  bigint,
  boolean,
  doublePrecision,
  index,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";

export const actorType = pgEnum("actor_type", ["player", "admin"]);
export const releaseStatus = pgEnum("release_status", ["draft", "published", "archived"]);
export const operationAction = pgEnum("operation_action", [
  "login",
  "settle",
  "breakthrough",
  "publish",
  "repair",
]);
export const operationResult = pgEnum("operation_result", ["success", "failure"]);

export const players = pgTable("players", {
  id: uuid("id").primaryKey().defaultRandom(),
  username: text("username").notNull().unique(),
  usernameLower: text("username_lower").notNull().default("").unique(),
  passwordHash: text("password_hash").notNull(),
  status: text("status").notNull().default("active"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  lastLoginAt: timestamp("last_login_at", { withTimezone: true }),
});

export const admins = pgTable("admins", {
  id: uuid("id").primaryKey().defaultRandom(),
  username: text("username").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  role: text("role").notNull().default("owner"),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  lastLoginAt: timestamp("last_login_at", { withTimezone: true }),
});

export const sessions = pgTable("sessions", {
  id: uuid("id").primaryKey().defaultRandom(),
  tokenHash: text("token_hash").notNull().unique(),
  actorType: actorType("actor_type").notNull(),
  actorId: uuid("actor_id").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
  lastSeenAt: timestamp("last_seen_at", { withTimezone: true }),
  revokedAt: timestamp("revoked_at", { withTimezone: true }),
});

export const contentReleases = pgTable("content_releases", {
  id: uuid("id").primaryKey().defaultRandom(),
  status: releaseStatus("status").notNull(),
  offlineCapSeconds: doublePrecision("offline_cap_seconds").notNull(),
  publishedAt: timestamp("published_at", { withTimezone: true }),
  note: text("note"),
});

export const realms = pgTable(
  "realms",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    releaseId: uuid("release_id")
      .notNull()
      .references(() => contentReleases.id),
    slug: text("slug").notNull(),
    displayName: text("display_name").notNull(),
    sortOrder: doublePrecision("sort_order").notNull(),
    gainPerSecond: doublePrecision("gain_per_second").notNull(),
    breakthroughCost: doublePrecision("breakthrough_cost").notNull(),
    nextSlug: text("next_slug"),
    attack: doublePrecision("attack").notNull(),
    defense: doublePrecision("defense").notNull(),
    hp: doublePrecision("hp").notNull(),
    speed: doublePrecision("speed").notNull(),
  },
  (table) => [unique("realms_release_slug").on(table.releaseId, table.slug)],
);

export const skills = pgTable(
  "skills",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    releaseId: uuid("release_id")
      .notNull()
      .references(() => contentReleases.id),
    slug: text("slug").notNull(),
    displayName: text("display_name").notNull(),
    description: text("description").notNull(),
    role: text("role").notNull(),
    attack: doublePrecision("attack").notNull(),
    defense: doublePrecision("defense").notNull(),
    hp: doublePrecision("hp").notNull(),
    speed: doublePrecision("speed").notNull(),
    cultivateBonus: doublePrecision("cultivate_bonus").notNull(),
    minRealmOrder: doublePrecision("min_realm_order").notNull(),
    prerequisiteSlugs: jsonb("prerequisite_slugs").$type<string[]>().notNull().default([]),
  },
  (table) => [unique("skills_release_slug").on(table.releaseId, table.slug)],
);

export const items = pgTable(
  "items",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    releaseId: uuid("release_id")
      .notNull()
      .references(() => contentReleases.id),
    slug: text("slug").notNull(),
    displayName: text("display_name").notNull(),
    description: text("description").notNull(),
    kind: text("kind").notNull(),
    quality: text("quality").notNull(),
    slot: text("slot"),
    attack: doublePrecision("attack").notNull(),
    defense: doublePrecision("defense").notNull(),
    hp: doublePrecision("hp").notNull(),
    speed: doublePrecision("speed").notNull(),
    grantable: boolean("grantable").notNull().default(false),
    skillSlug: text("skill_slug"),
  },
  (table) => [unique("items_release_slug").on(table.releaseId, table.slug)],
);

export const popupTypes = pgTable("popup_types", {
  slug: text("slug").primaryKey(),
  priority: integer("priority").notNull(),
  enabled: boolean("enabled").notNull().default(true),
  template: text("template").notNull(),
});

export const announcements = pgTable("announcements", {
  id: uuid("id").primaryKey().defaultRandom(),
  title: text("title").notNull(),
  body: text("body").notNull(),
  enabled: boolean("enabled").notNull().default(false),
  enabledAt: timestamp("enabled_at", { withTimezone: true }),
});

export const noticeDismissals = pgTable(
  "notice_dismissals",
  {
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    noticeId: text("notice_id").notNull(),
    dismissedAt: timestamp("dismissed_at", { withTimezone: true }).notNull(),
  },
  (table) => [primaryKey({ columns: [table.playerId, table.noticeId] })],
);

export const playerNotices = pgTable(
  "player_notices",
  {
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    noticeId: text("notice_id").notNull(),
    type: text("type").notNull(),
    priority: integer("priority").notNull(),
    template: text("template").notNull(),
    triggeredAt: timestamp("triggered_at", { withTimezone: true }).notNull(),
    payload: jsonb("payload").notNull(),
  },
  (table) => [primaryKey({ columns: [table.playerId, table.noticeId] })],
);

export const contentVersions = pgTable("content_versions", {
  version: integer("version").primaryKey().generatedAlwaysAsIdentity(),
  snapshot: jsonb("snapshot").notNull(),
  checksum: text("checksum").notNull(),
  note: text("note").notNull(),
  publishedBy: uuid("published_by"),
  publishedAt: timestamp("published_at", { withTimezone: true }).notNull(),
  sourceVersion: integer("source_version"),
});

export const contentCurrent = pgTable("content_current", {
  id: integer("id").primaryKey().default(1),
  version: integer("version").notNull(),
});

export const contentKnownSlugs = pgTable(
  "content_known_slugs",
  {
    kind: text("kind").notNull(),
    slug: text("slug").notNull(),
  },
  (table) => [primaryKey({ columns: [table.kind, table.slug] })],
);

export const contentGlobals = pgTable("content_globals", {
  id: integer("id").primaryKey().default(1),
  startingRealmSlug: text("starting_realm_slug").notNull().default("mortal"),
  offlineCapSeconds: integer("offline_cap_seconds"),
  bagCapacity: integer("bag_capacity"),
  starterItems: jsonb("starter_items").notNull().default([]),
  powerWeights: jsonb("power_weights").$type<{ attack: number; defense: number; hp: number; speed: number }>(),
  combat: jsonb("combat").$type<{
    minInterval?: number;
    challengeCooldownSeconds?: number;
    timeLimitSeconds?: number;
    defenseConstant?: number;
    speedBase?: number;
    recommendedPowerMargin?: number;
    gearSpeedFactor?: number;
  } & OptionalRuleValues>(),
  gearQualityFactors: jsonb("gear_quality_factors").$type<{
    white: number;
    green: number;
    blue: number;
    purple: number;
    orange: number;
  }>(),
  enhance: jsonb("enhance").$type<{
    expBase: number;
    expGrowth: number;
    statGrowthBp: number;
    refundBp: number;
    qualities: Partial<
      Record<
        "white" | "green" | "blue" | "purple" | "orange",
        {
          cap: number;
          costMult: number;
          decomposeExp: number;
          expGrowth?: number;
          statGrowthBp?: number;
          breakthroughs: { level: number; materials: { itemSlug: string; count: number }[] }[];
        }
      >
    >;
  }>(),
  /** 配置概览里的默认数值（见 content/tuning.ts）；缺的项用代码默认值。 */
  tuning: jsonb("tuning").$type<Partial<Tuning>>(),
  artSlotRules: jsonb("art_slot_rules").$type<{ minRealmOrder: number; slots: number }[]>(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentRealms = pgTable("content_realms", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  majorName: text("major_name").notNull().default(""),
  majorKey: text("major_key"),
  sortOrder: integer("sort_order").notNull(),
  nextRealmSlug: text("next_realm_slug"),
  tickSeconds: integer("tick_seconds").notNull().default(1),
  gainPerTick: integer("gain_per_tick").notNull().default(0),
  baseAttack: doublePrecision("base_attack").notNull().default(0),
  baseDefense: doublePrecision("base_defense").notNull().default(0),
  baseHp: doublePrecision("base_hp").notNull().default(0),
  baseSpeed: doublePrecision("base_speed").notNull().default(0),
  baseInterval: doublePrecision("base_interval"),
  /** 手动大招（按层填，同一个大境界的几层填一样的）。倍率 0 = 没有大招。 */
  ultName: text("ult_name").notNull().default(""),
  ultDamageMultBp: integer("ult_damage_mult_bp").notNull().default(0),
  ultCooldownSeconds: doublePrecision("ult_cooldown_seconds").notNull().default(0),
  ultFirstCooldownSeconds: doublePrecision("ult_first_cooldown_seconds").notNull().default(8),
  breakthroughCost: doublePrecision("breakthrough_cost").notNull().default(0),
  requiredStageSlug: text("required_stage_slug"),
  recommendedPower: integer("recommended_power").notNull().default(0),
  enabled: boolean("enabled").notNull().default(true),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentWeaponCategories = pgTable("content_weapon_categories", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentSkillCategories = pgTable("content_skill_categories", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentItems = pgTable("content_items", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  description: text("description").notNull().default(""),
  kind: text("kind"),
  quality: text("quality").notNull().default("white"),
  slot: text("slot"),
  attack: doublePrecision("attack").notNull().default(0),
  defense: doublePrecision("defense").notNull().default(0),
  hp: doublePrecision("hp").notNull().default(0),
  speed: doublePrecision("speed").notNull().default(0),
  requiredRealmOrder: integer("required_realm_order").notNull().default(0),
  skillSlug: text("skill_slug"),
  weaponCategorySlug: text("weapon_category_slug"),
  stackable: boolean("stackable").notNull().default(false),
  iconKey: text("icon_key").notNull().default(""),
  /** 装备掉率倍数：同大境界、同品质 6 件按倍数分配被抽中的机会（默认 1）。 */
  dropMult: doublePrecision("drop_mult").notNull().default(1),
  /** 名称 / 描述被后台改过：重新生成装备时不覆盖。 */
  nameCustom: boolean("name_custom").notNull().default(false),
  descriptionCustom: boolean("description_custom").notNull().default(false),
  /** formula = 公式生成的 90 件（重新生成会重算数值）；manual = 后台手动新建（gear_m_0001…，永远不被重算）。 */
  origin: text("origin").notNull().default("formula"),
  /** 所属套装（content_gear_sets.slug）；只有手动装备能进套装。 */
  setSlug: text("set_slug"),
  /** 参与本境界本品质的随机掉落池。公式装备总是参与；手动装备默认不参与（只靠指定掉落 / 补发）。 */
  randomDrop: boolean("random_drop").notNull().default(true),
  enabled: boolean("enabled").notNull().default(true),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentSkills = pgTable("content_skills", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  description: text("description").notNull().default(""),
  role: text("role"),
  rank: text("rank").notNull().default("yellow"),
  attack: doublePrecision("attack").notNull().default(0),
  defense: doublePrecision("defense").notNull().default(0),
  hp: doublePrecision("hp").notNull().default(0),
  speed: doublePrecision("speed").notNull().default(0),
  cultivateBonusBp: integer("cultivate_bonus_bp").notNull().default(0),
  requiredRealmOrder: integer("required_realm_order").notNull().default(0),
  prerequisiteSkillSlugs: jsonb("prerequisite_skill_slugs").$type<string[]>().notNull().default([]),
  skillCategorySlug: text("skill_category_slug"),
  enabled: boolean("enabled").notNull().default(true),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentDropTables = pgTable("content_drop_tables", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentDropEntries = pgTable(
  "content_drop_entries",
  {
    dropTableSlug: text("drop_table_slug")
      .notNull()
      .references(() => contentDropTables.slug),
    itemSlug: text("item_slug").notNull(),
    chanceBp: integer("chance_bp").notNull(),
    minQty: integer("min_qty").notNull(),
    maxQty: integer("max_qty").notNull(),
  },
  (table) => [primaryKey({ columns: [table.dropTableSlug, table.itemSlug] })],
);

export type StageBoss = {
  name: string;
  attack: number;
  defense: number;
  hp: number;
  interval: number;
  drops: { itemSlug: string; chanceBp: number }[];
  reward?: { major: string; stageIndex: number; nextMajor: string | null };
  /** 原型奖励模型：首通固定奖励（配了它或 repeat 就不再走旧的掉落表/方案奖励）。 */
  firstClear?: BossRewardEntry[];
  /** 首通之后每天前 N 次胜利的奖励（N = 规则“首领每日奖励次数”）。 */
  repeat?: BossRepeatReward;
};

export const contentStages = pgTable("content_stages", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  sortOrder: integer("sort_order").notNull().default(0),
  nextStageSlug: text("next_stage_slug"),
  requiredRealmOrder: integer("required_realm_order").notNull().default(0),
  /** null = 按公式自动算；数字 = 后台手动覆盖。 */
  recommendedPower: integer("recommended_power"),
  bossName: text("boss_name").notNull().default(""),
  bossAttack: doublePrecision("boss_attack").notNull().default(1),
  bossDefense: doublePrecision("boss_defense").notNull().default(0),
  bossHp: doublePrecision("boss_hp").notNull().default(1),
  bossInterval: doublePrecision("boss_interval").notNull().default(1.5),
  bosses: jsonb("bosses").$type<StageBoss[]>().notNull().default([]),
  /** 普通怪（每个关卡一种），空 = 这个关卡没有波次。 */
  monsters: jsonb("monsters").$type<StageMonster[]>().notNull().default([]),
  /** 关卡自己改过的掉率 / 品质权重；没改的项不存（或存 null），跟随配置概览。 */
  monsterDrop: jsonb("monster_drop").$type<MonsterDropOverride | null>(),
  /** 指定掉落：每条单独按概率抽，和随机掉落同时生效（迁移 0028）。 */
  designatedDrops: jsonb("designated_drops").$type<DesignatedDrop[]>().notNull().default([]),
  bossDropTableSlug: text("boss_drop_table_slug").notNull(),
  idleDropTableSlug: text("idle_drop_table_slug").notNull(),
  firstClearDropTableSlug: text("first_clear_drop_table_slug").notNull(),
  enabled: boolean("enabled").notNull().default(true),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

/** 套装（迁移 0028）：成员是 content_items.set_slug 指向它的手动装备；tiers 是件数档位加成。 */
export const contentGearSets = pgTable("content_gear_sets", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  description: text("description").notNull().default(""),
  tiers: jsonb("tiers").$type<SetTier[]>().notNull().default([]),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentTrialPuppets = pgTable("content_trial_puppets", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  kind: text("kind").notNull(),
  realmCode: integer("realm_code"),
  weaponIds: jsonb("weapon_ids").$type<string[]>().notNull().default([]),
  skillIds: jsonb("skill_ids").$type<string[]>().notNull().default([]),
  attack: doublePrecision("attack"),
  defense: doublePrecision("defense"),
  hp: doublePrecision("hp"),
  speed: doublePrecision("speed"),
  interval: doublePrecision("interval"),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const playerStates = pgTable("player_states", {
  playerId: uuid("player_id")
    .primaryKey()
    .references(() => players.id),
  cultivation: doublePrecision("cultivation").notNull(),
  spiritStones: bigint("spirit_stones", { mode: "number" }).notNull().default(0),
  realmSlug: text("realm_slug").notNull(),
  lastSettledAt: timestamp("last_settled_at", { withTimezone: true }).notNull(),
  breakthroughFailStreak: integer("breakthrough_fail_streak").notNull().default(0),
  idleStageSlug: text("idle_stage_slug"),
  lastChallengeAt: timestamp("last_challenge_at", { withTimezone: true }),
  stateVersion: integer("state_version").notNull().default(0),
  dropPity: jsonb("drop_pity").$type<Record<string, number>>().notNull().default({}),
  autoDecompose: boolean("auto_decompose").notNull().default(true),
  enhanceExp: bigint("enhance_exp", { mode: "number" }).notNull().default(0),
  bagBonus: integer("bag_bonus").notNull().default(0),
  /** 结算时不足 1 点修为的部分，单位万分之一点，0..9999。见 progress/settle.ts。 */
  cultivationRemainderBp: integer("cultivation_remainder_bp").notNull().default(0),
  /** 当前波次已经进行的秒数（前台在线时按波次周期推进）。 */
  waveProgress: doublePrecision("wave_progress").notNull().default(0),
  /** 连续阵亡次数（打赢一只就清零），客户端 ≥3 时提示去强化或切低关。 */
  waveDeathsInRow: integer("wave_deaths_in_row").notNull().default(0),
});

export const playerItems = pgTable(
  "player_items",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    itemSlug: text("item_slug").notNull(),
    isStack: boolean("is_stack").notNull().default(false),
    quantity: bigint("quantity", { mode: "number" }).notNull().default(1),
    equippedSlot: text("equipped_slot"),
    enhanceLevel: integer("enhance_level").notNull().default(0),
    /** 已经突破过的最高节点等级（0 表示一个节点都没突破过） */
    breakLevel: integer("break_level").notNull().default(0),
    acquiredAt: timestamp("acquired_at", { withTimezone: true }).notNull().defaultNow(),
    source: text("source").notNull().default("drop"),
  },
  (table) => [
    index("player_items_player_idx").on(table.playerId),
    uniqueIndex("player_items_equipped_slot")
      .on(table.playerId, table.equippedSlot)
      .where(sql`${table.equippedSlot} is not null`),
    uniqueIndex("player_items_stack")
      .on(table.playerId, table.itemSlug)
      .where(sql`${table.isStack} = true`),
  ],
);

/** 「发放指定装备」流水（ADMIN_SPEC §14，迁移 0027）：每次发放一行，request_id 唯一（幂等键）。 */
export const equipmentGrants = pgTable(
  "equipment_grants",
  {
    id: uuid("id").primaryKey().defaultRandom(),
    requestId: text("request_id").notNull(),
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    itemSlug: text("item_slug").notNull(),
    count: integer("count").notNull(),
    source: text("source").notNull(),
    sourceRef: text("source_ref"),
    operator: text("operator"),
    reason: text("reason"),
    note: text("note"),
    /** 这次发放生成的 player_items.id（按生成顺序）。 */
    instanceIds: jsonb("instance_ids").$type<string[]>().notNull().default([]),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    uniqueIndex("equipment_grants_request_id").on(table.requestId),
    index("equipment_grants_player_idx").on(table.playerId, table.createdAt),
    index("equipment_grants_source_idx").on(table.source, table.createdAt),
  ],
);

export const playerSkills = pgTable(
  "player_skills",
  {
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    skillSlug: text("skill_slug").notNull(),
    learnedAt: timestamp("learned_at", { withTimezone: true }).notNull().defaultNow(),
    level: integer("level").notNull().default(1),
    runningSlot: text("running_slot"),
  },
  (table) => [
    primaryKey({ columns: [table.playerId, table.skillSlug] }),
    uniqueIndex("player_skills_running_slot")
      .on(table.playerId, table.runningSlot)
      .where(sql`${table.runningSlot} is not null`),
  ],
);

export const playerStageProgress = pgTable(
  "player_stage_progress",
  {
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    stageSlug: text("stage_slug").notNull(),
    unlockedAt: timestamp("unlocked_at", { withTimezone: true }).notNull().defaultNow(),
    firstClearedAt: timestamp("first_cleared_at", { withTimezone: true }),
    clearCount: integer("clear_count").notNull().default(0),
    bestClearSeconds: doublePrecision("best_clear_seconds"),
    /** 首领每日奖励：今天（按每日重置整点算）已经拿过几次，和对应的日期。 */
    dailyRewardCount: integer("daily_reward_count").notNull().default(0),
    dailyRewardDay: text("daily_reward_day"),
  },
  (table) => [primaryKey({ columns: [table.playerId, table.stageSlug] })],
);

export const idempotencyKeys = pgTable(
  "idempotency_keys",
  {
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    key: text("key").notNull(),
    endpoint: text("endpoint").notNull(),
    response: jsonb("response").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [primaryKey({ columns: [table.playerId, table.key] })],
);

export const operationRecords = pgTable("operation_records", {
  id: uuid("id").primaryKey().defaultRandom(),
  at: timestamp("at", { withTimezone: true }).notNull(),
  actorType: actorType("actor_type").notNull(),
  actorId: uuid("actor_id"),
  actorName: text("actor_name").notNull(),
  action: operationAction("action").notNull(),
  result: operationResult("result").notNull(),
  reason: text("reason"),
  contentReleaseId: uuid("content_release_id"),
  summary: jsonb("summary").notNull(),
});

export const repairPreviews = pgTable("repair_previews", {
  id: uuid("id").primaryKey().defaultRandom(),
  repairName: text("repair_name").notNull(),
  entries: jsonb("entries").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
  stateToken: text("state_token").notNull(),
});

export const contentDocuments = pgTable(
  "content_documents",
  {
    releaseId: uuid("release_id")
      .notNull()
      .references(() => contentReleases.id),
    kind: text("kind").notNull(),
    body: jsonb("body").notNull(),
  },
  (table) => [primaryKey({ columns: [table.releaseId, table.kind] })],
);

export const appReleases = pgTable("app_releases", {
  id: uuid("id").primaryKey().defaultRandom(),
  versionName: text("version_name").notNull(),
  versionCode: integer("version_code").notNull().unique(),
  releaseNotes: text("release_notes").notNull().default(""),
  forceUpdate: boolean("force_update").notNull().default(false),
  sha256: text("sha256").notNull(),
  sizeBytes: integer("size_bytes").notNull(),
  storedName: text("stored_name").notNull(),
  isCurrent: boolean("is_current").notNull().default(false),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const repairApplications = pgTable(
  "repair_applications",
  {
    repairName: text("repair_name").notNull(),
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    previewId: uuid("preview_id")
      .notNull()
      .references(() => repairPreviews.id),
    appliedAt: timestamp("applied_at", { withTimezone: true }).notNull(),
  },
  (table) => [unique("repair_applications_name_player").on(table.repairName, table.playerId)],
);

/** 离线结算记录：一次离线（两次结算间隔超过在线判定）的结果。≥ 弹窗最短时长的会让客户端弹“闭关归来”，点“已读”只是确认，不领取（修为已经入账）。 */
export const playerOfflineReports = pgTable("player_offline_reports", {
  id: uuid("id").primaryKey().defaultRandom(),
  playerId: uuid("player_id")
    .notNull()
    .references(() => players.id),
  startedAt: timestamp("started_at", { withTimezone: true }).notNull(),
  endedAt: timestamp("ended_at", { withTimezone: true }).notNull(),
  /** 离线总秒数（可能超过上限）。 */
  seconds: integer("seconds").notNull(),
  /** 实际计入的秒数（≤ 离线上限）。 */
  countedSeconds: integer("counted_seconds").notNull(),
  hitCap: boolean("hit_cap").notNull().default(false),
  gained: bigint("gained", { mode: "number" }).notNull().default(0),
  baseGained: bigint("base_gained", { mode: "number" }).notNull().default(0),
  bonusGained: bigint("bonus_gained", { mode: "number" }).notNull().default(0),
  realmSlug: text("realm_slug").notNull(),
  acknowledgedAt: timestamp("acknowledged_at", { withTimezone: true }),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});
