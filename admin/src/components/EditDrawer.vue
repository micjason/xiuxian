<template>
  <el-drawer
    v-model="open"
    :size="size"
    :close-on-click-modal="true"
    :before-close="beforeClose"
    destroy-on-close
    class="edit-drawer"
    @keydown.ctrl.s.prevent="trySave"
    @keydown.meta.s.prevent="trySave"
  >
    <template #header>
      <div class="drawer-title">
        <strong>{{ title }}</strong>
        <el-tag v-if="dirty" type="warning" effect="plain" size="small">有未保存的改动</el-tag>
        <slot name="title-tags" />
      </div>
    </template>
    <slot />
    <template #footer>
      <div class="drawer-footer">
        <span class="left"><slot name="footer-left" /></span>
        <span class="hint">Ctrl + S 保存</span>
        <el-button @click="beforeClose(() => (open = false))">取消</el-button>
        <el-button type="primary" :loading="saving" :disabled="!dirty && !alwaysSavable" @click="trySave">{{ saveText }}</el-button>
      </div>
    </template>
  </el-drawer>
</template>

<script setup lang="ts">
import { confirmDiscard } from "../composables/confirm";

const props = withDefaults(
  defineProps<{ title: string; dirty: boolean; saving?: boolean; size?: string | number; saveText?: string; alwaysSavable?: boolean }>(),
  { size: 800, saveText: "保存" },
);
const open = defineModel<boolean>({ required: true });
const emit = defineEmits<{ save: [] }>();

/** 点蒙层、右上角叉、Esc、取消按钮都会走这里：有未保存的改动先确认，没有就直接关。 */
async function beforeClose(done: () => void): Promise<void> {
  if (props.dirty && !(await confirmDiscard())) {
    return;
  }
  done();
}

function trySave(): void {
  if (!props.saving && (props.dirty || props.alwaysSavable)) {
    emit("save");
  }
}
</script>

<style scoped>
.drawer-title {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  color: var(--xx-text-primary);
  font-size: var(--xx-fs-lg);
}
.drawer-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: var(--xx-space-3);
}
.left {
  margin-right: auto;
  display: flex;
  gap: var(--xx-space-2);
}
.hint {
  color: var(--xx-text-placeholder);
  font-size: var(--xx-fs-xs);
}
</style>
