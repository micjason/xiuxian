<template>
  <div>
    <PageHeader title="玩家管理" desc="查询玩家、查看战力是怎么算出来的、查看该玩家最近的操作；清空进度属于危险操作，需要输入账号确认。">
      <template #actions>
        <el-button :icon="Refresh" :loading="loading" @click="reload">刷新</el-button>
      </template>
    </PageHeader>

    <div class="filter-bar">
      <el-input v-model="query" clearable placeholder="搜索账号" class="search" :prefix-icon="Search" />
      <el-select v-model="realm" clearable placeholder="境界" class="filter">
        <el-option v-for="name in realmNames" :key="name" :label="name" :value="name" />
      </el-select>
      <el-checkbox v-model="onlyBroken">只看战力算不出的</el-checkbox>
      <span class="count">共 {{ rows.length }} 名玩家<template v-if="filtered.length !== rows.length">，筛选出 {{ filtered.length }} 名</template></span>
      <span class="spacer" />
      <el-button :disabled="filtered.length === 0" @click="exportCsv(filtered)">导出 CSV</el-button>
    </div>

    <DataState :loading="loading" :error="error" :has-data="rows.length > 0" empty-text="还没有玩家注册" @retry="reload">
      <el-table :data="paged" class="grid" @row-click="openDetail" @selection-change="(v: PlayerRow[]) => (selection = v)" @sort-change="onSort">
        <el-table-column type="selection" width="44" />
        <el-table-column prop="username" label="账号" min-width="160" sortable="custom" />
        <el-table-column prop="realmName" label="境界" min-width="140" />
        <el-table-column prop="cultivation" label="修为" min-width="120" sortable="custom">
          <template #default="{ row }">{{ compactNumber(row.cultivation) }}</template>
        </el-table-column>
        <el-table-column prop="power" label="战力" width="130" sortable="custom">
          <template #default="{ row }">
            <el-tag v-if="row.power == null" type="warning" effect="light" size="small">算不出</el-tag>
            <span v-else>{{ row.power }}</span>
          </template>
        </el-table-column>
        <el-table-column prop="lastSettledAt" label="上次结算" min-width="150" sortable="custom">
          <template #default="{ row }">
            <el-tooltip :content="formatTime(row.lastSettledAt)" placement="top">
              <span>{{ relativeTime(row.lastSettledAt) }}</span>
            </el-tooltip>
          </template>
        </el-table-column>
        <el-table-column label="操作" prop="__actions" width="170" fixed="right" align="right">
          <template #default="{ row }">
            <el-button link type="primary" @click.stop="openDetail(row)">详情</el-button>
            <el-button link type="primary" @click.stop="goAudit(row)">操作日志</el-button>
            <el-button link type="danger" @click.stop="clearPlayer(row)">清空</el-button>
          </template>
        </el-table-column>
        <template #empty><el-empty description="没有符合条件的玩家" /></template>
      </el-table>
      <el-pagination v-if="filtered.length > pageSize" v-model:current-page="page" class="pager" layout="total, prev, pager, next" :page-size="pageSize" :total="filtered.length" background />
    </DataState>

    <el-drawer v-model="drawer" size="720px" :title="`玩家：${current?.username ?? ''}`">
      <template v-if="current">
        <section class="summary">
          <div class="stat"><span>境界</span><strong>{{ current.realmName }}</strong></div>
          <div class="stat"><span>修为</span><strong>{{ compactNumber(current.cultivation) }}</strong></div>
          <div class="stat"><span>战力</span><strong>{{ current.power ?? "算不出" }}</strong></div>
          <div class="stat"><span>上次结算</span><strong>{{ relativeTime(current.lastSettledAt) }}</strong></div>
        </section>
        <el-tabs v-model="detailTab">
          <el-tab-pane label="战力来源" name="power">
            <p v-if="current.breakdown?.error" class="problem">{{ current.breakdown.error }}</p>
            <p class="hint">只算已经到达的境界、穿上的装备、正在运转的功法。行囊里的物品和没运转的功法不算。</p>
            <el-table :data="current.breakdown?.lines ?? []" size="small">
              <el-table-column prop="group" label="来源" width="80" />
              <el-table-column prop="name" label="名称" min-width="140" />
              <el-table-column label="攻击" width="70"><template #default="{ row }">{{ num(row.attack) }}</template></el-table-column>
              <el-table-column label="防御" width="70"><template #default="{ row }">{{ num(row.defense) }}</template></el-table-column>
              <el-table-column label="气血" width="70"><template #default="{ row }">{{ num(row.hp) }}</template></el-table-column>
              <el-table-column label="速度" width="70"><template #default="{ row }">{{ num(row.speed) }}</template></el-table-column>
              <el-table-column label="计入" width="70"><template #default="{ row }">{{ row.counted ? "是" : "否" }}</template></el-table-column>
              <el-table-column prop="note" label="说明" min-width="140" />
            </el-table>
            <div v-if="current.breakdown && current.breakdown.steps.length > 0" class="math">
              <p>计入后合计：攻击 {{ num(current.breakdown.attack) }}，防御 {{ num(current.breakdown.defense) }}，气血 {{ num(current.breakdown.hp) }}，速度 {{ num(current.breakdown.speed) }}</p>
              <p v-for="step in current.breakdown.steps" :key="step">{{ step }}</p>
            </div>
          </el-tab-pane>
          <el-tab-pane label="最近操作" name="ops" lazy>
            <DataState :loading="opsLoading" :error="opsError" :has-data="ops.length > 0" empty-text="近 30 天没有这个玩家的操作记录" @retry="loadOps">
              <el-timeline>
                <el-timeline-item v-for="(op, index) in ops.slice(0, 12)" :key="index" :timestamp="formatTime(op.at)" placement="top">
                  <strong>{{ op.action }}</strong> · {{ op.result }}<span v-if="op.reason">（{{ op.reason }}）</span>
                </el-timeline-item>
              </el-timeline>
              <el-button link type="primary" @click="goAudit(current)">在操作日志里查看全部</el-button>
            </DataState>
          </el-tab-pane>
          <el-tab-pane label="处理" name="act">
            <div class="actions">
              <div class="action">
                <div><strong>清空进度</strong><p>账号保留，修为回到 0，境界回到编号最小的一档。不可恢复。</p></div>
                <el-button type="danger" @click="clearPlayer(current)">清空进度</el-button>
              </div>
            </div>
          </el-tab-pane>
        </el-tabs>
      </template>
    </el-drawer>
  </div>
