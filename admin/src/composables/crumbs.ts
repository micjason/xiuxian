import { computed, reactive } from "vue";
import { useRoute } from "vue-router";

/**
 * 面包屑末尾的动态一段，例如打开编辑抽屉后显示「编辑：炼气初期」。
 * 按页面路径分开存：多标签页缓存时，切到别的标签不会串。
 */
const tails = reactive(new Map<string, string>());

export function crumbTailOf(path: string) {
  return computed(() => tails.get(path) ?? null);
}

export function tailFor(path: string): string | null {
  return tails.get(path) ?? null;
}

/** 在页面组件里调用：返回只作用于本页的 setter。 */
export function useCrumbTail(): (label: string | null) => void {
  const path = useRoute().path;
  return (label) => {
    if (label) {
      tails.set(path, label);
    } else {
      tails.delete(path);
    }
  };
}

/** 兼容旧调用：按当前地址栏路径设置。 */
export function setCrumbTail(label: string | null): void {
  const path = window.location.pathname;
  if (label) {
    tails.set(path, label);
  } else {
    tails.delete(path);
  }
}
