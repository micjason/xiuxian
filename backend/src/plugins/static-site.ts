// 线上没有 nginx 时，由后端自己提供两类静态文件（都只读、不需要登录）：
//   STATIC_DOWNLOAD_DIR → /download/…    安装包和 latest.json（客户端检查更新用）
//   STATIC_ADMIN_DIR    → /              后台网页（Vue 单页应用：找不到的页面路径回到 index.html）
// 两个变量都不设时什么都不注册（本机开发、测试和以前一样）。
import { createReadStream } from "node:fs";
import { stat } from "node:fs/promises";
import path from "node:path";
import type { FastifyInstance, FastifyReply } from "fastify";

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".ttf": "font/ttf",
  ".txt": "text/plain; charset=utf-8",
  ".apk": "application/vnd.android.package-archive",
};

// 这些前缀是接口，不能被后台网页的“回到 index.html”吞掉
const API_PREFIXES = ["/api/", "/admin/", "/auth/", "/me", "/content/", "/apk/", "/update.json", "/healthz", "/download/"];

/** 把 URL 路径安全地映射到 root 下的文件；越界（../）或隐藏文件返回 null。 */
export function resolveInside(root: string, urlPath: string): string | null {
  let decoded: string;
  try {
    decoded = decodeURIComponent(urlPath.split("?")[0] ?? "");
  } catch {
    return null;
  }
  if (decoded.includes("\0")) return null;
  const parts = decoded.split("/").filter((p) => p.length > 0);
  if (parts.some((p) => p === ".." || p.startsWith("."))) return null;
  const full = path.resolve(root, ...parts);
  const base = path.resolve(root);
  return full === base || full.startsWith(base + path.sep) ? full : null;
}

async function sendFile(reply: FastifyReply, file: string, cache: string, head: boolean): Promise<boolean> {
  let info;
  try {
    info = await stat(file);
  } catch {
    return false;
  }
  if (!info.isFile()) return false;
  reply.header("content-type", TYPES[path.extname(file).toLowerCase()] ?? "application/octet-stream");
  reply.header("content-length", String(info.size));
  reply.header("cache-control", cache);
  reply.header("x-content-type-options", "nosniff");
  if (head) {
    await reply.send();
  } else {
    await reply.send(createReadStream(file));
  }
  return true;
}

export async function registerStaticSite(app: FastifyInstance, env: NodeJS.ProcessEnv = process.env): Promise<void> {
  const downloadDir = env.STATIC_DOWNLOAD_DIR;
  const adminDir = env.STATIC_ADMIN_DIR;

  if (downloadDir) {
    app.route({
      method: ["GET", "HEAD"],
      url: "/download/*",
      handler: async (request, reply) => {
        const rel = (request.params as { "*": string })["*"] ?? "";
        const file = resolveInside(downloadDir, rel);
        // latest.json 每次都要拿最新的；安装包文件名带版本号，可以长期缓存
        const cache = rel.endsWith(".json") ? "no-cache, no-store, must-revalidate" : "public, max-age=31536000, immutable";
        if (file && (await sendFile(reply, file, cache, request.method === "HEAD"))) return reply;
        return reply.code(404).send({ code: "NOT_FOUND", message: "文件不存在" });
      },
    });
  }

  if (adminDir) {
    app.setNotFoundHandler(async (request, reply) => {
      const url = request.url.split("?")[0] ?? "/";
      const isApi = API_PREFIXES.some((p) => url === p.replace(/\/$/, "") || url.startsWith(p));
      if ((request.method === "GET" || request.method === "HEAD") && !isApi) {
        const head = request.method === "HEAD";
        const file = resolveInside(adminDir, url);
        // 构建产物 assets/ 下的文件名带哈希，长期缓存；index.html 不缓存
        const cache = url.startsWith("/assets/") ? "public, max-age=604800, immutable" : "no-cache";
        if (file && file !== path.resolve(adminDir) && (await sendFile(reply, file, cache, head))) return reply;
        // 单页应用：没有扩展名的路径（/dashboard、/config/items…）回到 index.html
        if (!path.extname(url) && (await sendFile(reply, path.join(adminDir, "index.html"), "no-cache", head))) return reply;
      }
      return reply.code(404).send({ message: `Route ${request.method}:${url} not found`, error: "Not Found", statusCode: 404 });
    });
  }
}
