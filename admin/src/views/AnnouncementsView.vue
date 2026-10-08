<template>
  <div>
    <div class="toolbar">
      <h2>公告</h2>
      <el-button type="primary" @click="openCreate">新增</el-button>
    </div>
    <el-table :data="rows">
      <el-table-column prop="title" label="标题" />
      <el-table-column prop="body" label="正文" />
      <el-table-column prop="enabled" label="启用" />
      <el-table-column label="操作">
        <template #default="{ row }">
          <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="visible" title="公告" width="520px">
      <el-form label-width="80px">
        <el-form-item label="标题"><el-input v-model="form.title" /></el-form-item>
        <el-form-item label="正文"><el-input v-model="form.body" type="textarea" /></el-form-item>
        <el-form-item label="启用"><el-switch v-model="form.enabled" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="visible = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Announcement = { id: string; title: string; body: string; enabled: boolean };

const rows = ref<Announcement[]>([]);
const visible = ref(false);
const form = reactive({ id: "", title: "", body: "", enabled: false });

async function load(): Promise<void> {
  rows.value = await api<Announcement[]>("/admin/announcements");
}

function openCreate(): void {
  form.id = "";
  form.title = "";
  form.body = "";
  form.enabled = true;
  visible.value = true;
}

function openEdit(row: Announcement): void {
  form.id = row.id;
  form.title = row.title;
  form.body = row.body;
  form.enabled = row.enabled;
  visible.value = true;
}

async function save(): Promise<void> {
  try {
    await api("/admin/announcements", {
      method: "POST",
      body: JSON.stringify({
        id: form.id || undefined,
        title: form.title,
        body: form.body,
        enabled: form.enabled,
      }),
    });
    visible.value = false;
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
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
