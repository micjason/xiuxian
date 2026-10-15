<template>
  <header class="page-header">
    <div class="titles">
      <h1>{{ title }}</h1>
      <slot name="tags" />
    </div>
    <div class="actions"><slot name="actions" /></div>
    <p v-if="desc" class="desc">{{ desc }}</p>
  </header>
</template>

<script setup lang="ts">
defineProps<{ title: string; desc?: string }>();
</script>

<style scoped>
.page-header {
  display: grid;
  grid-template-columns: 1fr auto;
  align-items: center;
  gap: var(--xx-space-1) var(--xx-space-4);
  margin-bottom: var(--xx-space-4);
}
.titles {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  min-width: 0;
}
h1 {
  margin: 0;
  color: var(--xx-text-primary);
  font-family: var(--xx-font-serif);
  font-size: var(--xx-fs-xl);
  letter-spacing: 0.04em;
}
.actions {
  display: flex;
  align-items: center;
  gap: var(--xx-space-2);
}
.desc {
  grid-column: 1 / -1;
  margin: 0;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
</style>
