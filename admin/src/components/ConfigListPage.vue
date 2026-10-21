<template>
  <div class="list-page">
    <div class="filter-bar">
      <el-input v-model="query" class="search" clearable :placeholder="searchPlaceholder ?? `搜索${entityName}`" :prefix-icon="Search" />
      <el-select
        v-for="filter in filters ?? []"
        :key="filter.key"
        v-model="filterValues[filter.key]"
        clearable
        :placeholder="filter.label"
        class="filter"
      >
        <el-option v-for="option in filter.options" :key="option.value" :label="option.label" :value="option.value" />
      </el-select>
      <el-button v-if="filtering" link type="primary" @click="clearFilters">清除筛选</el-button>
      <span class="count">共 {{ rows.length }} 条<template v-if="filtering">，筛选出 {{ filtered.length }} 条</template></span>
      <span class="spacer" />
      <slot name="toolbar" />
      <el-button :disabled="filtered.length === 0" @click="exportCsv(filtered)">导出 CSV</el-button>
      <el-button v-if="creatable" type="primary" @click="openCreate">新建{{ entityName }}</el-button>
    </div>

    <transition name="fade">
      <div v-if="selection.length > 0" class="bulk-bar" role="status">
        <span>已选 <strong>{{ selection.length }}</strong> 项</span>
        <el-button size="small" @click="exportCsv(selection)">导出所选</el-button>
        <slot name="bulk" :selection="selection" />
        <el-button v-if="deletable" size="small" type="danger" plain @click="bulkRemove">批量删除</el-button>
        <el-button size="small" link @click="table?.clearSelection()">取消选择</el-button>
      </div>
    </transition>

    <DataState :loading="loading" :error="error" :has-data="rows.length > 0" :empty-text="`还没有${entityName}`" @retry="$emit('reload')">
      <template #empty-action>
        <el-button v-if="creatable" type="primary" @click="openCreate">新建{{ entityName }}</el-button>
      </template>
      <el-table
        ref="table"
        v-loading="loading"
        :data="pageRows"
        :row-key="idKey"
        :row-class-name="({ row }: { row: Row }) => (drawer && String(row[idKey]) === editingId ? 'editing-row' : '')"
        class="grid"
        :span-method="spanKey ? spanOf : undefined"
        @selection-change="(value: Row[]) => (selection = value)"
        @row-click="(row: Row, column: { type?: string; property?: string }) => column.type !== 'selection' && column.property !== '__actions' && openEdit(row)"
        @sort-change="onSort"
      >
        <el-table-column v-if="selectable" type="selection" width="44" :reserve-selection="false" />
        <el-table-column
          v-for="column in cols"
          :key="column.key"
          :prop="column.key"
          :label="column.label"
          :width="column.width"
          :min-width="column.minWidth"
          :sortable="column.sortable ? 'custom' : false"
          show-overflow-tooltip
        >
          <template #default="{ row }">
            <slot :name="`cell-${column.key}`" :row="row" :value="row[column.key]">
              <template v-if="column.kind === 'bool'">
                <el-tag :type="row[column.key] ? 'success' : 'info'" effect="light" size="small">{{ row[column.key] ? "启用" : "停用" }}</el-tag>
              </template>
              <template v-else-if="column.kind === 'select'">{{ optionLabel(column.key, row[column.key]) }}</template>
              <span v-else-if="row[column.key] === null || row[column.key] === undefined || row[column.key] === ''" class="muted">—</span>
              <template v-else>{{ row[column.key] }}</template>
            </slot>
          </template>
        </el-table-column>
        <slot name="extra-columns" />
        <el-table-column label="操作" prop="__actions" fixed="right" :width="actionWidth" align="right">
          <template #default="{ row }">
            <slot name="row-actions" :row="row" />
            <el-button link type="primary" @click.stop="openEdit(row)">编辑</el-button>
            <el-button v-if="cloneable" link type="primary" @click.stop="openClone(row)">复制</el-button>
            <el-button v-if="deletable" link type="danger" @click.stop="remove(row)">删除</el-button>
          </template>
        </el-table-column>
        <template #empty>
          <el-empty :description="`没有符合条件的${entityName}`">
            <el-button type="primary" link @click="clearFilters">清除筛选</el-button>
          </el-empty>
        </template>
      </el-table>
      <el-pagination
        v-if="filtered.length > pageSize"
        v-model:current-page="page"
        class="pager"
        layout="total, prev, pager, next"
        :page-size="pageSize"
        :total="filtered.length"
        background
      />
    </DataState>

    <EditDrawer
      v-model="drawer"
      :title="drawerTitle"
      :subtitle="drawerSubtitle ? drawerSubtitle(form) : undefined"
      :dirty="dirty || mode === 'create'"
      :change-count="changeCount"
      :error-count="showAllErrors ? Object.keys(errors).length : 0"
      :saving="saving"
      :size="drawerSize"
      @save="save"
    >
      <slot name="form" :form="form" :errors="errors" :mode="mode" :show-all-errors="showAllErrors" :original="originalValues">
        <SchemaForm
          ref="schemaForm"
          v-model="form"
          :schema="schema"
          :original="mode === 'edit' ? originalValues : undefined"
          :mode="mode"
          :show-all-errors="showAllErrors"
          :options-map="optionsMap"
          :hidden-keys="[idKey, ...(hiddenKeys ?? [])]"
        />
      </slot>
      <template #footer-left>
        <slot name="drawer-footer-left" :form="form" :mode="mode" />
      </template>
    </EditDrawer>
  </div>
