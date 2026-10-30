<template>
  <div class="drop-tables-page">
    <PageHeader title="掉落表" desc="维护 content_drop_tables / content_drop_entries。关卡的首领掉落、挂机掉落、首通掉落引用这里的表。保存后立即生效。">
      <template #actions>
        <el-button @click="reload">重新读取</el-button>
        <el-button type="primary" @click="openCreate">＋ 新建掉落表</el-button>
      </template>
    </PageHeader>
    <DataState :loading="loading" :error="error" :has-data="rows.length > 0" empty-text="还没有掉落表" @retry="reload">
      <el-table :data="rows" class="grid" row-key="id" @row-click="openEdit">
        <el-table-column label="名称" min-width="180">
          <template #default="{ row }">
            <div class="name">{{ row.displayName }}</div>
            <div class="sub">{{ row.id }}</div>
          </template>
        </el-table-column>
        <el-table-column label="条目" width="90" align="right">
          <template #default="{ row }">{{ row.entries.length }}</template>
        </el-table-column>
        <el-table-column label="引用关卡" min-width="320">
          <template #default="{ row }">
            <span v-if="!row.stageRefs.length" class="muted">无引用</span>
            <span v-for="ref in row.stageRefs" :key="ref.stageId" class="stage-chip">
              {{ ref.displayName }}
              <CustomTag v-for="role in ref.roles" :key="role" kind="default">{{ roleLabel(role) }}</CustomTag>
            </span>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="120" align="right" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click.stop="openEdit(row)">编辑</el-button>
            <el-button link type="danger" @click.stop="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </DataState>

    <EditDrawer
      v-model="drawer"
      :title="mode === 'create' ? '新建掉落表' : `编辑掉落表：${original?.displayName ?? ''}`"
      :subtitle="mode === 'edit' ? original?.id : ''"
      :dirty="dirty"
      :saving="saving"
      :size="820"
      @save="save"
    >
      <SectionCard title="基础信息">
        <div class="rows">
          <FormRow v-if="mode === 'create'" label="编号" required help="小写字母开头，字母数字下划线；创建后不能改。关卡用它引用这张表。">
            <el-input v-model="form.id" style="width: 320px" placeholder="例如 proto_boss" />
          </FormRow>
          <FormRow v-else label="编号"><span class="mono">{{ form.id }}</span></FormRow>
          <FormRow label="名称" required><el-input v-model="form.displayName" style="width: 320px" maxlength="40" show-word-limit /></FormRow>
        </div>
      </SectionCard>
      <SectionCard title="掉落条目" desc="每条：物品 + 概率（万分比）+ 数量区间。保存后立即生效。">
        <div v-if="form.entries.length === 0" class="empty">
          <span class="muted">还没有条目</span>
          <el-button type="primary" plain size="small" @click="addEntry">＋ 添加条目</el-button>
        </div>
        <template v-else>
          <el-table :data="form.entries" size="small" class="entries">
            <el-table-column label="物品" min-width="260">
              <template #default="{ row }">
                <el-select v-model="row.itemSlug" filterable class="w240" placeholder="搜索物品">
                  <el-option
                    v-for="item in items"
                    :key="item.id"
                    :label="item.displayName"
                    :value="item.id"
                    :disabled="used(item.id, row)"
                  >
                    <span>{{ item.displayName }} <span class="muted small">{{ item.id }}</span></span>
                  </el-option>
                </el-select>
              </template>
            </el-table-column>
            <el-table-column width="160">
              <template #header>概率<HelpTip title="概率" text="万分比：10000 = 100%。每次掷骰独立判定。" /></template>
              <template #default="{ row }">
                <NumInput v-model="row.chancePercent" :width="120" unit="%" :precision="2" :min="0" :max="100" />
              </template>
            </el-table-column>
            <el-table-column label="最少" width="120">
              <template #default="{ row }"><NumInput v-model="row.minQty" :width="88" unit="个" :precision="0" :min="1" :max="999" /></template>
            </el-table-column>
            <el-table-column label="最多" width="120">
              <template #default="{ row }"><NumInput v-model="row.maxQty" :width="88" unit="个" :precision="0" :min="row.minQty || 1" :max="999" /></template>
            </el-table-column>
            <el-table-column width="70">
              <template #default="{ $index }"><el-button link type="danger" @click="form.entries.splice($index, 1)">删除</el-button></template>
            </el-table-column>
          </el-table>
          <el-button class="add" size="small" :disabled="form.entries.length >= 50" @click="addEntry">＋ 添加条目</el-button>
        </template>
      </SectionCard>
      <SectionCard v-if="mode === 'edit' && original?.stageRefs.length" title="引用关卡" desc="这些关卡的首领 / 挂机 / 首通掉落指向本表。">
        <div class="ref-list">
          <div v-for="ref in original.stageRefs" :key="ref.stageId" class="ref-line">
            <span class="ref-name">{{ ref.displayName }}</span>
            <span class="sub">{{ ref.stageId }}</span>
            <CustomTag v-for="role in ref.roles" :key="role" kind="default">{{ roleLabel(role) }}</CustomTag>
          </div>
        </div>
      </SectionCard>
    </EditDrawer>
  </div>
