<template>
  <SectionCard title="技能栏位" anchor="slots" desc="同时运转的技能数，按境界开放">
    <FormRow label="开放规则" help="到达某个境界后，最多能同时运转几门技能。境界越高栏位越多；运转中的技能只有在开放的栏位里才算属性。改少以后，多出来的那门不再生效（玩家可以自己换）。" :help-meta="`栏位数 1–${max}`">
      <div class="rules">
        <div class="row labels"><span class="w320">到达境界</span><span>开放栏位</span></div>
        <div v-for="(rule, index) in rules" :key="index" class="row">
          <el-select v-model="rule.minRealmOrder" class="w320">
            <el-option v-for="realm in realmOptions" :key="realm.code" :label="realm.displayName" :value="realm.code" />
          </el-select>
          <NumInput v-model="rule.slots" :width="120" unit="个" :precision="0" :min="1" :max="max" />
          <el-button link type="danger" :disabled="rules.length <= 1" @click="rules.splice(index, 1)">删除</el-button>
        </div>
        <el-button size="small" :disabled="rules.length >= max" @click="add">＋ 添加一档</el-button>
      </div>
      <template #note>{{ preview }}</template>
    </FormRow>
  </SectionCard>
</template>

<script setup lang="ts">
import { computed } from "vue";
import FormRow from "../../../components/FormRow.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";

/** 配置概览「技能栏位」（批次②）：artSlotRules，服务端按它限制同时运转的技能数，游戏端按 /me/state 的 skillSlots 显示。 */
export type SlotRule = { minRealmOrder: number; slots: number | null };

const rules = defineModel<SlotRule[]>({ required: true });
const props = defineProps<{ realms: { code: number; displayName: string }[]; max: number }>();

// 排序号 0 = 一开始就开（旧数据的默认规则）
const realmOptions = computed(() => [{ code: 0, displayName: "一开始（不限境界）" }, ...props.realms]);
const nameOf = (code: number) => realmOptions.value.find((realm) => realm.code === code)?.displayName ?? `境界 ${code}`;
const preview = computed(() =>
  [...rules.value]
    .sort((left, right) => left.minRealmOrder - right.minRealmOrder)
    .map((rule) => `${nameOf(rule.minRealmOrder)} ${rule.slots ?? "—"} 个`)
    .join(" → "),
);

function add(): void {
  const last = [...rules.value].sort((left, right) => left.minRealmOrder - right.minRealmOrder).at(-1);
  const next = props.realms.find((realm) => realm.code > (last?.minRealmOrder ?? 0));
  rules.value.push({ minRealmOrder: next?.code ?? props.realms[0]?.code ?? 1, slots: Math.min(props.max, (last?.slots ?? 0) + 1) });
}
</script>

<style scoped>
.rules {
  display: grid;
  gap: 8px;
  justify-items: start;
}
.row {
  display: flex;
  align-items: center;
  gap: 10px;
}
.row.labels {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.w320 {
  width: 320px;
}
</style>