</template>

<script setup lang="ts">
import { Search } from "@element-plus/icons-vue";
import { ElMessage } from "element-plus";
import { computed, nextTick, onBeforeUnmount, reactive, ref, watch } from "vue";
import { isConflictAbort } from "../composables/conflict";
import { useRoute, useRouter } from "vue-router";
import { confirmAction, confirmDanger } from "../composables/confirm";
import { useCrumbTail } from "../composables/crumbs";
import { refreshDraftStatus } from "../composables/draftStatus";
import { downloadText, toCsv } from "../composables/format";
import type { FieldOption, FormValues, Schema } from "../schema/types";
import { validateSchema } from "../schema/validate";
import DataState from "./DataState.vue";
import EditDrawer from "./EditDrawer.vue";
import SchemaForm from "./SchemaForm.vue";

type Row = Record<string, unknown>;
type Column = {
  key: string;
  label: string;
  width?: number;
  minWidth?: number;
  sortable?: boolean;
  kind?: string;
};

const props = withDefaults(
  defineProps<{
    schema: Schema;
    rows: Row[];
    loading?: boolean;
    error?: string;
    idKey: string;
    nameKey?: string;
    entityName: string;
    searchKeys: string[];
    searchPlaceholder?: string;
    filters?: { key: string; label: string; options: FieldOption[]; match?: (row: Row, value: string | number) => boolean }[];
    columns?: Column[];
    creatable?: boolean;
    deletable?: boolean;
    cloneable?: boolean;
    selectable?: boolean;
    newRow?: () => Row;
    optionsMap?: Record<string, FieldOption[]>;
    hiddenKeys?: string[];
    saveFn: (values: Row, mode: "create" | "edit", editingId: string) => Promise<void>;
    removeFn?: (row: Row) => Promise<void>;
    /** 删除前要求输入名称确认（对已有玩家数据有影响的内容） */
    dangerDelete?: boolean;
    deleteHint?: (row: Row) => string;
    drawerSize?: string | number;
    pageSize?: number;
    savedMessage?: string;
    /** 保存后是否刷新草稿状态（草稿类数据 true；演示数据 false） */
    refreshDraft?: boolean;
    exportName?: string;
    /** 抽屉标题后的灰色副标题，例如「炼气 · 第 1 关 · 无首领」 */
    drawerSubtitle?: (form: Row) => string;
    /** 抽屉标题，例如「编辑关卡：黑风岭·一」（不传按 entityName + 名称） */
    titleOf?: (form: Row, mode: "create" | "edit") => string;
    /** 按这一列分组：相邻同值的行合并成一格（例如关卡按章节）。只合并这一列，排序后不相邻就不合并。 */
    spanKey?: string;
  }>(),
  { drawerSize: 800, pageSize: 20, savedMessage: "已保存到草稿", refreshDraft: true, exportName: "export" },
);
const emit = defineEmits<{ reload: [] }>();

