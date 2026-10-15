<template>
  <div class="change-list">
    <div class="totals">
      <el-tag type="success" effect="light">新增 {{ diff.added }}</el-tag>
      <el-tag type="warning" effect="light">修改 {{ diff.changed }}</el-tag>
      <el-tag type="danger" effect="light">删除 {{ diff.removed }}</el-tag>
      <span class="muted">共 {{ diff.total }} 项</span>
    </div>
    <el-empty v-if="diff.total === 0" :description="emptyText ?? '没有改动'" :image-size="72" />
    <el-collapse v-else v-model="openGroups">
      <el-collapse-item v-for="group in groups" :key="group.kind" :name="group.kind">
        <template #title>
          <strong>{{ group.title }}</strong>
          <span class="count">{{ group.rows.length }} 项</span>
        </template>
        <ul class="rows">
          <li v-for="row in group.rows" :key="row.slug + row.type">
            <div class="line">
              <el-tag :type="tagType[row.type]" size="small" effect="light">{{ typeText[row.type] }}</el-tag>
              <span class="name">{{ row.name }}</span>
              <code v-if="row.name !== row.slug" class="slug">{{ row.slug }}</code>
            </div>
            <ul v-if="row.fields.length > 0" class="fields">
              <li v-for="field in row.fields" :key="field.field">
                <span class="f">{{ fieldLabel(field.field) }}</span>
                <span class="before">{{ show(field.before) }}</span>
                <span class="arrow">→</span>
                <span class="after">{{ show(field.after) }}</span>
              </li>
            </ul>
          </li>
        </ul>
      </el-collapse-item>
    </el-collapse>
  </div>
</template>

<script setup lang="ts">
import { computed, ref } from "vue";
import type { DiffResult, SnapshotChange } from "../composables/draftStatus";
import { fieldLabel } from "../schema/resources";

const props = defineProps<{ diff: DiffResult; emptyText?: string }>();

const kindTitle: Record<string, string> = { realm: "境界", stage: "关卡与首领", item: "物品与装备", skill: "技能", dropTable: "掉落表", globals: "全局参数" };
const typeText = { added: "新增", removed: "删除", changed: "修改" } as const;
const tagType = { added: "success", removed: "danger", changed: "warning" } as const;

const groups = computed(() =>
  Object.keys(kindTitle)
    .map((kind) => ({ kind, title: kindTitle[kind], rows: props.diff.changes.filter((row: SnapshotChange) => row.kind === kind) }))
    .filter((group) => group.rows.length > 0),
);
const openGroups = ref<string[]>([]);
openGroups.value = groups.value.slice(0, 2).map((group) => group.kind);

function show(value: unknown): string {
  if (value === null || value === undefined || value === "") return "（空）";
  if (typeof value === "boolean") return value ? "是" : "否";
  if (typeof value === "object") {
    const text = JSON.stringify(value);
    return text.length > 90 ? `${text.slice(0, 90)}…` : text;
  }
  return String(value);
}
</script>

<style scoped>
.totals {
  display: flex;
  align-items: center;
  gap: var(--xx-space-2);
  margin-bottom: var(--xx-space-3);
}
.muted,
.count {
  margin-left: var(--xx-space-2);
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.rows {
  margin: 0;
  padding: 0;
  list-style: none;
}
.rows > li {
  padding: var(--xx-space-2) 0;
  border-bottom: 1px dashed var(--xx-border);
}
.line {
  display: flex;
  align-items: center;
  gap: var(--xx-space-2);
}
.name {
  font-weight: 600;
}
.slug {
  color: var(--xx-text-placeholder);
  font-size: var(--xx-fs-xs);
}
.fields {
  margin: 4px 0 0 56px;
  padding: 0;
  list-style: none;
  font-size: var(--xx-fs-sm);
}
.fields li {
  display: flex;
  gap: var(--xx-space-2);
}
.f {
  min-width: 120px;
  color: var(--xx-text-secondary);
}
.before {
  color: var(--xx-danger);
  text-decoration: line-through;
  text-decoration-color: color-mix(in srgb, var(--xx-danger) 40%, transparent);
}
.after {
  color: var(--xx-success);
  font-weight: 600;
}
.arrow {
  color: var(--xx-text-placeholder);
}
</style>
