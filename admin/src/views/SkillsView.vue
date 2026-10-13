<template>
  <div>
    <div class="toolbar">
      <h2>技能分类</h2>
      <el-button type="primary" @click="openCategory()">新建分类</el-button>
    </div>
    <el-table :data="categories" v-loading="loading">
      <el-table-column prop="displayName" label="名称" />
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="openCategory(row)">编辑</el-button>
          <el-button link type="danger" @click="removeCategory(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <div class="toolbar second">
      <h2>技能</h2>
      <el-button type="primary" @click="create">新建技能</el-button>
    </div>
    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="displayName" label="名称" width="180" />
      <el-table-column label="分类" width="160">
        <template #default="{ row }">{{ row.categoryMissing ? "分类不存在" : row.categoryName }}</template>
      </el-table-column>
      <el-table-column prop="description" label="描述" />
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="edit(row)">编辑</el-button>
          <el-button link type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="open" :title="creating ? '新建技能' : '编辑技能'" width="520px">
      <el-form label-width="120px">
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="分类">
          <el-select v-model="form.categoryId" placeholder="选择分类" style="width: 220px">
            <el-option v-for="category in categories" :key="category.id" :label="category.displayName" :value="category.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="描述">
          <el-input v-model="form.description" />
        </el-form-item>
        <el-form-item label="攻击（%）">
          <el-input-number v-model="form.attack" :min="0" :max="100" :step="0.01" :controls="false" />
        </el-form-item>
        <el-form-item label="防御（%）">
          <el-input-number v-model="form.defense" :min="0" :max="100" :step="0.01" :controls="false" />
        </el-form-item>
        <el-form-item label="气血（%）">
          <el-input-number v-model="form.hp" :min="0" :max="100" :step="0.01" :controls="false" />
        </el-form-item>
        <el-form-item label="修炼加成（万分比）">
          <el-input-number v-model="form.cultivateBonus" :min="0" :controls="false" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="open = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>
    <el-dialog v-model="categoryOpen" :title="categoryCreating ? '新建分类' : '编辑分类'" width="420px">
      <el-form label-width="80px">
        <el-form-item label="名称">
          <el-input v-model="categoryName" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="categoryOpen = false">取消</el-button>
        <el-button type="primary" @click="saveCategory">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Category = { id: string; displayName: string };
type Skill = {
  id: string;
  displayName: string;
  description: string;
  categoryId: string;
  categoryName: string;
  categoryMissing: boolean;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  cultivateBonus: number;
};

const loading = ref(false);
const open = ref(false);
const creating = ref(false);
const editingId = ref("");
const rows = ref<Skill[]>([]);
const categories = ref<Category[]>([]);
const categoryOpen = ref(false);
const categoryCreating = ref(false);
const categoryEditId = ref("");
const categoryName = ref("");
const form = reactive({
  displayName: "",
  description: "",
  categoryId: "",
  attack: 0,
  defense: 0,
  hp: 0,
  speed: 0,
  cultivateBonus: 0,
});

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<Skill[]>("/admin/draft/skills");
    categories.value = await api<Category[]>("/admin/draft/skill-categories");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function blank(): void {
  form.displayName = "";
  form.description = "";
  form.categoryId = "";
  form.attack = 0;
  form.defense = 0;
  form.hp = 0;
  form.speed = 0;
  form.cultivateBonus = 0;
}

function create(): void {
  creating.value = true;
  editingId.value = "";
  blank();
  open.value = true;
}

function edit(row: Skill): void {
  creating.value = false;
  editingId.value = row.id;
  form.displayName = row.displayName;
  form.description = row.description;
  form.categoryId = row.categoryId;
  form.attack = row.attack;
  form.defense = row.defense;
  form.hp = row.hp;
  form.speed = row.speed;
  form.cultivateBonus = row.cultivateBonus;
  open.value = true;
}

async function save(): Promise<void> {
  const body = { ...form };
  try {
    if (creating.value) {
      await api("/admin/draft/skills", { method: "POST", body: JSON.stringify(body) });
    } else {
      await api(`/admin/draft/skills/${editingId.value}`, { method: "PUT", body: JSON.stringify(body) });
    }
    open.value = false;
    ElMessage.success("已保存，游戏会马上使用");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function remove(row: Skill): Promise<void> {
  await ElMessageBox.confirm(`删除技能「${row.displayName}」？`, "删除技能");
  await api(`/admin/draft/skills/${row.id}`, { method: "DELETE" });
  ElMessage.success("已删除");
  await load();
}

function openCategory(row?: Category): void {
  categoryCreating.value = !row;
  categoryEditId.value = row?.id ?? "";
  categoryName.value = row?.displayName ?? "";
  categoryOpen.value = true;
}

async function saveCategory(): Promise<void> {
  const body = JSON.stringify({ displayName: categoryName.value });
  try {
    if (categoryCreating.value) {
      await api("/admin/draft/skill-categories", { method: "POST", body });
    } else {
      await api(`/admin/draft/skill-categories/${categoryEditId.value}`, { method: "PUT", body });
    }
    categoryOpen.value = false;
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function removeCategory(row: Category): Promise<void> {
  await ElMessageBox.confirm(`删除分类「${row.displayName}」？`, "删除分类");
  await api(`/admin/draft/skill-categories/${row.id}`, { method: "DELETE" });
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
.second {
  margin-top: 28px;
}
</style>