const route = useRoute();
const router = useRouter();
const setCrumbTail = useCrumbTail();
const table = ref<{ clearSelection: () => void } | null>(null);
const schemaForm = ref<{ touchAll: () => void } | null>(null);

const query = ref(typeof route.query.q === "string" ? route.query.q : "");
const filterValues = reactive<Record<string, string | number | undefined>>({});
const selection = ref<Row[]>([]);
const page = ref(1);
const sortState = ref<{ prop: string; order: string } | null>(null);

const drawer = ref(false);
const mode = ref<"create" | "edit">("edit");
const editingId = ref("");
const form = ref<FormValues>({});
const original = ref("");
const originalValues = ref<FormValues>({});
const saving = ref(false);
const showAllErrors = ref(false);

const cols = computed<Column[]>(
  () =>
    props.columns ??
    props.schema.fields
      .filter((field) => field.column)
      .map((field) => {
        const spec = typeof field.column === "object" ? field.column : {};
        return { key: field.key, label: field.label, width: spec.width, minWidth: spec.minWidth, kind: field.kind, sortable: field.kind === "number" || field.kind === "int" };
      }),
);
const actionWidth = computed(() => 90 + (props.cloneable ? 44 : 0) + (props.deletable ? 44 : 0));

const filtering = computed(() => query.value.trim() !== "" || Object.values(filterValues).some((value) => value !== undefined && value !== ""));

const filtered = computed(() => {
  const text = query.value.trim().toLowerCase();
  let list = props.rows.filter((row) => {
    if (text && !props.searchKeys.some((key) => String(row[key] ?? "").toLowerCase().includes(text))) {
      return false;
    }
    for (const filter of props.filters ?? []) {
      const value = filterValues[filter.key];
      if (value === undefined || value === "") {
        continue;
      }
      if (filter.match ? !filter.match(row, value) : row[filter.key] !== value) {
        return false;
      }
    }
    return true;
  });
  if (sortState.value && sortState.value.order) {
    const { prop, order } = sortState.value;
    const sign = order === "ascending" ? 1 : -1;
    list = [...list].sort((left, right) => {
      const a = left[prop] as number | string;
      const b = right[prop] as number | string;
      return a === b ? 0 : (a ?? 0) > (b ?? 0) ? sign : -sign;
    });
  }
  return list;
});

const pageRows = computed(() => filtered.value.slice((page.value - 1) * props.pageSize, page.value * props.pageSize));

function spanOf({ row, column, rowIndex }: { row: Row; column: { property?: string }; rowIndex: number }): { rowspan: number; colspan: number } {
  if (!props.spanKey || column.property !== props.spanKey) return { rowspan: 1, colspan: 1 };
  const list = pageRows.value;
  if (rowIndex > 0 && list[rowIndex - 1]?.[props.spanKey] === row[props.spanKey]) return { rowspan: 0, colspan: 0 };
  let span = 1;
  while (list[rowIndex + span]?.[props.spanKey] === row[props.spanKey]) span += 1;
  return { rowspan: span, colspan: 1 };
}
watch([query, filterValues, () => props.rows], () => {
  page.value = 1;
});

