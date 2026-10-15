import { onBeforeUnmount, onMounted, type Ref } from "vue";
import { onBeforeRouteLeave } from "vue-router";
import { confirmDiscard } from "./confirm";

/** 页面级未保存守卫：切换路由和刷新/关闭标签页前提醒。 */
export function useDirtyGuard(dirty: Ref<boolean>): void {
  onBeforeRouteLeave(async () => {
    if (!dirty.value) {
      return true;
    }
    return confirmDiscard();
  });
  const handler = (event: BeforeUnloadEvent): void => {
    if (dirty.value) {
      event.preventDefault();
    }
  };
  onMounted(() => window.addEventListener("beforeunload", handler));
  onBeforeUnmount(() => window.removeEventListener("beforeunload", handler));
}
