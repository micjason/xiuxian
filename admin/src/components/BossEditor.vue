<template>
  <div class="boss-editor">
    <div v-if="bosses.length === 0" class="empty">
      <p>本关没有首领，玩家在这里只刷普通怪</p>
      <el-button size="small" @click="addBoss">＋ 添加首领</el-button>
    </div>
    <template v-else>
      <table class="grid">
        <thead>
          <tr>
            <th class="name">名称</th>
            <th class="num">攻击</th>
            <th class="num">防御</th>
            <th class="num">气血</th>
            <th class="num">攻击间隔<HelpTip title="首领攻击间隔" text="每次出手相隔的秒数，越小越快；比境界基础间隔快的部分会折算成速度，计入首领战力。" meta="不能小于最短出手间隔" /></th>
            <th class="num">首领战力<HelpTip title="首领战力（只读）" :text="`攻击 × ${weights.attack} + 防御 × ${weights.defense} + 气血 × ${weights.hp} + 速度 × ${weights.speed}`" /></th>
            <th class="ops">操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(boss, index) in bosses" :key="index">
            <td class="name"><el-input v-model="boss.name" placeholder="首领名称" /></td>
            <td class="num"><NumInput v-model="boss.attack" :width="120" /></td>
            <td class="num"><NumInput v-model="boss.defense" :width="120" /></td>
            <td class="num"><NumInput v-model="boss.hp" :width="120" :min="1" /></td>
            <td class="num"><NumInput v-model="boss.interval" :width="120" unit="秒" :precision="2" :step="0.05" :min="0.1" /></td>
            <td class="num"><NumInput :model-value="powerOf(boss)" :width="120" unit="战力" readonly /></td>
            <td class="ops">
              <el-button link type="primary" :disabled="!(boss.hp > 0 && boss.interval > 0)" @click="$emit('trial', boss)">试打</el-button>
              <el-button link type="danger" @click="bosses.splice(index, 1)">删除</el-button>
            </td>
          </tr>
        </tbody>
      </table>
      <p v-if="bosses.length > 1" class="muted pad">玩家点「挑战」打第一个首领。</p>

      <div v-for="(boss, index) in bosses.slice(0, 1)" :key="`r${index}`" class="rewards">
        <!-- 首通奖励 -->
        <div class="sub-card">
          <header class="sub-head"><strong>首通奖励</strong><span class="muted">第一次击败时全部发放</span></header>
          <table class="grid">
            <thead>
              <tr>
                <th class="type">类型</th>
                <th>物品</th>
                <th class="num">数量</th>
                <th class="ops">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(entry, entryIndex) in boss.firstClear ?? []" :key="entryIndex">
                <td class="type">
                  <el-select :model-value="entryKind(entry)" class="w100" @update:model-value="(kind: string) => setKind(boss, entryIndex, kind)">
                    <el-option label="功法" value="skill" />
                    <el-option label="装备" value="gear" />
                    <el-option label="物品" value="item" />
                    <el-option label="修为" value="cultivation" />
                  </el-select>
                </td>
                <td>
                  <el-select v-if="entry.kind === 'item'" v-model="entry.itemId" filterable placeholder="选择" class="w320">
                    <el-option v-for="option in optionsFor(entryKind(entry))" :key="option.id" :label="option.displayName || '名称缺失'" :value="option.id" />
                  </el-select>
                  <span v-else class="muted">直接加到修为</span>
                </td>
                <td class="num">
                  <NumInput v-if="entry.kind === 'item'" v-model="entry.quantity" :width="100" :min="1" :precision="0" :unit="entryKind(entry) === 'skill' ? '本' : entryKind(entry) === 'gear' ? '件' : '个'" />
                  <NumInput v-else v-model="entry.amount" :width="100" :min="1" :precision="0" unit="修为" />
                </td>
                <td class="ops"><el-button link type="danger" @click="firstClear(boss).splice(entryIndex, 1)">删除</el-button></td>
              </tr>
            </tbody>
          </table>
          <button type="button" class="add-row" @click="firstClear(boss).push({ kind: 'item', itemId: '', quantity: 1 })">＋ 添加奖励</button>
        </div>

        <!-- 重复奖励 -->
        <div class="sub-card">
          <header class="sub-head"><strong>重复奖励</strong><span class="muted">之后每次胜利；每日前 {{ dailyCount }} 次有奖励</span></header>
          <div class="repeat-line">
            <el-switch :model-value="!!boss.repeat?.gear" @update:model-value="(on: string | number | boolean) => setGear(boss, !!on)" />
            <span>每次给 1 件本境界阶装备</span>
            <HelpTip title="重复奖励 · 给装备" :text="`每次有奖励的胜利给 1 件本境界阶装备，品质用本关权重，白改为绿；每日前 ${dailyCount} 次有奖励。部位按装备的掉率倍数分配。`" />
            <span class="muted">品质按上方权重，白改为绿</span>
          </div>
          <div v-if="boss.repeat?.gear" class="repeat-line">
            <span class="lbl">其中橙装概率<HelpTip title="首领橙装概率" text="给的这件装备直接是橙色的概率。橙装只由首领掉，普通怪不掉。不改就跟随配置概览。" :meta="`范围 0–100% · 默认 ${orangeDefault}%（配置概览）`" /></span>
            <NumInput
              v-model="boss.repeat.orangeChancePercent"
              :width="120"
              unit="%"
              :precision="2"
              :max="100"
              :inherit-value="orangeDefault"
              :custom="boss.repeat.orangeChancePercent != null"
            />
            <CustomTag v-if="boss.repeat.orangeChancePercent != null" kind="custom">已自定义</CustomTag>
            <el-button v-if="boss.repeat.orangeChancePercent != null" link type="primary" @click="boss.repeat.orangeChancePercent = null">↺ 恢复默认</el-button>
            <span v-else class="muted">跟随配置概览</span>
          </div>
          <table class="grid">
            <thead>
              <tr>
                <th>额外物品</th>
                <th class="num">概率<HelpTip title="额外物品概率" text="每样物品各自独立掷骰。" /></th>
                <th class="range">数量范围</th>
                <th class="ops">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(extra, extraIndex) in boss.repeat?.extras ?? []" :key="extraIndex">
                <td>
                  <el-select v-model="extra.itemId" filterable placeholder="选择物品" class="w320">
                    <el-option v-for="item in items" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
                  </el-select>
                </td>
                <td class="num"><NumInput v-model="extra.chancePercent" :width="120" unit="%" :precision="2" :max="100" /></td>
                <td class="range">
                  <NumInput v-model="extra.minQty" :width="88" :min="1" :precision="0" unit="个" />
                  <span class="dash">–</span>
                  <NumInput v-model="extra.maxQty" :width="88" :min="1" :precision="0" unit="个" />
                </td>
                <td class="ops"><el-button link type="danger" @click="repeat(boss).extras.splice(extraIndex, 1)">删除</el-button></td>
              </tr>
            </tbody>
          </table>
          <button type="button" class="add-row" @click="repeat(boss).extras.push({ itemId: '', chancePercent: 30, minQty: 1, maxQty: 1 })">＋ 添加额外物品</button>
        </div>

        <!-- 旧版按概率掉落（老内容才有；新内容走首通 / 重复奖励） -->
        <div v-if="boss.drops.length > 0" class="sub-card">
          <header class="sub-head"><strong>旧版掉落</strong><span class="muted">老内容的按概率掉落，已配了首通 / 重复奖励时不再生效</span></header>
          <div v-for="(drop, dropIndex) in boss.drops" :key="dropIndex" class="repeat-line">
            <el-select v-model="drop.itemId" filterable class="w320">
              <el-option v-for="item in [...weapons, ...items, ...skills]" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
            </el-select>
            <NumInput v-model="drop.chancePercent" :width="120" unit="%" :precision="2" :max="100" />
            <el-button link type="danger" @click="boss.drops.splice(dropIndex, 1)">删除</el-button>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
