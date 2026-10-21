<template>
  <div>
    <PageHeader title="技能" desc="功法按层数放大属性百分比。分类和技能在同一页维护，先建分类再建技能。" />
    <el-tabs v-model="tab" class="tabs" @tab-change="onTab">
      <el-tab-pane :label="`技能（${skills.length}）`" name="skills">
        <ConfigListPage
          :schema="skillSchema"
          :rows="skills"
          :loading="loading"
          :error="error"
          id-key="id"
          entity-name="技能"
          :search-keys="['displayName', 'description', 'categoryName']"
          :filters="skillFilters"
          :options-map="{ categoryId: categoryOptions, requiredRealmCode: realmOptions, prerequisiteIds: skillOptions }"
          :hidden-keys="['categoryName', 'categoryMissing', 'speed']"
          creatable
          deletable
          cloneable
          selectable
          :new-row="newSkill"
          :save-fn="saveSkill"
          :remove-fn="removeSkill"
          export-name="技能"
          @reload="reload"
        >
          <template #cell-categoryId="{ row }">
            <el-tag v-if="row.categoryMissing" type="danger" effect="light" size="small">分类不存在</el-tag>
            <span v-else>{{ row.categoryName }}</span>
          </template>
        </ConfigListPage>
      </el-tab-pane>
      <el-tab-pane :label="`分类（${categories.length}）`" name="categories">
        <ConfigListPage
          :schema="skillCategorySchema"
          :rows="categories"
          :loading="loading"
          :error="error"
          id-key="id"
          entity-name="分类"
          :search-keys="['displayName']"
          creatable
          deletable
          :new-row="() => ({ displayName: '' })"
          :save-fn="saveCategory"
          :remove-fn="removeCategory"
          :delete-hint="categoryHint"
          :drawer-size="520"
          export-name="技能分类"
          @reload="reload"
        />
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import PageHeader from "../../components/PageHeader.vue";
import { skillCategorySchema, skillSchema } from "../../schema/resources";
import { defaultsOf } from "../../schema/validate";

type Category = { id: string; displayName: string };
type Skill = Record<string, unknown> & { id: string; categoryId: string };

const route = useRoute();
const router = useRouter();
const tab = ref(route.query.tab === "categories" ? "categories" : "skills");
const skills = ref<Skill[]>([]);
const categories = ref<Category[]>([]);
const loading = ref(false);
const error = ref("");

const categoryOptions = computed(() => categories.value.map((row) => ({ label: row.displayName, value: row.id })));
const realms = ref<{ code: number; displayName: string }[]>([]);
const realmOptions = computed(() => [{ label: "不限", value: 0 }, ...realms.value.map((row) => ({ label: `${row.code} ${row.displayName}`, value: row.code }))]);
const skillOptions = computed(() => skills.value.map((row) => ({ label: String(row.displayName), value: String(row.id) })));
const skillFilters = computed(() => [{ key: "categoryId", label: "分类", options: categoryOptions.value }]);

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    skills.value = await api<Skill[]>("/admin/draft/skills");
    categories.value = await api<Category[]>("/admin/draft/skill-categories");
    realms.value = await api<{ code: number; displayName: string }[]>("/admin/draft/realms");
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function onTab(name: string | number): void {
  void router.replace({ query: { ...route.query, tab: String(name) } });
}

function newSkill(): Record<string, unknown> {
  return { ...defaultsOf(skillSchema), categoryId: categories.value[0]?.id ?? "" };
}

async function saveSkill(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body = JSON.stringify({
    displayName: values.displayName,
    description: values.description,
    categoryId: values.categoryId,
    attack: values.attack,
    defense: values.defense,
    hp: values.hp,
    speed: values.speed ?? 0,
    cultivateBonus: values.cultivateBonus,
    role: values.role || undefined,
    rank: values.rank || undefined,
    requiredRealmCode: values.requiredRealmCode ?? undefined,
    prerequisiteIds: Array.isArray(values.prerequisiteIds) ? values.prerequisiteIds : undefined,
  });
  if (mode === "create") {
    await api("/admin/draft/skills", { method: "POST", body });
  } else {
    await api(`/admin/draft/skills/${editingId}`, { method: "PUT", body });
  }
}

async function removeSkill(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/skills/${String(row.id)}`, { method: "DELETE" });
}

async function saveCategory(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body = JSON.stringify({ displayName: values.displayName });
  if (mode === "create") {
    await api("/admin/draft/skill-categories", { method: "POST", body });
  } else {
    await api(`/admin/draft/skill-categories/${editingId}`, { method: "PUT", body });
  }
}

async function removeCategory(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/skill-categories/${String(row.id)}`, { method: "DELETE" });
}

function categoryHint(row: Record<string, unknown>): string {
  const used = skills.value.filter((skill) => skill.categoryId === row.id).length;
  return used > 0 ? `分类「${String(row.displayName)}」下还有 ${used} 个技能，删除后这些技能会显示「分类不存在」。确认删除？` : `删除分类「${String(row.displayName)}」？`;
}

onMounted(reload);
</script>

<style scoped>
.tabs :deep(.el-tabs__header) {
  margin-bottom: var(--xx-space-4);
}
</style>
