<template>
  <div>
    <PageHeader title="物品" desc="突破石等材料、丹药：名称、类型、品质、能否叠加、描述。装备在「装备配置」里看和改（名称、掉率倍数），功法书随功法自动生成。">
      <template #actions>
        <el-button @click="router.push('/config/gear')">去装备配置 ›</el-button>
      </template>
    </PageHeader>
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
      :new-row="() => ({ displayName: '', kind: 'material', quality: 'white', stackable: true, description: '' })"
      :save-fn="save"
      :remove-fn="remove"
      :drawer-size="560"
      :options-map="{ iconKey: iconOptions }"
      export-name="物品"
      @reload="reload"
    />
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { useRouter } from "vue-router";
import { useItemIcons } from "../../composables/itemIcons";
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import PageHeader from "../../components/PageHeader.vue";
import { useList } from "../../composables/useList";
import { itemSchema } from "../../schema/resources";

const router = useRouter();
const icons = useItemIcons();
// 材料、丹药、功法书的图（装备图在「装备配置」里选）
const iconOptions = computed(() => [{ label: "自动（按编号）", value: "" }, ...icons.value.filter((icon) => !icon.key.startsWith("gear_") && !icon.key.startsWith("eq_")).map((icon) => ({ label: icon.key, value: icon.key }))]);
const { rows, loading, error, reload } = useList(() => api<Record<string, unknown>[]>("/admin/draft/items"));

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body = JSON.stringify({ displayName: values.displayName, description: values.description, kind: values.kind || undefined, quality: values.quality || undefined, stackable: values.stackable, iconKey: values.iconKey ?? "" });
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
