<template>
  <div>
    <h2>用户</h2>
    <el-table :data="rows" v-loading="loading" class="users" @row-click="openPlayer">
      <el-table-column prop="username" label="账号" min-width="160" />
      <el-table-column prop="realmName" label="境界" min-width="160" />
      <el-table-column prop="cultivation" label="修为" min-width="140" />
      <el-table-column label="上次结算" min-width="220">
        <template #default="{ row }">{{ formatTime(row.lastSettledAt) }}</template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { api } from "../api";

type PlayerRow = {
  username: string;
  realmName: string;
  cultivation: number;
  lastSettledAt: string;
};

const router = useRouter();
const rows = ref<PlayerRow[]>([]);
const loading = ref(false);

function formatTime(value: string): string {
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? "" : date.toLocaleString();
}

function openPlayer(row: PlayerRow): void {
  void router.push({ path: "/operations", query: { name: row.username } });
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
</style>
