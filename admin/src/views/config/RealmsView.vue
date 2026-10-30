<template>
  <div>
    <PageHeader title="境界" desc="固定 8 大境界 × 3 层 = 24 行；只调数字；改过标金「已调」。无新建 / 删除 / 导入导出。" />
    <div class="banner" role="note">
      <i class="mark" aria-hidden="true">i</i>
      <p>
        <strong>固定炼气→大乘 · 每天按 6 小时有效挂机估时长 · <span class="gold">改过标金</span></strong>
        <span class="more">不可新增 / 删除 / 导入导出 · 预计时长：出厂目标，不随改数变 · 本境修为非累计前境</span>
      </p>
    </div>

    <div class="filter-bar">
      <el-input v-model="query" class="search" clearable placeholder="搜索境界" :prefix-icon="Search" />
      <el-select v-model="majorFilter" clearable placeholder="全部大境界" class="filter">
        <el-option v-for="name in majorOptions" :key="name" :label="name" :value="name" />
      </el-select>
      <el-button v-if="filtering" link type="primary" @click="clearFilters">清除筛选</el-button>
      <span v-if="rows.length > 0" class="count">共 {{ majorCount }} 个大境界 · {{ filtered.length }} 层 · 已调 {{ tunedLayers }} 层</span>
    </div>

    <DataState :loading="loading" :error="error" :has-data="rows.length > 0" empty-text="境界表还没有加载出来" @retry="reload">
      <el-table
        :data="tableRows"
        row-key="key"
        class="grid"
        :row-class-name="rowClass"
        :span-method="spanOf"
        @row-click="onRow"
      >
        <el-table-column label="名称" min-width="148">
          <template #default="{ row }">
            <template v-if="row.kind === 'group'">
              <strong class="group-name">{{ row.majorName }}</strong>
              <span class="group-fixed">固定 3 层 · 不可增删</span>
            </template>
            <span v-else>{{ row.displayName }}</span>
          </template>
        </el-table-column>
        <el-table-column label="本境每秒修为" min-width="148" align="right">
          <template #header>
            <span>本境每秒修为</span>
            <HelpTip title="本境每秒修为" text="挂机时这一境每秒获得的修为。只算本境，不把前面境界加进来。修炼间隔固定 1 秒。" meta="本境绝对值 · 出厂见各行" />
          </template>
          <template #default="{ row }">
            <span v-if="row.kind === 'layer'" class="num" :class="{ gold: changed(row, 'gainPerTick') }">{{ formatNum(row.gainPerTick) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="升下层所需修为" min-width="148" align="right">
          <template #default="{ row }">
            <span v-if="row.kind === 'layer'" class="num" :class="{ gold: changed(row, 'breakthroughCost') }">{{ formatNum(row.breakthroughCost) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="速度" width="96" align="right">
          <template #header>
            <span>速度</span>
            <HelpTip title="速度" text="到达本层增加的速度，会和更低境界加在一起。出手间隔只在配置概览里用全局基准间隔折算，这一页不列出手。" />
          </template>
          <template #default="{ row }">
            <span v-if="row.kind === 'layer'" class="num" :class="{ gold: changed(row, 'speed') }">{{ formatNum(row.speed) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="攻击" width="88" align="right">
          <template #default="{ row }">
            <span v-if="row.kind === 'layer'" class="num" :class="{ gold: changed(row, 'attack') }">{{ formatNum(row.attack) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="防御" width="88" align="right">
          <template #default="{ row }">
            <span v-if="row.kind === 'layer'" class="num" :class="{ gold: changed(row, 'defense') }">{{ formatNum(row.defense) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="气血" width="96" align="right">
          <template #default="{ row }">
            <span v-if="row.kind === 'layer'" class="num" :class="{ gold: changed(row, 'hp') }">{{ formatNum(row.hp) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="预计时长" min-width="120">
          <template #header>
            <span>预计时长</span>
            <HelpTip title="预计时长" text="出厂目标，不随改数变。按每天 6 小时有效挂机折算，写死在出厂表里。改修为或突破消耗只会把数字标金，不会重算这一列。" meta="约 30 分 … 约 55 天" />
          </template>
          <template #default="{ row }">
            <span v-if="row.kind === 'layer'">{{ row.etaLabel }}</span>
          </template>
        </el-table-column>
        <el-table-column label="已调/完整" width="168">
          <template #default="{ row }">
            <div v-if="row.kind === 'layer'" class="status-cell">
              <CustomTag :kind="row.tuned ? 'custom' : 'default'">{{ row.tuned ? "已调" : "完整" }}</CustomTag>
              <el-button link type="primary" @click.stop="openEdit(row)">编辑</el-button>
            </div>
          </template>
        </el-table-column>
        <template #empty>
          <el-empty description="没有符合条件的境界">
            <el-button v-if="filtering" link type="primary" @click="clearFilters">清除筛选</el-button>
          </el-empty>
        </template>
      </el-table>
    </DataState>

    <EditDrawer
      v-model="drawer"
      :title="editing ? `${editing.displayName} · 调整数字` : '调整数字'"
      :subtitle="drawerSubtitle"
      :dirty="dirty"
      :change-count="changeCount"
      :saving="saving"
      :status-text="statusText"
      :size="800"
      @save="save"
    >
      <template #title-tags>
        <CustomTag v-if="editing" :kind="factoryDiffCount > 0 ? 'custom' : 'default'">{{ factoryDiffCount > 0 ? "已调" : "完整" }}</CustomTag>
      </template>
      <template v-if="editing">
        <div class="eta">
          <div class="eta-label">预计时长（出厂目标，不随改数变 · 只读）</div>
          <div class="eta-value">{{ editing.etaLabel }}</div>
          <p>出厂目标，不随改数变；按每天 6 小时有效挂机折算。改数字只标金，不会按当前修为重算本列。</p>
        </div>

        <SectionCard title="修炼与突破" desc="只显示可改数字">
          <template #extra>
            <CustomTag :kind="cultivateTuned ? 'custom' : 'default'">{{ cultivateTuned ? "已调" : "完整" }}</CustomTag>
          </template>
          <div class="two-col">
            <FormRow label="本境每秒修为" required help="挂机时这一境每秒获得的修为。只算本境，不把前面境界加进来。修炼间隔固定 1 秒。">
              <NumInput v-model="form.gainPerTick" :width="160" unit="修为" :precision="0" :custom="tuned('gainPerTick')" />
              <template #note>
                <span>本境生效，非累计前境 · 修炼间隔固定 1 秒</span>
                <span v-if="tuned('gainPerTick')" class="tuned-note">出厂 {{ formatNum(editing.factory.gainPerTick) }} · 已调 <el-button link type="primary" @click="restore('gainPerTick')">恢复出厂</el-button></span>
              </template>
            </FormRow>
            <FormRow v-if="editing.showBreakthroughCost" label="升到下一层所需修为" required>
              <NumInput v-model="form.breakthroughCost" :width="160" unit="修为" :precision="0" :custom="tuned('breakthroughCost')" />
              <template #note>
                <span>从本层突破到下一层要消耗的修为</span>
                <span v-if="tuned('breakthroughCost')" class="tuned-note">出厂 {{ formatNum(editing.factory.breakthroughCost) }} · 已调 <el-button link type="primary" @click="restore('breakthroughCost')">恢复出厂</el-button></span>
              </template>
            </FormRow>
          </div>
        </SectionCard>

        <SectionCard title="境界属性" desc="到达本层增加量。入库为差分加算，与现逻辑一致">
          <template #extra>
            <CustomTag :kind="statsTuned ? 'custom' : 'default'">{{ statsTuned ? "已调" : "完整" }}</CustomTag>
          </template>
          <div class="two-col">
            <FormRow v-for="stat in statFields" :key="stat.key" :label="stat.label" required :help="stat.help">
              <NumInput v-model="form[stat.key]" :width="120" :precision="0" :custom="tuned(stat.key)" />
              <template v-if="tuned(stat.key)" #note>
                <span class="tuned-note">出厂 {{ formatNum(editing.factory[stat.key]) }} · 已调 <el-button link type="primary" @click="restore(stat.key)">恢复出厂</el-button></span>
              </template>
            </FormRow>
          </div>
        </SectionCard>

        <SectionCard v-if="editing.showGate" title="突破门槛" desc="仅各大境三层需要；一二层不显示">
          <template #extra>
            <CustomTag :kind="gateTuned ? 'custom' : 'default'">{{ gateTuned ? "已调" : "完整" }}</CustomTag>
          </template>
          <FormRow label="突破前通关关卡">
            <el-select v-model="form.requiredStageId" class="w320" :class="{ 'gate-custom': gateTuned }" placeholder="不需要">
              <el-option v-for="option in stageOptions" :key="option.value || 'none'" :label="option.label" :value="option.value" />
            </el-select>
            <template #note>
              <span>突破到下一大境一层前，需先通关本境章末首领关</span>
              <span v-if="gateTuned" class="tuned-note">出厂 {{ editing.factory.requiredStageId ? "已配关卡" : "不需要" }} · 已调 <el-button link type="primary" @click="restoreGate">恢复出厂</el-button></span>
              <span v-if="stageError" class="err">关卡列表加载失败：{{ stageError }}</span>
            </template>
          </FormRow>
        </SectionCard>
        <p v-if="formError" class="err">{{ formError }}</p>
      </template>
      <template #footer-extra>
        <el-button type="primary" :disabled="!editing || factoryDiffCount === 0 || saving" @click="restoreAll">整行恢复出厂</el-button>
      </template>
    </EditDrawer>
  </div>
</template>

<script setup lang="ts">
import { Search } from "@element-plus/icons-vue";
import { ElMessage } from "element-plus";
import { computed, reactive, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { api } from "../../api";
import { isConflictAbort } from "../../composables/conflict";
import { refreshDraftStatus } from "../../composables/draftStatus";
import { latestFrom, useRevisions } from "../../composables/revisions";
import { useList } from "../../composables/useList";
import CustomTag from "../../components/CustomTag.vue";
import DataState from "../../components/DataState.vue";
import EditDrawer from "../../components/EditDrawer.vue";
import FormRow from "../../components/FormRow.vue";
import HelpTip from "../../components/HelpTip.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SectionCard from "../../components/SectionCard.vue";

type NumKey = "gainPerTick" | "breakthroughCost" | "attack" | "defense" | "hp" | "speed";

type RealmRow = {
  code: number;
  slug: string;
  displayName: string;
  majorName: string;
  layer: 1 | 2 | 3;
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  requiredStageId: string;
  etaLabel: string;
  showBreakthroughCost: boolean;
  showGate: boolean;
  factory: Record<NumKey, number> & { requiredStageId: string };
  changed: string[];
  tuned: boolean;
  tickSeconds: number;
  interval: number | null;
};

type StageRow = { id: string; displayName: string; realmCode: number; tier: string | null; bosses: { name: string }[] };
type FormState = Record<NumKey, number | null> & { requiredStageId: string };
type GroupRow = { kind: "group"; key: string; majorName: string };
type LayerRow = { kind: "layer"; key: string } & RealmRow;
type TableRow = GroupRow | LayerRow;

const LAYER_NAME: Record<RealmRow["layer"], string> = { 1: "第一层", 2: "第二层", 3: "第三层" };
const statFields: { key: "attack" | "defense" | "hp" | "speed"; label: string; help?: string }[] = [
  { key: "attack", label: "攻击" },
  { key: "defense", label: "防御" },
  { key: "hp", label: "气血" },
  { key: "speed", label: "速度", help: "到达本层增加的速度，会和更低境界加在一起。出手间隔只在配置概览里用全局基准间隔折算，这一页不列出手。" },
];

const rev = useRevisions("realm");
const { rows, loading, error, reload } = useList(async () => {
  await rev.load();
  return await api<RealmRow[]>("/admin/draft/realms");
});

const stages = ref<StageRow[]>([]);
const stageError = ref("");
async function loadStages(): Promise<void> {
  try {
    stages.value = await api<StageRow[]>("/admin/draft/stages");
    stageError.value = "";
  } catch (cause) {
    stageError.value = cause instanceof Error ? cause.message : "加载失败";
  }
}
void loadStages();

const query = ref("");
const majorFilter = ref("");
const filtering = computed(() => query.value.trim() !== "" || majorFilter.value !== "");
const majorOptions = computed(() => {
  const names: string[] = [];
  for (const row of rows.value) {
    if (!names.includes(row.majorName)) names.push(row.majorName);
  }
  return names;
});
const filtered = computed(() => {
  const text = query.value.trim();
  return rows.value.filter((row) => {
    if (majorFilter.value && row.majorName !== majorFilter.value) return false;
    if (!text) return true;
    return row.displayName.includes(text) || row.majorName.includes(text);
  });
});
const majorCount = computed(() => new Set(filtered.value.map((row) => row.majorName)).size);
const tunedLayers = computed(() => filtered.value.filter((row) => row.tuned).length);
const tableRows = computed<TableRow[]>(() => {
  const out: TableRow[] = [];
  for (const name of majorOptions.value) {
    const layers = filtered.value.filter((row) => row.majorName === name);
    if (layers.length === 0) continue;
    out.push({ kind: "group", key: `group-${name}`, majorName: name });
    for (const layer of layers) out.push({ kind: "layer", key: String(layer.code), ...layer });
  }
  return out;
});

function clearFilters(): void {
  query.value = "";
  majorFilter.value = "";
}
function formatNum(value: number): string {
  return Math.round(value).toLocaleString("en-US");
}
function changed(row: LayerRow, key: string): boolean {
  return row.changed.includes(key);
}
function spanOf({ row, columnIndex }: { row: TableRow; columnIndex: number }): { rowspan: number; colspan: number } {
  if (row.kind !== "group") return { rowspan: 1, colspan: 1 };
  if (columnIndex === 0) return { rowspan: 1, colspan: 9 };
  return { rowspan: 0, colspan: 0 };
}

const drawer = ref(false);
const saving = ref(false);
const editing = ref<RealmRow | null>(null);
const formError = ref("");
const form = reactive<FormState>({
  gainPerTick: 0,
  breakthroughCost: 0,
  attack: 0,
  defense: 0,
  hp: 0,
  speed: 0,
  requiredStageId: "",
});
const snapshot = ref("");

function payloadOf(row: RealmRow): Record<string, number | string | null> {
  const body: Record<string, number | string | null> = {
    gainPerTick: form.gainPerTick,
    attack: form.attack,
    defense: form.defense,
    hp: form.hp,
    speed: form.speed,
  };
  if (row.showBreakthroughCost) body.breakthroughCost = form.breakthroughCost;
  if (row.showGate) body.requiredStageId = form.requiredStageId;
  return body;
}
const dirty = computed(() => editing.value != null && JSON.stringify(payloadOf(editing.value)) !== snapshot.value);
const changeCount = computed(() => {
  if (!editing.value) return 0;
  const current = payloadOf(editing.value);
  const saved = JSON.parse(snapshot.value || "{}") as Record<string, unknown>;
  return Object.keys(current).filter((key) => current[key] !== saved[key]).length;
});
function tuned(key: NumKey): boolean {
  const row = editing.value;
  if (!row) return false;
  return Number(form[key]) !== Number(row.factory[key]);
}
const gateTuned = computed(() => editing.value != null && form.requiredStageId !== editing.value.factory.requiredStageId);
const cultivateTuned = computed(() => tuned("gainPerTick") || (editing.value?.showBreakthroughCost === true && tuned("breakthroughCost")));
const statsTuned = computed(() => tuned("attack") || tuned("defense") || tuned("hp") || tuned("speed"));
const factoryDiffCount = computed(() => {
  const row = editing.value;
  if (!row) return 0;
  let count = (["gainPerTick", "attack", "defense", "hp", "speed"] as const).filter((key) => tuned(key)).length;
  if (row.showBreakthroughCost && tuned("breakthroughCost")) count += 1;
  if (row.showGate && gateTuned.value) count += 1;
  return count;
});
const statusText = computed(() => (factoryDiffCount.value > 0 ? `已调 ${factoryDiffCount.value} 项（相对出厂），本次未再改` : undefined));
const drawerSubtitle = computed(() => {
  const row = editing.value;
  if (!row) return "";
  return `${row.majorName} · ${LAYER_NAME[row.layer]}${row.showGate ? " · 可配突破关卡" : ""}`;
});
const stageOptions = computed(() => {
  const row = editing.value;
  const options = (row ? stages.value.filter((stage) => stage.bosses.length > 0 && stage.realmCode <= row.code) : []).map((stage) => ({
    value: stage.id,
    label: stage.tier === "chief" ? `${stage.displayName}（章末）` : stage.displayName,
  }));
  if (form.requiredStageId && !options.some((option) => option.value === form.requiredStageId)) {
    options.unshift({ value: form.requiredStageId, label: `关卡不存在（${form.requiredStageId}）` });
  }
  return [{ value: "", label: "不需要" }, ...options];
});

function fillForm(row: RealmRow): void {
  form.gainPerTick = row.gainPerTick;
  form.breakthroughCost = row.breakthroughCost;
  form.attack = row.attack;
  form.defense = row.defense;
  form.hp = row.hp;
  form.speed = row.speed;
  form.requiredStageId = row.requiredStageId ?? "";
  snapshot.value = JSON.stringify(payloadOf(row));
}
function openEdit(row: RealmRow): void {
  editing.value = row;
  formError.value = "";
  fillForm(row);
  drawer.value = true;
}
function restore(key: NumKey): void {
  if (!editing.value) return;
  form[key] = editing.value.factory[key];
}
function restoreGate(): void {
  if (!editing.value) return;
  form.requiredStageId = editing.value.factory.requiredStageId;
}
function restoreAll(): void {
  if (!editing.value) return;
  for (const key of ["gainPerTick", "breakthroughCost", "attack", "defense", "hp", "speed"] as const) {
    form[key] = editing.value.factory[key];
  }
  if (editing.value.showGate) form.requiredStageId = editing.value.factory.requiredStageId;
}

function requireInt(value: number | null, label: string): number {
  if (value === null || value === undefined) throw new Error(`请填写${label}`);
  if (!Number.isInteger(value) || value < 0) throw new Error(`${label}必须是大于等于 0 的整数`);
  return value;
}

async function save(): Promise<void> {
  const row = editing.value;
  if (!row) return;
  formError.value = "";
  let body: Record<string, number | string>;
  try {
    body = {
      gainPerTick: requireInt(form.gainPerTick, "本境每秒修为"),
      attack: requireInt(form.attack, "攻击"),
      defense: requireInt(form.defense, "防御"),
      hp: requireInt(form.hp, "气血"),
      speed: requireInt(form.speed, "速度"),
    };
    if (row.showBreakthroughCost) body.breakthroughCost = requireInt(form.breakthroughCost, "升到下一层所需修为");
    if (row.showGate) body.requiredStageId = form.requiredStageId;
  } catch (cause) {
    formError.value = cause instanceof Error ? cause.message : "请检查数字";
    return;
  }
  saving.value = true;
  try {
    await api(`/admin/draft/realms/${row.code}`, {
      method: "PUT",
      body: JSON.stringify(body),
      guard: {
        revisions: rev,
        id: row.code,
        reload,
        latest: () => latestFrom("/admin/draft/realms", "code", row.code),
        title: `境界「${row.displayName}」`,
      },
    });
    ElMessage.success("已保存，已生效");
    snapshot.value = JSON.stringify(payloadOf(row));
    drawer.value = false;
    await reload();
    void refreshDraftStatus();
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") {
        const hit = rows.value.find((item) => item.code === row.code);
        if (hit) openEdit(hit);
      }
      return;
    }
    formError.value = cause instanceof Error ? cause.message : "保存失败";
  } finally {
    saving.value = false;
  }
}

function onRow(row: TableRow): void {
  if (row.kind === "layer") openEdit(row);
}
function rowClass({ row }: { row: TableRow }): string {
  if (row.kind === "group") return "group-row";
  return editing.value?.code === row.code && drawer.value ? "editing-row" : "";
}

const route = useRoute();
const router = useRouter();
const ownPath = route.path;
watch(
  () => [rows.value, route.query.open, route.path] as const,
  ([list, open, path]) => {
    if (path !== ownPath || typeof open !== "string" || list.length === 0) return;
    const hit = list.find((row) => String(row.code) === open);
    if (hit) openEdit(hit);
    const rest = { ...route.query };
    delete rest.open;
    void router.replace({ query: rest });
  },
  { immediate: true },
);
</script>

<style scoped>
.banner {
  display: flex;
  gap: 10px;
  align-items: flex-start;
  margin: 0 0 16px;
  padding: 10px 14px;
  border: 1px solid #d5e4dc;
  border-radius: 8px;
  background: #f3f8f5;
  color: var(--xx-text-regular);
  font-size: 13px;
  line-height: 1.6;
}
.banner p {
  margin: 0;
}
.banner strong {
  color: var(--xx-text-primary);
  font-weight: 650;
}
.banner .gold {
  color: #8f5c0c;
}
.banner .more {
  color: var(--xx-text-secondary);
}
.mark {
  display: inline-grid;
  place-items: center;
  flex: none;
  width: 18px;
  height: 18px;
  margin-top: 2px;
  border-radius: 50%;
  background: var(--xx-jade-600);
  color: #fff;
  font-size: 12px;
  font-style: normal;
  font-weight: 700;
}
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
  margin-bottom: 12px;
}
.search {
  width: 200px;
}
.filter {
  width: 160px;
}
.count {
  color: var(--xx-text-secondary);
  font-size: 13px;
  white-space: nowrap;
}
.grid {
  width: 100%;
}
.grid :deep(.el-table__cell .cell) {
  white-space: nowrap;
}
.grid :deep(.el-table__row) {
  cursor: pointer;
}
.grid :deep(.group-row),
.grid :deep(.group-row td) {
  cursor: default;
  background: var(--xx-bg-subtle);
}
.grid :deep(.editing-row td) {
  background: #eef5f1;
}
.group-name {
  margin-right: 12px;
}
.group-fixed {
  color: var(--xx-text-secondary);
  font-size: 12px;
  font-weight: 400;
}
.num {
  font-variant-numeric: tabular-nums;
}
.gold {
  color: #8f5c0c;
  font-weight: 650;
}
.status-cell {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
.eta {
  margin-bottom: 16px;
  padding: 14px 16px;
  border: 1px solid var(--xx-border);
  border-radius: 8px;
  background: var(--xx-bg-surface);
}
.eta-label {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.eta-value {
  margin: 4px 0;
  color: var(--xx-text-primary);
  font-size: 22px;
  font-weight: 650;
}
.eta p,
.tuned-note,
.err {
  margin: 0;
}
.eta p,
.tuned-note {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.tuned-note {
  display: block;
  color: #8f5c0c;
}
.two-col {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 18px 40px;
}
.w320 {
  width: 320px;
  max-width: 100%;
}
.gate-custom :deep(.el-select__wrapper) {
  background: #fffcf3;
  box-shadow: 0 0 0 1px #d9b874 inset;
}
.err {
  color: var(--xx-danger, #c45656);
  font-size: 12px;
}
</style>
