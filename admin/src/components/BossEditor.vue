<template>
  <section class="bosses">
    <header class="head">
      <h3>首领与掉落</h3>
      <span class="sub">玩家挑战时打第一个首领；掉落按掉率逐件判定。</span>
      <el-button size="small" @click="addBoss">添加首领</el-button>
    </header>
    <el-empty v-if="bosses.length === 0" description="还没有首领，玩家无法挑战这个关卡" :image-size="64" />
    <article v-for="(boss, index) in bosses" :key="index" class="boss">
      <header class="boss-head">
        <strong>首领 {{ index + 1 }}<template v-if="index === 0">（玩家挑战的首领）</template></strong>
        <span class="spacer" />
        <el-button size="small" type="success" plain :disabled="!(boss.hp > 0 && boss.interval > 0)" @click="$emit('trial', boss)">试打</el-button>
        <el-button size="small" :disabled="index === 0" @click="move(index, -1)">上移</el-button>
        <el-button size="small" type="danger" plain @click="removeBoss(index)">删除</el-button>
      </header>
      <SchemaForm
        :model-value="boss as unknown as Record<string, unknown>"
        :schema="bossSchema"
        :card="false"
        :show-all-errors="showAllErrors"
        :hidden-keys="['drops']"
        @update:model-value="() => undefined"
        @active="(field) => $emit('active', field)"
      />
      <div class="drops">
        <div class="drops-head">
          <strong>掉落</strong>
          <el-button size="small" link type="primary" @click="boss.drops.push({ itemId: '', chancePercent: undefined })">添加掉落</el-button>
        </div>
        <p v-if="boss.drops.length === 0 && (boss.firstClear ?? []).length === 0 && !boss.repeat" class="muted">没有掉落。玩家打赢也拿不到东西。</p>
        <p v-else-if="boss.drops.length === 0" class="muted">没有按概率掉落的物品；奖励来自下面的「首通固定奖励」和「重复挑战奖励」。</p>
        <div v-for="(drop, dropIndex) in boss.drops" :key="dropIndex" class="drop">
          <el-select v-model="drop.itemId" filterable placeholder="选择装备、物品或功法" class="pick" @focus="$emit('active', dropField)">
            <el-option-group label="装备">
              <el-option v-for="item in weapons" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
            </el-option-group>
            <el-option-group label="物品">
              <el-option v-for="item in items" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
            </el-option-group>
            <el-option-group label="功法">
              <el-option v-for="skill in skills" :key="skill.id" :label="skill.displayName || '名称缺失'" :value="skill.id" />
            </el-option-group>
          </el-select>
          <el-input-number v-model="drop.chancePercent" :min="0" :max="100" :precision="2" :controls="false" class="chance" @focus="$emit('active', chanceField)" />
          <span class="pct">%</span>
          <span class="hint">{{ dropHint(drop.chancePercent) }}</span>
          <el-button link type="danger" @click="boss.drops.splice(dropIndex, 1)">去掉</el-button>
        </div>
      </div>
      <div class="drops">
        <div class="drops-head">
          <strong>首通固定奖励</strong>
          <span>
            <el-button size="small" link type="primary" @click="firstClear(boss).push({ kind: 'item', itemId: '', quantity: 1 })">添加物品</el-button>
            <el-button size="small" link type="primary" @click="firstClear(boss).push({ kind: 'cultivation', amount: 1000 })">添加修为</el-button>
          </span>
        </div>
        <p v-if="(boss.firstClear ?? []).length === 0" class="muted">没有首通固定奖励（走旧的掉落规则）。首通奖励允许暂时超出行囊容量，修为直接入账。</p>
        <div v-for="(entry, entryIndex) in boss.firstClear ?? []" :key="entryIndex" class="drop">
          <el-tag size="small" :type="entry.kind === 'cultivation' ? 'warning' : 'info'">{{ entry.kind === "cultivation" ? "修为" : "物品" }}</el-tag>
          <template v-if="entry.kind === 'item'">
            <el-select v-model="entry.itemId" filterable placeholder="选择装备、物品或功法" class="pick">
              <el-option-group label="装备"><el-option v-for="item in weapons" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" /></el-option-group>
              <el-option-group label="物品"><el-option v-for="item in items" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" /></el-option-group>
              <el-option-group label="功法"><el-option v-for="skill in skills" :key="skill.id" :label="skill.displayName || '名称缺失'" :value="skill.id" /></el-option-group>
            </el-select>
            <el-input-number v-model="entry.quantity" :min="1" :precision="0" :controls="false" class="chance" />
            <span class="pct">个</span>
          </template>
          <template v-else>
            <el-input-number v-model="entry.amount" :min="1" :precision="0" :controls="false" class="pick" />
            <span class="pct">点修为（整数）</span>
          </template>
          <span class="hint" />
          <el-button link type="danger" @click="firstClear(boss).splice(entryIndex, 1)">去掉</el-button>
        </div>
      </div>
      <div class="drops">
        <div class="drops-head">
          <strong>重复挑战奖励（首通之后每天前几次胜利）</strong>
          <el-button v-if="!boss.repeat" size="small" link type="primary" @click="boss.repeat = { gear: true, extras: [] }">启用</el-button>
          <el-button v-else size="small" link type="danger" @click="boss.repeat = null">关闭</el-button>
        </div>
        <p v-if="!boss.repeat" class="muted">没有重复挑战奖励。次数在「战斗公式与参数」里的“首领每日奖励次数”。</p>
        <template v-else>
          <el-checkbox v-model="boss.repeat.gear">本境界阶装备 1 件（品质权重取本关卡的怪物掉落权重，白色按绿色算）</el-checkbox>
          <div class="drops-head">
            <span class="muted">额外物品（各自按概率判定，例如突破石）</span>
            <el-button size="small" link type="primary" @click="boss.repeat.extras.push({ itemId: '', chancePercent: 35, minQty: 1, maxQty: 1 })">添加</el-button>
          </div>
          <div v-for="(extra, extraIndex) in boss.repeat.extras" :key="extraIndex" class="drop">
            <el-select v-model="extra.itemId" filterable placeholder="选择物品" class="pick">
              <el-option v-for="item in items" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
            </el-select>
            <el-input-number v-model="extra.chancePercent" :min="0" :max="100" :precision="2" :controls="false" class="chance" />
            <span class="pct">%</span>
            <el-input-number v-model="extra.minQty" :min="1" :precision="0" :controls="false" class="qty" />
            <span class="pct">到</span>
            <el-input-number v-model="extra.maxQty" :min="1" :precision="0" :controls="false" class="qty" />
            <span class="hint" />
            <el-button link type="danger" @click="boss.repeat.extras.splice(extraIndex, 1)">去掉</el-button>
          </div>
        </template>
      </div>
    </article>
  </section>
