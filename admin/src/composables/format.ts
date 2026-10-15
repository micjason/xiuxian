export function formatTime(value: string | number | Date | null | undefined): string {
  if (value === null || value === undefined || value === "") {
    return "—";
  }
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return "—";
  }
  const pad = (n: number): string => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

export function relativeTime(value: string | number | Date | null | undefined, now = Date.now()): string {
  if (value === null || value === undefined || value === "") {
    return "—";
  }
  const time = new Date(value).getTime();
  if (Number.isNaN(time)) {
    return "—";
  }
  const seconds = Math.max(0, Math.round((now - time) / 1000));
  if (seconds < 60) return "刚刚";
  if (seconds < 3600) return `${Math.floor(seconds / 60)} 分钟前`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} 小时前`;
  if (seconds < 86400 * 30) return `${Math.floor(seconds / 86400)} 天前`;
  return formatTime(value);
}

export function compactNumber(value: number | null | undefined): string {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return "—";
  }
  const abs = Math.abs(value);
  if (abs >= 100_000_000) return `${(value / 100_000_000).toFixed(2)} 亿`;
  if (abs >= 10_000) return `${(value / 10_000).toFixed(2)} 万`;
  return Number.isInteger(value) ? String(value) : value.toFixed(2);
}

export function toCsv(rows: Record<string, unknown>[], columns: { key: string; label: string }[]): string {
  const cell = (value: unknown): string => {
    const text = value === null || value === undefined ? "" : typeof value === "object" ? JSON.stringify(value) : String(value);
    return /[",\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  };
  const head = columns.map((column) => cell(column.label)).join(",");
  const body = rows.map((row) => columns.map((column) => cell(row[column.key])).join(","));
  return `\uFEFF${[head, ...body].join("\n")}`;
}

export function downloadText(filename: string, text: string): void {
  const url = URL.createObjectURL(new Blob([text], { type: "text/csv;charset=utf-8" }));
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  link.click();
  URL.revokeObjectURL(url);
}
