import { stageAutoPower } from "./stage-power.js";
import type { ContentSnapshot } from "./validate.js";

export type SnapshotChangeKind = "realm" | "stage" | "item" | "skill" | "dropTable" | "globals";

export type SnapshotChange = {
  kind: SnapshotChangeKind;
  slug: string;
  name: string;
  type: "added" | "removed" | "changed";
  /** beforeText / afterText：给人看的写法（目前只有关卡推荐战力：快照里 0 = 没手动覆盖、按公式自动算，显示成「自动 6406」） */
  fields: { field: string; before: unknown; after: unknown; beforeText?: string; afterText?: string }[];
};

export type SnapshotDiff = {
  total: number;
  added: number;
  removed: number;
  changed: number;
  changes: SnapshotChange[];
};

type Row = { slug: string; displayName?: string | null } & Record<string, unknown>;

const COLLECTIONS: { key: "realms" | "stages" | "items" | "skills" | "dropTables"; kind: SnapshotChangeKind }[] = [
  { key: "realms", kind: "realm" },
  { key: "stages", kind: "stage" },
  { key: "items", kind: "item" },
  { key: "skills", kind: "skill" },
  { key: "dropTables", kind: "dropTable" },
];

// 这两个字段由排序推导得出，改顺序会连带变化，不当作用户改动列出来。
const DERIVED = new Set(["nextRealmSlug", "nextStageSlug", "version"]);

function stable(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map(stable).join(",")}]`;
  }
  if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, item]) => item !== undefined)
      .sort(([left], [right]) => (left < right ? -1 : 1));
    return `{${entries.map(([key, item]) => `${JSON.stringify(key)}:${stable(item)}`).join(",")}}`;
  }
  return JSON.stringify(value ?? null);
}

function fieldChanges(before: Record<string, unknown>, after: Record<string, unknown>): SnapshotChange["fields"] {
  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].filter((key) => !DERIVED.has(key)).sort();
  const fields: SnapshotChange["fields"] = [];
  for (const key of keys) {
    if (stable(before[key]) !== stable(after[key])) {
      fields.push({ field: key, before: before[key] ?? null, after: after[key] ?? null });
    }
  }
  return fields;
}

/** 推荐战力的显示文字：快照里 >0 是手动覆盖；0 / 空 = 自动，按这份快照的首领 / 普通怪数值现算。 */
export function stagePowerText(world: Partial<ContentSnapshot> | null, stage: Row): string {
  const manual = Math.round(Number(stage.recommendedPower ?? 0));
  if (manual > 0) {
    return `${manual}（手动）`;
  }
  try {
    return `自动 ${stageAutoPower(world as ContentSnapshot, stage as unknown as ContentSnapshot["stages"][number])}`;
  } catch {
    return "自动（暂时算不出）";
  }
}

function nameOf(row: Row): string {
  return typeof row.displayName === "string" && row.displayName ? row.displayName : row.slug;
}

/** 比较两份内容快照。from 为空表示还没有发布过，所有内容都算新增。纯函数，不访问数据库。 */
export function diffSnapshots(from: Partial<ContentSnapshot> | null, to: Partial<ContentSnapshot>): SnapshotDiff {
  const changes: SnapshotChange[] = [];
  for (const { key, kind } of COLLECTIONS) {
    const before = new Map(((from?.[key] ?? []) as unknown as Row[]).map((row) => [row.slug, row]));
    const after = new Map(((to[key] ?? []) as unknown as Row[]).map((row) => [row.slug, row]));
    for (const [slug, row] of after) {
      const old = before.get(slug);
      if (!old) {
        changes.push({ kind, slug, name: nameOf(row), type: "added", fields: [] });
        continue;
      }
      const fields = fieldChanges(old, row);
      if (kind === "stage") {
        for (const field of fields) {
          if (field.field === "recommendedPower") {
            field.beforeText = stagePowerText(from, old);
            field.afterText = stagePowerText(to, row);
          }
        }
      }
      if (fields.length > 0) {
        changes.push({ kind, slug, name: nameOf(row), type: "changed", fields });
      }
    }
    for (const [slug, row] of before) {
      if (!after.has(slug)) {
        changes.push({ kind, slug, name: nameOf(row), type: "removed", fields: [] });
      }
    }
  }
  const globalFields = fieldChanges((from?.globals ?? {}) as Record<string, unknown>, (to.globals ?? {}) as Record<string, unknown>);
  if (globalFields.length > 0) {
    changes.push({ kind: "globals", slug: "globals", name: "全局参数", type: "changed", fields: globalFields });
  }
  const count = (type: SnapshotChange["type"]) => changes.filter((row) => row.type === type).length;
  return { total: changes.length, added: count("added"), removed: count("removed"), changed: count("changed"), changes };
}
