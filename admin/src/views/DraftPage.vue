<template>
  <div>
    <div class="toolbar">
      <h2>{{ title }}</h2>
      <div>
        <el-select v-if="filterOptions" v-model="filter" clearable placeholder="全部分类" style="width: 140px">
          <el-option v-for="option in filterOptions" :key="option.value" :label="option.label" :value="option.value" />
        </el-select>
        <el-button type="primary" @click="openCreate">新增</el-button>
      </div>
    </div>
    <el-table :data="visibleRows" v-loading="loading">
      <el-table-column prop="slug" label="编号" width="160" />
      <el-table-column v-for="field in fields" :key="field.key" :prop="field.key" :label="field.label" />
      <el-table-column label="操作" width="100">
        <template #default="{ row }">
          <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="visible" :title="creating ? '新增' : '编辑'" width="520px">
      <el-form label-width="100px">
        <el-form-item label="编号">
          <el-input v-model="form.slug" :disabled="!creating" />
        </el-form-item>
        <el-form-item v-for="field in fields" :key="field.key" :label="field.label">
          <el-input v-if="field.kind === 'text'" v-model="form[field.key]" />
          <el-switch v-else-if="field.kind === 'bool'" v-model="form[field.key]" />
          <el-input-number v-else v-model="form[field.key]" :controls="false" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="visible = false">取消</el-button>
        <el-button type="primary" :loading="saving" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { computed, onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Field = { key: string; label: string; kind: "text" | "number" | "bool" };
type Row = Record<string, string | number | boolean | null> & { slug: string };

const props = defineProps<{
  title: string;
  resource: "realms" | "skills" | "items" | "stages" | "buildings";
  fields: Field[];
  filterKey?: string;
  filterOptions?: { label: string; value: string }[];
}>();

const rows = ref<Row[]>([]);
const loading = ref(false);
const saving = ref(false);
const visible = ref(false);
const creating = ref(false);
const filter = ref("");
const form = reactive<Record<string, string | number | boolean | null>>({ slug: "" });

const visibleRows = computed(() => {
  if (!props.filterKey || !filter.value) {
    return rows.value;
  }
  return rows.value.filter((row) => row[props.filterKey!] === filter.value);
});

function blankForm(): void {
  form.slug = "";
  for (const field of props.fields) {
    form[field.key] = field.kind === "number" ? 0 : field.kind === "bool" ? false : "";
  }
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<Row[]>(`/admin/content/${props.resource}`);
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function openCreate(): void {
  creating.value = true;
  blankForm();
  visible.value = true;
}

function openEdit(row: Row): void {
  creating.value = false;
  form.slug = row.slug;
  for (const field of props.fields) {
    form[field.key] = row[field.key];
  }
  visible.value = true;
}

async function save(): Promise<void> {
  if (!form.slug) {
    ElMessage.error("请填写编号");
    return;
  }
  saving.value = true;
  const body: Record<string, string | number | boolean | null> = {};
  for (const field of props.fields) {
    body[field.key] = form[field.key] ?? null;
  }
  try {
    await api(`/admin/content/${props.resource}/${form.slug}`, {
      method: "PUT",
      body: JSON.stringify(body),
    });
    visible.value = false;
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
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
.toolbar h2 {
  margin: 0 0 12px;
}
</style>
