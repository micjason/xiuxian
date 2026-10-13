<template>
  <div>
    <div class="toolbar">
      <h2>关卡</h2>
      <el-button type="primary" @click="create">新建关卡</el-button>
    </div>
    <p>一个境界下面可以有多关。首领可以有多个，玩家挑战时打第一个。首领身上可以挂武器、物品或功法，并填掉率，打赢后每件按掉率判定。功法掉进背包，是一本技能书，点了才学会。同一门功法的技能书各算一本，不叠在一起。填好数后可以点「试打」，选好已经保存的人偶一起打。保存后游戏立刻使用。推荐战力由服务器按第一个首领自动算出，不能手填。</p>
    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="displayName" label="名称" width="180" />
      <el-table-column label="境界" width="180">
        <template #default="{ row }">
          {{ row.realmMissing ? `${row.realmCode} 不存在` : `${row.realmCode} ${row.realmName}` }}
        </template>
      </el-table-column>
      <el-table-column label="首领">
        <template #default="{ row }">
          {{ bossSummary(row) }}
        </template>
      </el-table-column>
      <el-table-column label="推荐战力" width="220">
        <template #default="{ row }">
          <span v-if="row.powerProblem" class="hint">{{ row.powerProblem }}</span>
          <span v-else>{{ row.recommendedPower }}</span>
        </template>
      </el-table-column>
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="edit(row)">编辑</el-button>
          <el-button link type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="open" :title="creating ? '新建关卡' : '编辑关卡'" width="640px">
      <el-form label-width="100px">
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="境界">
          <el-select v-model="form.realmCode" placeholder="选择境界" style="width: 220px">
            <el-option v-for="realm in realms" :key="realm.code" :label="`${realm.code} ${realm.displayName}`" :value="realm.code" />
          </el-select>
        </el-form-item>
        <div v-for="(boss, index) in form.bosses" :key="index" class="boss">
          <div class="boss-title">
            <span>首领 {{ index + 1 }}</span>
            <el-button link type="danger" @click="form.bosses.splice(index, 1)">去掉</el-button>
          </div>
          <el-form-item label="名称">
            <el-input v-model="boss.name" />
          </el-form-item>
          <el-form-item label="攻击">
            <el-input-number v-model="boss.attack" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="防御">
            <el-input-number v-model="boss.defense" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="气血">
            <el-input-number v-model="boss.hp" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="出手间隔">
            <el-input-number v-model="boss.interval" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="掉落">
            <div class="drops">
              <div v-for="(drop, dropIndex) in boss.drops" :key="dropIndex" class="drop">
                <el-select v-model="drop.itemId" placeholder="选择武器、物品或功法" style="width: 220px">
                  <el-option-group label="武器">
                    <el-option v-for="item in weapons" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
                  </el-option-group>
                  <el-option-group label="物品">
                    <el-option v-for="item in items" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
                  </el-option-group>
                  <el-option-group label="功法">
                    <el-option v-for="skill in skills" :key="skill.id" :label="skill.displayName || '名称缺失'" :value="skill.id" />
                  </el-option-group>
                </el-select>
                <el-input-number v-model="drop.chancePercent" :min="0" :max="100" :precision="2" :controls="false" style="width: 90px" />
                <span>%</span>
                <span class="hint">{{ dropHint(drop.chancePercent) }}</span>
                <el-button link type="danger" @click="boss.drops.splice(dropIndex, 1)">去掉</el-button>
              </div>
              <el-button size="small" @click="boss.drops.push({ itemId: '', chancePercent: undefined })">加一个掉落</el-button>
            </div>
          </el-form-item>
          <el-form-item label="">
            <el-button type="success" plain @click="openTrial(boss)">试打这个首领</el-button>
          </el-form-item>
        </div>
        <el-button @click="addBoss">加一个首领</el-button>
      </el-form>
      <template #footer>
        <el-button @click="open = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>
    <el-dialog v-model="trialOpen" title="试打" width="640px">
      <p class="hint">用游戏里同一套规则算。首领用的是表单里现在填的数，不用先保存。可以同时选多个人偶。</p>
      <el-form label-width="80px">
        <el-form-item label="人偶">
          <el-select v-model="trial.puppetIds" multiple placeholder="选择人偶" style="width: 100%">
            <el-option v-for="puppet in puppets" :key="puppet.id" :label="puppetLabel(puppet)" :value="puppet.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="">
          <el-button type="primary" @click="runTrial">开打</el-button>
          <router-link v-if="puppets.length === 0" class="hint" to="/puppets">还没有人偶，去新建</router-link>
        </el-form-item>
      </el-form>
      <div v-for="result in trialResults" :key="result.puppetId" class="result">
        <h3 :class="result.error || !result.win ? 'lose' : 'win'">{{ result.displayName }} · {{ result.kindName }}</h3>
        <p v-if="result.error">{{ result.error }}</p>
        <template v-else-if="result.player">
          <p>{{ verdict(result) }}</p>
          <p>
            战力 {{ result.player.power }}，攻击 {{ result.player.attack }}，防御 {{ result.player.defense }}，气血
            {{ result.player.hp }}，速度 {{ result.player.speed }}，每 {{ round(result.player.interval) }} 秒出手一次
          </p>
          <p v-if="result.playerHits == null">人偶攻击是 0，打不动首领</p>
          <p v-else>
            每下打掉 {{ round(result.playerHit ?? 0) }}，要打 {{ result.playerHits }} 下，约
            {{ round(result.playerKillSeconds ?? 0) }} 秒打死首领
          </p>
          <p v-if="result.bossHits == null">首领攻击是 0，打不动这个人偶</p>
          <p v-else>
            首领每下打掉 {{ round(result.bossHit ?? 0) }}，要打 {{ result.bossHits }} 下，约
            {{ round(result.bossKillSeconds ?? 0) }} 秒打死这个人偶
          </p>
          <p class="hint">超过 {{ result.timeLimitSeconds }} 秒没分出胜负算输。</p>
        </template>
      </div>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Realm = { code: number; displayName: string };
