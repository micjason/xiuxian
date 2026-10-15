import { ref } from "vue";

/** 面包屑末尾的动态一段，例如打开编辑抽屉后显示「编辑：炼气初期」。 */
export const crumbTail = ref<string | null>(null);

export function setCrumbTail(label: string | null): void {
  crumbTail.value = label;
}
