import { askConflict, ConflictAbort, type ConflictDetails, type SaveGuard } from "./composables/conflict";
import { noteRequest } from "./composables/dataVersion";

const tokenKey = "xiuxian-admin-token";
const nameKey = "xiuxian-admin-name";

function readSaved(key: string): string {
  const saved = localStorage.getItem(key);
  if (saved) {
    return saved;
  }
  const currentTab = sessionStorage.getItem(key);
  if (!currentTab) {
    return "";
  }
  localStorage.setItem(key, currentTab);
  sessionStorage.removeItem(key);
  return currentTab;
}

function writeSaved(key: string, value: string): void {
  localStorage.setItem(key, value);
  sessionStorage.removeItem(key);
}

function removeSaved(key: string): void {
  localStorage.removeItem(key);
  sessionStorage.removeItem(key);
}

export function getToken(): string {
  return readSaved(tokenKey);
}

export function setSession(token: string, name: string): void {
  writeSaved(tokenKey, token);
  writeSaved(nameKey, name);
}

export function adminName(): string {
  return readSaved(nameKey);
}

export function clearSession(): void {
  removeSaved(tokenKey);
  removeSaved(nameKey);
}

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public details?: unknown,
    public code?: string,
  ) {
    super(message);
  }
}

export type ApiInit = RequestInit & { guard?: SaveGuard };

export async function api<T>(path: string, options: ApiInit = {}): Promise<T> {
  const { guard, ...init } = options;
  const headers = new Headers(init.headers);
  // 旧表单覆盖保护：带上页面读数据时的版本号
  const revision = guard?.revisions.of(guard.id);
  if (revision) {
    headers.set("if-match", revision);
  }
  if (init.body) {
    headers.set("content-type", "application/json");
  }
  const token = getToken();
  if (token) {
    headers.set("authorization", `Bearer ${token}`);
  }
  const response = await fetch(path, { ...init, headers });
  if ((response.status === 401 || response.status === 403) && !path.startsWith("/admin/auth/login")) {
    clearSession();
    if (!location.pathname.startsWith("/login")) {
      location.href = "/login";
    }
    throw new Error("需要重新登录");
  }
  if (!response.ok) {
    const body = (await response.json().catch(() => ({}))) as { reason?: string; error?: { code?: string; message?: string; details?: unknown } };
    if (response.status === 409 && body.error?.code === "STALE_REVISION" && guard) {
      const details = body.error.details as ConflictDetails;
      const mine = ((): unknown => {
        try {
          return typeof init.body === "string" ? JSON.parse(init.body) : null;
        } catch {
          return null;
        }
      })();
      const choice = await askConflict({ title: guard.title, details, mine, latest: guard.latest });
      if (choice === "overwrite") {
        // 仍然覆盖 = 带上服务器现在的版本号再发一次（期间又有人保存会再弹一次）
        guard.revisions.set(guard.id, details.revision);
        return api<T>(path, options);
      }
      if (choice === "reload") {
        await guard.reload?.();
      }
      throw new ConflictAbort(choice === "reload" ? "reload" : "cancel");
    }
    throw new ApiError(body.error?.message ?? body.reason ?? "请求失败", response.status, body.error?.details, body.error?.code);
  }
  const fresh = response.headers.get("x-revision");
  if (guard && fresh) {
    guard.revisions.set(guard.id, fresh);
  }
  noteRequest(path, init.method);
  if (response.status === 204) {
    return undefined as T;
  }
  return (await response.json()) as T;
}
