<template>
  <div class="save-bar">
    <span class="status" :class="{ dirty }"><i class="dot" />{{ dirty ? (changeCount ? `已改动 ${changeCount} 处，未保存` : "有未保存的改动") : "没有未保存的改动" }}</span>
    <span class="left"><slot /></span>
    <el-button :disabled="!dirty || saving" @click="$emit('cancel')">取消</el-button>
    <el-button type="primary" :loading="saving" :disabled="!dirty" @click="$emit('save')">{{ saveText }}</el-button>
  </div>
</template>

<script setup lang="ts">
/** 菜单页自带表单的底部操作条（规范第 1 节）：64px，固定在页面底部，左边改动状态，右边「取消」「保存」。 */
withDefaults(defineProps<{ dirty: boolean; saving?: boolean; changeCount?: number; saveText?: string }>(), { saveText: "保存", changeCount: 0 });
defineEmits<{ save: []; cancel: [] }>();
</script>

<style scoped>
.save-bar {
  position: sticky;
  bottom: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  gap: 12px;
  height: 64px;
  margin: 16px -24px 0;
  padding: 0 24px;
  background: var(--xx-bg-surface);
  box-shadow: 0 -2px 8px rgba(0, 0, 0, 0.06);
}
.status {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--xx-border-strong);
}
.status.dirty .dot {
  background: var(--xx-gold-500);
}
.left {
  flex: 1;
  display: flex;
  gap: 8px;
}
</style>
