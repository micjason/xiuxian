import {
  boolean,
  doublePrecision,
  integer,
  jsonb,
  pgEnum,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
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
  passwordHash: text("password_hash").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const admins = pgTable("admins", {
  id: uuid("id").primaryKey().defaultRandom(),
  username: text("username").notNull().unique(),
  passwordHash: text("password_hash").notNull(),
  createdAt: timestamp("created_at", { withTimezone: true }).notNull().defaultNow(),
});

export const sessions = pgTable("sessions", {
  id: uuid("id").primaryKey().defaultRandom(),
  tokenHash: text("token_hash").notNull().unique(),
  actorType: actorType("actor_type").notNull(),
  actorId: uuid("actor_id").notNull(),
  expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
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

export const playerStates = pgTable("player_states", {
  playerId: uuid("player_id")
    .primaryKey()
    .references(() => players.id),
  cultivation: doublePrecision("cultivation").notNull(),
  realmSlug: text("realm_slug").notNull(),
  lastSettledAt: timestamp("last_settled_at", { withTimezone: true }).notNull(),
});

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
