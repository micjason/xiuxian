<template>
  <div>
    <h2>弹窗</h2>
    <el-table :data="rows">
      <el-table-column prop="slug" label="类型" />
      <el-table-column prop="template" label="模板" />
      <el-table-column label="优先级">
        <template #default="{ row }">
          <el-input-number v-model="row.priority" :min="1" :step="1" />
        </template>
      </el-table-column>
      <el-table-column label="启用">
        <template #default="{ row }">
          <el-switch v-model="row.enabled" />
        </template>
      </el-table-column>
      <el-table-column label="操作">
        <template #default="{ row }">
          <el-button type="primary" link @click="save(row)">保存</el-button>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, ref } from "vue";
import { api } from "../api";

type PopupType = { slug: string; priority: number; enabled: boolean; template: string };

const rows = ref<PopupType[]>([]);

async function load(): Promise<void> {
  rows.value = await api<PopupType[]>("/admin/popup-types");
}

async function save(row: PopupType): Promise<void> {
  try {
    await api(`/admin/popup-types/${row.slug}`, {
      method: "PUT",
      body: JSON.stringify({ priority: row.priority, enabled: row.enabled }),
    });
    ElMessage.success("已保存");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

onMounted(load);
</script>
