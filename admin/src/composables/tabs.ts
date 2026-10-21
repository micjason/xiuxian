import { ElMessageBox } from "element-plus";
import { computed, nextTick, reactive, ref } from "vue";
import type { Router } from "vue-router";
import { navOf } from "../nav";

/**
 * 顶部多标签页（常见后台的 TagsView 做法）：
 * - 只有左侧菜单里的功能页会开标签；关卡、装备的编辑仍是页面上的右侧抽屉。
 * - 每个标签对应一个被 <keep-alive> 缓存的页面（按路由 path），切回来表单、筛选、滚动、抽屉都保持原样；关闭标签才释放。
 * - 「运营概览」常驻不能关；最多 15 个，超过时自动关最早的、没有改动的那个。
 */
export type Tab = { path: string; title: string; fullPath: string };

export const HOME_PATH = "/dashboard";
const MAX_TABS = 15;
const STORAGE_KEY = "xx-admin-tabs";

type PageHooks = { dirty: () => boolean; save?: () => Promise<boolean> };

function restore(): Tab[] {
  try {
    const saved = JSON.parse(sessionStorage.getItem(STORAGE_KEY) ?? "[]") as Tab[];
    return saved.filter((tab) => navOf(tab.path)?.path === tab.path);
  } catch {
    return [];
  }
}

export const tabs = reactive<Tab[]>(restore());
if (!tabs.some((tab) => tab.path === HOME_PATH)) {
  tabs.unshift({ path: HOME_PATH, title: navOf(HOME_PATH)?.label ?? "运营概览", fullPath: HOME_PATH });
}
const hooks = new Map<string, PageHooks>();
/** 每个标签的「有未保存改动」状态（页面通过 useDirtyGuard 上报） */
export const dirtyPaths = reactive(new Set<string>());
/** 刷新时临时把页面移出缓存 */
const refreshing = ref<string | null>(null);

export const cachedNames = computed(() => tabs.map((tab) => tab.path).filter((path) => path !== refreshing.value));

function persist(): void {
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(tabs));
}

export function tabFor(path: string): string | null {
  const nav = navOf(path);
  return nav && nav.path === path ? nav.path : null;
}

/** 路由变化时调用：菜单页就开（或更新）一个标签。 */
export function openTab(path: string, fullPath: string): void {
  const key = tabFor(path);
  if (!key) {
    return;
  }
  const existing = tabs.find((tab) => tab.path === key);
  if (existing) {
    existing.fullPath = fullPath;
  } else {
    tabs.push({ path: key, title: navOf(key)?.label ?? key, fullPath });
    while (tabs.length > MAX_TABS) {
      const victim = tabs.find((tab) => tab.path !== HOME_PATH && tab.path !== key && !dirtyPaths.has(tab.path));
      if (!victim) {
        break;
      }
      tabs.splice(tabs.indexOf(victim), 1);
    }
  }
  persist();
}

export function registerPage(path: string, page: PageHooks): void {
  hooks.set(path, page);
}

export function unregisterPage(path: string): void {
  hooks.delete(path);
  dirtyPaths.delete(path);
}

/** 关闭有改动的标签前确认：取消 / 不保存，关闭 / 保存并关闭。返回 true = 可以关。 */
async function confirmClose(tab: Tab): Promise<boolean> {
  const page = hooks.get(tab.path);
  if (!dirtyPaths.has(tab.path) && !page?.dirty()) {
    return true;
  }
  try {
    await ElMessageBox.confirm(`「${tab.title}」有未保存的改动`, "关闭标签", {
      confirmButtonText: page?.save ? "保存并关闭" : "不保存，关闭",
      cancelButtonText: page?.save ? "不保存，关闭" : "取消",
      distinguishCancelAndClose: true,
      type: "warning",
    });
    if (page?.save) {
      return await page.save();
    }
    return true;
  } catch (action) {
    return action === "cancel" && !!page?.save;
  }
}

export async function closeTabs(router: Router, targets: Tab[], currentPath: string): Promise<void> {
  for (const tab of targets) {
    if (tab.path === HOME_PATH) {
      continue;
    }
    if (!(await confirmClose(tab))) {
      break;
    }
    const index = tabs.indexOf(tab);
    if (index < 0) {
      continue;
    }
    tabs.splice(index, 1);
    dirtyPaths.delete(tab.path);
    if (tab.path === currentPath) {
      const next = tabs[Math.min(index, tabs.length - 1)] ?? tabs[0];
      await router.push(next?.fullPath ?? HOME_PATH);
    }
  }
  persist();
}

export async function refreshTab(path: string): Promise<void> {
  refreshing.value = path;
  await nextTick();
  refreshing.value = null;
}

/** 刷新期间渲染用的 key：让 <component> 重新挂载 */
export const refreshingPath = refreshing;
