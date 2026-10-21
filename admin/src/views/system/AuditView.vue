<template>
  <div>
    <PageHeader title="操作日志" desc="谁在什么时候做了什么。日志只读，不能修改或删除。「装备发放」里是所有发给玩家的装备（关卡掉落、首领奖励、后台补发），按来源筛。" />
    <el-tabs v-model="tab" class="tabs">
      <el-tab-pane label="操作记录" name="ops" />
      <el-tab-pane label="装备发放" name="grants" />
    </el-tabs>
    <GrantLog v-if="tab === 'grants'" :initial-source="typeof route.query.source === 'string' ? route.query.source : ''" />
    <template v-else>
    <div class="filter-bar">
      <el-input v-model="name" clearable placeholder="玩家名 / 账号" class="f-name" @keyup.enter="load" />
      <el-select v-model="action" clearable placeholder="全部动作" class="f-action">
        <el-option v-for="(label, key) in actions" :key="key" :label="label" :value="key" />
      </el-select>
      <el-date-picker v-model="range" type="datetimerange" range-separator="至" start-placeholder="开始时间" end-placeholder="结束时间" :shortcuts="shortcuts" />
      <el-select v-model="resultFilter" clearable placeholder="全部结果" class="f-action">
        <el-option label="成功" value="success" />
        <el-option label="失败" value="failure" />
      </el-select>
      <el-button type="primary" :loading="loading" @click="load">查询</el-button>
      <el-button @click="reset">重置</el-button>
      <span class="spacer" />
      <el-button :disabled="shown.length === 0" @click="exportCsv">导出 CSV</el-button>
    </div>
    <DataState :loading="loading" :error="error" :has-data="shown.length > 0" empty-text="这个时间段没有符合条件的记录" @retry="load">
      <el-table :data="paged" row-key="key" size="default" class="grid">
        <el-table-column type="expand">
          <template #default="{ row }"><pre class="summary">{{ JSON.stringify(row.summary, null, 2) }}</pre></template>
        </el-table-column>
        <el-table-column label="时间" width="170"><template #default="{ row }">{{ formatTime(row.at) }}</template></el-table-column>
        <el-table-column prop="actorName" label="谁" min-width="140" show-overflow-tooltip />
        <el-table-column label="动作" width="110"><template #default="{ row }">{{ actionText(row.action) }}</template></el-table-column>
        <el-table-column label="结果" width="100"><template #default="{ row }"><el-tag :type="row.result === 'success' ? 'success' : 'danger'" effect="light" size="small">{{ row.result === "success" ? "成功" : row.result }}</el-tag></template></el-table-column>
        <el-table-column label="原因" min-width="160" show-overflow-tooltip><template #default="{ row }">{{ row.reason ?? "—" }}</template></el-table-column>
        <el-table-column label="前后变化" min-width="260" class-name="mono" show-overflow-tooltip><template #default="{ row }">{{ brief(row.summary) }}</template></el-table-column>
        <el-table-column label="操作" prop="__a" width="90" fixed="right" align="right">
          <template #default="{ row }"><el-button v-if="row.action !== 'publish'" link type="primary" @click="viewPlayer(row.actorName)">看玩家</el-button></template>
        </el-table-column>
      </el-table>
      <el-pagination v-if="shown.length > pageSize" v-model:current-page="page" class="pager" layout="total, prev, pager, next" :page-size="pageSize" :total="shown.length" background />
    </DataState>
    </template>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { useRoute, useRouter } from "vue-router";
import { api } from "../../api";
import DataState from "../../components/DataState.vue";
import PageHeader from "../../components/PageHeader.vue";
import { downloadText, formatTime, toCsv } from "../../composables/format";
import { actionText } from "../../composables/lookups";
import GrantLog from "./GrantLog.vue";

type Row = { key: string; at: string; actorName: string; action: string; result: string; reason: string | null; summary: Record<string, unknown> };

const route = useRoute();
const router = useRouter();
const actions: Record<string, string> = { login: "登录", settle: "结算", breakthrough: "突破", publish: "发布", repair: "修复" };
const tab = ref(route.query.tab === "grants" ? "grants" : "ops");
const name = ref(typeof route.query.name === "string" ? route.query.name : "");
const action = ref("");
const resultFilter = ref("");
const range = ref<[Date, Date] | null>(null);
const rows = ref<Row[]>([]);
const loading = ref(false);
const error = ref("");
const page = ref(1);
const pageSize = 25;
const shortcuts = [
  { text: "最近 1 小时", value: () => [new Date(Date.now() - 3600_000), new Date()] },
  { text: "最近 24 小时", value: () => [new Date(Date.now() - 86400_000), new Date()] },
  { text: "最近 7 天", value: () => [new Date(Date.now() - 7 * 86400_000), new Date()] },
];

const shown = computed(() => rows.value.filter((row) => !resultFilter.value || row.result === resultFilter.value));
const paged = computed(() => shown.value.slice((page.value - 1) * pageSize, page.value * pageSize));

function brief(summary: Record<string, unknown>): string {
  const text = JSON.stringify(summary);
  return text === "{}" ? "—" : text;
}

async function load(): Promise<void> {
  const lookback = name.value ? 30 * 86400_000 : 86400_000;
  const from = range.value?.[0] ?? new Date(Date.now() - lookback);
  const to = range.value?.[1] ?? new Date();
  const params = new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
  if (name.value) params.set("name", name.value);
  if (action.value) params.set("action", action.value);
  loading.value = true;
  error.value = "";
  try {
    const list = await api<Omit<Row, "key">[]>(`/admin/operations?${params.toString()}`);
    rows.value = list.map((row, index) => ({ ...row, key: `${row.at}-${index}` }));
    page.value = 1;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "查询失败";
  } finally {
    loading.value = false;
  }
}

function reset(): void {
  name.value = "";
  action.value = "";
  resultFilter.value = "";
  range.value = null;
  void load();
}

function viewPlayer(username: string): void {
  void router.push({ path: "/players", query: { open: username } });
}

function exportCsv(): void {
  downloadText(
    "操作日志.csv",
    toCsv(shown.value.map((row) => ({ ...row, actionText: actionText(row.action), summaryText: JSON.stringify(row.summary) })) as unknown as Record<string, unknown>[], [
      { key: "at", label: "时间" },
      { key: "actorName", label: "谁" },
      { key: "actionText", label: "动作" },
      { key: "result", label: "结果" },
      { key: "reason", label: "原因" },
      { key: "summaryText", label: "前后变化" },
    ]),
  );
}

watch(
  () => route.query.tab,
  (value) => {
    if (route.path === "/system/audit") tab.value = value === "grants" ? "grants" : "ops";
  },
);
useRefetchOnActivate(load);
onMounted(load);
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
.tabs {
  margin-bottom: 4px;
}
.f-name {
  width: 200px;
}
.f-action {
  width: 140px;
}
.spacer {
  flex: 1;
}
.summary {
  margin: 0;
  padding: var(--xx-space-3) var(--xx-space-5);
  font-family: var(--xx-font-mono);
  font-size: var(--xx-fs-sm);
  white-space: pre-wrap;
}
.pager {
  justify-content: flex-end;
  margin-top: var(--xx-space-3);
}
</style>
