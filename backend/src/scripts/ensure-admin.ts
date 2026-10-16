// 本地开发用：保证有一个后台管理员账号。账号已存在就不动（除非 ADMIN_RESET=1，则只改密码）。
// 账号和密码从环境变量 ADMIN_USERNAME / ADMIN_PASSWORD 读，不放在命令行参数里，避免出现在进程列表。
// 退出码 0；标准输出最后一行是 created / exists / reset 之一。
import { eq } from "drizzle-orm";
import argon2 from "argon2";
import { getDb, getSql } from "../db/client.js";
import { admins } from "../db/schema.js";
import { createAdmin } from "../modules/auth/service.js";
import { parseCredentials } from "../modules/auth/credentials.js";

const username = process.env.ADMIN_USERNAME;
const password = process.env.ADMIN_PASSWORD;
if (!username || !password) {
  console.error("需要环境变量 ADMIN_USERNAME 和 ADMIN_PASSWORD");
  process.exit(1);
}
if (password.length < 8 || password.toLowerCase() === username.toLowerCase()) {
  console.error("管理员密码至少 8 位，且不能和用户名相同");
  process.exit(1);
}
parseCredentials(username, password);
const db = getDb();
const [existing] = await db.select().from(admins).where(eq(admins.username, username)).limit(1);
if (!existing) {
  await createAdmin(db, { username, password, role: "owner" });
  console.log("created");
} else if (process.env.ADMIN_RESET === "1") {
  await db.update(admins).set({ passwordHash: await argon2.hash(password) }).where(eq(admins.id, existing.id));
  console.log("reset");
} else {
  console.log("exists");
}
await getSql().end();
