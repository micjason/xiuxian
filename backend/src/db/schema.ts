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
  offlineCapSeconds: integer("offline_cap_seconds").notNull().default(28800),
  bagCapacity: integer("bag_capacity").notNull().default(100),
  starterItems: jsonb("starter_items").notNull().default([]),
  powerWeights: jsonb("power_weights").notNull().default({ attack: 1, defense: 0.8, hp: 0.04, speed: 1.5 }),
  combat: jsonb("combat").notNull().default({ minInterval: 0.7, respawnSeconds: 0.8, challengeCooldownSeconds: 3 }),
  artSlotRules: jsonb("art_slot_rules").notNull().default([{ minRealmOrder: 0, slots: 1 }, { minRealmOrder: 4, slots: 2 }]),
  idleKillCap: integer("idle_kill_cap").notNull().default(200),
  minClientVersionCode: integer("min_client_version_code").notNull().default(0),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentRealms = pgTable("content_realms", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  majorName: text("major_name").notNull().default(""),
  sortOrder: integer("sort_order").notNull(),
  nextRealmSlug: text("next_realm_slug"),
  tickSeconds: integer("tick_seconds").notNull().default(1),
  gainPerTick: integer("gain_per_tick").notNull().default(0),
  baseAttack: doublePrecision("base_attack").notNull().default(0),
  baseDefense: doublePrecision("base_defense").notNull().default(0),
  baseHp: doublePrecision("base_hp").notNull().default(0),
  baseSpeed: doublePrecision("base_speed").notNull().default(0),
  baseInterval: doublePrecision("base_interval").notNull().default(1.5),
  breakthroughCost: doublePrecision("breakthrough_cost").notNull().default(0),
  requiredStageSlug: text("required_stage_slug"),
  recommendedPower: integer("recommended_power").notNull().default(0),
  baseRateBp: integer("base_rate_bp").notNull().default(9000),
  powerFactorBp: integer("power_factor_bp").notNull().default(3000),
  minRateBp: integer("min_rate_bp").notNull().default(2000),
  maxRateBp: integer("max_rate_bp").notNull().default(9500),
  failLossBp: integer("fail_loss_bp").notNull().default(3000),
  pityStepBp: integer("pity_step_bp").notNull().default(1000),
  enabled: boolean("enabled").notNull().default(true),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentItems = pgTable("content_items", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  description: text("description").notNull().default(""),
  kind: text("kind").notNull(),
  quality: text("quality").notNull().default("white"),
  slot: text("slot"),
  attack: doublePrecision("attack").notNull().default(0),
  defense: doublePrecision("defense").notNull().default(0),
  hp: doublePrecision("hp").notNull().default(0),
  speed: doublePrecision("speed").notNull().default(0),
  requiredRealmOrder: integer("required_realm_order").notNull().default(0),
  skillSlug: text("skill_slug"),
  stackable: boolean("stackable").notNull().default(false),
  iconKey: text("icon_key").notNull().default(""),
  enabled: boolean("enabled").notNull().default(true),
  updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  updatedBy: uuid("updated_by"),
});

export const contentSkills = pgTable("content_skills", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  description: text("description").notNull().default(""),
  role: text("role").notNull(),
  rank: text("rank").notNull().default("yellow"),
  attack: doublePrecision("attack").notNull().default(0),
  defense: doublePrecision("defense").notNull().default(0),
  hp: doublePrecision("hp").notNull().default(0),
  speed: doublePrecision("speed").notNull().default(0),
  cultivateBonusBp: integer("cultivate_bonus_bp").notNull().default(0),
  requiredRealmOrder: integer("required_realm_order").notNull().default(0),
  prerequisiteSkillSlugs: jsonb("prerequisite_skill_slugs").$type<string[]>().notNull().default([]),
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

export const contentStages = pgTable("content_stages", {
  slug: text("slug").primaryKey(),
  displayName: text("display_name").notNull(),
  sortOrder: integer("sort_order").notNull().default(0),
  nextStageSlug: text("next_stage_slug"),
  requiredRealmOrder: integer("required_realm_order").notNull().default(0),
  recommendedPower: integer("recommended_power").notNull().default(0),
  bossName: text("boss_name").notNull().default(""),
  bossAttack: doublePrecision("boss_attack").notNull().default(1),
  bossDefense: doublePrecision("boss_defense").notNull().default(0),
  bossHp: doublePrecision("boss_hp").notNull().default(1),
  bossInterval: doublePrecision("boss_interval").notNull().default(1.5),
  bossDropTableSlug: text("boss_drop_table_slug").notNull(),
  idleDropTableSlug: text("idle_drop_table_slug").notNull(),
  firstClearDropTableSlug: text("first_clear_drop_table_slug").notNull(),
  enabled: boolean("enabled").notNull().default(true),
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

export const playerSkills = pgTable(
  "player_skills",
  {
    playerId: uuid("player_id")
      .notNull()
      .references(() => players.id),
    skillSlug: text("skill_slug").notNull(),
    learnedAt: timestamp("learned_at", { withTimezone: true }).notNull().defaultNow(),
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
