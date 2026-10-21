<template>
  <div>
    <div class="filter-bar">
      <el-select v-model="source" clearable placeholder="全部来源" class="f-source" @change="load(1)">
        <el-option v-for="(label, key) in SOURCE_NAMES" :key="key" :label="`${label}（${key}）`" :value="key" />
      </el-select>
      <el-input v-model="player" clearable placeholder="玩家账号 / ID" class="f-name" @keyup.enter="load(1)" />
      <el-date-picker v-model="range" type="datetimerange" range-separator="至" start-placeholder="开始时间" end-placeholder="结束时间" />
      <el-button type="primary" :loading="loading" @click="load(1)">查询</el-button>
      <el-button @click="reset">重置</el-button>
      <span class="spacer" />
      <el-button type="primary" plain @click="grantOpen = true">补发装备</el-button>
    </div>
    <DataState :loading="loading" :error="error" :has-data="rows.length > 0" empty-text="没有符合条件的发放记录" @retry="load(page)">
      <el-table :data="rows" row-key="id" class="grid">
        <el-table-column label="时间" width="170"><template #default="{ row }">{{ formatTime(row.createdAt) }}</template></el-table-column>
        <el-table-column label="来源" width="150">
          <template #default="{ row }"><el-tag :type="row.source === 'admin_grant' ? 'warning' : 'info'" effect="light" size="small">{{ SOURCE_NAMES[row.source] ?? row.source }}</el-tag></template>
        </el-table-column>
        <el-table-column label="玩家" min-width="130"><template #default="{ row }">{{ row.username }}</template></el-table-column>
        <el-table-column label="装备" min-width="160">
          <template #default="{ row }"><span>{{ row.itemName ?? row.itemSlug }}</span> <span class="muted small">{{ row.itemSlug }}</span></template>
        </el-table-column>
        <el-table-column label="件数" width="70" align="right"><template #default="{ row }">{{ row.count }}</template></el-table-column>
        <el-table-column label="关联" min-width="140" show-overflow-tooltip><template #default="{ row }">{{ row.sourceRef ?? "—" }}</template></el-table-column>
        <el-table-column label="操作人" width="110"><template #default="{ row }">{{ row.operator ?? "—" }}</template></el-table-column>
        <el-table-column label="原因 / 备注" min-width="220" show-overflow-tooltip>
          <template #default="{ row }">{{ row.reason ? `${row.reason}${row.note ? ` · ${row.note}` : ""}` : "—" }}</template>
        </el-table-column>
      </el-table>
      <el-pagination v-if="total > pageSize" v-model:current-page="page" class="pager" layout="total, prev, pager, next" :page-size="pageSize" :total="total" background @current-change="load" />
    </DataState>
    <GrantDrawer v-model="grantOpen" @sent="load(1)" />
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from "vue";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { api } from "../../api";
import DataState from "../../components/DataState.vue";
import GrantDrawer from "../../components/GrantDrawer.vue";
import { formatTime } from "../../composables/format";

/** 操作日志 →「装备发放」：equipment_grants 流水，所有发装备的地方（掉落、首领、补发）都在这里，按来源筛。 */
type Grant = { id: string; createdAt: string; source: string; sourceRef: string | null; username: string; itemSlug: string; itemName: string | null; count: number; operator: string | null; reason: string | null; note: string | null };

const SOURCE_NAMES: Record<string, string> = {
  admin_grant: "后台补发",
  stage_drop: "关卡掉落",
  boss_first: "首领首通",
  boss_repeat: "首领重复",
  event: "活动",
  mail: "邮件",
};
const props = defineProps<{ initialSource?: string }>();
const source = ref(props.initialSource ?? "");
const player = ref("");
const range = ref<[Date, Date] | null>(null);
const rows = ref<Grant[]>([]);
const total = ref(0);
const page = ref(1);
const pageSize = 50;
const loading = ref(false);
const error = ref("");
const grantOpen = ref(false);

async function load(to = 1): Promise<void> {
  page.value = to;
  const params = new URLSearchParams({ limit: String(pageSize), offset: String((to - 1) * pageSize) });
  if (source.value) params.set("source", source.value);
  if (player.value.trim()) params.set("player", player.value.trim());
  if (range.value) {
    params.set("from", range.value[0].toISOString());
    params.set("to", range.value[1].toISOString());
  }
  loading.value = true;
  error.value = "";
  try {
    const result = await api<{ rows: Grant[]; total: number }>(`/admin/grants?${params.toString()}`);
    rows.value = result.rows;
    total.value = result.total;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "查询失败";
  } finally {
    loading.value = false;
  }
}

function reset(): void {
  source.value = "";
  player.value = "";
  range.value = null;
  void load(1);
}

useRefetchOnActivate(() => load(1));
onMounted(() => load(1));
</script>

<style scoped>
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xx-space-2) var(--xx-space-3);
  margin-bottom: var(--xx-space-3);
  padding: var(--xx-space-3) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-surface);
}
.f-source {
  width: 200px;
}
.f-name {
  width: 200px;
}
.spacer {
  flex: 1;
}
.pager {
  justify-content: flex-end;
  margin-top: var(--xx-space-3);
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
</style>
