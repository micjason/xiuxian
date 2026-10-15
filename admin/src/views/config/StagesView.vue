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
            <section class="monsters">
              <header class="mhead">
                <h3>普通怪与掉落</h3>
                <span class="sub">玩家前台在线时在这个关卡刷怪：每波几只依次上前，每只击杀给固定修为，并按概率掉本境界阶装备。</span>
                <el-button size="small" @click="addMonster(form as StageForm)">添加怪物</el-button>
              </header>
              <p v-if="(form as StageForm).monsters.length === 0" class="muted">没有普通怪：这个关卡不能刷怪（只有首领）。</p>
              <div v-for="(monster, mIndex) in (form as StageForm).monsters" :key="mIndex" class="mrow">
                <el-input v-model="monster.name" placeholder="名称" class="mname" />
                <label>攻击<el-input-number v-model="monster.attack" :min="0" :controls="false" class="mnum" /></label>
                <label>防御<el-input-number v-model="monster.defense" :min="0" :controls="false" class="mnum" /></label>
                <label>气血<el-input-number v-model="monster.hp" :min="1" :controls="false" class="mnum" /></label>
                <label>间隔<el-input-number v-model="monster.interval" :min="0.1" :step="0.05" :precision="2" :controls="false" class="mnum" /></label>
                <label>击杀修为<el-input-number v-model="monster.killCultivation" :min="0" :precision="0" :controls="false" class="mnum" /></label>
                <el-button link type="danger" @click="(form as StageForm).monsters.splice(mIndex, 1)">去掉</el-button>
              </div>
              <div v-if="(form as StageForm).monsters.length > 0" class="mdrop">
                <strong>装备掉落</strong>
                <label>每只击杀掉落率<el-input-number v-model="dropOf(form as StageForm).chancePercent" :min="0" :max="100" :precision="2" :controls="false" class="mnum" />%</label>
                <label>品质权重 白<el-input-number v-model="dropOf(form as StageForm).weights.white" :min="0" :controls="false" class="mnum" /></label>
                <label>绿<el-input-number v-model="dropOf(form as StageForm).weights.green" :min="0" :controls="false" class="mnum" /></label>
                <label>蓝<el-input-number v-model="dropOf(form as StageForm).weights.blue" :min="0" :controls="false" class="mnum" /></label>
                <label>紫<el-input-number v-model="dropOf(form as StageForm).weights.purple" :min="0" :controls="false" class="mnum" /></label>
                <span class="muted">6 个部位等概率。掉的是本关卡所属境界所在大境界的装备。</span>
              </div>
            </section>
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

type MonsterRow = { name: string; attack: number; defense: number; hp: number; interval: number; killCultivation: number };
type DropForm = { chancePercent: number; weights: { white: number; green: number; blue: number; purple: number } };
type StageForm = { displayName: string; realmCode: number | undefined; bosses: BossRow[]; monsters: MonsterRow[]; monsterDrop: DropForm | null };
type ApiBoss = {
  name: string;
  attack: number;
  defense: number;
  hp: number;
  interval: number;
  drops: { itemId: string; chancePercent: number }[];
  firstClear: ({ kind: "item"; itemId: string; quantity: number } | { kind: "cultivation"; amount: number })[];
  repeat: { gear: boolean; extras: { itemId: string; chancePercent: number; minQty: number; maxQty: number }[] } | null;
};
type ApiStage = {
  id: string;
  displayName: string;
  realmCode: number;
  realmName: string;
  realmMissing: boolean;
  recommendedPower: number | null;
  powerProblem: string | null;
  bosses: ApiBoss[];
  monsters: MonsterRow[];
  monsterDrop: { chancePercent: number; weights: Partial<DropForm["weights"]> } | null;
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

const hidden = ['id', 'dropCount', 'realmName', 'realmMissing', 'recommendedPower', 'powerProblem', 'bossText', 'bosses', 'monsters', 'monsterDrop'];

function addMonster(form: StageForm): void {
  form.monsters.push({ name: '', attack: 0, defense: 0, hp: 100, interval: 1.5, killCultivation: 1 });
}

function dropOf(form: StageForm): DropForm {
  if (!form.monsterDrop) {
    form.monsterDrop = { chancePercent: 4, weights: { white: 70, green: 25, blue: 5, purple: 0 } };
  }
  return form.monsterDrop;
}
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
        firstClear: boss.firstClear.map((entry) => (entry.kind === "cultivation" ? { kind: "cultivation" as const, amount: entry.amount } : { kind: "item" as const, itemId: entry.itemId, quantity: entry.quantity })),
        repeat: boss.repeat ? { gear: boss.repeat.gear, extras: boss.repeat.extras.map((extra) => ({ ...extra })) } : null,
      })),
      monsters: stage.monsters.map((monster) => ({ ...monster })),
      monsterDrop: stage.monsterDrop
        ? { chancePercent: stage.monsterDrop.chancePercent, weights: { white: 0, green: 0, blue: 0, purple: 0, ...stage.monsterDrop.weights } }
        : null,
    }));
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function newRow(): Record<string, unknown> {
  return { displayName: "", realmCode: realms.value[0]?.code, bosses: [] as BossRow[], monsters: [] as MonsterRow[], monsterDrop: null };
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body = JSON.stringify({ displayName: values.displayName, realmCode: values.realmCode, bosses: values.bosses, monsters: values.monsters, monsterDrop: (values.monsters as MonsterRow[]).length > 0 ? values.monsterDrop : null });
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
.monsters {
  margin-bottom: var(--xx-space-4);
  padding-bottom: var(--xx-space-3);
  border-bottom: 1px solid var(--xx-border);
}
.mhead {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
}
.mhead h3 {
  margin: 0;
  font-size: var(--xx-fs-md);
}
.sub {
  flex: 1;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-xs);
}
.mrow,
.mdrop {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xx-space-2);
  margin-top: var(--xx-space-2);
  font-size: var(--xx-fs-sm);
}
.mname {
  width: 120px;
}
.mnum {
  width: 78px;
  margin-left: 4px;
}
.muted {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
</style>
