<template>
  <div>
    <h2>用户</h2>
    <el-table :data="rows" v-loading="loading" class="users" @row-click="openPlayer">
      <el-table-column prop="username" label="账号" min-width="160" />
      <el-table-column prop="realmName" label="境界" min-width="160" />
      <el-table-column prop="cultivation" label="修为" min-width="140" />
      <el-table-column label="战力" width="160">
        <template #default="{ row }">
          <span>{{ row.power == null ? "算不出" : row.power }}</span>
          <el-button link type="primary" @click.stop="openPower(row)">来源</el-button>
        </template>
      </el-table-column>
      <el-table-column label="上次结算" min-width="220">
        <template #default="{ row }">{{ formatTime(row.lastSettledAt) }}</template>
      </el-table-column>
      <el-table-column label="" width="120">
        <template #default="{ row }">
          <el-button link type="danger" @click.stop="clearPlayer(row)">清空</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="powerOpen" :title="`${powerPlayer} 的战力`" width="760px">
      <p v-if="breakdown?.error" class="problem">{{ breakdown.error }}</p>
      <p v-else class="power">战力 {{ breakdown?.power }}</p>
      <p class="hint">只算已经到达的境界、穿上的武器、正在运转的功法。背包里的物品和没运转的功法不算。</p>
      <el-table :data="breakdown?.lines ?? []">
        <el-table-column prop="group" label="来源" width="90" />
        <el-table-column prop="name" label="名称" width="160" />
        <el-table-column prop="attack" label="攻击" width="80" />
        <el-table-column prop="defense" label="防御" width="80" />
        <el-table-column prop="hp" label="气血" width="80" />
        <el-table-column prop="speed" label="速度" width="80" />
        <el-table-column label="计入" width="80">
          <template #default="{ row }">{{ row.counted ? "是" : "否" }}</template>
        </el-table-column>
        <el-table-column prop="note" label="说明" />
      </el-table>
      <div v-if="breakdown && breakdown.steps.length > 0" class="math">
        <p>计入后合计：攻击 {{ breakdown.attack }}，防御 {{ breakdown.defense }}，气血 {{ breakdown.hp }}，速度 {{ breakdown.speed }}</p>
        <p v-for="step in breakdown.steps" :key="step">{{ step }}</p>
      </div>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { api } from "../api";

type PowerLine = {
  group: string;
  name: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  counted: boolean;
  note: string;
};
type Breakdown = {
  power: number | null;
  error: string | null;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  lines: PowerLine[];
  steps: string[];
};
type PlayerRow = {
  username: string;
  realmName: string;
  cultivation: number;
  power: number | null;
  lastSettledAt: string;
  breakdown: Breakdown;
};

const router = useRouter();
const rows = ref<PlayerRow[]>([]);
const loading = ref(false);
const powerOpen = ref(false);
const powerPlayer = ref("");
const breakdown = ref<Breakdown | null>(null);

function openPower(row: PlayerRow): void {
  powerPlayer.value = row.username;
  breakdown.value = row.breakdown;
  powerOpen.value = true;
}

function formatTime(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : date.toLocaleString();
}

function openPlayer(row: PlayerRow): void {
  void router.push({ path: "/operations", query: { name: row.username } });
}

async function clearPlayer(row: PlayerRow): Promise<void> {
  await ElMessageBox.confirm(`清空「${row.username}」的进度？账号保留，修为回到 0，境界回到编号最小的那一档。`, "清空进度");
  await api(`/admin/players/${encodeURIComponent(row.username)}/reset`, { method: "POST" });
  ElMessage.success("进度已清空");
  await load();
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<PlayerRow[]>("/admin/players");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
h2 {
  margin-bottom: 16px;
}
.users {
  font-size: 16px;
}
.users :deep(.el-table__row) {
  cursor: pointer;
}
.users :deep(.el-table__cell) {
  padding: 16px 0;
}
.power {
  font-size: 28px;
  margin: 0 0 8px;
}
.hint,
.math {
  color: var(--el-text-color-secondary);
}
.problem {
  color: var(--el-color-danger);
}
.math p {
  margin: 4px 0;
}
</style>
