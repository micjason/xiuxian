<template>
  <div>
    <el-alert type="info" :closable="false" show-icon class="slot-note" title="6 个核心部位">
      武器、头部、身体、手部（护手）、腿/鞋、饰品。法宝、灵宠为第三期预留，游戏端已按部位配置做成数据驱动，新增部位只需要后端和这里加一行。
    </el-alert>

    <section class="block">
      <header class="block-head">
        <h2>品质系数</h2>
        <div class="actions">
          <el-tag v-if="dirty" type="warning" effect="plain">有未保存的改动</el-tag>
          <el-button :disabled="!dirty" @click="revert">还原</el-button>
          <el-button type="primary" :disabled="!dirty || !!Object.keys(errors).length" :loading="saving" @click="saveFactors">保存系数并重算装备</el-button>
        </div>
      </header>
      <SchemaForm v-model="factors" :schema="qualityFactorSchema" :original="original" show-all-errors />
    </section>

    <section class="block">
      <h2>全部装备（{{ pieces.length }} 件）</h2>
      <ConfigListPage
        :schema="gearPieceSchema"
        :rows="pieces"
        :loading="loading"
        :error="error"
        id-key="id"
        entity-name="装备"
        :search-keys="['displayName', 'majorName', 'slotName']"
        :filters="filters"
        :columns="columns"
        :save-fn="savePiece"
        :hidden-keys="['majorKey', 'qualityName', 'slotName', 'majorName', 'attack', 'defense', 'hp', 'speed', 'power', 'requiredRealmOrder']"
        :drawer-size="620"
        export-name="装备"
        @reload="load"
      >
        <template #cell-qualityName="{ row }"><RarityTag :name="String(row.qualityName)" /></template>
        <template #cell-power="{ row }">{{ row.power ?? "规则未填" }}</template>
      </ConfigListPage>
    </section>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import RarityTag from "../../components/RarityTag.vue";
import SchemaForm from "../../components/SchemaForm.vue";
import { useDirtyGuard } from "../../composables/dirty";
import { refreshDraftStatus } from "../../composables/draftStatus";
import { gearPieceSchema, qualityFactorSchema } from "../../schema/resources";
import type { FormValues } from "../../schema/types";
import { validateSchema } from "../../schema/validate";

type Piece = {
  id: string;
  displayName: string;
  description: string;
  iconKey: string;
  slotName: string;
  qualityName: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  power: number | null;
};
type Major = { majorName: string; majorKey: string; requiredRealmOrder: number; pieces: Piece[] };

const factors = ref<FormValues>({});
const original = ref<FormValues>({});
const pieces = ref<(Piece & { majorName: string; requiredRealmOrder: number })[]>([]);
const loading = ref(false);
const error = ref("");
const saving = ref(false);

const dirty = computed(() => JSON.stringify(factors.value) !== JSON.stringify(original.value));
const errors = computed(() => validateSchema(qualityFactorSchema, factors.value));
useDirtyGuard(dirty);

const columns = [
  { key: "displayName", label: "名称", minWidth: 200 },
  { key: "majorName", label: "大境界", width: 100 },
  { key: "slotName", label: "部位", width: 80 },
  { key: "qualityName", label: "品质", width: 80 },
  { key: "attack", label: "攻击", width: 80, sortable: true },
  { key: "defense", label: "防御", width: 80, sortable: true },
  { key: "hp", label: "气血", width: 80, sortable: true },
  { key: "speed", label: "速度", width: 80, sortable: true },
  { key: "power", label: "战力", width: 90, sortable: true },
];

const filters = computed(() => [
  { key: "majorName", label: "大境界", options: [...new Set(pieces.value.map((row) => row.majorName))].map((name) => ({ label: name, value: name })) },
  { key: "slotName", label: "部位", options: [...new Set(pieces.value.map((row) => row.slotName))].map((name) => ({ label: name, value: name })) },
  { key: "qualityName", label: "品质", options: ["白", "绿", "蓝", "紫", "橙"].map((name) => ({ label: name, value: name })) },
]);

async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const page = await api<{ factors: Record<string, number>; majors: Major[] }>("/admin/draft/gear");
    factors.value = { ...page.factors };
    original.value = { ...page.factors };
    pieces.value = page.majors.flatMap((major) =>
      major.pieces.map((piece) => ({ ...piece, majorName: major.majorName, requiredRealmOrder: major.requiredRealmOrder })),
    );
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function revert(): void {
  factors.value = { ...original.value };
}

async function saveFactors(): Promise<void> {
  saving.value = true;
  try {
    await api("/admin/draft/gear-qualities", { method: "PUT", body: JSON.stringify({ ...factors.value }) });
    ElMessage.success("已保存，装备属性已重算");
    await load();
    void refreshDraftStatus();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

async function savePiece(values: Record<string, unknown>, _mode: "create" | "edit", editingId: string): Promise<void> {
  await api(`/admin/draft/gear/${editingId}`, {
    method: "PUT",
    body: JSON.stringify({ displayName: values.displayName, description: values.description, iconKey: values.iconKey }),
  });
}

onMounted(load);
</script>

<style scoped>
.slot-note {
  margin-bottom: var(--xx-space-4);
}
.block {
  margin-bottom: var(--xx-space-5);
  padding: var(--xx-space-4) var(--xx-space-5);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-lg);
  background: var(--xx-bg-surface);
}
.block-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.block h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-lg);
}
.actions {
  display: flex;
  align-items: center;
  gap: var(--xx-space-2);
}
</style>
