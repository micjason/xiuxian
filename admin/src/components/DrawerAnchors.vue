<template>
  <nav ref="bar" class="anchors">
    <button v-for="item in items" :key="item.id" type="button" :class="{ on: active === item.id }" @click="go(item.id)">{{ item.label }}</button>
  </nav>
</template>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref } from "vue";

/** 抽屉锚点栏（规范第 8 节）：44px，固定在正文顶上；滚到哪一节高亮哪一节，点一下平滑滚过去。 */
const props = defineProps<{ items: { id: string; label: string }[] }>();
const bar = ref<HTMLElement | null>(null);
const active = ref(props.items[0]?.id ?? "");
let scroller: HTMLElement | null = null;
let lockedUntil = 0;

function onScroll(): void {
  if (!scroller || Date.now() < lockedUntil) return;
  const top = scroller.getBoundingClientRect().top + 60;
  let current = props.items[0]?.id ?? "";
  for (const item of props.items) {
    const element = document.getElementById(item.id);
    if (element && element.getBoundingClientRect().top <= top) {
      current = item.id;
    }
  }
  // 滚到底了：最后几节可能顶不到上面，取已经露出来的最后一节
  if (scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 4) {
    const bottom = scroller.getBoundingClientRect().bottom;
    for (const item of props.items) {
      const element = document.getElementById(item.id);
      if (element && element.getBoundingClientRect().top < bottom - 80) current = item.id;
    }
  }
  active.value = current;
}

function go(id: string): void {
  const element = document.getElementById(id);
  if (!element || !scroller) return;
  active.value = id;
  lockedUntil = Date.now() + 900;
  scroller.scrollTo({ top: scroller.scrollTop + element.getBoundingClientRect().top - scroller.getBoundingClientRect().top - 52, behavior: "smooth" });
}

onMounted(async () => {
  await nextTick();
  scroller = bar.value?.closest(".el-drawer__body") as HTMLElement | null;
  scroller?.addEventListener("scroll", onScroll, { passive: true });
});
onBeforeUnmount(() => scroller?.removeEventListener("scroll", onScroll));
</script>

<style scoped>
.anchors {
  position: sticky;
  top: -20px;
  z-index: 5;
  display: flex;
  gap: 28px;
  height: 44px;
  margin: -20px -24px 16px;
  padding: 0 24px;
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-surface);
}
.anchors button {
  position: relative;
  padding: 0;
  border: 0;
  background: none;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  cursor: pointer;
}
.anchors button.on {
  color: var(--xx-jade-600);
  font-weight: 600;
}
.anchors button.on::after {
  content: "";
  position: absolute;
  left: 0;
  right: 0;
  bottom: 0;
  height: 2px;
  background: var(--xx-jade-600);
}
</style>
