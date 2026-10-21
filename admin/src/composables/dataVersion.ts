import { onActivated, onDeactivated, ref } from "vue";
import { useRoute } from "vue-router";
import { dirtyPaths, tabFor } from "./tabs";

/**
 * 全局「数据版本号」：任何写操作（api() 里非 GET 且成功的请求）都会 +1。
 * 被 <keep-alive> 缓存的页签切回来时，如果版本号变了（别的页签保存过东西），就自动重新读取，
 * 不用手动刷新。页面自己有未保存改动时不重读，免得冲掉正在改的内容。
 */
export const dataVersion = ref(0);

/** 不改数据的 POST（试打、公式预览、登录），不算写操作 */
const READ_ONLY_POSTS = ["/admin/auth/login", "/admin/draft/trial", "/admin/draft/formula-preview"];

export function noteRequest(path: string, method: string | undefined): void {
  const verb = (method ?? "GET").toUpperCase();
  if (verb === "GET" || verb === "HEAD") return;
  const bare = path.split("?")[0] ?? path;
  if (READ_ONLY_POSTS.some((prefix) => bare.startsWith(prefix))) return;
  dataVersion.value += 1;
}

/** 在缓存页面（或其子组件）里调用：切回本页签时，若其他地方保存过数据就重新读取。 */
export function useRefetchOnActivate(reload: () => unknown): void {
  const path = useRoute().path;
  const key = tabFor(path) ?? path;
  let seen = dataVersion.value;
  onDeactivated(() => {
    seen = dataVersion.value;
  });
  onActivated(() => {
    if (dataVersion.value === seen) return;
    if (dirtyPaths.has(key)) return;
    seen = dataVersion.value;
    void reload();
  });
}
