import { reactive } from "vue";
import { api } from "../api";
import { analyzeDraft, type HealthInput, type Problem } from "./healthCheck";

export type SnapshotChange = {
  kind: string;
  slug: string;
  name: string;
  type: "added" | "removed" | "changed";
  fields: { field: string; before: unknown; after: unknown; beforeText?: string; afterText?: string }[];
};
export type DiffResult = { from: string | number; to: string | number; total: number; added: number; removed: number; changed: number; changes: SnapshotChange[] };

/** 全局草稿状态：顶栏的「N 项未发布」、概览页待办、发布中心都读它。 */
export const draft = reactive({
  loaded: false,
  loading: false,
  contentVersion: null as number | null,
  /** 后端是否提供 /admin/draft/diff；没有时变更数显示「未知」 */
  diffAvailable: true,
  changes: 0,
  diff: null as DiffResult | null,
  problems: [] as Problem[],
  error: "",
});

async function safe<T>(call: () => Promise<T>): Promise<T | null> {
  try {
    return await call();
  } catch {
    return null;
  }
}

export async function refreshDraftStatus(): Promise<void> {
  draft.loading = true;
  draft.error = "";
  try {
    const [health, diff, realms, stages, items, skills, rules, puppets] = await Promise.all([
      safe(() => api<{ contentVersion: number | null }>("/healthz")),
      safe(() => api<DiffResult>("/admin/draft/diff")),
      safe(() => api<HealthInput["realms"]>("/admin/draft/realms")),
      safe(() => api<HealthInput["stages"]>("/admin/draft/stages")),
      safe(() => api<HealthInput["items"]>("/admin/draft/items")),
      safe(() => api<HealthInput["skills"]>("/admin/draft/skills")),
      safe(() => api<Record<string, number | null>>("/admin/draft/rules")),
      safe(() => api<NonNullable<HealthInput["puppets"]>>("/admin/draft/puppets")),
    ]);
    draft.contentVersion = health?.contentVersion ?? null;
    draft.diffAvailable = diff !== null;
    draft.diff = diff;
    draft.changes = diff?.total ?? 0;
    if (realms && stages && items && skills) {
      draft.problems = analyzeDraft({ realms, stages, items, skills, rules, puppets: puppets ?? [] });
    } else {
      draft.error = "部分草稿数据加载失败，体检结果可能不完整。";
    }
    draft.loaded = true;
  } finally {
    draft.loading = false;
  }
}
