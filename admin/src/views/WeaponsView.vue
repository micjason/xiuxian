<template>
  <div>
    <div class="toolbar">
      <h2>武器分类</h2>
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
      <h2>武器</h2>
      <el-button type="primary" @click="openWeapon()">新建武器</el-button>
    </div>
    <el-table :data="weapons">
      <el-table-column prop="displayName" label="名称" width="180" />
      <el-table-column label="分类" width="140">
        <template #default="{ row }">{{ row.categoryMissing ? "分类不存在" : row.categoryName }}</template>
      </el-table-column>
      <el-table-column label="部位" width="100">
        <template #default="{ row }">{{ slotName(row.slot) }}</template>
      </el-table-column>
      <el-table-column label="战力" width="100">
        <template #default="{ row }">{{ row.power ?? "规则未填" }}</template>
      </el-table-column>
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="openWeapon(row)">编辑</el-button>
          <el-button link type="danger" @click="removeWeapon(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

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

    <el-dialog v-model="weaponOpen" :title="weaponCreating ? '新建武器' : '编辑武器'" width="520px">
      <el-form label-width="80px">
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="分类">
          <el-select v-model="form.categoryId" placeholder="选择分类" style="width: 220px">
            <el-option v-for="category in categories" :key="category.id" :label="category.displayName" :value="category.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="部位">
          <el-select v-model="form.slot" placeholder="选择部位" style="width: 220px">
            <el-option v-for="slot in slots" :key="slot.id" :label="slot.name" :value="slot.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="描述">
          <el-input v-model="form.description" />
        </el-form-item>
        <el-form-item label="攻击">
          <el-input-number v-model="form.attack" :min="0" :controls="false" />
        </el-form-item>
        <el-form-item label="防御">
          <el-input-number v-model="form.defense" :min="0" :controls="false" />
        </el-form-item>
        <el-form-item label="气血">
          <el-input-number v-model="form.hp" :min="0" :controls="false" />
        </el-form-item>
        <el-form-item label="速度">
          <el-input-number v-model="form.speed" :min="0" :controls="false" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="weaponOpen = false">取消</el-button>
        <el-button type="primary" @click="saveWeapon">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Category = { id: string; displayName: string };
type Weapon = Category & {
  description: string;
  categoryId: string;
  categoryName: string;
  categoryMissing: boolean;
  slot: string | null;
  power: number | null;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
};

const slots = [
  { id: "weapon", name: "武器" },
  { id: "helmet", name: "头冠" },
  { id: "clothes", name: "衣服" },
  { id: "shoes", name: "鞋子" },
  { id: "accessory", name: "饰品" },
];

function slotName(slot: string | null): string {
  return slots.find((item) => item.id === slot)?.name ?? "未选";
}

const loading = ref(false);
const categories = ref<Category[]>([]);
const weapons = ref<Weapon[]>([]);
const categoryOpen = ref(false);
const categoryCreating = ref(false);
const categoryId = ref("");
const categoryName = ref("");
const weaponOpen = ref(false);
const weaponCreating = ref(false);
const weaponId = ref("");
const form = reactive({
  displayName: "",
  description: "",
  categoryId: "",
  slot: "weapon",
  attack: 0,
  defense: 0,
  hp: 0,
  speed: 0,
});

async function load(): Promise<void> {
  loading.value = true;
  try {
    categories.value = await api<Category[]>("/admin/draft/weapon-categories");
    weapons.value = await api<Weapon[]>("/admin/draft/weapons");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function openCategory(row?: Category): void {
  categoryCreating.value = !row;
  categoryId.value = row?.id ?? "";
  categoryName.value = row?.displayName ?? "";
  categoryOpen.value = true;
}

async function saveCategory(): Promise<void> {
  const body = JSON.stringify({ displayName: categoryName.value });
  try {
    if (categoryCreating.value) {
      await api("/admin/draft/weapon-categories", { method: "POST", body });
    } else {
      await api(`/admin/draft/weapon-categories/${categoryId.value}`, { method: "PUT", body });
    }
    categoryOpen.value = false;
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function removeCategory(row: Category): Promise<void> {
  await ElMessageBox.confirm(`删除分类「${row.displayName}」？`, "删除分类");
  await api(`/admin/draft/weapon-categories/${row.id}`, { method: "DELETE" });
  await load();
}

function openWeapon(row?: Weapon): void {
  weaponCreating.value = !row;
  weaponId.value = row?.id ?? "";
  form.displayName = row?.displayName ?? "";
  form.description = row?.description ?? "";
  form.categoryId = row?.categoryId ?? "";
  form.slot = row?.slot ?? "weapon";
  form.attack = row?.attack ?? 0;
  form.defense = row?.defense ?? 0;
  form.hp = row?.hp ?? 0;
  form.speed = row?.speed ?? 0;
  weaponOpen.value = true;
}

async function saveWeapon(): Promise<void> {
  const body = JSON.stringify({ ...form });
  try {
    if (weaponCreating.value) {
      await api("/admin/draft/weapons", { method: "POST", body });
    } else {
      await api(`/admin/draft/weapons/${weaponId.value}`, { method: "PUT", body });
    }
    weaponOpen.value = false;
    ElMessage.success("已保存");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function removeWeapon(row: Weapon): Promise<void> {
  await ElMessageBox.confirm(`删除武器「${row.displayName}」？`, "删除武器");
  await api(`/admin/draft/weapons/${row.id}`, { method: "DELETE" });
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
