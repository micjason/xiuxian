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
  ) {
    super(message);
  }
}

export async function api<T>(path: string, init: RequestInit = {}): Promise<T> {
  const headers = new Headers(init.headers);
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
    const body = (await response.json().catch(() => ({}))) as { reason?: string; error?: { message?: string; details?: unknown } };
    throw new ApiError(body.error?.message ?? body.reason ?? "请求失败", response.status, body.error?.details);
  }
  if (response.status === 204) {
    return undefined as T;
  }
  return (await response.json()) as T;
}
