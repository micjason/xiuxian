import { eq } from "drizzle-orm";
import { announcements, appReleases, noticeDismissals, popupTypes } from "../../db/schema.js";
import type { Db } from "../operations/record.js";
import { orderNotices, type Notice } from "./rules.js";

const DEFAULT_TYPES = [
  { slug: "version_update", priority: 1, enabled: true, template: "confirm" },
  { slug: "announcement", priority: 2, enabled: true, template: "acknowledge" },
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
  return orderNotices(notices);
}

export async function dismissNotice(db: Db, playerId: string, noticeId: string, now: Date): Promise<void> {
  await db
    .insert(noticeDismissals)
    .values({ playerId, noticeId, dismissedAt: now })
    .onConflictDoNothing();
}

/**
 * 游戏端心跳（GET /me/state）带的公告：只有后台「公告」里启用、玩家没点过「知道了」的。
 * 版本更新由客户端自己查 latest.json 弹窗，离线收益由「闭关归来」弹窗负责，这里都不带。
 */
export async function announcementNoticesForPlayer(db: Db, playerId: string): Promise<Notice[]> {
  const types = await ensurePopupTypes(db);
  const type = types.find((row) => row.slug === "announcement");
  if (type && !type.enabled) {
    return [];
  }
  const priority = type?.priority ?? 2;
  const dismissed = new Set((await db.select().from(noticeDismissals).where(eq(noticeDismissals.playerId, playerId))).map((row) => row.noticeId));
  const rows = await db.select().from(announcements).where(eq(announcements.enabled, true));
  return orderNotices(
    rows
      .filter((row) => !dismissed.has(row.id))
      .map((row) => ({
        id: row.id,
        type: "announcement",
        priority,
        template: "acknowledge",
        triggeredAt: (row.enabledAt ?? new Date(0)).toISOString(),
        payload: { title: row.title, body: row.body },
      })),
  );
}
