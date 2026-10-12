<template>
  <div>
    <div class="toolbar">
      <h2>发布</h2>
      <el-button type="primary" @click="confirmPublish">发布</el-button>
    </div>
    <p>当前内容版本：{{ version ?? "还没有发布" }}</p>
    <p>先在境界页写好「多少秒获得多少修为」，再发布。发布后版本从 1 开始往后加。玩家读的是已发布的版本，不是你正在改的草稿。</p>
    <el-form inline>
      <el-form-item label="发布说明">
        <el-input v-model="note" placeholder="例如：设置凡人修炼" />
      </el-form-item>
    </el-form>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, ref } from "vue";
import { api } from "../api";

const version = ref<number | null>(null);
const note = ref("第一次发布");

async function load(): Promise<void> {
  try {
    const health = await api<{ contentVersion: number | null }>("/healthz");
    version.value = health.contentVersion;
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  }
}

async function confirmPublish(): Promise<void> {
  await ElMessageBox.confirm("确认把当前草稿发布给玩家？没填修炼秒数和获得修为时，玩家仍然得不到修为。", "发布");
  const result = await api<{ version: number }>("/admin/draft/publish", {
    method: "POST",
    body: JSON.stringify({ note: note.value }),
  });
  version.value = result.version;
  ElMessage.success(`已发布版本 ${result.version}`);
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
