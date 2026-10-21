<template>
  <SectionCard title="指定掉落" anchor="sec-designated" desc="和随机掉落同时生效：每条单独按概率抽，不占随机掉落的概率">
    <div v-if="rows.length === 0" class="empty">
      <span class="muted">本关没有指定掉落，只有随机掉落和首领奖励</span>
      <el-button type="primary" plain size="small" @click="add">＋ 添加指定掉落</el-button>
    </div>
    <template v-else>
      <el-table :data="rows" size="small" class="drops">
        <el-table-column label="装备" min-width="330">
          <template #default="{ row }">
            <el-select v-model="row.itemId" filterable class="w320" placeholder="搜索装备">
              <el-option v-for="item in gear" :key="item.id" :label="item.displayName" :value="item.id" :disabled="used(item.id, row)">
                <span class="opt">
                  <span class="icon-box" :style="{ background: QUALITY_BG[item.quality] }"><img v-if="iconOf(item)" :src="iconOf(item)" alt="" /></span>
                  {{ item.displayName }}
                  <span class="q-tag" :style="{ color: qColor(item.quality), borderColor: qColor(item.quality) }">{{ qShort(item.quality) }}</span>
                  <span class="muted small">{{ item.slotName }} · {{ item.origin === "manual" ? "手动" : "公式" }}</span>
                  <span v-if="used(item.id, row)" class="muted small">· 已在本关</span>
                </span>
              </el-option>
            </el-select>
          </template>
        </el-table-column>
        <el-table-column width="170">
          <template #header>触发<HelpTip title="触发" text="普通怪每只：每杀一只抽一次。首领首通：第一次击败首领时。首领重复：有奖励的重打（首领规则不给重打奖励时不生效）。" /></template>
          <template #default="{ row }">
            <el-select v-model="row.trigger" class="w160">
              <el-option v-for="trigger in TRIGGERS" :key="trigger.key" :label="trigger.name" :value="trigger.key" />
            </el-select>
          </template>
        </el-table-column>
        <el-table-column width="150">
          <template #header>概率<HelpTip title="概率" text="每次触发时掉这一条的概率，0.01%–100%。" /></template>
          <template #default="{ row }"><NumInput v-model="row.chancePercent" :width="120" unit="%" :precision="2" :min="0.01" :max="100" /></template>
        </el-table-column>
        <el-table-column label="数量" width="130">
          <template #default="{ row }"><NumInput v-model="row.count" :width="100" unit="件" :precision="0" :min="1" :max="10" /></template>
        </el-table-column>
        <el-table-column width="70">
          <template #default="{ $index }"><el-button link type="danger" @click="rows.splice($index, 1)">删除</el-button></template>
        </el-table-column>
      </el-table>
      <el-button class="add" size="small" :disabled="rows.length >= 20" @click="add">＋ 添加指定掉落</el-button>
    </template>
    <p class="muted small note">所有掉落都走「发放指定装备」接口（来源：普通怪 = stage_drop，首领首通 = boss_first，首领重复 = boss_repeat）。手动装备不参与随机掉落时，只能从这里或补发获得。</p>
  </SectionCard>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue";
import { api } from "../../../api";
import HelpTip from "../../../components/HelpTip.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";
import { autoGearIcon, iconUrl, useItemIcons } from "../../../composables/itemIcons";

/** 关卡抽屉「指定掉落」一节（批次②）：单独的组件，关卡抽屉只负责挂载和把值带进保存。 */
export type DesignatedRow = { itemId: string; trigger: "monster" | "boss_first" | "boss_repeat"; chancePercent: number | null; count: number | null };
type GearOption = { id: string; displayName: string; quality: string; slot: string; slotName: string; origin: "formula" | "manual"; iconKey: string };

const rows = defineModel<DesignatedRow[]>({ required: true });
const TRIGGERS = [
  { key: "monster", name: "普通怪每只" },
  { key: "boss_first", name: "首领首通" },
  { key: "boss_repeat", name: "首领重复" },
] as const;
const QUALITY_BG: Record<string, string> = { white: "#eceeea", green: "#e3f1e5", blue: "#e2ecf7", purple: "#efe6f7", orange: "#fbeadb" };
const icons = useItemIcons();
const gear = ref<GearOption[]>([]);
const qualities = ref<{ key: string; short: string; color: string }[]>([]);

function add(): void {
  rows.value.push({ itemId: "", trigger: "monster", chancePercent: 1, count: 1 });
}

function used(id: string, row: DesignatedRow): boolean {
  return id !== row.itemId && rows.value.some((other) => other !== row && other.itemId === id && other.trigger === row.trigger);
}

function qShort(key: string): string {
  return qualities.value.find((row) => row.key === key)?.short ?? key;
}

function qColor(key: string): string {
  return qualities.value.find((row) => row.key === key)?.color ?? "#999";
}

function iconOf(item: GearOption): string {
  return iconUrl(icons.value, item.iconKey || autoGearIcon(item.slot));
}

onMounted(async () => {
  if (!Array.isArray(rows.value)) rows.value = [];
  type List = {
    majors: { majorName: string; pieces: Omit<GearOption, "origin">[] }[];
    manual: Omit<GearOption, "origin">[];
    qualities: { key: string; short: string; color: string }[];
  };
  const list = await api<List>("/admin/draft/gear");
  qualities.value = list.qualities ?? [];
  gear.value = [
    ...(list.manual ?? []).map((row) => ({ ...row, origin: "manual" as const })),
    ...list.majors.flatMap((major) => major.pieces.map((piece) => ({ ...piece, origin: "formula" as const }))),
  ];
});
</script>

<style scoped>
.empty {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 16px;
  border: 1px dashed #c9cec8;
  border-radius: 8px;
}
.add {
  margin-top: 10px;
}
.note {
  margin: 10px 0 0;
}
.opt {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.icon-box {
  display: inline-grid;
  place-items: center;
  width: 24px;
  height: 24px;
  border-radius: 6px;
  overflow: hidden;
}
.icon-box img {
  width: 22px;
  height: 22px;
}
.q-tag {
  padding: 0 6px;
  border: 1px solid;
  border-radius: 4px;
  font-size: 12px;
  line-height: 18px;
}
.w160 {
  width: 160px;
}
.w320 {
  width: 320px;
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
</style>
