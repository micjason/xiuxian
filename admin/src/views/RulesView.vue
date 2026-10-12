<template>
  <div>
    <div class="toolbar">
      <h2>规则</h2>
      <el-button type="primary" @click="save">保存</el-button>
    </div>
    <p>
      这里的数会直接被游戏使用。没填的话，对应功能会失败，不会再用代码里的数顶上。出手间隔 = 境界的基础出手间隔 × 速度基数 ÷（速度基数 + 速度），再和最短出手间隔比，取更大的。玩家每下伤害 = 玩家攻击 − 首领防御 × 防御比例，低不过「玩家每下最少伤害」。战力 = 攻击×权重 + 防御×权重 + 气血×权重 + 速度×权重。
    </p>
    <el-form v-loading="loading" label-width="220px" class="form">
      <el-form-item label="挑战冷却（秒）">
        <el-input-number v-model="form.challengeCooldownSeconds" :min="0" :controls="false" />
      </el-form-item>
      <el-form-item label="单场时限（秒）">
        <el-input-number v-model="form.timeLimitSeconds" :min="0" :controls="false" />
      </el-form-item>
      <el-form-item label="玩家攻击时的防御比例">
        <el-input-number v-model="form.playerDefenseFactor" :min="0" :step="0.1" :controls="false" />
      </el-form-item>
      <el-form-item label="首领攻击时的防御比例">
        <el-input-number v-model="form.bossDefenseFactor" :min="0" :step="0.1" :controls="false" />
      </el-form-item>
      <el-form-item label="最短出手间隔（秒）">
        <el-input-number v-model="form.minInterval" :min="0" :step="0.1" :controls="false" />
      </el-form-item>
      <el-form-item label="速度基数">
        <el-input-number v-model="form.speedBase" :min="0" :controls="false" />
      </el-form-item>
      <el-form-item label="玩家每下最少伤害">
        <el-input-number v-model="form.playerDamageFloor" :min="0" :controls="false" />
      </el-form-item>
      <el-form-item label="首领每下最少伤害">
        <el-input-number v-model="form.bossDamageFloor" :min="0" :controls="false" />
      </el-form-item>
      <el-form-item label="战力里攻击的权重">
        <el-input-number v-model="form.attackWeight" :min="0" :step="0.1" :controls="false" />
      </el-form-item>
      <el-form-item label="战力里防御的权重">
        <el-input-number v-model="form.defenseWeight" :min="0" :step="0.1" :controls="false" />
      </el-form-item>
      <el-form-item label="战力里气血的权重">
        <el-input-number v-model="form.hpWeight" :min="0" :step="0.01" :controls="false" />
      </el-form-item>
      <el-form-item label="战力里速度的权重">
        <el-input-number v-model="form.speedWeight" :min="0" :step="0.1" :controls="false" />
      </el-form-item>
      <el-form-item label="行囊容量">
        <el-input-number v-model="form.bagCapacity" :min="0" :step="1" :precision="0" :controls="false" />
      </el-form-item>
      <el-form-item label="离线最多结算（秒）">
        <el-input-number v-model="form.offlineCapSeconds" :min="0" :step="1" :precision="0" :controls="false" />
      </el-form-item>
    </el-form>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Rules = {
  offlineCapSeconds: number | null;
  bagCapacity: number | null;
  attackWeight: number | null;
  defenseWeight: number | null;
  hpWeight: number | null;
  speedWeight: number | null;
  minInterval: number | null;
  playerDefenseFactor: number | null;
  bossDefenseFactor: number | null;
  challengeCooldownSeconds: number | null;
  timeLimitSeconds: number | null;
  playerDamageFloor: number | null;
  bossDamageFloor: number | null;
  speedBase: number | null;
};

const keys = [
  "offlineCapSeconds",
  "bagCapacity",
  "attackWeight",
  "defenseWeight",
  "hpWeight",
  "speedWeight",
  "minInterval",
  "playerDefenseFactor",
  "bossDefenseFactor",
  "challengeCooldownSeconds",
  "timeLimitSeconds",
  "playerDamageFloor",
  "bossDamageFloor",
  "speedBase",
] as const;

const loading = ref(false);
const form = reactive<Record<(typeof keys)[number], number | undefined>>({
  offlineCapSeconds: undefined,
  bagCapacity: undefined,
  attackWeight: undefined,
  defenseWeight: undefined,
  hpWeight: undefined,
  speedWeight: undefined,
  minInterval: undefined,
  playerDefenseFactor: undefined,
  bossDefenseFactor: undefined,
  challengeCooldownSeconds: undefined,
  timeLimitSeconds: undefined,
  playerDamageFloor: undefined,
  bossDamageFloor: undefined,
  speedBase: undefined,
});

function apply(rules: Rules): void {
  for (const key of keys) {
    form[key] = rules[key] ?? undefined;
  }
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    apply(await api<Rules>("/admin/draft/rules"));
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

async function save(): Promise<void> {
  try {
    apply(await api<Rules>("/admin/draft/rules", { method: "PUT", body: JSON.stringify(form) }));
    ElMessage.success("已保存，游戏会马上使用");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

onMounted(load);
</script>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.form {
  max-width: 640px;
}
</style>
