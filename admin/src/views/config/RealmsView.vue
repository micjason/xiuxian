<template>
  <div>
    <PageHeader title="境界" desc="境界决定突破顺序、挂机修为产出，以及到达后永久增加的属性。点击一行在右侧抽屉编辑；新建按「大境界」一次生成三层。" />
    <div class="tip">修炼间隔固定 1 秒 · 基础出手间隔全局 {{ combat.baseInterval }} 秒（最短 {{ combat.minInterval }} 秒，速度基数 {{ combat.speedBase }}）· 境界不再自带大招</div>
    <ConfigListPage
      :schema="realmSchema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="code"
      entity-name="境界"
      :search-keys="['displayName', 'majorName', 'code']"
      search-placeholder="搜索境界名称、大境界、编号"
      :filters="filters"
      :creatable="false"
      deletable
      selectable
      danger-delete
      :hidden-keys="['majorKey', 'tickSeconds', 'majorName']"
      :options-map="{ requiredStageId: stageOptions }"
      :save-fn="save"
      :remove-fn="remove"
      :delete-hint="deleteHint"
      :title-of="titleOf"
      export-name="境界"
      @reload="reload"
    >
      <template #toolbar>
        <el-button type="primary" @click="openMajorCreate">新建大境界</el-button>
      </template>
      <template #cell-speed="{ row, value }">
        <span class="speed-cell">
          <strong>{{ value ?? 0 }}</strong>
          <span class="muted">折算出手约 {{ intervalText(Number((row as Realm).speed) || 0) }} 秒</span>
        </span>
      </template>
      <template #extra-columns>
        <el-table-column label="每秒修为" width="120" align="right">
          <template #default="{ row }">
            <span v-if="perSecondOf(row as Realm) == null" class="muted">—</span>
            <span v-else class="per-sec" title="本境数值，非累计前境：每次获得 ÷ 修炼间隔（固定 1 秒）">{{ perSecondOf(row as Realm) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="120">
          <template #default="{ row }">
            <el-tag v-for="tag in statusOf(row as Realm)" :key="tag" type="warning" effect="light" size="small" class="tag">{{ tag }}</el-tag>
            <el-tag v-if="statusOf(row as Realm).length === 0" type="success" effect="light" size="small">完整</el-tag>
          </template>
        </el-table-column>
      </template>
      <template #form="{ form, mode, showAllErrors, original }">
        <SchemaForm
          :model-value="form"
          :schema="realmSchema"
          :original="mode === 'edit' ? original : undefined"
          :mode="mode"
          :show-all-errors="showAllErrors"
          :options-map="{ requiredStageId: stageOptions }"
          :hidden-keys="['code', 'majorKey', 'tickSeconds']"
        />
        <div class="per-sec-box">
          <FormRow label="每秒修为（只读）" help="每次获得修为 ÷ 1 秒。本境自己的数，不是前面境界加起来。">
            <NumInput :model-value="formPerSecond(form)" unit="点/秒" :precision="2" readonly />
          </FormRow>
          <FormRow label="折算出手（只读）" help="max(最短间隔, 基准出手间隔 × 速度基数 ÷ (速度基数 + 本行境界速度))。只按境界速度，不含装备速度。">
            <NumInput :model-value="Number(intervalText(Number(form.speed) || 0))" unit="秒" :precision="2" readonly />
          </FormRow>
        </div>
      </template>
    </ConfigListPage>

    <EditDrawer
      v-model="majorOpen"
      title="新建大境界"
      subtitle="自动生成一层 / 二层 / 三层；沿用上一大境界 ×3（速度 +10），可改"
      :dirty="majorDirty"
      :saving="majorSaving"
      :error-count="majorError ? 1 : 0"
      save-text="创建三层"
      @save="saveMajor"
    >
      <FormRow label="大境界名称" help="例如「元婴」。保存后生成「元婴一层 / 二层 / 三层」，编号自动接在末尾。">
        <el-input v-model="majorName" maxlength="20" placeholder="例如：元婴" @input="onMajorNameInput" />
      </FormRow>
      <p class="rule">预填规则：上一大境界同层 · 修为/攻/防/血/突破消耗 ×3 · 速度 = 同层 +10；没有上一境时用炼气种子。折算出手只按境界速度。基础出手间隔用全局 {{ combat.baseInterval }} 秒，不按层填。</p>
      <el-table :data="majorLayers" size="small" class="major-grid" border>
        <el-table-column prop="displayName" label="名称" min-width="110" />
        <el-table-column label="每次修为" width="100">
          <template #default="{ row }"><el-input-number v-model="row.gainPerTick" :min="0" :step="1" controls-position="right" class="num" /></template>
        </el-table-column>
        <el-table-column label="突破消耗" width="110">
          <template #default="{ row }"><el-input-number v-model="row.breakthroughCost" :min="0" :step="1" controls-position="right" class="num" /></template>
        </el-table-column>
        <el-table-column label="攻击" width="90">
          <template #default="{ row }"><el-input-number v-model="row.attack" :min="0" :step="1" controls-position="right" class="num" /></template>
        </el-table-column>
        <el-table-column label="防御" width="90">
          <template #default="{ row }"><el-input-number v-model="row.defense" :min="0" :step="1" controls-position="right" class="num" /></template>
        </el-table-column>
        <el-table-column label="气血" width="90">
          <template #default="{ row }"><el-input-number v-model="row.hp" :min="0" :step="1" controls-position="right" class="num" /></template>
        </el-table-column>
        <el-table-column label="速度" width="90">
          <template #default="{ row }"><el-input-number v-model="row.speed" :min="0" :step="1" controls-position="right" class="num" /></template>
        </el-table-column>
      </el-table>
      <p v-if="majorError" class="err">{{ majorError }}</p>
    </EditDrawer>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { computed, reactive, ref, watch } from "vue";
import { api } from "../../api";
import { latestFrom, useRevisions } from "../../composables/revisions";
import { useList } from "../../composables/useList";
import ConfigListPage from "../../components/ConfigListPage.vue";
import EditDrawer from "../../components/EditDrawer.vue";
import FormRow from "../../components/FormRow.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SchemaForm from "../../components/SchemaForm.vue";
import { realmSchema } from "../../schema/resources";

type Realm = {
  code: number;
  displayName: string;
  majorName: string;
  tickSeconds: number;
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  requiredStageId: string;
};

type LayerForm = {
  displayName: string;
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
};

type ApiStage = { id: string; displayName: string; realmCode: number; bosses: { name: string }[] };

const stageOptions = ref<{ label: string; value: string }[]>([{ label: "不需要", value: "" }]);
async function loadStages() {
  const stages = await api<ApiStage[]>("/admin/draft/stages");
  stageOptions.value = [
    { label: "不需要", value: "" },
    ...stages.filter((stage) => stage.bosses.length > 0).map((stage) => ({ label: `${stage.displayName}（首领：${stage.bosses[0]?.name ?? ""}）`, value: stage.id })),
  ];
}
loadStages().catch(() => undefined);

const combat = reactive({ baseInterval: 1.5, minInterval: 0.5, speedBase: 100 });
async function loadCombat() {
  const rules = await api<{ baseInterval?: number; minInterval?: number; speedBase?: number }>("/admin/draft/rules");
  combat.baseInterval = Number(rules.baseInterval) > 0 ? Number(rules.baseInterval) : 1.5;
  combat.minInterval = Number(rules.minInterval) > 0 ? Number(rules.minInterval) : 0.5;
  combat.speedBase = Number(rules.speedBase) > 0 ? Number(rules.speedBase) : 100;
}
loadCombat().catch(() => undefined);

const rev = useRevisions("realm");
const { rows, loading, error, reload } = useList(async () => {
  await rev.load();
  return await api<Realm[]>("/admin/draft/realms");
});

const filters = computed(() => [
  {
    key: "majorName",
    label: "大境界",
    options: [...new Set(rows.value.map((row) => row.majorName).filter(Boolean))].map((name) => ({ label: name, value: name })),
  },
]);

function statusOf(row: Realm): string[] {
  const tags: string[] = [];
  if (!row.gainPerTick) tags.push("未设修炼速度");
  return tags;
}

function perSecondOf(row: Realm): string | null {
  if (row.gainPerTick == null || row.gainPerTick < 0) return null;
  if (row.gainPerTick === 0) return "0";
  return String(row.gainPerTick);
}

function formPerSecond(form: Record<string, unknown>): number | null {
  const gain = Number(form.gainPerTick);
  if (!Number.isFinite(gain) || gain < 0) return null;
  return Math.round(gain * 100) / 100;
}

/** 折算出手秒数（用本行速度增量作近似；真实战斗用面板总速度）。 */
function intervalText(speed: number): string {
  const value = Math.max(combat.minInterval, (combat.baseInterval * combat.speedBase) / (combat.speedBase + Math.max(speed, 0)));
  return value.toFixed(2);
}

function titleOf(form: Record<string, unknown>, mode: "create" | "edit"): string {
  const name = String(form.displayName ?? "");
  return mode === "create" ? "新建境界" : `编辑境界：${name || "未命名"}`;
}

function bodyOf(values: Record<string, unknown>): string {
  const body: Record<string, unknown> = {};
  for (const field of realmSchema.fields) {
    if (field.key === "tickSeconds") {
      body.tickSeconds = 1;
      continue;
    }
    body[field.key] = values[field.key];
  }
  return JSON.stringify(body);
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  if (mode === "create") {
    throw new Error("请用「新建大境界」");
  }
  await api(`/admin/draft/realms/${editingId}`, {
    method: "PUT",
    body: bodyOf(values),
    guard: {
      revisions: rev,
      id: editingId,
      reload,
      latest: () => latestFrom("/admin/draft/realms", "code", editingId),
      title: `境界「${String(values.displayName)}」`,
    },
  });
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/realms/${String(row.code)}`, { method: "DELETE" });
}

function deleteHint(row: Record<string, unknown>): string {
  return `将删除境界「${String(row.displayName)}」。已经在这个境界的测试账号需要你自己清掉（玩家管理里可清空进度）。`;
}

// ----- 新建大境界 -----
const majorOpen = ref(false);
const majorSaving = ref(false);
const majorName = ref("");
const majorLayers = ref<LayerForm[]>([]);
const majorOriginal = ref("");
const majorError = ref("");
const majorDirty = computed(() => JSON.stringify({ name: majorName.value, layers: majorLayers.value }) !== majorOriginal.value);

async function fillMajorPreview(name: string) {
  const preview = await api<{ layers: LayerForm[] }>(`/admin/draft/realms/major-preview?majorName=${encodeURIComponent(name)}`);
  majorLayers.value = preview.layers.map((layer) => ({
    displayName: layer.displayName,
    gainPerTick: layer.gainPerTick,
    breakthroughCost: layer.breakthroughCost,
    attack: layer.attack,
    defense: layer.defense,
    hp: layer.hp,
    speed: layer.speed,
  }));
}

async function openMajorCreate() {
  majorName.value = "";
  majorError.value = "";
  await fillMajorPreview("");
  majorOriginal.value = JSON.stringify({ name: majorName.value, layers: majorLayers.value });
  majorOpen.value = true;
}

let nameTimer: ReturnType<typeof setTimeout> | null = null;
function onMajorNameInput() {
  majorError.value = "";
  if (nameTimer) clearTimeout(nameTimer);
  nameTimer = setTimeout(() => {
    const name = majorName.value.trim();
    // 只改名称列，保留用户已改的数值
    majorLayers.value = majorLayers.value.map((layer, index) => ({
      ...layer,
      displayName: name ? `${name}${["一层", "二层", "三层"][index]}` : `？${["一层", "二层", "三层"][index]}`,
    }));
  }, 120);
}

async function saveMajor() {
  const name = majorName.value.trim();
  if (!name) {
    majorError.value = "请填写大境界名称";
    return;
  }
  if (majorLayers.value.length !== 3) {
    majorError.value = "需要三层数据";
    return;
  }
  majorSaving.value = true;
  majorError.value = "";
  try {
    await api("/admin/draft/realms/major", {
      method: "POST",
      body: JSON.stringify({
        majorName: name,
        layers: majorLayers.value.map((layer) => ({
          gainPerTick: layer.gainPerTick,
          breakthroughCost: layer.breakthroughCost,
          attack: layer.attack,
          defense: layer.defense,
          hp: layer.hp,
          speed: layer.speed,
        })),
      }),
    });
    ElMessage.success(`已创建大境界「${name}」三层`);
    majorOriginal.value = JSON.stringify({ name: majorName.value, layers: majorLayers.value });
    majorOpen.value = false;
    await reload();
  } catch (cause) {
    majorError.value = cause instanceof Error ? cause.message : "创建失败";
  } finally {
    majorSaving.value = false;
  }
}

watch(majorOpen, (open) => {
  if (!open) majorError.value = "";
});
</script>

<style scoped>
.tip {
  margin: 0 0 var(--xx-space-3);
  padding: var(--xx-space-2) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.tag + .tag {
  margin-left: 4px;
}
.muted {
  color: var(--xx-text-secondary);
}
.per-sec {
  font-variant-numeric: tabular-nums;
  font-weight: 600;
}
.per-sec-box {
  margin-top: var(--xx-space-4);
  padding: var(--xx-space-3) var(--xx-space-4);
  border: 1px dashed var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
  display: grid;
  gap: var(--xx-space-3);
}
.speed-cell {
  display: inline-flex;
  flex-direction: column;
  line-height: 1.25;
  font-variant-numeric: tabular-nums;
}
.speed-cell .muted {
  font-size: 12px;
}
.rule {
  margin: 0 0 var(--xx-space-3);
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  line-height: 1.5;
}
.major-grid {
  width: 100%;
}
.major-grid :deep(.num) {
  width: 100%;
}
.major-grid :deep(.el-input-number .el-input__inner) {
  padding-left: 4px;
  padding-right: 28px;
}
.err {
  margin: var(--xx-space-3) 0 0;
  color: var(--xx-danger, #c45656);
}
</style>
