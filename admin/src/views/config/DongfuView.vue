<template>
  <div>
    <PageHeader title="洞府" desc="药园地块、种子成熟时间、炼丹队列与配方。改完保存到草稿，再到「发布中心」发布后玩家才生效。强化规则仍在「装备强化」页，洞府客户端只挂入口。">
      <template #actions><el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button></template>
    </PageHeader>

    <DataState :loading="loading && !loaded" :error="error" :has-data="loaded" empty-text="" @retry="load">
      <div class="savebar" :class="{ dirty }">
        <span v-if="!hasSaved" class="state">还没有保存过洞府配置：游戏端药园/炼丹会报「尚未发布」，请先填写并保存。</span>
        <span v-else-if="dirty" class="state">有未保存的改动。</span>
        <span v-else class="state ok">已和草稿一致。保存后还要到「发布中心」发布，玩家才会看到。</span>
        <span class="spacer" />
        <el-button @click="fillStarting">填入建议起始值</el-button>
        <el-button :disabled="!dirty" @click="revert">还原</el-button>
        <el-button type="primary" :disabled="!dirty || problems.length > 0" :loading="saving" @click="save">保存到草稿</el-button>
      </div>

      <el-alert v-if="problems.length > 0 && touched" type="warning" :closable="false" show-icon class="gap" title="有几项还没填对">
        <ul class="problems"><li v-for="item in problems" :key="item">{{ item }}</li></ul>
      </el-alert>

      <section class="xx-card">
        <h2>通用</h2>
        <el-form label-position="top" class="form grid2">
          <el-form-item label="药园地块数">
            <el-input-number v-model="form.plotCount" :min="1" :max="20" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">玩家同时能种几块地。建议 4。</p>
          </el-form-item>
          <el-form-item label="炼丹队列长度">
            <el-input-number v-model="form.alchemyQueueLength" :min="1" :max="10" :precision="0" controls-position="right" @change="touched = true" />
            <p class="hint">同时炼几炉。建议 2。</p>
          </el-form-item>
        </el-form>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>种子表</h2>
            <p class="hint">种子物品 → 成熟后产出的草药物品 → 成熟秒数。种子/草药须先在「物品」页建好。</p>
          </div>
          <el-button type="primary" plain @click="addSeed">加一种子</el-button>
        </header>
        <el-table :data="form.seeds" size="default">
          <el-table-column label="种子物品" min-width="180">
            <template #default="{ row }">
              <el-select v-model="row.seedSlug" filterable allow-create default-first-option placeholder="选或填编号" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="产出草药" min-width="180">
            <template #default="{ row }">
              <el-select v-model="row.herbSlug" filterable allow-create default-first-option placeholder="选或填编号" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="成熟秒数" width="140">
            <template #default="{ row }">
              <el-input-number v-model="row.growSeconds" :min="1" :max="604800" :precision="0" size="small" controls-position="right" @change="touched = true" />
            </template>
          </el-table-column>
          <el-table-column label="" width="70" align="right">
            <template #default="{ $index }">
              <el-button link type="danger" :disabled="form.seeds.length <= 1" @click="removeSeed($index)">删</el-button>
            </template>
          </el-table-column>
        </el-table>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>炼丹配方</h2>
            <p class="hint">材料从背包扣；灵石可选。效果保存时会同步到产出物品的 effect（玩家使用丹药读物品效果）。临时属性只能填 attack / defense。</p>
          </div>
          <el-button type="primary" plain @click="addRecipe">加一配方</el-button>
        </header>

        <div v-for="(recipe, rIndex) in form.recipes" :key="rIndex" class="recipe">
          <div class="recipe-head">
            <strong>配方 {{ rIndex + 1 }}</strong>
            <el-button link type="danger" :disabled="form.recipes.length <= 1" @click="removeRecipe(rIndex)">删除配方</el-button>
          </div>
          <el-form label-position="top" class="form recipe-grid">
            <el-form-item label="配方编号">
              <el-input v-model="recipe.recipeSlug" placeholder="pill_cultivate" @input="touched = true" />
            </el-form-item>
            <el-form-item label="产出物品">
              <el-select v-model="recipe.outputItemSlug" filterable allow-create default-first-option placeholder="选或填编号" class="full" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
            </el-form-item>
            <el-form-item label="产出数量">
              <el-input-number v-model="recipe.outputQty" :min="1" :max="9999" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
            <el-form-item label="炼制秒数">
              <el-input-number v-model="recipe.craftSeconds" :min="1" :max="604800" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
            <el-form-item label="灵石消耗（可选）">
              <el-input-number v-model="recipe.spiritStones" :min="0" :precision="0" controls-position="right" @change="touched = true" />
            </el-form-item>
          </el-form>

          <div class="sub">
            <div class="sub-head">
              <span>材料</span>
              <el-button link type="primary" @click="addCost(recipe)">加材料</el-button>
            </div>
            <div v-for="(cost, cIndex) in recipe.costs" :key="cIndex" class="cost-row">
              <el-select v-model="cost.itemSlug" filterable allow-create default-first-option placeholder="物品" class="cost-item" @change="touched = true">
                <el-option v-for="option in itemOptions" :key="option.value" :label="option.label" :value="option.value" />
              </el-select>
              <el-input-number v-model="cost.count" :min="1" :max="9999" :precision="0" size="small" controls-position="right" @change="touched = true" />
              <el-button link type="danger" :disabled="recipe.costs.length <= 1" @click="removeCost(recipe, cIndex)">删</el-button>
            </div>
          </div>

          <div class="sub">
            <div class="sub-head">
              <span>效果（可选，与产出物品共用）</span>
              <el-select :model-value="effectMode(recipe)" placeholder="无效果" clearable style="width: 180px" @change="(v: string | null) => setEffectMode(recipe, v)" @clear="setEffectMode(recipe, null)">
                <el-option label="立刻加修为" value="cultivation" />
                <el-option label="临时攻击" value="attack" />
                <el-option label="临时防御" value="defense" />
              </el-select>
            </div>
            <template v-if="recipe.effect?.cultivationGain != null">
              <el-form-item label="修为获得">
                <el-input-number v-model="recipe.effect.cultivationGain" :min="1" :precision="0" controls-position="right" @change="touched = true" />
              </el-form-item>
            </template>
            <template v-else-if="recipe.effect?.buffStat">
              <el-form label-position="top" class="form recipe-grid">
                <el-form-item label="万分比（1000 = +10%）">
                  <el-input-number v-model="recipe.effect.buffBp" :min="1" :max="100000" :precision="0" controls-position="right" @change="touched = true" />
                </el-form-item>
                <el-form-item label="持续秒数">
                  <el-input-number v-model="recipe.effect.durationSeconds" :min="1" :max="86400" :precision="0" controls-position="right" @change="touched = true" />
                </el-form-item>
              </el-form>
            </template>
          </div>
        </div>
      </section>
    </DataState>
  </div>
