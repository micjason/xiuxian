<template>
  <SectionCard title="首领规则" anchor="boss" desc="首领重复挑战奖励与挑战规则">
    <FormRow
      label="首领橙装概率"
      help="首领重复奖励给的那件装备直接是橙色的概率。橙装只由首领掉，普通怪不掉。单个首领可以在关卡抽屉里单独改。"
      :help-meta="`范围 0–100% · 出厂值 ${defaultOrangePercent}%`"
    >
      <NumInput v-model="orangePercent" unit="%" :precision="2" :max="100" />
    </FormRow>
    <SchemaForm v-model="rules" :schema="schema" :hidden-keys="hiddenKeys" class="grid-form row-gap" />
  </SectionCard>
</template>

<script setup lang="ts">
/**
 * 配置概览里的「首领规则」一节（单独的组件：批次 3「每关一个首领」会替换这里的内容）。
 * 现在只有：首领橙装概率（tuning.bossOrangeChanceBp）+ 首领每日奖励次数等挑战规则（rules）。
 * 数据由父页面持有：改动走父页面的一次保存。
 */
import { computed } from "vue";
import FormRow from "../../../components/FormRow.vue";
import NumInput from "../../../components/NumInput.vue";
import SchemaForm from "../../../components/SchemaForm.vue";
import SectionCard from "../../../components/SectionCard.vue";
import { rulesSchema } from "../../../schema/resources";
import type { FormValues, Schema } from "../../../schema/types";

const BOSS_RULE_KEYS = ["bossDailyRewardCount", "challengeCooldownSeconds", "timeLimitSeconds", "ultAutoCastWindowSeconds"];

const props = defineProps<{ defaultOrangeBp: number }>();
/** 全部战斗规则（父页面的同一份对象，这里只显示首领相关的几项） */
const rules = defineModel<FormValues>("rules", { required: true });
/** 首领橙装概率（万分比） */
const orangeBp = defineModel<number>("orangeBp", { required: true });

const schema: Schema = { title: "首领规则", fields: rulesSchema.fields.filter((field) => BOSS_RULE_KEYS.includes(field.key)).map((field) => ({ ...field, group: undefined })) };
const hiddenKeys = computed(() => Object.keys(rules.value).filter((key) => !BOSS_RULE_KEYS.includes(key)));
const defaultOrangePercent = computed(() => props.defaultOrangeBp / 100);
const orangePercent = computed({
  get: () => (orangeBp.value ?? 0) / 100,
  set: (value: number | null) => (orangeBp.value = Math.round((value ?? 0) * 100)),
});
</script>

<style scoped>
.row-gap {
  margin-top: 20px;
}
.grid-form :deep(.fields) {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0 64px;
}
.grid-form :deep(.group) {
  display: contents;
}
</style>
