// 后台管理员账号密码：只从 0600 文件读（路径来自 ADMIN_CRED_FILE，默认 /workspace/.deploy/admin-credentials.env）。
// 支持两种格式：KEY=VALUE（ADMIN_USER / ADMIN_PASS / ADMIN_URL，deploy.sh admin-password 写的），
// 或服务器原始格式「后台管理员账号：x」（全角或半角冒号）。不打印任何内容；权限比 0600 宽时拒绝读取。
import { readFileSync, statSync } from "node:fs";

export const DEFAULT_ADMIN_CRED_FILE = "/workspace/.deploy/admin-credentials.env";

export function readCredFile(path) {
  const mode = statSync(path).mode & 0o777;
  if (mode & 0o077) {
    throw new Error(`凭据文件 ${path} 的权限是 ${mode.toString(8)}，要先 chmod 600`);
  }
  const out = {};
  for (const raw of readFileSync(path, "utf8").split(/\r?\n/)) {
    const m = raw.match(/^\s*([^=:：＝]+?)\s*[=:：＝]\s*(.*?)\s*$/);
    if (!m) continue;
    const key = m[1];
    const value = m[2].replace(/^["']|["']$/g, "");
    if (/^ADMIN_USER$|账号/.test(key)) out.username = value;
    else if (/^ADMIN_PASS$|密码/.test(key)) out.password = value;
    else if (/^ADMIN_URL$|网址/.test(key)) out.url = value;
    else out[key] = value;
  }
  return out;
}

export function readAdminCred(path = process.env.ADMIN_CRED_FILE || DEFAULT_ADMIN_CRED_FILE) {
  const cred = readCredFile(path);
  if (!cred.username || !cred.password) {
    throw new Error(`凭据文件 ${path} 里没有账号或密码`);
  }
  return { username: cred.username, password: cred.password };
}