</template>

<script setup lang="ts">
import { Refresh } from "@element-plus/icons-vue";
import { ElMessage } from "element-plus";
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import DataState from "../../components/DataState.vue";
import PageHeader from "../../components/PageHeader.vue";
import { isConflictAbort } from "../../composables/conflict";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { useDirtyGuard } from "../../composables/dirty";
import { refreshDraftStatus } from "../../composables/draftStatus";
import { useRevisions } from "../../composables/revisions";

type Cost = { itemSlug: string; count: number | null };
type Effect = {
  cultivationGain?: number | null;
  buffStat?: string | null;
  buffBp?: number | null;
  durationSeconds?: number | null;
};
type Seed = { seedSlug: string; herbSlug: string; growSeconds: number | null };
type Recipe = {
  recipeSlug: string;
  outputItemSlug: string;
  outputQty: number | null;
  craftSeconds: number | null;
  spiritStones: number | null;
  costs: Cost[];
  effect?: Effect | null;
};
type Form = {
  plotCount: number | null;
  alchemyQueueLength: number | null;
  seeds: Seed[];
  recipes: Recipe[];
};
type View = { config: Form | null; starting: Form };
type ItemRow = { id: string; displayName: string };

const SLUG = /^[a-z][a-z0-9_]*$/;

