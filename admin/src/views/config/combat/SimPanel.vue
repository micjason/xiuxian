<template>
  <div>
    <el-alert type="info" :closable="false" show-icon class="note" title="试炼人偶只用于试打和战斗模拟，不会进入游戏。">
      「按配置算」会跟着境界、装备、功法的数值变；「手填属性」直接用填写的数。倾向按属性占战力的比例自动判断。
    </el-alert>
    <ConfigListPage
      :schema="listSchema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="id"
      entity-name="人偶"
      :search-keys="['displayName', 'summary', 'tendency']"
      :filters="filters"
      :columns="columns"
      :options-map="optionsMap"
      creatable
      deletable
      selectable
      :new-row="newRow"
      :save-fn="save"
      :remove-fn="remove"
      :drawer-size="700"
      :refresh-draft="false"
      export-name="试炼人偶"
      @reload="reload"
    >
      <template #toolbar>
        <el-button @click="openDuels">战斗模拟</el-button>
      </template>
      <template #cell-power="{ row }">
        <el-button v-if="row.power != null && row.powerDetail" link type="primary" @click.stop="openPower(row as unknown as Puppet)">{{ row.power }}</el-button>
      </template>
      <template #form="{ form, mode, showAllErrors }">
        <p v-if="form.problem" class="problem">{{ form.problem }}<template v-if="form.kind === 'configured'">。保存会按你现在选中的重新记录。</template></p>
        <SchemaForm
          :model-value="form"
          :schema="schemaFor(String(form.kind))"
          :mode="mode"
          :show-all-errors="showAllErrors"
          :options-map="optionsMap"
          :hidden-keys="hidden"
        />
      </template>
    </ConfigListPage>

    <el-dialog v-model="powerOpen" :title="powerRow ? `${powerRow.displayName} 的战力` : '战力'" width="560px">
      <template v-if="powerRow?.powerDetail">
        <p class="formula">战力 = 攻击 × 攻击权重 + 防御 × 防御权重 + 气血 × 气血权重 + 速度 × 速度权重，再四舍五入。</p>
        <p>出手间隔 {{ powerRow.interval }} 秒。战力不算出手间隔，速度只按速度这个数乘权重。</p>
        <ul class="math">
          <li v-for="line in powerRow.powerDetail.lines" :key="line.key">{{ line.label }} {{ line.stat }} × {{ line.weight }} = {{ line.amount }}</li>
        </ul>
        <p>相加 {{ powerRow.powerDetail.total }}，四舍五入是 <strong>{{ powerRow.powerDetail.power }}</strong>。倾向是 <strong>{{ powerRow.tendency }}</strong>。</p>
        <ul class="math">
          <li v-for="share in powerRow.powerDetail.shares" :key="share.key">{{ share.label }}占 {{ percent(share.ratio) }}，标准角色占 {{ percent(share.standardRatio) }}</li>
        </ul>
        <p>{{ powerRow.tendencyNote }}</p>
      </template>
    </el-dialog>

    <el-dialog v-model="duelOpen" title="战斗模拟" width="860px">
      <p>勾选多个人偶，每两个人各打一场：甲当攻方打乙，再换过来。同时出手时攻方先打。超过单场时限算攻方输。</p>
      <el-table :data="fightable" @selection-change="(value: Puppet[]) => (selected = value)">
        <el-table-column type="selection" width="48" />
        <el-table-column prop="displayName" label="名称" />
        <el-table-column prop="tendency" label="倾向" width="160" />
        <el-table-column prop="power" label="战力" width="100" />
      </el-table>
      <p v-if="fightable.length < rows.length" class="problem">属性不完整的人偶不能参加。</p>
      <div class="duel-actions">
        <span>每两人打</span>
        <el-input-number v-model="times" :min="1" :max="99" :step="1" :precision="0" :controls="false" />
        <span>场</span>
        <el-button type="primary" :disabled="selected.length < 2 || dueling" @click="runDuels">开始对打（{{ matchCount }} 场）</el-button>
      </div>
    </el-dialog>

    <el-dialog v-model="resultOpen" title="战斗结果" width="92%">
      <p v-if="matrix">行是攻方，列是守方。格子是这一行的人打这一列的人，写出胜场和负场。超过单场时限记为负。同一对人偶每次结果相同，所以重复打会是全胜或全负。</p>
      <div v-if="matrix" class="matrix-wrap">
        <table class="matrix">
          <thead>
            <tr>
              <th class="corner">攻方＼守方</th>
              <th v-for="person in matrix.people" :key="person.id" class="col">{{ person.name }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(person, rowIndex) in matrix.people" :key="person.id">
              <th class="row-name">{{ person.name }}</th>
              <td v-for="(cell, colIndex) in matrix.rows[rowIndex]" :key="matrix.people[colIndex].id" :class="cell.kind">{{ cell.text }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { useRefetchOnActivate } from "../../../composables/dataVersion";
import { computed, onMounted, ref } from "vue";
import { api } from "../../../api";
import ConfigListPage from "../../../components/ConfigListPage.vue";
import SchemaForm from "../../../components/SchemaForm.vue";
import { loadWeapons, type Named } from "../../../composables/lookups";
import type { FieldDef, Schema } from "../../../schema/types";
import { defaultsOf } from "../../../schema/validate";
import { puppetManualSchema } from "../../../schema/resources";

type Realm = { code: number; displayName: string };
type Gear = { id: string; displayName: string; missing: boolean };
type Puppet = {
  id: string;
  displayName: string;
  kind: "configured" | "manual";
  kindName: string;
  realmCode: number | null;
  realmName: string;
  realmMissing: boolean;
  weapons: Gear[];
  skills: Gear[];
  attack: number | null;
  defense: number | null;
  hp: number | null;
  speed: number | null;
  interval: number | null;
  power: number | null;
  powerDetail: {
    lines: { key: string; label: string; stat: number; weight: number; amount: number }[];
    total: number;
    power: number;
    shares: { key: string; label: string; ratio: number; standardRatio: number }[];
  } | null;
  tendency: string | null;
  tendencyNote: string | null;
  problem: string | null;
};
type DuelFight = { attackerId: string; attackerName: string; defenderId: string; defenderName: string; wins: number; losses: number };
type Duel = { timeLimitSeconds: number; fights: DuelFight[] };

const loading = ref(false);
const error = ref("");
const puppets = ref<Puppet[]>([]);
const realms = ref<Realm[]>([]);
const weapons = ref<Named[]>([]);
const skills = ref<Named[]>([]);
const powerOpen = ref(false);
const powerRow = ref<Puppet | null>(null);
const duelOpen = ref(false);
const resultOpen = ref(false);
const dueling = ref(false);
const selected = ref<Puppet[]>([]);
const times = ref(1);
const duel = ref<Duel | null>(null);

const hidden = ["id", "kindName", "realmName", "realmMissing", "weapons", "skills", "power", "powerDetail", "tendency", "tendencyNote", "problem", "summary", "kind"];

const kindField: FieldDef = {
  key: "kind", label: "类型", kind: "select", required: true, lockedAfterCreate: true,
  options: [{ label: "按配置算", value: "configured" }, { label: "手填属性", value: "manual" }],
  hint: "按配置算：跟着境界、装备、功法的数值变。手填属性：直接填数。类型建好后不能改。",
};
const nameField: FieldDef = { key: "displayName", label: "名称", kind: "text", required: true, hint: "人偶名称，只在后台试打时使用。" };
const configuredSchema: Schema = {
  title: "人偶",
  fields: [
    nameField,
    kindField,
    { key: "realmCode", label: "境界", kind: "select", required: true, options: [], hint: "人偶所在境界，决定基础属性。" },
    { key: "weaponIds", label: "装备", kind: "multiselect", options: [], hint: "穿哪些装备，不选就是空身。" },
    { key: "skillIds", label: "功法", kind: "multiselect", options: [], hint: "运转哪些功法，不选就是不运转。" },
  ],
};
const manualSchema: Schema = {
  title: "人偶",
  fields: [nameField, kindField, ...puppetManualSchema.fields.filter((field) => field.key !== "displayName").map((field) => ({ ...field, required: true }))],
};
const listSchema: Schema = { title: "人偶", fields: [nameField, kindField] };
function schemaFor(kind: string): Schema {
  return kind === "manual" ? manualSchema : configuredSchema;
}

const optionsMap = computed(() => ({
  realmCode: realms.value.map((realm) => ({ label: `${realm.code} ${realm.displayName}`, value: realm.code })),
  weaponIds: weapons.value.map((item) => ({ label: item.displayName || "名称缺失", value: item.id })),
  skillIds: skills.value.map((item) => ({ label: item.displayName || "名称缺失", value: item.id })),
}));
const filters = [{ key: "kind", label: "类型", options: kindField.options ?? [] }];
const columns = [
  { key: "displayName", label: "名称", minWidth: 160 },
  { key: "kindName", label: "类型", width: 100 },
  { key: "summary", label: "内容", minWidth: 280 },
  { key: "tendency", label: "倾向", width: 120 },
  { key: "power", label: "战力", width: 100, sortable: true },
];

function summaryOf(row: Puppet): string {
  if (row.problem) return row.problem;
  if (row.kind === "manual") return `攻击 ${row.attack}，防御 ${row.defense}，气血 ${row.hp}，速度 ${row.speed}，每 ${row.interval} 秒出手`;
  const gear = [...row.weapons.map((item) => item.displayName), ...row.skills.map((item) => item.displayName)];
  return gear.length > 0 ? `${row.realmName} · ${gear.join("、")}` : row.realmName;
}

const rows = computed(() =>
  puppets.value.map((row) => ({
    ...row,
    summary: summaryOf(row),
    realmCode: row.realmMissing ? undefined : (row.realmCode ?? undefined),
    weaponIds: row.weapons.filter((item) => !item.missing).map((item) => item.id),
    skillIds: row.skills.filter((item) => !item.missing).map((item) => item.id),
    attack: row.attack ?? undefined,
    defense: row.defense ?? undefined,
    hp: row.hp ?? undefined,
    speed: row.speed ?? undefined,
    interval: row.interval ?? undefined,
  })) as unknown as Record<string, unknown>[],
);

const fightable = computed(() => puppets.value.filter((row) => row.power != null && row.powerDetail && !row.problem));
const matchCount = computed(() => selected.value.length * Math.max(selected.value.length - 1, 0) * (times.value || 0));
const matrix = computed(() => {
  const fights = duel.value?.fights ?? [];
  const people: { id: string; name: string }[] = [];
  for (const fight of fights) {
    if (!people.some((person) => person.id === fight.attackerId)) {
      people.push({ id: fight.attackerId, name: fight.attackerName });
    }
  }
  return {
    people,
    rows: people.map((attacker) =>
      people.map((defender) => {
        if (attacker.id === defender.id) return { text: "—", kind: "self" };
        const fight = fights.find((item) => item.attackerId === attacker.id && item.defenderId === defender.id);
        if (!fight) return { text: "—", kind: "self" };
        const kind = fight.wins > fight.losses ? "win" : fight.losses > fight.wins ? "loss" : "tie";
        return { text: `${fight.wins}胜${fight.losses}负`, kind };
      }),
    ),
  };
});

function percent(ratio: number): string {
  return `${Math.round(ratio * 100)}%`;
}

function openPower(row: Puppet): void {
  powerRow.value = row;
  powerOpen.value = true;
}

function openDuels(): void {
  selected.value = [];
  resultOpen.value = false;
  duelOpen.value = true;
}

async function runDuels(): Promise<void> {
  dueling.value = true;
  try {
    duel.value = await api<Duel>("/admin/draft/puppets/duels", {
      method: "POST",
      body: JSON.stringify({ ids: selected.value.map((row) => row.id), times: times.value }),
    });
    duelOpen.value = false;
    resultOpen.value = true;
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "对打失败");
  } finally {
    dueling.value = false;
  }
}

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const [list, realmList, weaponList, skillList] = await Promise.all([
      api<Puppet[]>("/admin/draft/puppets"),
      api<Realm[]>("/admin/draft/realms"),
      loadWeapons(),
      api<Named[]>("/admin/draft/skills"),
    ]);
    puppets.value = list;
    realms.value = realmList;
    weapons.value = weaponList;
    skills.value = skillList;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function newRow(): Record<string, unknown> {
  return { ...defaultsOf(configuredSchema), kind: "configured", realmCode: realms.value[0]?.code, weaponIds: [], skillIds: [] };
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const body =
    values.kind === "manual"
      ? { displayName: values.displayName, kind: values.kind, attack: values.attack, defense: values.defense, hp: values.hp, speed: values.speed, interval: values.interval }
      : { displayName: values.displayName, kind: values.kind, realmCode: values.realmCode, weaponIds: values.weaponIds, skillIds: values.skillIds };
  if (mode === "create") {
    await api("/admin/draft/puppets", { method: "POST", body: JSON.stringify(body) });
  } else {
    await api(`/admin/draft/puppets/${editingId}`, { method: "PUT", body: JSON.stringify(body) });
  }
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/puppets/${String(row.id)}`, { method: "DELETE" });
}

useRefetchOnActivate(reload);
onMounted(reload);
</script>

<style scoped>
.note {
  margin-bottom: var(--xx-space-3);
}
.problem {
  color: var(--xx-danger);
}
.formula {
  padding: 8px 12px;
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
}
.math {
  margin: 8px 0;
  padding-left: 1.2em;
}
.duel-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 12px 0;
}
.duel-actions .el-input-number {
  width: 88px;
}
.matrix-wrap {
  overflow: auto;
  max-height: 70vh;
}
.matrix {
  width: max-content;
  border-collapse: collapse;
}
.matrix th,
.matrix td {
  padding: 8px 12px;
  border: 1px solid var(--xx-border);
  background: var(--xx-bg-surface);
  text-align: center;
  white-space: nowrap;
}
.matrix .corner,
.matrix .row-name {
  position: sticky;
  left: 0;
  z-index: 1;
  background: var(--xx-bg-subtle);
  text-align: left;
}
.matrix .col {
  font-weight: 600;
}
.matrix .win {
  color: var(--xx-success);
  font-weight: 700;
}
.matrix .loss {
  color: var(--xx-chart-2);
  font-weight: 700;
}
.matrix .self {
  color: var(--xx-text-placeholder);
}
</style>
