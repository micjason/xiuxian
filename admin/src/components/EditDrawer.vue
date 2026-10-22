<template>
  <el-drawer
    v-model="open"
    :size="size"
    :close-on-click-modal="true"
    :before-close="beforeClose"
    destroy-on-close
    class="edit-drawer"
    modal-class="xx-drawer-mask"
    @keydown.ctrl.s.prevent="trySave"
    @keydown.meta.s.prevent="trySave"
  >
    <template #header>
      <div class="drawer-title">
        <strong>{{ title }}</strong>
        <span v-if="subtitle" class="subtitle">{{ subtitle }}</span>
        <slot name="title-tags" />
      </div>
    </template>
    <slot />
    <template #footer>
      <div class="drawer-footer">
        <span class="status" :class="statusKind" @click="statusKind === 'error' && $emit('locate-error')">
          <i class="dot" />
          <template v-if="statusKind === 'error'">{{ errorCount }} 处校验未通过 · 点击定位</template>
          <template v-else-if="statusKind === 'dirty'">{{ changeCount ? `已改动 ${changeCount} 处，未保存` : "有未保存的改动" }}</template>
          <template v-else-if="statusText">{{ statusText }}</template>
          <template v-else>没有未保存的改动</template>
        </span>
        <span class="left"><slot name="footer-left" /></span>
        <el-button @click="beforeClose(() => (open = false))">取消</el-button>
        <el-button type="primary" :loading="saving" :disabled="!dirty && !alwaysSavable" @click="trySave">{{ saveText }}</el-button>
        <slot name="footer-extra" />
      </div>
    </template>
  </el-drawer>
</template>

<script setup lang="ts">
import { ElMessageBox } from "element-plus";
import { computed } from "vue";

/**
 * 右侧编辑抽屉（后台改版规范第 8 节）：页眉标题 + 灰色副标题；只有正文滚动；
 * 页脚左边显示改动状态，右边「取消」「保存」。关闭时有未保存改动：取消 / 不保存，关闭 / 保存并关闭。
 */
const props = withDefaults(
  defineProps<{
    title: string;
    subtitle?: string;
    dirty: boolean;
    saving?: boolean;
    size?: string | number;
    saveText?: string;
    alwaysSavable?: boolean;
    changeCount?: number;
    errorCount?: number;
    /** 没有未保存改动时替换页脚文案。已调（相对出厂）不等于 dirty。 */
    statusText?: string;
  }>(),
  { size: 800, saveText: "保存", changeCount: 0, errorCount: 0 },
);
const open = defineModel<boolean>({ required: true });
const emit = defineEmits<{ save: []; "locate-error": [] }>();

const statusKind = computed(() => (props.errorCount > 0 ? "error" : props.dirty ? "dirty" : "clean"));

async function beforeClose(done: () => void): Promise<void> {
  if (!props.dirty) {
    done();
    return;
  }
  try {
    await ElMessageBox.confirm(`「${props.title}」有未保存的改动`, "关闭抽屉", {
      confirmButtonText: "保存并关闭",
      cancelButtonText: "不保存，关闭",
      distinguishCancelAndClose: true,
      type: "warning",
    });
    emit("save");
  } catch (action) {
    if (action === "cancel") {
      done();
    }
  }
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
  align-items: baseline;
  gap: 12px;
  color: var(--xx-text-primary);
}
.drawer-title strong {
  font-family: var(--xx-font-serif);
  font-size: 19px;
}
.subtitle {
  color: var(--xx-text-secondary);
  font-family: var(--xx-font-mono);
  font-size: 12px;
}
.drawer-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: var(--xx-space-3);
}
.status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.status .dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--xx-border-strong);
}
.status.dirty .dot {
  background: var(--xx-gold-500);
}
.status.error {
  color: var(--xx-danger);
  cursor: pointer;
}
.status.error .dot {
  background: var(--xx-danger);
}
.left {
  margin-right: auto;
  display: flex;
  gap: var(--xx-space-2);
}
</style>

<style>
.xx-drawer-mask {
  background-color: rgba(18, 24, 22, 0.46) !important;
}
.edit-drawer .el-drawer__header {
  height: 64px;
  margin: 0;
  padding: 0 24px;
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-surface);
}
.edit-drawer .el-drawer__body {
  padding: 20px 24px;
  background: var(--xx-bg-page);
}
.edit-drawer .el-drawer__footer {
  height: 64px;
  padding: 0 24px;
  display: flex;
  align-items: center;
  justify-content: stretch;
  background: var(--xx-bg-surface);
  box-shadow: 0 -2px 8px rgba(0, 0, 0, 0.06);
}
.edit-drawer .el-drawer__footer > .drawer-footer {
  width: 100%;
}
</style>