function emptySeed(): Seed {
  return { seedSlug: "", herbSlug: "", growSeconds: 60 };
}
function emptyRecipe(): Recipe {
  return {
    recipeSlug: "",
    outputItemSlug: "",
    outputQty: 1,
    craftSeconds: 30,
    spiritStones: 0,
    costs: [{ itemSlug: "", count: 1 }],
    effect: null,
  };
}
function emptyForm(): Form {
  return { plotCount: 4, alchemyQueueLength: 2, seeds: [emptySeed()], recipes: [emptyRecipe()] };
}

function normalize(raw: Partial<Form> | null | undefined): Form {
  if (!raw) return emptyForm();
  return {
    plotCount: raw.plotCount ?? null,
    alchemyQueueLength: raw.alchemyQueueLength ?? null,
    seeds: (raw.seeds?.length ? raw.seeds : [emptySeed()]).map((row) => ({
      seedSlug: row.seedSlug ?? "",
      herbSlug: row.herbSlug ?? "",
      growSeconds: row.growSeconds ?? null,
    })),
    recipes: (raw.recipes?.length ? raw.recipes : [emptyRecipe()]).map((row) => ({
      recipeSlug: row.recipeSlug ?? "",
      outputItemSlug: row.outputItemSlug ?? "",
      outputQty: row.outputQty ?? null,
      craftSeconds: row.craftSeconds ?? null,
      spiritStones: row.spiritStones ?? 0,
      costs: (row.costs?.length ? row.costs : [{ itemSlug: "", count: 1 }]).map((cost) => ({
        itemSlug: cost.itemSlug ?? "",
        count: cost.count ?? null,
      })),
      effect: row.effect
        ? {
            cultivationGain: row.effect.cultivationGain ?? null,
            buffStat: row.effect.buffStat ?? null,
            buffBp: row.effect.buffBp ?? null,
            durationSeconds: row.effect.durationSeconds ?? null,
          }
        : null,
    })),
  };
}

function payload(form: Form): Record<string, unknown> {
  return {
    plotCount: form.plotCount,
    alchemyQueueLength: form.alchemyQueueLength,
    seeds: form.seeds.map((row) => ({
      seedSlug: row.seedSlug.trim(),
      herbSlug: row.herbSlug.trim(),
      growSeconds: row.growSeconds,
    })),
    recipes: form.recipes.map((row) => {
      const out: Record<string, unknown> = {
        recipeSlug: row.recipeSlug.trim(),
        outputItemSlug: row.outputItemSlug.trim(),
        outputQty: row.outputQty,
        craftSeconds: row.craftSeconds,
        spiritStones: row.spiritStones ?? 0,
        costs: row.costs.map((cost) => ({ itemSlug: cost.itemSlug.trim(), count: cost.count })),
      };
      if (row.effect?.cultivationGain != null) {
        out.effect = { cultivationGain: row.effect.cultivationGain };
      } else if (row.effect?.buffStat) {
        out.effect = {
          buffStat: row.effect.buffStat,
          buffBp: row.effect.buffBp,
          durationSeconds: row.effect.durationSeconds,
        };
      }
      return out;
    }),
  };
}

