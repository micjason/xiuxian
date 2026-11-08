<template>
  <SectionCard title="完整战斗系统" anchor="combat-runtime" desc="历练和迷雾共用出手规则；迷雾敌表、掉落、地图时限仍独立。保存后随现有配置流程生效。">
    <template v-if="model">
      <FormRow label="通关后允许跳过"><el-switch v-model="model.skipAfterWin" /></FormRow>
      <FormRow label="可选倍速"><el-checkbox-group v-model="model.speeds"><el-checkbox v-for="n in [1,2,3]" :key="n" :value="n">×{{ n }}</el-checkbox></el-checkbox-group></FormRow>
      <div class="runtime-grid">
        <FormRow v-for="field in fields" :key="field.key" :label="field.label"><NumInput v-model="model[field.key]" :min="field.min" :max="field.max" :precision="field.precision ?? 0" /></FormRow>
        <FormRow v-for="field in rageFields" :key="field.key" :label="field.label"><NumInput v-model="model.rage[field.key]" :min="field.min" :max="100000" :precision="0" /></FormRow>
      </div>
      <FormRow label="运转功法战斗效果（JSON）" help="以技能 id 为键，只有已装备且运转中的功法生效。valueBp 为万分比；状态可用 attack_up / defense_down / heal / shield。未配时不额外送暴击、闪避或状态。">
        <el-input v-model="skillText" type="textarea" :rows="10" @input="applySkills" />
        <p v-if="error" class="runtime-error">{{ error }}</p>
        <p class="muted">示例：{"skill_tuna":{"critChanceBp":0,"dodgeChanceBp":0,"effects":[{"kind":"heal","valueBp":1000},{"kind":"shield","valueBp":1500,"durationSeconds":3}]}}</p>
      </FormRow>
    </template>
  </SectionCard>
</template>
<script setup lang="ts">
import { ref, watch } from "vue";
import SectionCard from "../../../components/SectionCard.vue";
import FormRow from "../../../components/FormRow.vue";
import NumInput from "../../../components/NumInput.vue";
export type CombatRuntime = { skipAfterWin: boolean; speeds: number[]; statusDurationSeconds: number; fogTimeLimitSeconds: number; critChanceBp: number; dodgeChanceBp: number; critMultBp: number; rage: { max: number; onAttack: number; onHit: number; damageMultBp: number }; skills: Record<string, unknown> };
const model = defineModel<CombatRuntime>();
const skillText = ref("");
const error = ref("");
watch(() => model.value?.skills, value => { skillText.value = JSON.stringify(value ?? {}, null, 2); error.value = ""; }, { immediate: true });
const fields = [
  { key: "statusDurationSeconds" as const, label: "短时状态默认秒数", min: 0.1, max: 120, precision: 1 },
  { key: "fogTimeLimitSeconds" as const, label: "迷雾默认时限（秒）", min: 1, max: 600 },
  { key: "critChanceBp" as const, label: "基础暴击率（万分比，默认 0）", min: 0, max: 10000 },
  { key: "dodgeChanceBp" as const, label: "基础闪避率（万分比，默认 0）", min: 0, max: 10000 },
  { key: "critMultBp" as const, label: "暴击伤害倍率（万分比）", min: 10000, max: 100000 },
];
const rageFields = [{ key: "max" as const, label: "怒气上限", min: 1 }, { key: "onAttack" as const, label: "普攻获得怒气", min: 0 }, { key: "onHit" as const, label: "受击获得怒气", min: 0 }, { key: "damageMultBp" as const, label: "怒气强击倍率（万分比）", min: 0 }];
function applySkills() {
  try {
    const skills: unknown = JSON.parse(skillText.value);
    if (!skills || typeof skills !== "object" || Array.isArray(skills)) throw new Error("请填写以技能 id 为键的 JSON 对象");
    if (model.value) model.value.skills = skills as Record<string, unknown>;
    error.value = "";
  } catch (e) { error.value = e instanceof Error ? e.message : "JSON 格式不正确"; }
}
function validate() { applySkills(); return !error.value && !!model.value?.speeds.length; }
defineExpose({ validate });
</script>
<style scoped>.runtime-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; }.runtime-error { color: #cf3434; }</style>