import type { Named } from "../composables/lookups";
import CustomTag from "./CustomTag.vue";
import HelpTip from "./HelpTip.vue";
import NumInput from "./NumInput.vue";

export type DropRow = { itemId: string; chancePercent: number | undefined };
export type FirstClearRow = { kind: "item"; itemId: string; quantity: number } | { kind: "cultivation"; amount: number };
export type RepeatRow = { gear: boolean; orangeChancePercent?: number | null; extras: { itemId: string; chancePercent: number; minQty: number; maxQty: number }[] };
export type BossRow = { name: string; attack: number; defense: number; hp: number; interval: number; drops: DropRow[]; firstClear?: FirstClearRow[]; repeat?: RepeatRow | null };

const props = defineProps<{
  items: Named[];
  weapons: Named[];
  skills: Named[];
  showAllErrors?: boolean;
  powerOf: (boss: BossRow) => number | null;
  weights: { attack: number; defense: number; hp: number; speed: number };
  dailyCount: number;
  orangeDefault: number;
}>();
const bosses = defineModel<BossRow[]>({ required: true });
defineEmits<{ trial: [boss: BossRow] }>();

function firstClear(boss: BossRow): FirstClearRow[] {
  if (!boss.firstClear) {
    boss.firstClear = [];
  }
  return boss.firstClear;
}