function clientProblems(form: Form): string[] {
  const list: string[] = [];
  if (form.plotCount == null || form.plotCount < 1 || form.plotCount > 20) list.push("地块数要在 1～20");
  if (form.alchemyQueueLength == null || form.alchemyQueueLength < 1 || form.alchemyQueueLength > 10) list.push("炼丹队列要在 1～10");
  if (!form.seeds.length) list.push("至少一种种子");
  const seedSeen = new Set<string>();
  form.seeds.forEach((row, index) => {
    if (!SLUG.test(row.seedSlug)) list.push(`种子第 ${index + 1} 行：种子编号格式不对`);
    else if (seedSeen.has(row.seedSlug)) list.push(`种子编号重复：${row.seedSlug}`);
    else seedSeen.add(row.seedSlug);
    if (!SLUG.test(row.herbSlug)) list.push(`种子第 ${index + 1} 行：草药编号格式不对`);
    if (row.growSeconds == null || row.growSeconds < 1) list.push(`种子第 ${index + 1} 行：成熟秒数要 ≥ 1`);
  });
  if (!form.recipes.length) list.push("至少一种配方");
  const recipeSeen = new Set<string>();
  form.recipes.forEach((row, index) => {
    const label = `配方第 ${index + 1} 行`;
    if (!SLUG.test(row.recipeSlug)) list.push(`${label}：配方编号格式不对`);
    else if (recipeSeen.has(row.recipeSlug)) list.push(`配方编号重复：${row.recipeSlug}`);
    else recipeSeen.add(row.recipeSlug);
    if (!SLUG.test(row.outputItemSlug)) list.push(`${label}：产出编号格式不对`);
    if (row.outputQty == null || row.outputQty < 1) list.push(`${label}：产出数量要 ≥ 1`);
    if (row.craftSeconds == null || row.craftSeconds < 1) list.push(`${label}：炼制秒数要 ≥ 1`);
    if (!row.costs.length) list.push(`${label}：至少一种材料`);
    row.costs.forEach((cost, cIndex) => {
      if (!SLUG.test(cost.itemSlug)) list.push(`${label}材料 ${cIndex + 1}：编号格式不对`);
      if (cost.count == null || cost.count < 1) list.push(`${label}材料 ${cIndex + 1}：数量要 ≥ 1`);
    });
    if (row.effect?.cultivationGain != null && row.effect.cultivationGain < 1) list.push(`${label}：修为获得要 ≥ 1`);
    if (row.effect?.buffStat) {
      if (row.effect.buffBp == null || row.effect.buffBp < 1) list.push(`${label}：临时属性万分比要 ≥ 1`);
      if (row.effect.durationSeconds == null || row.effect.durationSeconds < 1) list.push(`${label}：持续秒数要 ≥ 1`);
    }
  });
  return list;
}

const loading = ref(false);
const saving = ref(false);
const loaded = ref(false);
const error = ref("");
const touched = ref(false);
const hasSaved = ref(false);
const form = ref<Form>(emptyForm());
const original = ref("");
const starting = ref<Form | null>(null);
const items = ref<ItemRow[]>([]);

const dirty = computed(() => original.value !== "" && JSON.stringify(form.value) !== original.value);
const problems = computed(() => clientProblems(form.value));
useDirtyGuard(dirty);

const itemOptions = computed(() =>
  items.value.map((item) => ({ value: item.id, label: `${item.displayName}（${item.id}）` })),
);

function effectMode(recipe: Recipe): string | null {
  if (recipe.effect?.cultivationGain != null) return "cultivation";
  if (recipe.effect?.buffStat === "attack") return "attack";
  if (recipe.effect?.buffStat === "defense") return "defense";
  return null;
}

function setEffectMode(recipe: Recipe, mode: string | null): void {
  touched.value = true;
  if (!mode) {
    recipe.effect = null;
    return;
  }
  if (mode === "cultivation") {
    recipe.effect = { cultivationGain: recipe.effect?.cultivationGain ?? 100 };
    return;
  }
  recipe.effect = {
    buffStat: mode,
    buffBp: recipe.effect?.buffBp ?? 1000,
    durationSeconds: recipe.effect?.durationSeconds ?? 300,
  };
}

