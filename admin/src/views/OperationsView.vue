<template>
  <div>
    <h2>操作记录</h2>
    <el-form inline>
      <el-form-item label="玩家名">
        <el-input v-model="name" clearable />
      </el-form-item>
      <el-form-item label="动作">
        <el-select v-model="action" clearable placeholder="全部" style="width: 140px">
          <el-option label="登录" value="login" />
          <el-option label="结算" value="settle" />
          <el-option label="突破" value="breakthrough" />
          <el-option label="发布" value="publish" />
          <el-option label="修复" value="repair" />
        </el-select>
      </el-form-item>
      <el-form-item label="时间">
        <el-date-picker v-model="range" type="datetimerange" />
      </el-form-item>
      <el-button type="primary" @click="load">查询</el-button>
    </el-form>
    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="at" label="时间" width="200" />
      <el-table-column prop="actorName" label="谁" width="140" />
      <el-table-column prop="action" label="动作" width="120" />
      <el-table-column prop="result" label="结果" width="100" />
      <el-table-column prop="reason" label="原因" width="160" />
      <el-table-column label="前后">
        <template #default="{ row }">{{ JSON.stringify(row.summary) }}</template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, ref } from "vue";
import { useRoute } from "vue-router";
import { api } from "../api";

type RecordRow = {
  at: string;
  actorName: string;
  action: string;
  result: string;
  reason: string | null;
  summary: Record<string, unknown>;
};

const route = useRoute();
const name = ref(typeof route.query.name === "string" ? route.query.name : "");
const action = ref("");
const range = ref<[Date, Date] | null>(null);
const rows = ref<RecordRow[]>([]);
const loading = ref(false);

async function load(): Promise<void> {
  const lookback = name.value ? 30 * 24 * 60 * 60 * 1000 : 24 * 60 * 60 * 1000;
  const from = range.value?.[0] ?? new Date(Date.now() - lookback);
  const to = range.value?.[1] ?? new Date();
  const params = new URLSearchParams({
    from: from.toISOString(),
    to: to.toISOString(),
  });
  if (name.value) {
    params.set("name", name.value);
  }
  if (action.value) {
    params.set("action", action.value);
  }
  loading.value = true;
  try {
    rows.value = await api<RecordRow[]>(`/admin/operations?${params.toString()}`);
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "查询失败");
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>
