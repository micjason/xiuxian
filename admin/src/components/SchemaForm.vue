<template>
  <div class="schema-form" :class="{ 'with-card': card }">
    <div class="fields">
      <slot name="top" />
      <section v-for="section in sections" :key="section.key" class="group">
        <header v-if="section.title" class="group-head">
          <h3>{{ section.title }}</h3>
          <p v-if="section.desc">{{ section.desc }}</p>
        </header>
        <div
          v-for="field in section.fields"
          :key="field.key"
          class="row"
          :class="{ active: activeKey === field.key, changed: isChanged(field.key), invalid: !!shownError(field.key) }"
          @focusin="activate(field)"
          @mouseenter="activate(field)"
        >
          <label class="label" :for="`f-${field.key}`">
            <span v-if="field.required && !field.readonly" class="star" aria-hidden="true">*</span>{{ field.label }}
            <span v-if="isChanged(field.key)" class="dot" title="已修改" />
          </label>
          <div class="control">
            <el-input
              v-if="field.kind === 'text' || field.kind === 'textarea'"
              :id="`f-${field.key}`"
              v-model="model[field.key] as string"
              :type="field.kind === 'textarea' ? 'textarea' : 'text'"
              :autosize="field.kind === 'textarea' ? { minRows: 2, maxRows: 6 } : undefined"
              :disabled="isDisabled(field)"
              :placeholder="field.placeholder ?? field.example"
              @blur="touch(field.key)"
            />
            <el-switch v-else-if="field.kind === 'bool'" :id="`f-${field.key}`" v-model="model[field.key] as boolean" :disabled="isDisabled(field)" />
            <el-select
              v-else-if="field.kind === 'select'"
              :id="`f-${field.key}`"
              v-model="model[field.key] as string | number"
              :disabled="isDisabled(field)"
              placeholder="请选择"
              style="width: 100%"
              @change="touch(field.key)"
            >
              <el-option v-for="option in optionsOf(field)" :key="option.value" :label="option.label" :value="option.value" />
            </el-select>
            <el-select
              v-else-if="field.kind === 'multiselect'"
              :id="`f-${field.key}`"
              v-model="model[field.key] as string[]"
              multiple
              collapse-tags
              collapse-tags-tooltip
              :disabled="isDisabled(field)"
              :placeholder="field.placeholder ?? '不选'"
              style="width: 100%"
            >
              <el-option v-for="option in optionsOf(field)" :key="option.value" :label="option.label" :value="option.value" />
            </el-select>
            <el-date-picker
              v-else-if="field.kind === 'datetime'"
              :id="`f-${field.key}`"
              v-model="model[field.key] as string"
              type="datetime"
              value-format="YYYY-MM-DDTHH:mm:ss"
              :disabled="isDisabled(field)"
              style="width: 100%"
            />
            <el-input-number
              v-else
              :id="`f-${field.key}`"
              v-model="model[field.key] as number | undefined"
              :controls="false"
              :step="field.step ?? 1"
              :precision="field.kind === 'int' ? 0 : field.precision"
              :disabled="isDisabled(field)"
              :placeholder="field.example"
              class="num"
              @blur="touch(field.key)"
            />
            <span v-if="field.unit && (field.kind === 'number' || field.kind === 'int')" class="unit">{{ field.unit }}</span>
          </div>
          <p v-if="shownError(field.key)" class="error" role="alert">{{ shownError(field.key) }}</p>
        </div>
      </section>
      <slot name="bottom" />
    </div>
    <FieldCard v-if="card" :field="activeField" :value="activeField ? model[activeField.key] : undefined" @reset="resetField" />
  </div>
</template>

<script setup lang="ts">
import { computed, reactive, ref } from "vue";
import type { FieldDef, FieldOption, FormValues, Schema } from "../schema/types";
import { sameValue, unregisteredFields, validateSchema } from "../schema/validate";
import FieldCard from "./FieldCard.vue";

const props = withDefaults(
  defineProps<{
    schema: Schema;
    original?: FormValues;
    mode?: "create" | "edit";
    showAllErrors?: boolean;
    card?: boolean;
    optionsMap?: Record<string, FieldOption[]>;
    /** 数据里有但不想当成「未登记字段」显示的键（编号、派生值等） */
    hiddenKeys?: string[];
    /** 只显示这些分组 */
    onlyGroups?: string[];
  }>(),
  { mode: "edit", card: true, showAllErrors: false },
);

const model = defineModel<FormValues>({ required: true });
const emit = defineEmits<{ active: [field: FieldDef | null] }>();

