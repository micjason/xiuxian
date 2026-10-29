<template>
  <SectionCard title="种子掉落" anchor="seed-drops" desc="洞府药园用的种子：普通怪每只击杀独立按概率掉。关卡没单独改就用这里；单关可覆盖或关掉。">
    <div v-if="rows.length === 0" class="empty">
      <span class="muted">全局没有种子掉落</span>
      <el-button type="primary" plain size="small" @click="add">＋ 添加种子</el-button>
    </div>
    <template v-else>
      <el-table :data="rows" size="small" class="drops">
        <el-table-column label="种子" min-width="280">
          <template #default="{ row }">
            <el-select v-model="row.itemSlug" filterable class="w260" placeholder="搜索物品">
              <el-option v-for="item in items" :key="item.id" :label="item.displayName" :value="item.id" :disabled="used(item.id, row)">
                <span>{{ item.displayName }} <span class="muted small">{{ item.id }}</span></span>
              </el-option>
            </el-select>
          </template>
        </el-table-column>
        <el-table-column width="150">
          <template #header>概率<HelpTip title="概率" text="每打死一只普通怪，掉这一条的概率。0%–100%。" /></template>
          <template #default="{ row }"><NumInput v-model="row.chancePercent" :width="120" unit="%" :precision="2" :min="0" :max="100" /></template>
        </el-table-column>
        <el-table-column label="最少" width="120">
          <template #default="{ row }"><NumInput v-model="row.minCount" :width="88" unit="个" :precision="0" :min="1" :max="99" /></template>
        </el-table-column>
        <el-table-column label="最多" width="120">
          <template #default="{ row }"><NumInput v-model="row.maxCount" :width="88" unit="个" :precision="0" :min="row.minCount || 1" :max="99" /></template>
        </el-table-column>
        <el-table-column width="70">
          <template #default="{ $index }"><el-button link type="danger" @click="rows.splice($index, 1)">删除</el-button></template>
        </el-table-column>
      </el-table>
      <el-button class="add" size="small" :disabled="rows.length >= 20" @click="add">＋ 添加种子</el-button>
    </template>
    <p class="muted small note">存到 tuning.seedDrops（itemSlug + chanceBp 万分比 + minCount/maxCount）。在线挂机与离线估算击杀都会掉。商店/初始赠送不在这里。</p>
  </SectionCard>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { api } from "../../../api";
import HelpTip from "../../../components/HelpTip.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";

/** 配置概览绑定用：内部用 itemSlug + chancePercent，保存前由父级转成 chanceBp。 */
export type SeedDropFormRow = { itemSlug: string; chancePercent: number | null; minCount: number | null; maxCount: number | null };

const rows = defineModel<SeedDropFormRow[]>({ required: true });
const items = ref<{ id: string; displayName: string }[]>([]);

function add(): void {
  rows.value.push({ itemSlug: "", chancePercent: 8, minCount: 1, maxCount: 1 });
}

function used(id: string, row: SeedDropFormRow): boolean {
  return id !== row.itemSlug && rows.value.some((other) => other !== row && other.itemSlug === id);
}

onMounted(async () => {
  if (!Array.isArray(rows.value)) rows.value = [];
  try {
    const list = await api<{ id: string; displayName: string; kind?: string }[]>("/admin/draft/items");
    items.value = (list ?? []).filter((row) => !row.kind || row.kind === "material" || row.kind === "pill" || String(row.id).startsWith("seed_"));
  } catch {
    items.value = [];
  }
});
</script>

<style scoped>
.empty { display: flex; align-items: center; gap: 12px; padding: 8px 0; }
.drops { width: 100%; }
.add { margin-top: 8px; }
.note { margin-top: 8px; }
.w260 { width: 260px; }
.muted { color: var(--el-text-color-secondary); }
.small { font-size: 12px; }
</style>
