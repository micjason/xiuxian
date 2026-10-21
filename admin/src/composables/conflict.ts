import { reactive } from "vue";

/**
 * 旧表单覆盖保护（后台这一侧）。服务器版本号对不上时回 409 STALE_REVISION，
 * api() 弹出 ConflictDialog 让用户选：重新读取 / 查看差异 / 仍然覆盖 / 取消。
 */
export type Revisions = { kind: string; of: (id: string | number) => string | undefined; set: (id: string | number, revision: string) => void; load: () => Promise<void> };

export type SaveGuard = {
  revisions: Revisions;
  id: string | number;
  /** 选「重新读取」时调用：重新读这一页（表单换成最新内容） */
  reload?: () => Promise<unknown>;
  /** 「查看差异」用：读服务器现在的内容，形状尽量和保存的 body 一样 */
  latest?: () => Promise<unknown>;
  /** 弹窗里显示的名字，例如「关卡：黑风岭·一」 */
  title?: string;
};

export type ConflictDetails = { kind?: string; id?: string; revision: string; updatedAt?: string | null; updatedBy?: string | null };
export type ConflictChoice = "reload" | "overwrite" | "cancel";

/** 用户没有覆盖（重新读取或取消）：页面不用再报错。 */
export class ConflictAbort extends Error {
  constructor(public readonly action: "reload" | "cancel") {
    super(action === "reload" ? "已重新读取最新内容，你这次的改动没有保存" : "已取消保存");
  }
}

export function isConflictAbort(cause: unknown): cause is ConflictAbort {
  return cause instanceof ConflictAbort;
}

export const conflictState = reactive<{
  open: boolean;
  title: string;
  details: ConflictDetails | null;
  mine: unknown;
  latest: (() => Promise<unknown>) | null;
  resolve: ((choice: ConflictChoice) => void) | null;
}>({ open: false, title: "", details: null, mine: null, latest: null, resolve: null });

export function askConflict(input: { title?: string; details: ConflictDetails; mine: unknown; latest?: () => Promise<unknown> }): Promise<ConflictChoice> {
  conflictState.resolve?.("cancel");
  return new Promise((resolve) => {
    Object.assign(conflictState, {
      open: true,
      title: input.title ?? "",
      details: input.details,
      mine: input.mine,
      latest: input.latest ?? null,
      resolve: (choice: ConflictChoice) => {
        conflictState.open = false;
        conflictState.resolve = null;
        resolve(choice);
      },
    });
  });
}

/** 把对象拍平成「路径 → 值」，数组按下标。 */
export function flatten(value: unknown, prefix = "", out: Record<string, unknown> = {}): Record<string, unknown> {
  if (Array.isArray(value)) {
    if (value.length === 0) out[prefix] = [];
    value.forEach((item, index) => flatten(item, `${prefix}[${index}]`, out));
  } else if (value && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>);
    if (entries.length === 0 && prefix) out[prefix] = {};
    for (const [key, item] of entries) flatten(item, prefix ? `${prefix}.${key}` : key, out);
  } else if (prefix) {
    out[prefix] = value ?? null;
  }
  return out;
}

/** 你要保存的 vs 服务器现在的：只列你这次要保存的字段里，两边不一样的。 */
export function conflictRows(mine: unknown, latest: unknown): { path: string; server: unknown; mine: unknown }[] {
  const left = flatten(mine);
  const right = flatten(latest);
  const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null) || (a != null && b != null && String(a) === String(b));
  return Object.keys(left)
    .filter((path) => !same(left[path], right[path]))
    .map((path) => ({ path, server: path in right ? right[path] : undefined, mine: left[path] }));
}
