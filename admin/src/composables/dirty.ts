import { onBeforeUnmount, onMounted, watch, type Ref } from "vue";
import { useRoute } from "vue-router";
import { dirtyPaths, registerPage, tabFor, unregisterPage } from "./tabs";

/**
 * 页面级未保存守卫。
 * 多标签页之后，切换标签不再拦截（页面被缓存，改动不会丢）；改为：
 * - 标签标题后显示金点；关闭标签时确认（可传 save 支持「保存并关闭」）；
 * - 刷新 / 关闭浏览器前提醒。
 */
export function useDirtyGuard(dirty: Ref<boolean>, save?: () => Promise<boolean>): void {
  const path = useRoute().path;
  const key = tabFor(path) ?? path;
  registerPage(key, { dirty: () => dirty.value, save });
  watch(
    dirty,
    (value) => {
      if (value) {
        dirtyPaths.add(key);
      } else {
        dirtyPaths.delete(key);
      }
    },
    { immediate: true },
  );
  const handler = (event: BeforeUnloadEvent): void => {
    if (dirty.value) {
      event.preventDefault();
    }
  };
  onMounted(() => window.addEventListener("beforeunload", handler));
  onBeforeUnmount(() => {
    window.removeEventListener("beforeunload", handler);
    unregisterPage(key);
  });
}
