const tokenKey = "xiuxian-admin-token";
const nameKey = "xiuxian-admin-name";

export function getToken(): string {
  return sessionStorage.getItem(tokenKey) ?? "";
}

export function setSession(token: string, name: string): void {
  sessionStorage.setItem(tokenKey, token);
  sessionStorage.setItem(nameKey, name);
}

export function adminName(): string {
  return sessionStorage.getItem(nameKey) ?? "";
}

export function clearSession(): void {
  sessionStorage.removeItem(tokenKey);
  sessionStorage.removeItem(nameKey);
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
    const body = (await response.json().catch(() => ({}))) as { reason?: string; error?: { message?: string } };
    throw new Error(body.error?.message ?? body.reason ?? "请求失败");
  }
  if (response.status === 204) {
    return undefined as T;
  }
  return (await response.json()) as T;
}
