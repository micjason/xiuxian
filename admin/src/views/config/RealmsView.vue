<template>
  <div>
    <PageHeader title="境界" desc="境界决定突破顺序、挂机修为产出，以及到达后永久增加的属性。点击一行直接在右侧抽屉里编辑。" />
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
      creatable
      deletable
      cloneable
      selectable
      danger-delete
      :new-row="newRow"
      :hidden-keys="['majorKey']"
      :options-map="{ requiredStageId: stageOptions }"
      :save-fn="save"
      :remove-fn="remove"
      :delete-hint="deleteHint"
      export-name="境界"
      @reload="reload"
    >
      <template #extra-columns>
        <el-table-column label="每秒修为" width="120" align="right">
          <template #default="{ row }">
            <span v-if="perSecondOf(row as Realm) == null" class="muted">—</span>
            <span v-else class="per-sec" :title="'本境数值，非累计前境：每次获得 ÷ 修炼间隔'">{{ perSecondOf(row as Realm) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="状态" width="150">
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
          :hidden-keys="['code', 'majorKey']"
        />
        <div class="per-sec-box">
          <FormRow
            label="每秒修为（只读）"
            help="每次获得修为 ÷ 修炼间隔。本境自己的数，不是前面境界加起来（和挂机结算 settle.ts 一致）。改上面两个数会立刻更新。"
          >
            <NumInput :model-value="formPerSecond(form)" unit="点/秒" :precision="2" readonly />
          </FormRow>
        </div>
      </template>
    </ConfigListPage>
  </div>
</template>

<script setup lang="ts">
import { latestFrom, useRevisions } from "../../composables/revisions";
import { computed, ref } from "vue";
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import FormRow from "../../components/FormRow.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SchemaForm from "../../components/SchemaForm.vue";
import { useList } from "../../composables/useList";
import { realmSchema } from "../../schema/resources";
import { defaultsOf } from "../../schema/validate";

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
  interval: number | null;
  requiredStageId: string;
  ultName: string;
  ultMultiplier: number;
  ultCooldownSeconds: number;
  ultFirstCooldownSeconds: number;
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

const rev = useRevisions("realm");
const { rows, loading, error, reload } = useList(async () => {
  await rev.load();
  const list = await api<Realm[]>("/admin/draft/realms");
  return list.map((row) => ({ ...row, interval: row.interval ?? undefined })) as unknown as Realm[];
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
  if (!row.tickSeconds || !row.gainPerTick) tags.push("未设修炼速度");
  if (row.interval == null) tags.push("缺出手间隔");
  return tags;
}

/** 本境每秒修为 = gainPerTick / tickSeconds；缺一则无法结算，显示 —。 */
function perSecondOf(row: Realm): string | null {
  if (!row.tickSeconds || row.tickSeconds < 1 || row.gainPerTick == null || row.gainPerTick < 0) return null;
  if (row.gainPerTick === 0) return "0";
  const value = row.gainPerTick / row.tickSeconds;
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/\.?0+$/, "");
}

function formPerSecond(form: Record<string, unknown>): number | null {
  const tick = Number(form.tickSeconds);
  const gain = Number(form.gainPerTick);
  if (!Number.isFinite(tick) || tick < 1 || !Number.isFinite(gain) || gain < 0) return null;
  return Math.round((gain / tick) * 100) / 100;
}

function newRow(): Record<string, unknown> {
  const max = rows.value.length === 0 ? 0 : Math.max(...rows.value.map((row) => row.code));
  return { ...defaultsOf(realmSchema), code: max + 1, interval: 1.5 };
}

function bodyOf(values: Record<string, unknown>): string {
  const body: Record<string, unknown> = {};
  for (const field of realmSchema.fields) {
    body[field.key] = values[field.key];
  }
  return JSON.stringify(body);
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  if (mode === "create") {
    await api("/admin/draft/realms", { method: "POST", body: bodyOf(values) });
  } else {
    await api(`/admin/draft/realms/${editingId}`, { method: "PUT", body: bodyOf(values), guard: { revisions: rev, id: editingId, reload, latest: () => latestFrom("/admin/draft/realms", "code", editingId), title: `境界「${String(values.displayName)}」` } });
  }
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/realms/${String(row.code)}`, { method: "DELETE" });
}

function deleteHint(row: Record<string, unknown>): string {
  return `将删除境界「${String(row.displayName)}」。已经在这个境界的测试账号需要你自己清掉（玩家管理里可清空进度）。`;
}
</script>

<style scoped>
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
}
</style>
