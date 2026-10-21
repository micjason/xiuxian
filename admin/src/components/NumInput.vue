<template>
  <div class="num-input" :class="[`w-${width}`, { inherit: inherited, custom: custom, readonly }]">
    <el-input-number
      :model-value="shown"
      :controls="false"
      :min="min"
      :max="max"
      :step="step ?? 1"
      :precision="precision"
      :disabled="readonly"
      :placeholder="placeholder"
      align="right"
      @update:model-value="onInput"
      @focus="$emit('focus')"
    >
      <template v-if="unit" #suffix><span class="unit">{{ unit }}</span></template>
      <template v-if="prefix" #prefix><span class="unit">{{ prefix }}</span></template>
    </el-input-number>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";

/**
 * 统一的数值输入框（后台改版规范第 1 节）：
 * - 宽度只用 160（独立数值）/ 120（表格、一排数值）/ 88（数量范围）/ 100 四档；
 * - 数值右对齐，单位放在框内右侧（灰色后缀）；
 * - 跟随默认（modelValue 为 null、传了 inheritValue）：浅底灰字显示默认值，一改就变成本条自己的值；
 * - custom：金色边框（已自定义）；readonly：只读灰底（自动计算的值）。
 */
const props = withDefaults(
  defineProps<{
    modelValue: number | null | undefined;
    width?: 160 | 120 | 100 | 88;
    unit?: string;
    prefix?: string;
    min?: number;
    max?: number;
    step?: number;
    precision?: number;
    inheritValue?: number | null;
    custom?: boolean;
    readonly?: boolean;
    placeholder?: string;
  }>(),
  { width: 160, min: 0, max: Number.MAX_SAFE_INTEGER },
);
const emit = defineEmits<{ "update:modelValue": [value: number | null]; focus: [] }>();

const inherited = computed(() => (props.modelValue === null || props.modelValue === undefined) && props.inheritValue !== undefined && props.inheritValue !== null);
const shown = computed(() => (inherited.value ? (props.inheritValue as number) : (props.modelValue ?? undefined)));

function onInput(value: number | null | undefined): void {
  emit("update:modelValue", value === undefined ? null : value);
}
</script>

<style scoped>
.num-input {
  display: inline-block;
}
.num-input :deep(.el-input-number) {
  width: 100%;
}
.num-input :deep(.el-input__inner) {
  text-align: right;
}
.w-160 {
  width: 160px;
}
.w-120 {
  width: 120px;
}
.w-100 {
  width: 100px;
}
.w-88 {
  width: 88px;
}
.unit {
  margin-left: 8px;
  color: var(--xx-text-placeholder);
  font-size: 13px;
}
.inherit :deep(.el-input__wrapper) {
  background: #faf9f4;
}
.inherit :deep(.el-input__inner) {
  color: #98a19c;
}
.custom :deep(.el-input__wrapper) {
  background: #fffcf3;
  box-shadow: 0 0 0 1px #d9b874 inset;
}
.readonly :deep(.el-input__wrapper) {
  background: var(--xx-bg-subtle);
}
</style>
