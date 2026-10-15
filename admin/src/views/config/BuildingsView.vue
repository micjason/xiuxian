<template>
  <div>
    <PageHeader title="洞府建筑" desc="洞府玩法目前只在旧版（main 分支）里，dev 分支客户端还没有接入。这里保留配置，方便以后迁移时继续使用。" />
    <ConfigListPage
      :schema="buildingSchema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="slug"
      entity-name="建筑"
      :search-keys="['displayName', 'slug']"
      creatable
      :new-row="() => ({ ...defaultsOf(buildingSchema) })"
      :save-fn="save"
      :refresh-draft="false"
      export-name="洞府建筑"
      @reload="reload"
    />
  </div>
</template>

<script setup lang="ts">
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import PageHeader from "../../components/PageHeader.vue";
import { useList } from "../../composables/useList";
import { buildingSchema } from "../../schema/resources";
import { defaultsOf } from "../../schema/validate";

const { rows, loading, error, reload } = useList(() => api<Record<string, unknown>[]>("/admin/content/buildings"));

async function save(values: Record<string, unknown>): Promise<void> {
  const body: Record<string, unknown> = {};
  for (const field of buildingSchema.fields.filter((item) => item.key !== "slug")) {
    body[field.key] = values[field.key];
  }
  await api(`/admin/content/buildings/${String(values.slug)}`, { method: "PUT", body: JSON.stringify(body) });
}
</script>
