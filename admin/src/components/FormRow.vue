<template>
  <div class="form-row" :class="{ wide }">
    <label class="label">
      <span v-if="required" class="star" aria-hidden="true">*</span>{{ label }}<HelpTip v-if="help" :title="label" :text="help" :meta="helpMeta" />
    </label>
    <div class="control"><slot /></div>
    <div v-if="$slots.note || note" class="note"><slot name="note">{{ note }}</slot></div>
  </div>
</template>

<script setup lang="ts">
import HelpTip from "./HelpTip.vue";

/** 表单一行：标签列固定 136px 右对齐，间隔 16px；说明文字放在输入框下方 6px（12px 灰字）。 */
defineProps<{ label: string; help?: string; helpMeta?: string; required?: boolean; note?: string; wide?: boolean }>();
</script>

<style scoped>
.form-row {
  display: grid;
  grid-template-columns: 136px minmax(0, 1fr);
  column-gap: 16px;
  align-items: center;
}
.label {
  color: var(--xx-text-regular);
  font-size: var(--xx-fs-sm);
  text-align: right;
  white-space: nowrap;
}
.star {
  margin-right: 2px;
  color: var(--xx-danger);
}
.control {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 12px;
  min-height: 32px;
  min-width: 0;
}
.note {
  grid-column: 2;
  margin-top: 6px;
  color: var(--xx-text-secondary);
  font-size: 12px;
}
</style>
