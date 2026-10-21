import { onMounted, ref, type Ref } from "vue";
import { useRefetchOnActivate } from "./dataVersion";

/** 统一的列表加载状态：loading / error / rows / reload。 */
export function useList<T>(fetcher: () => Promise<T[]>): { rows: Ref<T[]>; loading: Ref<boolean>; error: Ref<string>; reload: () => Promise<void> } {
  const rows = ref([]) as Ref<T[]>;
  const loading = ref(false);
  const error = ref("");
  async function reload(): Promise<void> {
    loading.value = true;
    error.value = "";
    try {
      rows.value = await fetcher();
    } catch (cause) {
      error.value = cause instanceof Error ? cause.message : "加载失败";
    } finally {
      loading.value = false;
    }
  }
  useRefetchOnActivate(reload);
onMounted(reload);
  return { rows, loading, error, reload };
}
