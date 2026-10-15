<template>
  <aside class="xx-field-card field-card" aria-live="polite">
    <template v-if="field">
      <div class="head">
        <span class="xx-field-card__name">{{ field.label }}</span>
        <code class="key">{{ field.key }}</code>
      </div>
      <dl class="meta">
        <div><dt>单位</dt><dd>{{ field.unit || (field.kind === "bool" ? "开关" : field.kind === "text" || field.kind === "textarea" ? "文字" : "无") }}</dd></div>
        <div><dt>范围</dt><dd>{{ rangeText(field) }}</dd></div>
        <div>
          <dt>默认值</dt>
          <dd>
            {{ defaultText }}
            <el-button v-if="canReset" link type="primary" size="small" @click="$emit('reset', field.key)">恢复默认</el-button>
          </dd>
        </div>
        <div v-if="value !== undefined">
          <dt>当前值</dt>
          <dd>
            {{ currentText }}
            <el-tag v-if="differs" size="small" type="warning" effect="plain">与默认不同</el-tag>
          </dd>
        </div>
        <div v-if="field.required"><dt>必填</dt><dd>是</dd></div>
        <div v-if="field.readonly"><dt>编辑</dt><dd>只读</dd></div>
        <div v-if="field.lockedAfterCreate"><dt>编辑</dt><dd>创建后不能改</dd></div>
      </dl>
      <p class="xx-field-card__hint">{{ field.hint }}</p>
      <p v-if="field.affects" class="line"><strong>影响：</strong>{{ field.affects }}</p>
      <p v-if="field.example" class="line"><strong>例：</strong>{{ field.example }}</p>
      <p v-if="field.warning" class="line warn">⚠ {{ field.warning }}</p>
    </template>
    <p v-else class="placeholder">点击任意字段，这里会显示它的中文名、单位、范围、默认值和填写提示。</p>
  </aside>
</template>

<script setup lang="ts">
import { computed } from "vue";
import type { FieldDef } from "../schema/types";
import { isBlank, rangeText } from "../schema/validate";

const props = defineProps<{ field: FieldDef | null; value?: unknown }>();
defineEmits<{ reset: [key: string] }>();

function show(value: unknown, field: FieldDef): string {
  if (isBlank(value)) {
    return "未填";
  }
  if (typeof value === "boolean") {
    return value ? "开" : "关";
  }
  if (field.kind === "select") {
    return field.options?.find((option) => option.value === value)?.label ?? String(value);
  }
  return `${value}${field.unit ?? ""}`;
}

const defaultText = computed(() => (props.field && props.field.default !== undefined ? show(props.field.default, props.field) : "无固定默认值"));
const currentText = computed(() => (props.field ? show(props.value, props.field) : ""));
const differs = computed(() => !!props.field && props.field.default !== undefined && !isBlank(props.value) && props.value !== props.field.default);
const canReset = computed(() => !!props.field && !props.field.readonly && props.field.default !== undefined && props.value !== props.field.default);
</script>

<style scoped>
.field-card {
  position: sticky;
  top: 0;
  align-self: start;
}
.head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
  gap: var(--xx-space-2);
}
.key {
  color: var(--xx-text-placeholder);
  font-family: var(--xx-font-mono);
  font-size: var(--xx-fs-xs);
}
.meta {
  display: grid;
  gap: 4px;
  margin: var(--xx-space-2) 0;
}
.meta div {
  display: grid;
  grid-template-columns: 56px 1fr;
  gap: var(--xx-space-2);
}
dt {
  color: var(--xx-text-secondary);
}
dd {
  margin: 0;
  color: var(--xx-text-primary);
}
.line {
  margin: var(--xx-space-1) 0 0;
  font-size: var(--xx-fs-sm);
}
.warn {
  color: var(--xx-warning);
}
.placeholder {
  margin: 0;
  color: var(--xx-text-secondary);
}
</style>