type Named = { id: string; displayName: string };
type Drop = { itemId: string; chancePercent: number | undefined };
type Boss = { name: string; attack: number; defense: number; hp: number; interval: number; drops: Drop[] };
type Stage = {
  id: string;
  displayName: string;
  realmCode: number;
  realmName: string;
  realmMissing: boolean;
  recommendedPower: number | null;
  powerProblem: string | null;
  bosses: {
    name: string;
    attack: number;
    defense: number;
    hp: number;
    interval: number;
    drops: { itemId: string; displayName: string; chancePercent: number }[];
  }[];
};
type PuppetOption = { id: string; displayName: string; kindName: string; problem: string | null };
type TrialResult = {
  puppetId: string;
  displayName: string;
  kindName: string;
  error: string | null;
  win: boolean | null;
  reason: "win" | "defeated" | "timeout" | null;
  durationSeconds: number | null;
  timeLimitSeconds: number | null;
  player: { power: number; attack: number; defense: number; hp: number; speed: number; interval: number } | null;
  playerHit: number | null;
  playerHits: number | null;
  playerKillSeconds: number | null;
  bossHit: number | null;
  bossHits: number | null;
  bossKillSeconds: number | null;
};

const loading = ref(false);
const open = ref(false);
const creating = ref(false);
const editingId = ref("");
const rows = ref<Stage[]>([]);
const realms = ref<Realm[]>([]);
const items = ref<Named[]>([]);
const weapons = ref<Named[]>([]);
const skills = ref<Named[]>([]);
const puppets = ref<PuppetOption[]>([]);
const form = reactive({ displayName: "", realmCode: undefined as number | undefined, bosses: [] as Boss[] });
const trialOpen = ref(false);
const trialBoss = ref<Boss | null>(null);
const trialResults = ref<TrialResult[]>([]);
const trial = reactive({ puppetIds: [] as string[] });

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

function dropHint(percent: number | undefined): string {
  if (percent == null) {
    return "请填掉率";
  }
  if (percent <= 0) {
    return "不会掉";
  }
  return `平均打赢约 ${round(100 / percent)} 次掉一件`;
}

