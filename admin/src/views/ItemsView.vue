<template>
  <div>
    <div class="toolbar">
      <h2>物品</h2>
      <el-button type="primary" @click="create">新建物品</el-button>
    </div>
    <p>这里只填名称和描述。武器在武器页建。</p>
    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="displayName" label="名称" width="180" />
      <el-table-column prop="description" label="描述" />
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="edit(row)">编辑</el-button>
          <el-button link type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="open" :title="creating ? '新建物品' : '编辑物品'" width="520px">
      <el-form label-width="80px">
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="描述">
          <el-input v-model="form.description" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="open = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Item = { id: string; displayName: string; description: string };

const loading = ref(false);
const open = ref(false);
const creating = ref(false);
const editingId = ref("");
const rows = ref<Item[]>([]);
const form = reactive({ displayName: "", description: "" });

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<Item[]>("/admin/draft/items");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function blank(): void {
  form.displayName = "";
  form.description = "";
}

function create(): void {
  creating.value = true;
  editingId.value = "";
  blank();
  open.value = true;
}

function edit(row: Item): void {
  creating.value = false;
  editingId.value = row.id;
  form.displayName = row.displayName;
  form.description = row.description;
  open.value = true;
}

async function save(): Promise<void> {
  const body = JSON.stringify({ displayName: form.displayName, description: form.description });
  try {
    if (creating.value) {
      await api("/admin/draft/items", { method: "POST", body });
    } else {
      await api(`/admin/draft/items/${editingId.value}`, { method: "PUT", body });
    }
    open.value = false;
    ElMessage.success("已保存，游戏会马上使用");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function remove(row: Item): Promise<void> {
  await ElMessageBox.confirm(`删除物品「${row.displayName}」？`, "删除物品");
  await api(`/admin/draft/items/${row.id}`, { method: "DELETE" });
  ElMessage.success("已删除");
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
