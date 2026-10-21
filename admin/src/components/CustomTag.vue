<template>
  <span class="ctag" :class="kind"><slot /></span>
</template>

<script setup lang="ts">
/** 小标签：custom = 已自定义（金）、default = 使用默认值（灰）、auto = 自动（绿）、info = 被 N 个关卡使用（蓝）。 */
withDefaults(defineProps<{ kind?: "custom" | "default" | "auto" | "info" | "readonly" }>(), { kind: "custom" });
</script>

<style scoped>
.ctag {
  display: inline-flex;
  align-items: center;
  height: 20px;
  padding: 0 7px;
  border: 1px solid transparent;
  border-radius: 4px;
  font-size: 12px;
  white-space: nowrap;
}
.custom {
  border-color: #ecd9b0;
  background: #f8eed9;
  color: #8f5c0c;
}
.default,
.readonly {
  border-color: var(--xx-border);
  background: var(--xx-bg-subtle);
  color: var(--xx-text-secondary);
}
.auto {
  border-color: #c8e0d2;
  background: var(--xx-success-bg);
  color: var(--xx-success);
}
.info {
  background: #e3eef5;
  color: #2f6a8e;
}
</style>