</template>

<script setup lang="ts">
import type { FieldDef } from "../schema/types";
import { bossSchema } from "../schema/resources";
import type { Named } from "../composables/lookups";
import SchemaForm from "./SchemaForm.vue";

export type DropRow = { itemId: string; chancePercent: number | undefined };
export type FirstClearRow = { kind: "item"; itemId: string; quantity: number } | { kind: "cultivation"; amount: number };
export type RepeatRow = { gear: boolean; extras: { itemId: string; chancePercent: number; minQty: number; maxQty: number }[] };
export type BossRow = { name: string; attack: number; defense: number; hp: number; interval: number; drops: DropRow[]; firstClear?: FirstClearRow[]; repeat?: RepeatRow | null };

defineProps<{ items: Named[]; weapons: Named[]; skills: Named[]; showAllErrors?: boolean }>();
const bosses = defineModel<BossRow[]>({ required: true });
defineEmits<{ trial: [boss: BossRow]; active: [field: FieldDef | null] }>();

const dropField: FieldDef = { key: "drops[].itemId", label: "掉落物", kind: "select", hint: "首领被击败后可能掉落的装备、物品或功法。功法掉成一本技能书，点了才学会；同一功法的技能书不叠加。", required: true };
const chanceField: FieldDef = { key: "drops[].chancePercent", label: "掉率", kind: "number", unit: "%", min: 0, max: 100, precision: 2, hint: "每次打赢单独判定一次。0 表示不会掉。例：25 即平均打赢 4 次掉一件。", required: true, affects: "掉落产出节奏、行囊压力" };

function firstClear(boss: BossRow): FirstClearRow[] {
  if (!boss.firstClear) {
    boss.firstClear = [];
  }
  return boss.firstClear;
}

function addBoss(): void {
  bosses.value.push({ name: "", attack: 0, defense: 0, hp: 0, interval: 1.5, drops: [] });
}

function removeBoss(index: number): void {
  bosses.value.splice(index, 1);
}

function move(index: number, delta: number): void {
  const target = index + delta;
  if (target < 0 || target >= bosses.value.length) {
    return;
  }
  const [row] = bosses.value.splice(index, 1);
  bosses.value.splice(target, 0, row);
}

function dropHint(percent: number | undefined): string {
  if (percent == null) return "请填掉率";
  if (percent <= 0) return "不会掉";
  return `平均打赢约 ${Math.round((100 / percent) * 100) / 100} 次掉一件`;
}
</script>

<style scoped>
.head {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  padding-bottom: var(--xx-space-1);
  border-bottom: 1px solid var(--xx-border);
}
.head h3 {
  margin: 0;
  font-size: var(--xx-fs-md);
}
.sub {
  flex: 1;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-xs);
}
.boss {
  margin-top: var(--xx-space-3);
  padding: var(--xx-space-3);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
}
.boss-head {
  display: flex;
  align-items: center;
  gap: var(--xx-space-2);
}
.spacer {
  flex: 1;
}
.drops {
  margin-top: var(--xx-space-2);
  padding-top: var(--xx-space-2);
  border-top: 1px dashed var(--xx-border);
}
.drops-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.drop {
  display: flex;
  align-items: center;
  gap: var(--xx-space-2);
  margin-top: var(--xx-space-2);
}
.pick {
  width: 220px;
}
.chance {
  width: 90px;
}
.qty {
  width: 64px;
}
.pct,
.hint,
.muted {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.hint {
  flex: 1;
}
</style>