</template>

<script setup lang="ts">
import { latestFrom, useRevisions } from "../../composables/revisions";
import { isConflictAbort } from "../../composables/conflict";
import { ElMessage, ElMessageBox } from "element-plus";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import CustomTag from "../../components/CustomTag.vue";
import DataState from "../../components/DataState.vue";
import EditDrawer from "../../components/EditDrawer.vue";
import FormRow from "../../components/FormRow.vue";
import HelpTip from "../../components/HelpTip.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SectionCard from "../../components/SectionCard.vue";
import { refreshDraftStatus } from "../../composables/draftStatus";

type Role = "boss" | "idle" | "firstClear";
type StageRef = { stageId: string; displayName: string; roles: Role[] };
type EntryApi = { itemSlug: string; itemName?: string; chanceBp: number; minQty: number; maxQty: number };
type DropTableRow = { id: string; displayName: string; entries: EntryApi[]; stageRefs: StageRef[] };
type EntryForm = { itemSlug: string; chancePercent: number | null; minQty: number | null; maxQty: number | null };
type Form = { id: string; displayName: string; entries: EntryForm[] };

const loading = ref(false);
const saving = ref(false);
const error = ref("");
const rows = ref<DropTableRow[]>([]);
const items = ref<{ id: string; displayName: string }[]>([]);
const drawer = ref(false);
const mode = ref<"create" | "edit">("edit");
const original = ref<DropTableRow | null>(null);
const form = ref<Form>(blank());
const baseline = ref("");
const dirty = computed(() => JSON.stringify(form.value) !== baseline.value);
const rev = useRevisions("dropTable");

function blank(): Form {
  return { id: "", displayName: "", entries: [] };
}

function roleLabel(role: Role): string {
  return role === "boss" ? "首领" : role === "idle" ? "挂机" : "首通";
}

function toFormEntries(entries: EntryApi[]): EntryForm[] {
  return entries.map((entry) => ({
    itemSlug: entry.itemSlug,
    chancePercent: entry.chanceBp / 100,
    minQty: entry.minQty,
    maxQty: entry.maxQty,
  }));
}

function addEntry(): void {
  form.value.entries.push({ itemSlug: "", chancePercent: 50, minQty: 1, maxQty: 1 });
}

function used(id: string, row: EntryForm): boolean {
  return id !== row.itemSlug && form.value.entries.some((other) => other !== row && other.itemSlug === id);
}

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    await rev.load();
    const [tables, itemList] = await Promise.all([
      api<DropTableRow[]>("/admin/draft/drop-tables"),
      api<{ id: string; displayName: string }[]>("/admin/draft/items"),
    ]);
    rows.value = tables;
    items.value = itemList;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

