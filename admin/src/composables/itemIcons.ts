import { ref } from "vue";

/** 后台图标选择器用的缩略图（admin/public/item-icons，和游戏客户端的图同名）。q = Q 版（游戏里优先），old = 旧版境界图。 */
export type ItemIcon = { key: string; style: "q" | "old"; file: string };

const icons = ref<ItemIcon[]>([]);
let loading: Promise<void> | null = null;

export function useItemIcons() {
  if (!loading) {
    loading = fetch(`${import.meta.env.BASE_URL}item-icons/index.json`)
      .then((response) => (response.ok ? (response.json() as Promise<ItemIcon[]>) : []))
      .then((list) => {
        // 同名时游戏先找 Q 版，所以选择器里只留 Q 版那张
        const seen = new Set<string>();
        icons.value = list.filter((icon) => (seen.has(icon.key) ? false : (seen.add(icon.key), true)));
      })
      .catch(() => undefined);
  }
  return icons;
}

/** 某个图标名的缩略图地址；没有这张图返回空串。 */
export function iconUrl(list: ItemIcon[], key: string): string {
  const icon = list.find((row) => row.key === key);
  return icon ? `${import.meta.env.BASE_URL}item-icons/${icon.file}` : "";
}

/** 没指定图标时游戏实际显示的图：Q 版通用部位图。 */
export function autoGearIcon(slot: string): string {
  return `gear_${slot}`;
}
