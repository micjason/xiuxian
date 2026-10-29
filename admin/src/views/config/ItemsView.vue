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
import { latestFrom, useRevisions } from "../../composables/revisions";
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
const rev = useRevisions("item");
function effectFromRow(row: Record<string, unknown>): Record<string, unknown> {
  const effect = (row.effect ?? null) as { buffStat?: string; buffBp?: number; durationSeconds?: number; cultivationGain?: number } | null;
  return {
    ...row,
    effectBuffStat: effect?.buffStat ?? "",
    effectBuffBp: effect?.buffBp ?? null,
    effectDurationSeconds: effect?.durationSeconds ?? null,
    effectCultivationGain: effect?.cultivationGain ?? null,
  };
}

function effectPayload(values: Record<string, unknown>) {
  const buffStat = String(values.effectBuffStat ?? "").trim();
  const buffBp = values.effectBuffBp == null || values.effectBuffBp === "" ? null : Number(values.effectBuffBp);
  const durationSeconds = values.effectDurationSeconds == null || values.effectDurationSeconds === "" ? null : Number(values.effectDurationSeconds);
  const cultivationGain = values.effectCultivationGain == null || values.effectCultivationGain === "" ? null : Number(values.effectCultivationGain);
  if (!buffStat && cultivationGain == null) return null;
  const effect: Record<string, unknown> = {};
  if (buffStat) {
    effect.buffStat = buffStat;
    effect.buffBp = buffBp ?? 1000;
    effect.durationSeconds = durationSeconds ?? 300;
  }
  if (cultivationGain != null && cultivationGain > 0) effect.cultivationGain = cultivationGain;
  return Object.keys(effect).length ? effect : null;
}

const { rows, loading, error, reload } = useList(async () => {
  await rev.load();
  const list = await api<Record<string, unknown>[]>("/admin/draft/items");
  return list.map(effectFromRow);
});

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body = JSON.stringify({
    displayName: values.displayName,
    description: values.description,
    kind: values.kind || undefined,
    quality: values.quality || undefined,
    stackable: values.stackable,
    iconKey: values.iconKey ?? "",
    effect: effectPayload(values),
  });
  if (mode === "create") {
    await api("/admin/draft/items", { method: "POST", body });
  } else {
    await api(`/admin/draft/items/${editingId}`, { method: "PUT", body, guard: { revisions: rev, id: editingId, reload, latest: () => latestFrom("/admin/draft/items", "id", editingId), title: `物品「${String(values.displayName)}」` } });
  }
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/items/${String(row.id)}`, { method: "DELETE" });
}
</script>
