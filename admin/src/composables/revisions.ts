import { api } from "../api";
import type { Revisions } from "./conflict";

/**
 * 每个页面自己的一份版本号（不是全局共享：A 页签读到的旧数据只能配 A 读数据时的版本号）。
 * 用法：页面 reload 时先 `await rev.load()` 再读数据（先取版本号再读，最多误报、不会漏报）；
 * 保存时 api(url, { method: "PUT", body, guard: { revisions: rev, id, reload, latest } })。
 */
export function useRevisions(kind: string): Revisions {
  let map: Record<string, string> = {};
  return {
    kind,
    of: (id) => map[String(id)],
    set: (id, revision) => {
      map = { ...map, [String(id)]: revision };
    },
    load: async () => {
      try {
        map = (await api<{ revisions: Record<string, string> }>(`/admin/draft/revisions?kind=${encodeURIComponent(kind)}`)).revisions ?? {};
      } catch {
        // 取不到版本号（服务器较旧）：保存时不带版本号，照旧保存
        map = {};
      }
    },
  };
}

/** 「查看差异」用：重新 GET 列表接口，按主键取出这一条。 */
export async function latestFrom(url: string, idKey: string, id: string | number): Promise<unknown> {
  const list = await api<Record<string, unknown>[]>(url);
  const hit = (Array.isArray(list) ? list : []).find((row) => String(row[idKey]) === String(id));
  if (!hit) throw new Error("这一条已经被删除");
  return hit;
}
