<template>
  <div>
    <PageHeader title="弹窗" desc="弹窗类型由客户端定义，这里只能调优先级和开关，不能新增或删除类型。" />
    <ConfigListPage
      :schema="schema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="slug"
      entity-name="弹窗类型"
      :search-keys="['slug', 'template']"
      :columns="columns"
      :save-fn="save"
      :refresh-draft="false"
      export-name="弹窗"
      @reload="reload"
    />
  </div>
</template>

<script setup lang="ts">
import { latestFrom, useRevisions } from "../../composables/revisions";
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import PageHeader from "../../components/PageHeader.vue";
import { useList } from "../../composables/useList";
import { popupSchema } from "../../schema/resources";
import type { Schema } from "../../schema/types";

const schema: Schema = {
  ...popupSchema,
  fields: [
    { key: "slug", label: "类型", kind: "text", readonly: true, hint: "弹窗类型编号，由客户端定义。" },
    { key: "template", label: "模板", kind: "text", readonly: true, hint: "客户端使用的弹窗模板。" },
    ...popupSchema.fields,
  ],
};
const columns = [
  { key: "slug", label: "类型", minWidth: 160 },
  { key: "template", label: "模板", minWidth: 160 },
  { key: "priority", label: "优先级", width: 100, kind: "int" },
  { key: "enabled", label: "启用", width: 90, kind: "bool" },
];
const rev = useRevisions("popupType");
const { rows, loading, error, reload } = useList(async () => {
  await rev.load();
  return api<Record<string, unknown>[]>("/admin/popup-types");
});

async function save(values: Record<string, unknown>): Promise<void> {
  await api(`/admin/popup-types/${String(values.slug)}`, {
    method: "PUT",
    body: JSON.stringify({ priority: values.priority, enabled: values.enabled }),
    guard: { revisions: rev, id: String(values.slug), reload, latest: () => latestFrom("/admin/popup-types", "slug", String(values.slug)), title: `弹窗类型「${String(values.slug)}」` },
  });
}
</script>