async function reopen(id: string): Promise<void> {
  await reload();
  const hit = rows.value.find((row) => row.id === id);
  if (hit) openEdit(hit);
  else drawer.value = false;
}

function openCreate(): void {
  mode.value = "create";
  original.value = null;
  form.value = blank();
  baseline.value = JSON.stringify(form.value);
  drawer.value = true;
}

function openEdit(row: DropTableRow): void {
  mode.value = "edit";
  original.value = row;
  form.value = { id: row.id, displayName: row.displayName, entries: toFormEntries(row.entries) };
  baseline.value = JSON.stringify(form.value);
  drawer.value = true;
}

function payloadEntries(): { itemSlug: string; chanceBp: number; minQty: number; maxQty: number }[] {
  const out: { itemSlug: string; chanceBp: number; minQty: number; maxQty: number }[] = [];
  for (const row of form.value.entries) {
    if (!row.itemSlug) throw new Error("请选择掉落物品");
    const chanceBp = Math.round((Number(row.chancePercent) || 0) * 100);
    const minQty = Math.trunc(Number(row.minQty) || 0);
    const maxQty = Math.trunc(Number(row.maxQty) || 0);
    if (chanceBp < 0 || chanceBp > 10000) throw new Error("概率必须在 0% 到 100%");
    if (minQty < 1 || maxQty < minQty) throw new Error("数量区间不正确");
    out.push({ itemSlug: row.itemSlug, chanceBp, minQty, maxQty });
  }
  return out;
}

async function save(): Promise<void> {
  if (!form.value.displayName.trim()) {
    ElMessage.error("请填写名称");
    return;
  }
  if (mode.value === "create" && !/^[a-z][a-z0-9_]{1,47}$/.test(form.value.id.trim())) {
    ElMessage.error("编号不正确（小写字母开头，字母数字下划线）");
    return;
  }
  saving.value = true;
  try {
    const body = JSON.stringify({
      slug: form.value.id.trim(),
      displayName: form.value.displayName.trim(),
      entries: payloadEntries(),
    });
    if (mode.value === "create") {
      await api("/admin/draft/drop-tables", { method: "POST", body });
    } else {
      const id = form.value.id;
      await api(`/admin/draft/drop-tables/${encodeURIComponent(id)}`, {
        method: "PUT",
        body,
        guard: {
          revisions: rev,
          id,
          reload: () => reopen(id),
          latest: () => latestFrom("/admin/draft/drop-tables", "id", id),
          title: `掉落表「${form.value.displayName}」`,
        },
      });
    }
    baseline.value = JSON.stringify(form.value);
    drawer.value = false;
    ElMessage.success("已保存，已生效");
    void refreshDraftStatus();
    await reload();
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
      return;
    }
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

async function remove(row: DropTableRow): Promise<void> {
  const hint = row.stageRefs.length
    ? `「${row.displayName}」正被 ${row.stageRefs.length} 个关卡引用，通常删不掉；确认仍要尝试？`
    : `删除掉落表「${row.displayName}」？`;
  try {
    await ElMessageBox.confirm(hint, "删除掉落表", { type: "warning", confirmButtonText: "删除" });
  } catch {
    return;
  }
  try {
    await api(`/admin/draft/drop-tables/${encodeURIComponent(row.id)}`, { method: "DELETE" });
    ElMessage.success("已删除");
    void refreshDraftStatus();
    await reload();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "删除失败");
  }
}

useRefetchOnActivate(reload);
onMounted(reload);
</script>

<style scoped>
.rows {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.name {
  font-weight: 600;
}
.sub {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.muted {
  color: var(--el-text-color-secondary);
}
.small {
  font-size: 12px;
}
.mono {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
}
.stage-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin: 0 8px 4px 0;
}
.empty {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 8px 0;
}
.entries {
  width: 100%;
}
.add {
  margin-top: 8px;
}
.w240 {
  width: 240px;
}
.ref-list {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.ref-line {
  display: flex;
  align-items: center;
  gap: 8px;
}
.ref-name {
  font-weight: 500;
}
</style>
