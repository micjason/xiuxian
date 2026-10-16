// 本地开发用：保证 DATABASE_URL 指向的库存在（以及测试库 xiuxian_test）。
// 用同一个账号连到 postgres 维护库去建库；库已经存在就什么都不做。
// 账号需要有建库权限（docker compose 里的 xiuxian 账号有）。
import postgres from "postgres";

const url = process.env.DATABASE_URL;
if (!url) {
  console.error("缺少 DATABASE_URL（检查 backend/.env）");
  process.exit(1);
}
const target = new URL(url);
const wanted = [decodeURIComponent(target.pathname.slice(1)), "xiuxian_test"];
const admin = new URL(url);
admin.pathname = "/postgres";
const sql = postgres(admin.toString(), { max: 1, connect_timeout: 5 });
try {
  for (const name of new Set(wanted)) {
    if (!/^[a-z0-9_]+$/i.test(name)) {
      throw new Error(`库名只能含字母、数字、下划线：${name}`);
    }
    const rows = await sql`select 1 from pg_database where datname = ${name}`;
    if (rows.length === 0) {
      await sql.unsafe(`create database "${name}"`);
      console.log(`created database ${name}`);
    } else {
      console.log(`database ${name} exists`);
    }
  }
} catch (error) {
  console.error(`连不上数据库或没有建库权限：${error instanceof Error ? error.message : String(error)}`);
  process.exitCode = 1;
} finally {
  await sql.end();
}
