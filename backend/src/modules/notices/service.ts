import { eq } from "drizzle-orm";
import { announcements, appReleases, noticeDismissals, playerNotices, popupTypes } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { incomeNotice, orderNotices, type Notice } from "./rules.js";

const DEFAULT_TYPES = [
  { slug: "version_update", priority: 1, enabled: true, template: "confirm" },
  { slug: "announcement", priority: 2, enabled: true, template: "acknowledge" },
  { slug: "income", priority: 3, enabled: true, template: "reward" },
];

export async function ensurePopupTypes(db: Db) {
  const rows = await db.select().from(popupTypes);
  if (rows.length > 0) {
    return rows;
  }
  await db.insert(popupTypes).values(DEFAULT_TYPES);
  return DEFAULT_TYPES;
}

export async function listPopupTypes(db: Db) {
  return ensurePopupTypes(db);
}

export async function savePopupType(db: Db, slug: string, input: { priority: number; enabled: boolean }): Promise<void> {
  if (!Number.isInteger(input.priority) || input.priority < 1) {
    throw new Error("优先级必须是不小于 1 的整数");
  }
  await ensurePopupTypes(db);
  await db.update(popupTypes).set({ priority: input.priority, enabled: input.enabled }).where(eq(popupTypes.slug, slug));
}

export async function listAnnouncements(db: Db) {
  return db.select().from(announcements);
}

export async function saveAnnouncement(
  db: Db,
  input: { id?: string; title: string; body: string; enabled: boolean },
  now: Date,
): Promise<void> {
  if (!input.title.trim() || !input.body.trim()) {
    throw new Error("公告需要标题和正文");
  }
  if (input.id) {
    await db
      .update(announcements)
      .set({ title: input.title, body: input.body, enabled: input.enabled, enabledAt: input.enabled ? now : null })
      .where(eq(announcements.id, input.id));
    return;
  }
  await db.insert(announcements).values({
    title: input.title,
    body: input.body,
    enabled: input.enabled,
    enabledAt: input.enabled ? now : null,
  });
}

export async function rememberIncome(
  db: Db,
  playerId: string,
  input: {
    countedSeconds: number;
    gained: number;
    hitCap: boolean;
    offlineCapSeconds: number;
    previousSettledAt: Date;
  },
): Promise<void> {
  const types = await ensurePopupTypes(db);
  const incomeType = types.find((row) => row.slug === "income");
  if (!incomeType?.enabled) {
    return;
  }
  const notice = incomeNotice({ ...input, priority: incomeType.priority });
  if (!notice) {
    return;
  }
  await db
    .insert(playerNotices)
    .values({
      playerId,
      noticeId: notice.id,
      type: notice.type,
      priority: notice.priority,
      template: notice.template,
      triggeredAt: input.previousSettledAt,
      payload: notice.payload,
    })
    .onConflictDoNothing();
}

export async function noticesForPlayer(db: Db, playerId: string, versionCode: number): Promise<Notice[]> {
  const types = await ensurePopupTypes(db);
  const enabled = new Map(types.filter((row) => row.enabled).map((row) => [row.slug, row]));
  const dismissedRows = await db.select().from(noticeDismissals).where(eq(noticeDismissals.playerId, playerId));
  const dismissed = new Set(dismissedRows.map((row) => row.noticeId));
  const notices: Notice[] = [];
  const versionType = enabled.get("version_update");
  if (versionType) {
    const [release] = await db.select().from(appReleases).where(eq(appReleases.isCurrent, true)).limit(1);
    if (release && release.versionCode > versionCode) {
      const id = `release-${release.versionCode}`;
      if (!dismissed.has(id)) {
        notices.push({
          id,
          type: "version_update",
          priority: versionType.priority,
          template: versionType.template,
          triggeredAt: release.createdAt.toISOString(),
          payload: { version: release.versionName, notes: release.releaseNotes },
        });
      }
    }
  }
  const announcementType = enabled.get("announcement");
  if (announcementType) {
    const rows = await db.select().from(announcements).where(eq(announcements.enabled, true));
    for (const row of rows) {
      if (dismissed.has(row.id)) {
        continue;
      }
      notices.push({
        id: row.id,
        type: "announcement",
        priority: announcementType.priority,
        template: announcementType.template,
        triggeredAt: (row.enabledAt ?? new Date(0)).toISOString(),
        payload: { title: row.title, body: row.body },
      });
    }
  }
  const stored = await db.select().from(playerNotices).where(eq(playerNotices.playerId, playerId));
  for (const row of stored) {
    const type = enabled.get(row.type);
    if (!type || dismissed.has(row.noticeId)) {
      continue;
    }
    notices.push({
      id: row.noticeId,
      type: row.type,
      priority: type.priority,
      template: type.template,
      triggeredAt: row.triggeredAt.toISOString(),
      payload: (row.payload ?? {}) as Record<string, unknown>,
    });
  }
  return orderNotices(notices);
}

export async function dismissNotice(db: Db, playerId: string, noticeId: string, now: Date): Promise<void> {
  await db
    .insert(noticeDismissals)
    .values({ playerId, noticeId, dismissedAt: now })
    .onConflictDoNothing();
}
