// 本地端到端联调用：给某个已注册的玩家改状态（只在开发库用）。
// 用法：DATABASE_URL=... npx tsx src/scripts/e2e-prepare.ts <用户名> <动作> [参数]
//   offline <小时>   把上次结算时间拨回 N 小时前（下一次心跳会生成离线收益报告）
//   cultivation <数>  设置修为
//   realm <slug>      设置境界
//   fillbag <数量>    往背包塞白色装备到指定总数（不含已穿戴）
//   autodecompose <on|off>
//   gear <品质>       穿上一整套 major1 装备（weapon/helmet/clothes/gloves/shoes/accessory），先卸掉已穿的
//   skill <slug>      学会并运行某本功法（running_slot=heart）
//   clear <stageSlug> 标记某关卡已首通
import postgres from "postgres";

const [username, action, arg] = process.argv.slice(2);
const sql = postgres(process.env.DATABASE_URL!, { max: 1 });
const [player] = await sql`select id from players where username_lower = ${username.toLowerCase()}`;
if (!player) throw new Error(`没有这个玩家：${username}`);
const id = player.id as string;
if (action === "offline") {
  await sql`update player_states set last_settled_at = now() - make_interval(secs => ${Number(arg) * 3600}) where player_id = ${id}`;
} else if (action === "cultivation") {
  await sql`update player_states set cultivation = ${Number(arg)} where player_id = ${id}`;
} else if (action === "realm") {
  await sql`update player_states set realm_slug = ${arg} where player_id = ${id}`;
} else if (action === "autodecompose") {
  await sql`update player_states set auto_decompose = ${arg === "on"} where player_id = ${id}`;
} else if (action === "clear") {
  await sql`insert into player_stage_progress (player_id, stage_slug, first_cleared_at, clear_count) values (${id}, ${arg}, now(), 1)
    on conflict (player_id, stage_slug) do update set first_cleared_at = coalesce(player_stage_progress.first_cleared_at, now())`;
} else if (action === "skill") {
  await sql`insert into player_skills (player_id, skill_slug, level, running_slot) values (${id}, ${arg}, 1, 'heart')
    on conflict (player_id, skill_slug) do update set running_slot = 'heart'`;
} else if (action === "gear") {
  await sql`delete from player_items where player_id = ${id} and equipped_slot is not null`;
  for (const slot of ["weapon", "helmet", "clothes", "gloves", "shoes", "accessory"]) {
    await sql`insert into player_items (player_id, item_slug, is_stack, quantity, equipped_slot, source) values (${id}, ${`gear_major1_${slot}_${arg}`}, false, 1, ${slot}, 'e2e')`;
  }
} else if (action === "fillbag") {
  const [{ n }] = await sql`select count(*)::int as n from player_items where player_id = ${id} and equipped_slot is null`;
  const need = Number(arg) - (n as number);
  for (let i = 0; i < need; i++) {
    await sql`insert into player_items (player_id, item_slug, is_stack, quantity, source) values (${id}, 'gear_major1_weapon_white', false, 1, 'e2e')`;
  }
  console.log(`bag ${n} -> ${Math.max(n as number, Number(arg))}`);
} else {
  throw new Error(`未知动作 ${action}`);
}
console.log("ok", action, arg ?? "");
await sql.end();
