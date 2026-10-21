<template>
  <span v-if="tier" class="tier-tag" :class="tier">{{ long ? TIER_NAME[tier] : TIER_SHORT[tier] }}</span>
</template>

<script setup lang="ts">
/** 首领档次标签：精英 = 蓝，章末 = 橙（ADMIN_SPEC §11 列表「首领」列）。 */
import { TIER_NAME, TIER_SHORT, type BossTier } from "../composables/bossRules";

defineProps<{ tier?: BossTier | null; long?: boolean }>();
</script>

<style scoped>
.tier-tag {
  display: inline-flex;
  align-items: center;
  height: 20px;
  padding: 0 7px;
  border: 1px solid transparent;
  border-radius: 4px;
  font-size: 12px;
  white-space: nowrap;
  vertical-align: middle;
}
.elite {
  border-color: #cddfeb;
  background: #eef3f7;
  color: #2f6a8e;
}
.chief {
  border-color: #efd0b8;
  background: #fbefe6;
  color: #a2531a;
}
</style>