const errors = computed(() => validateSchema(props.schema, form.value, props.optionsMap));
const dirty = computed(() => JSON.stringify(form.value) !== original.value);
/** 和打开时相比改了几处（按顶层字段 + 列表里每一行算） */
const changeCount = computed(() => {
  if (!dirty.value) return 0;
  const before = JSON.parse(original.value || "{}") as Row;
  let count = 0;
  for (const key of new Set([...Object.keys(before), ...Object.keys(form.value)])) {
    const left = before[key];
    const right = form.value[key];
    if (Array.isArray(left) && Array.isArray(right)) {
      const length = Math.max(left.length, right.length);
      for (let index = 0; index < length; index += 1) {
        if (JSON.stringify(left[index]) !== JSON.stringify(right[index])) count += 1;
      }
    } else if (left && right && typeof left === "object" && typeof right === "object") {
      for (const sub of new Set([...Object.keys(left as Row), ...Object.keys(right as Row)])) {
        if (JSON.stringify((left as Row)[sub]) !== JSON.stringify((right as Row)[sub])) count += 1;
      }
    } else if (JSON.stringify(left) !== JSON.stringify(right)) {
      count += 1;
    }
  }
  return count;
});
const drawerTitle = computed(() => {
  if (props.titleOf) {
    return props.titleOf(form.value, mode.value);
  }
  const name = String(form.value[props.nameKey ?? "displayName"] ?? "");
  return mode.value === "create" ? `新建${props.entityName}` : `编辑${props.entityName}：${name || "未命名"}`;
});

watch(drawer, (open) => {
  setCrumbTail(open ? drawerTitle.value : null);
  if (!open) {
    showAllErrors.value = false;
  }
});
onBeforeUnmount(() => setCrumbTail(null));

function onSort(sort: { prop: string; order: string }): void {
  sortState.value = sort.order ? sort : null;
}

function optionLabel(key: string, value: unknown): string {
  const field = props.schema.fields.find((item) => item.key === key);
  const options = props.optionsMap?.[key] ?? field?.options ?? [];
  return options.find((option) => option.value === value)?.label ?? String(value ?? "—");
}

function clearFilters(): void {
  query.value = "";
  for (const key of Object.keys(filterValues)) {
    filterValues[key] = undefined;
  }
}

function load(row: Row, asMode: "create" | "edit"): void {
  mode.value = asMode;
  form.value = JSON.parse(JSON.stringify(row)) as FormValues;
  original.value = JSON.stringify(form.value);
  originalValues.value = JSON.parse(original.value) as FormValues;
  showAllErrors.value = false;
  drawer.value = true;
}

function openCreate(): void {
  editingId.value = "";
  load(props.newRow ? props.newRow() : {}, "create");
}

function openEdit(row: Row): void {
  editingId.value = String(row[props.idKey]);
  load(row, "edit");
}

function openClone(row: Row): void {
  editingId.value = "";
  const copy = props.newRow ? { ...props.newRow(), ...row } : { ...row };
  const base = props.newRow ? props.newRow() : {};
  // 复制：编号/标识用新建默认值，名称加「副本」
  for (const key of [props.idKey, ...(props.hiddenKeys ?? [])]) {
    if (key in base) {
      copy[key] = base[key];
    }
  }
  const nameKey = props.nameKey ?? "displayName";
  if (typeof copy[nameKey] === "string" && copy[nameKey]) {
    copy[nameKey] = `${copy[nameKey] as string} 副本`;
  }
  load(copy, "create");
}

