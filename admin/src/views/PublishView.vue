<template>
  <div>
    <div class="toolbar">
      <h2>发布</h2>
      <el-button type="primary" @click="confirmPublish">发布</el-button>
    </div>
    <p>当前已发布：{{ publishedAt ? new Date(publishedAt).toLocaleString() : "还没有" }}</p>
    <el-form inline>
      <el-form-item label="离线上限（小时）">
        <el-input-number v-model="offlineHours" :min="1" :step="1" />
      </el-form-item>
      <el-form-item label="行囊容量">
        <el-input-number v-model="inventoryCapacity" :min="1" :step="1" />
      </el-form-item>
      <el-form-item label="洞府队列">
        <el-input-number v-model="queueLimit" :min="1" :step="1" />
      </el-form-item>
      <el-button @click="saveSettings">保存到草稿</el-button>
    </el-form>
    <el-table :data="changes" v-loading="loading">
      <el-table-column prop="kind" label="类型" width="100" />
      <el-table-column prop="slug" label="编号" width="160" />
      <el-table-column prop="field" label="字段" width="180" />
      <el-table-column prop="before" label="已发布" />
      <el-table-column prop="after" label="草稿" />
    </el-table>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, ref } from "vue";
import { api } from "../api";

type Change = {
  kind: string;
  slug: string;
  field: string;
  before: string | number | null;
  after: string | number | null;
};

const loading = ref(false);
const publishedAt = ref<string | null>(null);
const changes = ref<Change[]>([]);
const offlineHours = ref(8);
const inventoryCapacity = ref(100);
const queueLimit = ref(4);

async function load(): Promise<void> {
  loading.value = true;
  try {
    const result = await api<{ publishedAt: string | null; offlineCapSeconds: number; changes: Change[] }>(
      "/admin/content/diff",
    );
    publishedAt.value = result.publishedAt;
    changes.value = result.changes;
    offlineHours.value = Math.round(result.offlineCapSeconds / 3600);
    const settings = await api<{ inventoryCapacity: number; queueLimit: number }>("/admin/content/settings");
    inventoryCapacity.value = settings.inventoryCapacity;
    queueLimit.value = settings.queueLimit;
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

async function saveSettings(): Promise<void> {
  await api("/admin/content/settings", {
    method: "PUT",
    body: JSON.stringify({
      offlineCapSeconds: offlineHours.value * 3600,
      inventoryCapacity: inventoryCapacity.value,
      queueLimit: queueLimit.value,
    }),
  });
  ElMessage.success("已写入草稿");
  await load();
}

async function confirmPublish(): Promise<void> {
  await ElMessageBox.confirm("确认把当前草稿发布给玩家？", "发布");
  await api("/admin/content/publish", { method: "POST" });
  ElMessage.success("已发布");
  await load();
}

onMounted(load);
</script>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
