import { getDb, getSql } from "../db/client.js";
import { statsAtPower, type StatBlock } from "../modules/content/puppet-build.js";
import { createTrialPuppet, listTrialPuppets } from "../modules/content/puppets.js";
import { readGameRules } from "../modules/content/rules.js";
import { loadDraftSnapshot } from "../modules/content/snapshot.js";

const url = process.env.DATABASE_URL ?? "";
if (!url.includes("xiuxian_dev")) {
  console.error("只往 xiuxian_dev 里加人偶");
  process.exit(1);
}

const shapes: { name: string; power: number; shares: StatBlock }[] = [
  { name: "均衡 1000", power: 1000, shares: { attack: 0.47, defense: 0.16, hp: 0.32, speed: 0.05 } },
  { name: "偏攻击 1000", power: 1000, shares: { attack: 0.7, defense: 0.1, hp: 0.15, speed: 0.05 } },
  { name: "偏防御 1000", power: 1000, shares: { attack: 0.2, defense: 0.5, hp: 0.25, speed: 0.05 } },
  { name: "偏气血 1000", power: 1000, shares: { attack: 0.2, defense: 0.1, hp: 0.65, speed: 0.05 } },
  { name: "偏速度 1000", power: 1000, shares: { attack: 0.25, defense: 0.1, hp: 0.2, speed: 0.45 } },
  { name: "均衡 1200", power: 1200, shares: { attack: 0.47, defense: 0.16, hp: 0.32, speed: 0.05 } },
  { name: "偏攻击 1200", power: 1200, shares: { attack: 0.7, defense: 0.1, hp: 0.15, speed: 0.05 } },
  { name: "偏防御 1200", power: 1200, shares: { attack: 0.2, defense: 0.5, hp: 0.25, speed: 0.05 } },
  { name: "偏气血 1200", power: 1200, shares: { attack: 0.2, defense: 0.1, hp: 0.65, speed: 0.05 } },
  { name: "偏速度 1200", power: 1200, shares: { attack: 0.25, defense: 0.1, hp: 0.2, speed: 0.45 } },
  { name: "玻璃大炮", power: 1000, shares: { attack: 0.88, defense: 0.02, hp: 0.05, speed: 0.05 } },
  { name: "超快速度", power: 1000, shares: { attack: 0.12, defense: 0.04, hp: 0.08, speed: 0.76 } },
  { name: "超高血量", power: 1000, shares: { attack: 0.08, defense: 0.04, hp: 0.84, speed: 0.04 } },
  { name: "铁壁", power: 1000, shares: { attack: 0.08, defense: 0.78, hp: 0.1, speed: 0.04 } },
];

const db = getDb();
const rules = readGameRules(await loadDraftSnapshot(db));
const existing = new Set((await listTrialPuppets(db)).map((row) => row.displayName));

function intervalOf(speed: number): number {
  return Math.max(rules.minInterval, (1.5 * rules.speedBase) / (rules.speedBase + Math.max(speed, 0)));
}

for (const shape of shapes) {
  if (existing.has(shape.name)) {
    console.log(`已有 ${shape.name}`);
    continue;
  }
  const stats = statsAtPower(shape.power, shape.shares, rules.powerWeights);
  await createTrialPuppet(
    db,
    { displayName: shape.name, kind: "manual", ...stats, interval: intervalOf(stats.speed) },
    null,
  );
  console.log(`新建 ${shape.name}`);
}

const listed = await listTrialPuppets(db);
for (const shape of shapes) {
  const row = listed.find((item) => item.displayName === shape.name);
  console.log(`${shape.name}\t战力 ${row?.power}\t${row?.tendency}\t攻 ${row?.attack} 防 ${row?.defense} 血 ${row?.hp} 速 ${row?.speed} 间隔 ${row?.interval}`);
}
await getSql().end();
