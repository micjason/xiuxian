<template>
  <div>
    <PageHeader title="关卡与 Boss" desc="一个境界下可以有多个关卡。首领属性、掉落、试打都在同一个抽屉里完成；推荐战力由服务器按第一个首领自动算出，不能手填。" />
    <ConfigListPage
      :schema="stageSchema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="id"
      entity-name="关卡"
      :search-keys="['displayName', 'realmName', 'bossText']"
      search-placeholder="搜索关卡、境界、首领"
      :filters="filters"
      :columns="columns"
      :options-map="{ realmCode: realmOptions }"
      creatable
      deletable
      cloneable
      selectable
      :new-row="newRow"
      :save-fn="save"
      :remove-fn="remove"
      :drawer-size="940"
      export-name="关卡"
      @reload="reload"
    >
      <template #cell-realmName="{ row }">
        <el-tag v-if="row.realmMissing" type="danger" effect="light" size="small">境界 {{ row.realmCode }} 不存在</el-tag>
        <span v-else>{{ row.realmCode }} {{ row.realmName }}</span>
      </template>
      <template #cell-recommendedPower="{ row }">
        <el-tooltip v-if="row.powerProblem" :content="String(row.powerProblem)" placement="top">
          <el-tag type="warning" effect="light" size="small">算不出</el-tag>
        </el-tooltip>
        <span v-else>{{ row.recommendedPower }}</span>
      </template>
      <template #form="{ form, showAllErrors, mode }">
        <div class="stage-form">
          <div class="main">
            <SchemaForm
              :model-value="form"
              :schema="stageSchema"
              :mode="mode"
              :card="false"
              :show-all-errors="showAllErrors"
              :options-map="{ realmCode: realmOptions }"
              :hidden-keys="hidden"
              @active="(field) => (active = field)"
            />
            <BossEditor
              v-model="(form as StageForm).bosses"
              :items="items"
              :weapons="weapons"
              :skills="skills"
              :show-all-errors="showAllErrors"
              @active="(field) => (active = field)"
              @trial="openTrial"
            />
          </div>
          <FieldCard :field="active" :value="active ? (form as Record<string, unknown>)[active.key] : undefined" />
        </div>
      </template>
    </ConfigListPage>
    <TrialDialog v-model="trialOpen" :boss="trialBoss" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import type { BossRow } from "../../components/BossEditor.vue";
import BossEditor from "../../components/BossEditor.vue";
import ConfigListPage from "../../components/ConfigListPage.vue";
import FieldCard from "../../components/FieldCard.vue";
import PageHeader from "../../components/PageHeader.vue";
import SchemaForm from "../../components/SchemaForm.vue";
import TrialDialog from "../../components/TrialDialog.vue";
import { loadWeapons, type Named } from "../../composables/lookups";
import { stageSchema } from "../../schema/resources";
import type { FieldDef } from "../../schema/types";

type StageForm = { displayName: string; realmCode: number | undefined; bosses: BossRow[] };
type ApiBoss = { name: string; attack: number; defense: number; hp: number; interval: number; drops: { itemId: string; chancePercent: number }[] };
type ApiStage = {
  id: string;
  displayName: string;
  realmCode: number;
  realmName: string;
  realmMissing: boolean;
  recommendedPower: number | null;
  powerProblem: string | null;
  bosses: ApiBoss[];
};

const rows = ref<Record<string, unknown>[]>([]);
const loading = ref(false);
const error = ref("");
const realms = ref<{ code: number; displayName: string }[]>([]);
const items = ref<Named[]>([]);
const weapons = ref<Named[]>([]);
const skills = ref<Named[]>([]);
const active = ref<FieldDef | null>(null);
const trialOpen = ref(false);
const trialBoss = ref<BossRow | null>(null);

const hidden = ['id', 'dropCount', 'realmName', 'realmMissing', 'recommendedPower', 'powerProblem', 'bossText', 'bosses'];
const realmOptions = computed(() => realms.value.map((realm) => ({ label: `${realm.code} ${realm.displayName}`, value: realm.code })));
const filters = computed(() => [{ key: "realmCode", label: "境界", options: realmOptions.value }]);
const columns = [
  { key: "displayName", label: "关卡", minWidth: 160 },
  { key: "realmName", label: "所需境界", width: 150 },
  { key: "bossText", label: "首领", minWidth: 200 },
  { key: "dropCount", label: "掉落数", width: 90, sortable: true },
  { key: "recommendedPower", label: "推荐战力", width: 110, sortable: true },
];

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const [stages, realmList, itemList, weaponList, skillList] = await Promise.all([
      api<ApiStage[]>("/admin/draft/stages"),
      api<{ code: number; displayName: string }[]>("/admin/draft/realms"),
      api<Named[]>("/admin/draft/items"),
      loadWeapons(),
      api<Named[]>("/admin/draft/skills"),
    ]);
    realms.value = realmList;
    items.value = itemList;
    weapons.value = weaponList;
    skills.value = skillList;
    rows.value = stages.map((stage) => ({
      ...stage,
      bossText: stage.bosses.length === 0 ? "还没有首领" : stage.bosses.map((boss) => boss.name).join("、"),
      dropCount: stage.bosses.reduce((sum, boss) => sum + boss.drops.length, 0),
      bosses: stage.bosses.map((boss) => ({
        name: boss.name,
        attack: boss.attack,
        defense: boss.defense,
        hp: boss.hp,
        interval: boss.interval,
        drops: boss.drops.map((drop) => ({ itemId: drop.itemId, chancePercent: drop.chancePercent })),
      })),
    }));
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function newRow(): Record<string, unknown> {
  return { displayName: "", realmCode: realms.value[0]?.code, bosses: [] as BossRow[] };
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body = JSON.stringify({ displayName: values.displayName, realmCode: values.realmCode, bosses: values.bosses });
  if (mode === "create") {
    await api("/admin/draft/stages", { method: "POST", body });
  } else {
    await api(`/admin/draft/stages/${editingId}`, { method: "PUT", body });
  }
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/stages/${String(row.id)}`, { method: "DELETE" });
}

function openTrial(boss: BossRow): void {
  trialBoss.value = boss;
  trialOpen.value = true;
}

onMounted(reload);
</script>

<style scoped>
.stage-form {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 232px;
  gap: var(--xx-space-4);
}
.main {
  min-width: 0;
}
</style>
