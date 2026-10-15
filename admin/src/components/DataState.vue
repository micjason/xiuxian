<template>
  <div class="data-state">
    <div v-if="loading && !hasData" class="skeleton" aria-busy="true" aria-label="加载中">
      <el-skeleton :rows="6" animated />
    </div>
    <el-result v-else-if="error" icon="error" title="加载失败" :sub-title="error">
      <template #extra><el-button type="primary" @click="$emit('retry')">重试</el-button></template>
    </el-result>
    <slot v-else-if="hasData" />
    <slot v-else name="empty">
      <el-empty :description="emptyText ?? '还没有数据'">
        <slot name="empty-action" />
      </el-empty>
    </slot>
  </div>
</template>

<script setup lang="ts">
defineProps<{ loading?: boolean; error?: string; hasData: boolean; emptyText?: string }>();
defineEmits<{ retry: [] }>();
</script>

<style scoped>
.skeleton {
  padding: var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-surface);
}
</style>