</template>

<script setup lang="ts">
import { Refresh, Search } from "@element-plus/icons-vue";
import { ElMessage } from "element-plus";
import { computed, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { api } from "../../api";
import DataState from "../../components/DataState.vue";
import PageHeader from "../../components/PageHeader.vue";
import { confirmDanger } from "../../composables/confirm";
import { compactNumber, downloadText, formatTime, relativeTime, toCsv } from "../../composables/format";

/** 属性合计里会混入浮点误差（119.06000000000002），只在显示时收成两位。 */
function num(value: number): number {
  return Math.round(value * 100) / 100;
}

type Breakdown = {
  power: number | null;
  error: string | null;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  lines: { group: string; name: string; attack: number; defense: number; hp: number; speed: number; counted: boolean; note: string }[];
  steps: string[];
};
type PlayerRow = { username: string; realmName: string; cultivation: number; power: number | null; lastSettledAt: string; breakdown: Breakdown };
type Op = { at: string; actorName: string; action: string; result: string; reason: string | null };

const route = useRoute();
const router = useRouter();
const rows = ref<PlayerRow[]>([]);
const loading = ref(false);
const error = ref("");
const query = ref(typeof route.query.q === "string" ? route.query.q : "");
const realm = ref("");
const onlyBroken = ref(false);
const selection = ref<PlayerRow[]>([]);
const page = ref(1);
const pageSize = 20;
const sort = ref<{ prop: string; order: string } | null>(null);
const drawer = ref(false);
const current = ref<PlayerRow | null>(null);
const detailTab = ref("power");
const ops = ref<Op[]>([]);
const opsLoading = ref(false);
const opsError = ref("");

const realmNames = computed(() => [...new Set(rows.value.map((row) => row.realmName))]);
const filtered = computed(() => {
  const text = query.value.trim().toLowerCase();
  let list = rows.value.filter((row) => (!text || row.username.toLowerCase().includes(text)) && (!realm.value || row.realmName === realm.value) && (!onlyBroken.value || row.power == null));
  if (sort.value?.order) {
    const { prop, order } = sort.value;
    const sign = order === "ascending" ? 1 : -1;
    list = [...list].sort((a, b) => {
      const left = (a as unknown as Record<string, number | string | null>)[prop] ?? -1;
      const right = (b as unknown as Record<string, number | string | null>)[prop] ?? -1;
      return left === right ? 0 : left > right ? sign : -sign;
    });
  }
  return list;
});
const paged = computed(() => filtered.value.slice((page.value - 1) * pageSize, page.value * pageSize));
watch([query, realm, onlyBroken], () => (page.value = 1));

function onSort(value: { prop: string; order: string }): void {
  sort.value = value.order ? value : null;
}

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    rows.value = await api<PlayerRow[]>("/admin/players");
    const open = route.query.open;
    if (typeof open === "string") {
      const hit = rows.value.find((row) => row.username === open);
      if (hit) openDetail(hit);
      void router.replace({ query: {} });
    }
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function openDetail(row: PlayerRow): void {
  current.value = row;
  detailTab.value = "power";
  ops.value = [];
  drawer.value = true;
}

watch(detailTab, (tab) => {
  if (tab === "ops" && current.value) void loadOps();
});

async function loadOps(): Promise<void> {
  if (!current.value) return;
  opsLoading.value = true;
  opsError.value = "";
  try {
    const params = new URLSearchParams({ from: new Date(Date.now() - 30 * 86400_000).toISOString(), to: new Date().toISOString(), name: current.value.username });
    ops.value = await api<Op[]>(`/admin/operations?${params.toString()}`);
  } catch (cause) {
    opsError.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    opsLoading.value = false;
  }
}

function goAudit(row: PlayerRow): void {
  void router.push({ path: "/system/audit", query: { name: row.username } });
}

async function clearPlayer(row: PlayerRow): Promise<void> {
  const ok = await confirmDanger({
    title: "清空玩家进度",
    message: `将清空「${row.username}」的进度：账号保留，修为回到 0，境界回到编号最小的一档。此操作不可恢复，并会记入操作日志。`,
    typeText: row.username,
    confirmText: "清空进度",
  });
  if (!ok) return;
  try {
    await api(`/admin/players/${encodeURIComponent(row.username)}/reset`, { method: "POST" });
    ElMessage.success("进度已清空");
    drawer.value = false;
    await reload();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "清空失败");
  }
}

function exportCsv(list: PlayerRow[]): void {
  const target = selection.value.length > 0 ? selection.value : list;
  downloadText(
    "玩家.csv",
    toCsv(target as unknown as Record<string, unknown>[], [
      { key: "username", label: "账号" },
      { key: "realmName", label: "境界" },
      { key: "cultivation", label: "修为" },
      { key: "power", label: "战力" },
      { key: "lastSettledAt", label: "上次结算" },
    ]),
  );
}

onMounted(reload);
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
.search {
  width: 240px;
}
.filter {
  width: 160px;
}
.count {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.spacer {
  flex: 1;
}
.grid :deep(.el-table__row) {
  cursor: pointer;
}
.pager {
  justify-content: flex-end;
  margin-top: var(--xx-space-3);
}
.summary {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-4);
}
.stat {
  padding: var(--xx-space-3);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
}
.stat span {
  display: block;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-xs);
}
.stat strong {
  font-size: var(--xx-fs-lg);
}
.problem {
  color: var(--xx-danger);
}
.hint,
.math {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.actions {
  display: grid;
  gap: var(--xx-space-3);
}
.action {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--xx-space-4);
  padding: var(--xx-space-3) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
}
.action p {
  margin: 2px 0 0;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
</style>