function puppetLabel(puppet: PuppetOption): string {
  return puppet.problem ? `${puppet.displayName}（${puppet.problem}）` : `${puppet.displayName}（${puppet.kindName}）`;
}

function verdict(result: TrialResult): string {
  if (result.win) {
    return `赢，用时 ${round(result.durationSeconds ?? 0)} 秒`;
  }
  if (result.reason === "timeout") {
    return `输，${result.timeLimitSeconds} 秒没打死首领`;
  }
  return `输，第 ${round(result.durationSeconds ?? 0)} 秒被打死`;
}

async function openTrial(boss: Boss): Promise<void> {
  trialBoss.value = boss;
  trialResults.value = [];
  trialOpen.value = true;
  try {
    puppets.value = await api<PuppetOption[]>("/admin/draft/puppets");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "人偶加载失败");
  }
}

async function runTrial(): Promise<void> {
  if (!trialBoss.value) {
    return;
  }
  const boss = trialBoss.value;
  try {
    const body = await api<{ results: TrialResult[] }>("/admin/draft/trial", {
      method: "POST",
      body: JSON.stringify({
        puppetIds: trial.puppetIds,
        boss: { attack: boss.attack, defense: boss.defense, hp: boss.hp, interval: boss.interval },
      }),
    });
    trialResults.value = body.results;
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "试打失败");
  }
}

function bossSummary(row: Stage): string {
  if (row.bosses.length === 0) {
    return "还没有首领";
  }
  return row.bosses.map((boss) => boss.name).join("、");
}

function addBoss(): void {
  form.bosses.push({ name: "", attack: 0, defense: 0, hp: 0, interval: 0, drops: [] });
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<Stage[]>("/admin/draft/stages");
    realms.value = await api<Realm[]>("/admin/draft/realms");
    items.value = await api<Named[]>("/admin/draft/items");
    weapons.value = await api<Named[]>("/admin/draft/weapons");
    skills.value = await api<Named[]>("/admin/draft/skills");
    puppets.value = await api<PuppetOption[]>("/admin/draft/puppets");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function create(): void {
  creating.value = true;
  editingId.value = "";
  form.displayName = "";
  form.realmCode = realms.value[0]?.code;
  form.bosses = [];
  open.value = true;
}

function edit(row: Stage): void {
  creating.value = false;
  editingId.value = row.id;
  form.displayName = row.displayName;
  form.realmCode = row.realmCode;
  form.bosses = row.bosses.map((boss) => ({
    name: boss.name,
    attack: boss.attack,
    defense: boss.defense,
    hp: boss.hp,
    interval: boss.interval,
    drops: boss.drops.map((drop) => ({ itemId: drop.itemId, chancePercent: drop.chancePercent })),
  }));
  open.value = true;
}

async function save(): Promise<void> {
  const body = { displayName: form.displayName, realmCode: form.realmCode, bosses: form.bosses };
  try {
    if (creating.value) {
      await api("/admin/draft/stages", { method: "POST", body: JSON.stringify(body) });
    } else {
      await api(`/admin/draft/stages/${editingId.value}`, { method: "PUT", body: JSON.stringify(body) });
    }
    open.value = false;
    ElMessage.success("已保存，游戏会马上使用");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function remove(row: Stage): Promise<void> {
  await ElMessageBox.confirm(`删除关卡「${row.displayName}」？`, "删除关卡");
  await api(`/admin/draft/stages/${row.id}`, { method: "DELETE" });
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
.boss {
  margin: 12px 0;
  padding-top: 8px;
  border-top: 1px solid var(--el-border-color);
}
.drops {
  display: flex;
  flex-direction: column;
  gap: 8px;
  width: 100%;
}
.drop {
  display: flex;
  align-items: center;
  gap: 8px;
}
.hint {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.result + .result {
  margin-top: 16px;
  padding-top: 8px;
  border-top: 1px solid var(--el-border-color);
}
.result p {
  margin: 6px 0;
}
a.hint {
  margin-left: 12px;
}
.win {
  color: var(--el-color-success);
}
.lose {
  color: var(--el-color-danger);
}
.boss-title {
  display: flex;
  justify-content: space-between;
  margin-bottom: 8px;
}
</style>
