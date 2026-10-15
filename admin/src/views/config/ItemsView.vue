<template>
  <div>
    <PageHeader title="物品装备" desc="物品只填名称和描述；装备的属性由「装备预算 × 部位占比 × 品质系数」算出，在这里调品质系数并查看全部装备。" />
    <el-tabs v-model="tab" class="tabs" @tab-change="onTab">
      <el-tab-pane label="物品" name="items">
        <ConfigListPage
          :schema="itemSchema"
          :rows="rows"
          :loading="loading"
          :error="error"
          id-key="id"
          entity-name="物品"
          :search-keys="['displayName', 'description']"
          creatable
          deletable
          selectable
          :new-row="() => ({ displayName: '', description: '' })"
          :save-fn="save"
          :remove-fn="remove"
          :drawer-size="560"
          export-name="物品"
          @reload="reload"
        />
      </el-tab-pane>
      <el-tab-pane label="装备与品质系数" name="gear" lazy>
        <GearPanel />
      </el-tab-pane>
    </el-tabs>
  </div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import PageHeader from "../../components/PageHeader.vue";
import { useList } from "../../composables/useList";
import { itemSchema } from "../../schema/resources";
import GearPanel from "./GearPanel.vue";

const route = useRoute();
const router = useRouter();
const tab = ref(route.query.tab === "gear" ? "gear" : "items");
const { rows, loading, error, reload } = useList(() => api<Record<string, unknown>[]>("/admin/draft/items"));

function onTab(name: string | number): void {
  void router.replace({ query: { ...route.query, tab: String(name) } });
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body = JSON.stringify({ displayName: values.displayName, description: values.description });
  if (mode === "create") {
    await api("/admin/draft/items", { method: "POST", body });
  } else {
    await api(`/admin/draft/items/${editingId}`, { method: "PUT", body });
  }
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/items/${String(row.id)}`, { method: "DELETE" });
}
</script>

<style scoped>
.tabs :deep(.el-tabs__header) {
  margin-bottom: var(--xx-space-4);
}
</style>
