<template>
  <div>
    <PageHeader title="洞府建筑（已停用）" desc="旧版劳作加成建筑表已废弃。洞府 v1 请到「洞府」页配置药园与炼丹。" />
    <el-alert type="warning" :closable="false" show-icon class="banner" title="本页已停用">
      洞府 v1 配置在「游戏配置 → 洞府」（globals.dongfu）。
      <el-button link type="primary" @click="$router.push('/config/dongfu')">去洞府配置 ›</el-button>
    </el-alert>
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

<style scoped>
.banner {
  margin-bottom: 16px;
}
</style>
