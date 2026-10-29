<template>
  <SectionCard title="种子掉落" anchor="sec-seed-drops" desc="跟随配置概览的全局默认；勾选「本关自定义」后可改或清空（清空 = 本关不掉种子）。">
    <div class="bar">
      <el-checkbox v-model="custom" @change="onCustom">本关自定义</el-checkbox>
      <el-button v-if="custom" link type="primary" @click="reset">↺ 恢复跟随全局</el-button>
      <span v-else class="muted small">当前跟随全局默认（{{ defaults.length }} 条）</span>
    </div>
    <template v-if="custom">
      <div v-if="rows.length === 0" class="empty">
        <span class="muted">本关不掉种子</span>
        <el-button type="primary" plain size="small" @click="add">＋ 添加</el-button>
      </div>
      <el-table v-else :data="rows" size="small">
        <el-table-column label="种子" min-width="260">
          <template #default="{ row }">
            <el-select v-model="row.itemId" filterable class="w240" placeholder="搜索物品">
              <el-option v-for="item in items" :key="item.id" :label="item.displayName" :value="item.id" />
            </el-select>
          </template>
        </el-table-column>
        <el-table-column label="概率" width="140">
          <template #default="{ row }"><NumInput v-model="row.chancePercent" :width="110" unit="%" :precision="2" :min="0" :max="100" /></template>
        </el-table-column>
        <el-table-column label="最少" width="110">
          <template #default="{ row }"><NumInput v-model="row.minCount" :width="80" :precision="0" :min="1" :max="99" /></template>
        </el-table-column>
        <el-table-column label="最多" width="110">
          <template #default="{ row }"><NumInput v-model="row.maxCount" :width="80" :precision="0" :min="1" :max="99" /></template>
        </el-table-column>
        <el-table-column width="70">
          <template #default="{ $index }"><el-button link type="danger" @click="rows.splice($index, 1)">删除</el-button></template>
        </el-table-column>
      </el-table>
      <el-button v-if="rows.length > 0" class="add" size="small" :disabled="rows.length >= 20" @click="add">＋ 添加</el-button>
    </template>
    <el-table v-else :data="defaults" size="small" class="preview">
      <el-table-column label="种子（全局）" min-width="200">
        <template #default="{ row }">{{ row.itemId }}</template>
      </el-table-column>
      <el-table-column label="概率" width="100"><template #default="{ row }">{{ row.chancePercent }}%</template></el-table-column>
      <el-table-column label="数量" width="120"><template #default="{ row }">{{ row.minCount }}–{{ row.maxCount }}</template></el-table-column>
    </el-table>
  </SectionCard>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { api } from "../../../api";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";

export type SeedRow = { itemId: string; chancePercent: number | null; minCount: number | null; maxCount: number | null };

/** null = 跟随全局；数组（可空）= 本关覆盖。 */
const override = defineModel<SeedRow[] | null>({ required: true });
const props = defineProps<{ defaults: SeedRow[] }>();

const custom = ref(false);
const rows = computed({
  get: () => override.value ?? [],
  set: (value: SeedRow[]) => {
    override.value = value;
  },
});
const items = ref<{ id: string; displayName: string }[]>([]);

function onCustom(value: boolean | string | number): void {
  if (value) {
    override.value = props.defaults.map((row) => ({ ...row }));
  } else {
    override.value = null;
  }
}

function reset(): void {
  custom.value = false;
  override.value = null;
}

function add(): void {
  rows.value = [...rows.value, { itemId: "", chancePercent: 8, minCount: 1, maxCount: 1 }];
}

watch(
  () => override.value,
  (value) => {
    custom.value = value != null;
  },
  { immediate: true },
);

onMounted(async () => {
  try {
    const list = await api<{ id: string; displayName: string; kind?: string }[]>("/admin/draft/items");
    items.value = list ?? [];
  } catch {
    items.value = [];
  }
});
</script>

<style scoped>
.bar { display: flex; align-items: center; gap: 12px; margin-bottom: 8px; }
.empty { display: flex; align-items: center; gap: 12px; padding: 8px 0; }
.add { margin-top: 8px; }
.w240 { width: 240px; }
.muted { color: var(--el-text-color-secondary); }
.small { font-size: 12px; }
.preview { opacity: 0.85; }
</style>
