const key = "xiuxian-admin-theme";

export function isDark(): boolean {
  return localStorage.getItem(key) === "dark";
}

export function applyTheme(dark: boolean): void {
  document.documentElement.classList.toggle("dark", dark);
  localStorage.setItem(key, dark ? "dark" : "light");
}

export function initTheme(): void {
  document.documentElement.classList.toggle("dark", isDark());
}