async function save(): Promise<void> {
  const problems = errors.value;
  if (Object.keys(problems).length > 0) {
    showAllErrors.value = true;
    schemaForm.value?.touchAll();
    ElMessage.warning(Object.values(problems)[0]);
    return;
  }
  saving.value = true;
  try {
    await props.saveFn(form.value, mode.value, editingId.value);
    ElMessage.success(props.savedMessage);
    original.value = JSON.stringify(form.value);
    drawer.value = false;
    emit("reload");
    if (props.refreshDraft) {
      void refreshDraftStatus();
    }
  } catch (cause) {
    if (isConflictAbort(cause)) {
      // 旧表单覆盖保护：选了「重新读取」→ 用最新内容重新打开这一条；「取消」→ 表单留着不动
      if (cause.action === "reload") {
        await nextTick();
        const hit = props.rows.find((row) => String(row[props.idKey]) === editingId.value);
        if (hit && mode.value === "edit") {
          openEdit(hit);
        } else {
          drawer.value = false;
        }
        ElMessage.info(cause.message);
      }
      return;
    }
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

async function remove(row: Row): Promise<void> {
  if (!props.removeFn) {
    return;
  }
  const name = String(row[props.nameKey ?? "displayName"] ?? row[props.idKey]);
  const message = props.deleteHint ? props.deleteHint(row) : `删除${props.entityName}「${name}」？删除后需要重新创建才能恢复。`;
  const ok = props.dangerDelete
    ? await confirmDanger({ title: `删除${props.entityName}`, message, typeText: name })
    : await confirmAction(message, `删除${props.entityName}`, "删除");
  if (!ok) {
    return;
  }
  try {
    await props.removeFn(row);
    ElMessage.success("已删除");
    emit("reload");
    if (props.refreshDraft) {
      void refreshDraftStatus();
    }
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "删除失败");
  }
}

async function bulkRemove(): Promise<void> {
  if (!props.removeFn || selection.value.length === 0) {
    return;
  }
  const count = selection.value.length;
  const names = selection.value.slice(0, 5).map((row) => String(row[props.nameKey ?? "displayName"] ?? row[props.idKey]));
  const ok = await confirmDanger({
    title: `批量删除${props.entityName}`,
    message: `将删除 ${count} 个${props.entityName}：${names.join("、")}${count > 5 ? " 等" : ""}。`,
    typeText: `删除${count}项`,
  });
  if (!ok) {
    return;
  }
  let failed = 0;
  for (const row of selection.value) {
    try {
      await props.removeFn(row);
    } catch {
      failed += 1;
    }
  }
  if (failed > 0) {
    ElMessage.warning(`已删除 ${count - failed} 项，${failed} 项删除失败`);
  } else {
    ElMessage.success(`已删除 ${count} 项`);
  }
  emit("reload");
  if (props.refreshDraft) {
    void refreshDraftStatus();
  }
}

function exportCsv(list: Row[]): void {
  const columns = cols.value.map((column) => ({ key: column.key, label: column.label }));
  downloadText(`${props.exportName}.csv`, toCsv(list, columns));
}

// 从全局搜索、体检待办、配置概览「编辑」跳转过来：?open=<id> 直接打开编辑抽屉。
// 页面被 <keep-alive> 缓存，别的页签的 ?open= 也会触发这里，所以只认自己这一页的路径。
const ownPath = route.path;
watch(
  () => [props.rows, route.query.open, route.path] as const,
  ([rows, open, path]) => {
    if (path !== ownPath || typeof open !== "string" || rows.length === 0) {
      return;
    }
    const hit = rows.find((row) => String(row[props.idKey]) === open);
    if (hit) {
      openEdit(hit);
    }
    const rest = { ...route.query };
    delete rest.open;
    void router.replace({ query: rest });
  },
  { immediate: true },
);

defineExpose({ openCreate, openEdit });
</script>

<style scoped>
.filter-bar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xx-space-2) var(--xx-space-3);
  margin-bottom: var(--xx-space-3);
  padding: var(--xx-space-3) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-surface);
}
.search {
  width: 260px;
}
.filter {
  width: 150px;
}
.count {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.spacer {
  flex: 1;
}
.bulk-bar {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-3);
  padding: var(--xx-space-2) var(--xx-space-4);
  border: 1px solid var(--xx-jade-500);
  border-radius: var(--xx-radius-md);
  background: var(--xx-info-bg);
  font-size: var(--xx-fs-sm);
}
.grid :deep(.el-table__row) {
  cursor: pointer;
}
.grid :deep(.el-table__row.editing-row > td.el-table__cell) {
  background: #eef5f1;
}
.muted {
  color: var(--xx-text-placeholder);
}
.pager {
  justify-content: flex-end;
  margin-top: var(--xx-space-3);
}
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.15s;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