const touched = reactive(new Set<string>());
const activeKey = ref("");

const extras = computed(() => unregisteredFields(props.schema, model.value, props.hiddenKeys ?? []).map((field) => ({ ...field, readonly: true })));

const allFields = computed(() => [...props.schema.fields, ...extras.value]);
const errors = computed(() => validateSchema(props.schema, model.value));
const activeField = computed(() => allFields.value.find((field) => field.key === activeKey.value) ?? null);

const sections = computed(() => {
  const groups = props.schema.groups ?? [];
  const result: { key: string; title?: string; desc?: string; fields: FieldDef[] }[] = [];
  const used = new Set<string>();
  for (const group of groups) {
    if (props.onlyGroups && !props.onlyGroups.includes(group.key)) {
      continue;
    }
    const fields = props.schema.fields.filter((field) => field.group === group.key);
    fields.forEach((field) => used.add(field.key));
    if (fields.length > 0) {
      result.push({ key: group.key, title: group.title, desc: group.desc, fields });
    }
  }
  const rest = props.schema.fields.filter((field) => !used.has(field.key) && (!props.onlyGroups || (field.group && props.onlyGroups.includes(field.group))));
  if (rest.length > 0) {
    result.unshift({ key: "__main", fields: rest });
  }
  if (extras.value.length > 0 && !props.onlyGroups) {
    result.push({
      key: "__extra",
      title: "未登记字段（缺少说明）",
      desc: "这些字段接口里有，但后台还没有登记中文名、单位和范围。先只读显示，请补进 schema。",
      fields: extras.value,
    });
  }
  return result;
});

function optionsOf(field: FieldDef): FieldOption[] {
  return props.optionsMap?.[field.key] ?? field.options ?? [];
}

function isDisabled(field: FieldDef): boolean {
  return !!field.readonly || (!!field.lockedAfterCreate && props.mode === "edit");
}

function touch(key: string): void {
  touched.add(key);
}

function shownError(key: string): string {
  return props.showAllErrors || touched.has(key) ? (errors.value[key] ?? "") : "";
}

function isChanged(key: string): boolean {
  return !!props.original && !sameValue(model.value[key], props.original[key]);
}

function activate(field: FieldDef): void {
  if (activeKey.value !== field.key) {
    activeKey.value = field.key;
    emit("active", field);
  }
}

function resetField(key: string): void {
  const field = props.schema.fields.find((item) => item.key === key);
  if (field && field.default !== undefined) {
    model.value[key] = field.default;
    touch(key);
  }
}

defineExpose({ touchAll: () => props.schema.fields.forEach((field) => touched.add(field.key)), errors });
</script>

<style scoped>
.schema-form {
  display: grid;
  gap: var(--xx-space-4);
}
.schema-form.with-card {
  grid-template-columns: minmax(0, 1fr) 232px;
}
.group + .group {
  margin-top: var(--xx-space-4);
}
.group-head h3 {
  margin: 0;
  padding-bottom: var(--xx-space-1);
  border-bottom: 1px solid var(--xx-border);
  color: var(--xx-text-primary);
  font-size: var(--xx-fs-md);
}
.group-head p {
  margin: 4px 0 0;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-xs);
}
.row {
  display: grid;
  grid-template-columns: 124px minmax(0, 1fr);
  align-items: start;
  gap: 2px var(--xx-space-3);
  margin: 0 calc(var(--xx-space-2) * -1);
  padding: var(--xx-space-2);
  border-radius: var(--xx-radius-md);
}
.row.active {
  background: var(--xx-bg-hover);
}
.label {
  padding-top: 6px;
  color: var(--xx-text-regular);
  font-size: var(--xx-fs-sm);
  text-align: right;
}
.star {
  margin-right: 2px;
  color: var(--xx-danger);
}
.dot {
  display: inline-block;
  width: 6px;
  height: 6px;
  margin-left: 4px;
  border-radius: 50%;
  background: var(--xx-warning);
  vertical-align: middle;
}
.control {
  display: flex;
  align-items: center;
  gap: var(--xx-space-2);
  min-width: 0;
}
.unit {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  white-space: nowrap;
}
.num {
  width: 180px;
}
.error {
  grid-column: 2;
  margin: 0;
  color: var(--xx-danger);
  font-size: var(--xx-fs-xs);
}
.row.invalid :deep(.el-input__wrapper),
.row.invalid :deep(.el-textarea__inner) {
  box-shadow: 0 0 0 1px var(--xx-danger) inset;
}
</style>
