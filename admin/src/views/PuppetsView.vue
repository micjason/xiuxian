<template>
  <div>
    <div class="toolbar">
      <h2>人偶</h2>
      <div>
        <el-button @click="openDuels">战斗模拟</el-button>
        <el-button type="primary" @click="create">新建人偶</el-button>
      </div>
    </div>
    <p>人偶只用于试打，不进游戏。按配置算会跟着境界、武器、功法的数值变。手填属性直接用填进去的攻击、防御、气血、速度和出手间隔。类型建好后不能改。倾向按属性占战力的比例自动判断。点战力数字可以看每一项怎么乘出来的。</p>
    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="displayName" label="名称" width="180" />
      <el-table-column prop="kindName" label="类型" width="120" />
      <el-table-column label="内容">
        <template #default="{ row }">{{ summary(row) }}</template>
      </el-table-column>
      <el-table-column label="倾向" width="160">
        <template #default="{ row }">{{ row.tendency ?? "—" }}</template>
      </el-table-column>
      <el-table-column label="战力" width="100">
        <template #default="{ row }">
          <el-button v-if="row.power != null && row.powerDetail" link type="primary" @click="openPower(row)">{{ row.power }}</el-button>
          <span v-else>—</span>
        </template>
      </el-table-column>
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="edit(row)">编辑</el-button>
          <el-button link type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="open" :title="creating ? '新建人偶' : '编辑人偶'" width="560px">
      <el-form label-width="100px">
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="类型">
          <el-select v-if="creating" v-model="form.kind" placeholder="选择类型" style="width: 220px">
            <el-option label="按配置算" value="configured" />
            <el-option label="手填属性" value="manual" />
          </el-select>
          <span v-else>{{ form.kindName }}</span>
        </el-form-item>
        <p v-if="form.problem" class="problem">
          {{ form.problem }}<template v-if="form.kind === 'configured'">。保存会按你现在选中的重新记录。</template>
        </p>
        <template v-if="form.kind === 'configured'">
          <el-form-item label="境界">
            <el-select v-model="form.realmCode" placeholder="选择境界" style="width: 220px">
              <el-option v-for="realm in realms" :key="realm.code" :label="`${realm.code} ${realm.displayName}`" :value="realm.code" />
            </el-select>
          </el-form-item>
          <el-form-item label="武器">
            <el-select v-model="form.weaponIds" multiple placeholder="不穿" style="width: 100%">
              <el-option v-for="item in weapons" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
            </el-select>
          </el-form-item>
          <el-form-item label="功法">
            <el-select v-model="form.skillIds" multiple placeholder="不运转" style="width: 100%">
              <el-option v-for="skill in skills" :key="skill.id" :label="skill.displayName || '名称缺失'" :value="skill.id" />
            </el-select>
          </el-form-item>
        </template>
        <template v-if="form.kind === 'manual'">
          <el-form-item label="攻击">
            <el-input-number v-model="form.attack" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="防御">
            <el-input-number v-model="form.defense" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="气血">
            <el-input-number v-model="form.hp" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="速度">
            <el-input-number v-model="form.speed" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="出手间隔">
            <el-input-number v-model="form.interval" :min="0" :controls="false" />
          </el-form-item>
        </template>
      </el-form>
      <template #footer>
        <el-button @click="open = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="powerOpen" :title="powerRow ? `${powerRow.displayName} 的战力` : '战力'" width="560px">
      <template v-if="powerRow?.powerDetail">
        <p class="formula">战力 = 攻击 × 攻击权重 + 防御 × 防御权重 + 气血 × 气血权重 + 速度 × 速度权重，再四舍五入。</p>
        <p>出手间隔 {{ powerRow.interval }} 秒。战力不算出手间隔，速度只按速度这个数乘权重。</p>
        <ul class="math">
          <li v-for="line in powerRow.powerDetail.lines" :key="line.key">{{ line.label }} {{ line.stat }} × {{ line.weight }} = {{ line.amount }}</li>
        </ul>
        <p>相加 {{ powerRow.powerDetail.total }}，四舍五入是 <strong>{{ powerRow.powerDetail.power }}</strong>。</p>
        <p>倾向是 <strong>{{ powerRow.tendency }}</strong>。</p>
        <ul class="math">
          <li v-for="share in powerRow.powerDetail.shares" :key="share.key">
            {{ share.label }}占 {{ percent(share.ratio) }}，标准角色占 {{ percent(share.standardRatio) }}
          </li>
        </ul>
        <p>{{ powerRow.tendencyNote }}</p>
      </template>
    </el-dialog>

    <el-dialog v-model="duelOpen" title="战斗模拟" width="860px">
      <p>勾选多个人偶，每两个人各打一场：甲当攻方打乙，再换过来。同时出手时攻方先打。超过单场时限算攻方输。</p>
      <el-table :data="fightable" @selection-change="onSelect">
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
import { ElMessage, ElMessageBox } from "element-plus";
import { computed, onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Named = { id: string; displayName: string };
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
const open = ref(false);
const powerOpen = ref(false);
const powerRow = ref<Puppet | null>(null);
const duelOpen = ref(false);
const resultOpen = ref(false);
const dueling = ref(false);
const selected = ref<Puppet[]>([]);
const times = ref(1);
const duel = ref<Duel | null>(null);
const creating = ref(false);
const editingId = ref("");
const rows = ref<Puppet[]>([]);
const realms = ref<Realm[]>([]);
const weapons = ref<Named[]>([]);
const skills = ref<Named[]>([]);
const form = reactive({
  displayName: "",
  kind: "" as "" | "configured" | "manual",
  kindName: "",
  problem: "",
  realmCode: undefined as number | undefined,
  weaponIds: [] as string[],
  skillIds: [] as string[],
  attack: undefined as number | undefined,
  defense: undefined as number | undefined,
  hp: undefined as number | undefined,
  speed: undefined as number | undefined,
  interval: undefined as number | undefined,
});

const fightable = computed(() => rows.value.filter((row) => row.power != null && row.powerDetail && !row.problem));
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
        if (attacker.id === defender.id) {
          return { text: "—", kind: "self" };
        }
        const fight = fights.find((item) => item.attackerId === attacker.id && item.defenderId === defender.id);
        if (!fight) {
          return { text: "—", kind: "self" };
        }
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

function onSelect(rowsSelected: Puppet[]): void {
  selected.value = rowsSelected;
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

function summary(row: Puppet): string {
  if (row.problem) {
    return row.problem;
  }
  if (row.kind === "manual") {
    return `攻击 ${row.attack}，防御 ${row.defense}，气血 ${row.hp}，速度 ${row.speed}，每 ${row.interval} 秒出手`;
  }
  const gear = [...row.weapons.map((item) => item.displayName), ...row.skills.map((item) => item.displayName)];
  return gear.length > 0 ? `${row.realmName} · ${gear.join("、")}` : row.realmName;
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<Puppet[]>("/admin/draft/puppets");
    realms.value = await api<Realm[]>("/admin/draft/realms");
    weapons.value = await api<Named[]>("/admin/draft/weapons");
    skills.value = await api<Named[]>("/admin/draft/skills");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function resetForm(): void {
  form.displayName = "";
  form.kind = "";
  form.kindName = "";
  form.problem = "";
  form.realmCode = undefined;
  form.weaponIds = [];
  form.skillIds = [];
  form.attack = undefined;
  form.defense = undefined;
  form.hp = undefined;
  form.speed = undefined;
  form.interval = undefined;
}

function create(): void {
  creating.value = true;
  editingId.value = "";
  resetForm();
  open.value = true;
}

function edit(row: Puppet): void {
  creating.value = false;
  editingId.value = row.id;
  resetForm();
  form.displayName = row.displayName;
  form.kind = row.kind;
  form.kindName = row.kindName;
  form.problem = row.problem ?? "";
  form.realmCode = row.realmMissing ? undefined : (row.realmCode ?? undefined);
  form.weaponIds = row.weapons.filter((item) => !item.missing).map((item) => item.id);
  form.skillIds = row.skills.filter((item) => !item.missing).map((item) => item.id);
  form.attack = row.attack ?? undefined;
  form.defense = row.defense ?? undefined;
  form.hp = row.hp ?? undefined;
  form.speed = row.speed ?? undefined;
  form.interval = row.interval ?? undefined;
  open.value = true;
}

async function save(): Promise<void> {
  const body =
    form.kind === "manual"
      ? {
          displayName: form.displayName,
          kind: form.kind,
          attack: form.attack,
          defense: form.defense,
          hp: form.hp,
          speed: form.speed,
          interval: form.interval,
        }
      : {
          displayName: form.displayName,
          kind: form.kind,
          realmCode: form.realmCode,
          weaponIds: form.weaponIds,
          skillIds: form.skillIds,
        };
  try {
    if (creating.value) {
      await api("/admin/draft/puppets", { method: "POST", body: JSON.stringify(body) });
    } else {
      await api(`/admin/draft/puppets/${editingId.value}`, { method: "PUT", body: JSON.stringify(body) });
    }
    open.value = false;
    ElMessage.success("已保存");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function remove(row: Puppet): Promise<void> {
  await ElMessageBox.confirm(`删除人偶「${row.displayName}」？`, "删除人偶");
  await api(`/admin/draft/puppets/${row.id}`, { method: "DELETE" });
  ElMessage.success("已删除");
  await load();
}

onMounted(load);
</script>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.problem {
  color: var(--el-color-danger);
}
.formula {
  padding: 8px 12px;
  background: var(--el-fill-color-light);
  border-radius: 6px;
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
  border-collapse: collapse;
  width: max-content;
}
.matrix th,
.matrix td {
  border: 1px solid var(--el-border-color);
  padding: 8px 12px;
  text-align: center;
  white-space: nowrap;
  background: #fff;
}
.matrix .corner,
.matrix .row-name {
  position: sticky;
  left: 0;
  z-index: 1;
  text-align: left;
  background: var(--el-fill-color-light);
}
.matrix .col {
  font-weight: 600;
}
.matrix .win {
  color: #2f6f4e;
  font-weight: 700;
}
.matrix .loss {
  color: #c45c26;
  font-weight: 700;
}
.matrix .self {
  color: var(--el-text-color-placeholder);
}
</style>