function addSeed(): void {
  form.value.seeds.push(emptySeed());
  touched.value = true;
}
function removeSeed(index: number): void {
  form.value.seeds.splice(index, 1);
  touched.value = true;
}
function addRecipe(): void {
  form.value.recipes.push(emptyRecipe());
  touched.value = true;
}
function removeRecipe(index: number): void {
  form.value.recipes.splice(index, 1);
  touched.value = true;
}
function addCost(recipe: Recipe): void {
  recipe.costs.push({ itemSlug: "", count: 1 });
  touched.value = true;
}
function removeCost(recipe: Recipe, index: number): void {
  recipe.costs.splice(index, 1);
  touched.value = true;
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

const rev = useRevisions("globals");

async function loadItems(): Promise<void> {
  try {
    items.value = await api<ItemRow[]>("/admin/draft/items");
  } catch {
    items.value = [];
  }
}

async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    await rev.load();
    const [view] = await Promise.all([api<View>("/admin/draft/dongfu"), loadItems()]);
    starting.value = normalize(view.starting);
    hasSaved.value = view.config !== null;
    form.value = normalize(view.config ?? view.starting);
    original.value = JSON.stringify(form.value);
    touched.value = false;
    loaded.value = true;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function fillStarting(): void {
  if (!starting.value) return;
  form.value = normalize(clone(starting.value));
  touched.value = true;
  ElMessage.info("已填入建议起始值，还没有保存。");
}

function revert(): void {
  form.value = original.value ? (JSON.parse(original.value) as Form) : emptyForm();
  touched.value = false;
}

async function save(): Promise<void> {
  touched.value = true;
  if (problems.value.length > 0) {
    ElMessage.warning(problems.value[0]);
    return;
  }
  saving.value = true;
  try {
    const view = await api<View>("/admin/draft/dongfu", {
      method: "PUT",
      body: JSON.stringify(payload(form.value)),
      guard: {
        revisions: rev,
        id: 1,
        reload: load,
        latest: async () => (await api<View>("/admin/draft/dongfu")).config,
        title: "洞府配置",
      },
    });
    hasSaved.value = view.config !== null;
    if (view.config) form.value = normalize(view.config);
    original.value = JSON.stringify(form.value);
    touched.value = false;
    ElMessage.success("已保存到草稿，发布后玩家生效");
    void refreshDraftStatus();
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

useRefetchOnActivate(load);
onMounted(load);
</script>

<style scoped>
.savebar {
  position: sticky;
  top: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-4);
  padding: var(--xx-space-2) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-surface);
  box-shadow: var(--xx-shadow-card);
}
.savebar.dirty {
  border-color: var(--xx-warning);
  background: var(--xx-warning-bg);
}
.state {
  font-size: var(--xx-fs-sm);
}
.state.ok {
  color: var(--xx-text-secondary);
}
.spacer {
  flex: 1;
}
.gap {
  margin-top: var(--xx-space-4);
}
h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-lg);
}
.head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-3);
}
.head h2 {
  margin-bottom: 4px;
}
.hint {
  margin: 4px 0 0;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  line-height: 1.5;
}
.form :deep(.el-input-number) {
  width: 160px;
}
.grid2 {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 280px));
  gap: var(--xx-space-3);
}
.full {
  width: 100%;
}
.problems {
  margin: 4px 0 0;
  padding-left: 18px;
}
.recipe {
  padding: var(--xx-space-3);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
  margin-bottom: var(--xx-space-3);
}
.recipe-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--xx-space-2);
}
.recipe-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: var(--xx-space-2) var(--xx-space-3);
}
.sub {
  margin-top: var(--xx-space-3);
  padding-top: var(--xx-space-2);
  border-top: 1px dashed var(--xx-border);
}
.sub-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--xx-space-2);
  font-size: var(--xx-fs-sm);
  color: var(--xx-text-secondary);
}
.cost-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 8px;
}
.cost-item {
  flex: 1;
  min-width: 180px;
}
</style>
