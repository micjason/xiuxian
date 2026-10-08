import { getDb, getSql } from "../db/client.js";
import { createAdmin } from "../modules/auth/service.js";

const username = process.env.ADMIN_USERNAME;
const password = process.env.ADMIN_PASSWORD;
const roleFlag = process.argv.find((arg) => arg.startsWith("--role="));
const role = roleFlag?.slice("--role=".length);
if (!username || !password) {
  process.exit(1);
}

const db = getDb();
await createAdmin(db, { username, password, role });
await getSql().end();
