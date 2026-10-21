<template>
  <section :id="anchor" class="section-card">
    <header class="head">
      <h3>{{ title }}</h3>
      <span v-if="desc" class="desc">{{ desc }}</span>
      <span class="spacer" />
      <slot name="extra" />
    </header>
    <div class="body" :class="{ flush }"><slot /></div>
  </section>
</template>

<script setup lang="ts">
/** 卡片：圆角 8，标题栏 52px（左侧 3px 青色竖条），正文内边距 20px；卡片之间 16px。 */
defineProps<{ title: string; desc?: string; anchor?: string; flush?: boolean }>();
</script>

<style scoped>
.section-card {
  margin-bottom: 16px;
  border: 1px solid var(--xx-border);
  border-radius: 8px;
  background: var(--xx-bg-surface);
  scroll-margin-top: 8px;
}
.head {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 52px;
  padding: 0 20px;
  border-bottom: 1px solid var(--xx-border);
}
.head h3 {
  margin: 0;
  padding-left: 10px;
  border-left: 3px solid var(--xx-jade-600);
  color: var(--xx-text-primary);
  font-size: 15px;
  line-height: 16px;
}
.desc {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.spacer {
  flex: 1;
}
.body {
  padding: 20px;
}
.body.flush {
  padding: 0;
}
</style>