function repeat(boss: BossRow): RepeatRow {
  if (!boss.repeat) {
    boss.repeat = { gear: false, extras: [] };
  }
  return boss.repeat;
}

function setGear(boss: BossRow, on: boolean): void {
  repeat(boss).gear = on;
}

function entryKind(entry: FirstClearRow): string {
  if (entry.kind === "cultivation") return "cultivation";
  if (props.skills.some((skill) => skill.id === entry.itemId) || entry.itemId.startsWith("book_")) return "skill";
  if (props.weapons.some((weapon) => weapon.id === entry.itemId) || entry.itemId.startsWith("gear_")) return "gear";
  return "item";
}

function optionsFor(kind: string): Named[] {
  if (kind === "skill") return props.skills;
  if (kind === "gear") return props.weapons;
  return props.items;
}

function setKind(boss: BossRow, index: number, kind: string): void {
  const list = firstClear(boss);
  list[index] = kind === "cultivation" ? { kind: "cultivation", amount: 1000 } : { kind: "item", itemId: optionsFor(kind)[0]?.id ?? "", quantity: 1 };
}

function addBoss(): void {
  bosses.value.push({ name: "", attack: 0, defense: 0, hp: 1, interval: 1.5, drops: [], firstClear: [], repeat: { gear: true, extras: [] } });
}

defineExpose({ addBoss });
</script>

<style scoped>
.empty {
  display: grid;
  place-items: center;
  gap: 8px;
  padding: 24px;
  border: 1px dashed var(--xx-border-strong);
  border-radius: 8px;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.empty p {
  margin: 0;
}
.grid {
  width: 100%;
  border-collapse: collapse;
  font-size: var(--xx-fs-sm);
}
.grid th {
  height: 36px;
  padding: 0 8px;
  background: var(--xx-bg-subtle);
  color: var(--xx-text-secondary);
  font-weight: 500;
  text-align: left;
  white-space: nowrap;
}
.grid td {
  height: 44px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--xx-border);
}
.grid .num {
  width: 136px;
  text-align: right;
}
.grid .name :deep(.el-input) {
  width: 200px;
}
.grid .type {
  width: 116px;
}
.grid .range {
  width: 220px;
  white-space: nowrap;
}
.grid .ops {
  width: 96px;
  text-align: right;
  white-space: nowrap;
}
.dash {
  margin: 0 6px;
  color: var(--xx-text-placeholder);
}
.w100 {
  width: 100px;
}
.w320 {
  width: 320px;
}
.rewards {
  display: grid;
  gap: 16px;
  margin-top: 16px;
}
.sub-card {
  border: 1px solid var(--xx-border);
  border-radius: 8px;
  background: var(--xx-bg-surface);
  overflow: hidden;
}
.sub-head {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 40px;
  padding: 0 12px;
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-subtle);
}
.repeat-line {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  font-size: var(--xx-fs-sm);
}
.lbl {
  margin-left: 46px;
}
.add-row {
  display: block;
  width: calc(100% - 24px);
  margin: 10px 12px;
  padding: 6px;
  border: 1px dashed var(--xx-border-strong);
  border-radius: 6px;
  background: transparent;
  color: var(--xx-jade-600);
  cursor: pointer;
}
.add-row:hover {
  background: var(--xx-bg-hover);
}
.muted {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.pad {
  margin: 8px 0 0;
}
</style>
