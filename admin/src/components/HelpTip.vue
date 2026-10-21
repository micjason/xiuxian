<template>
  <el-popover
    :visible="pinned || hovering"
    placement="top-start"
    :width="300"
    popper-class="xx-help-pop"
    :show-arrow="true"
  >
    <template #reference>
      <button
        type="button"
        class="help"
        :class="{ on: pinned }"
        :aria-label="`${title} 说明`"
        @mouseenter="enter"
        @mouseleave="leave"
        @click.stop="pinned = !pinned"
      >?</button>
    </template>
    <div class="body" @click.stop>
      <strong>{{ title }}</strong>
      <p>{{ text }}</p>
      <p v-if="meta" class="meta">{{ meta }}</p>
    </div>
  </el-popover>
</template>

<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from "vue";

/** 字段旁 14px 的圆形问号：悬停 200ms 出现，点击后固定不消失（再点或点别处关掉）。 */
defineProps<{ title: string; text: string; meta?: string }>();
const pinned = ref(false);
const hovering = ref(false);
let timer: ReturnType<typeof setTimeout> | undefined;

function enter(): void {
  clearTimeout(timer);
  timer = setTimeout(() => (hovering.value = true), 200);
}
function leave(): void {
  clearTimeout(timer);
  hovering.value = false;
}
const unpin = (): void => {
  pinned.value = false;
};
onMounted(() => window.addEventListener("click", unpin));
onBeforeUnmount(() => {
  window.removeEventListener("click", unpin);
  clearTimeout(timer);
});
</script>

<style scoped>
.help {
  display: inline-grid;
  place-items: center;
  width: 14px;
  height: 14px;
  margin-left: 4px;
  padding: 0;
  border: 1px solid var(--xx-border-strong);
  border-radius: 50%;
  background: transparent;
  color: var(--xx-text-secondary);
  font-size: 10px;
  font-weight: 700;
  line-height: 1;
  vertical-align: 1px;
  cursor: help;
}
.help:hover,
.help.on {
  border-color: var(--xx-jade-600);
  background: var(--xx-jade-600);
  color: #fff;
}
.body strong {
  display: block;
  margin-bottom: 4px;
  font-size: 12px;
  color: #fff;
}
.body p {
  margin: 0;
  font-size: 12px;
  line-height: 1.6;
}
.body .meta {
  margin-top: 4px;
  color: #a9b3ae;
}
</style>

<style>
.el-popover.el-popper.xx-help-pop {
  padding: 10px 12px;
  border: 0;
  background: #26302c;
  color: #eef1ee;
}
.el-popover.el-popper.xx-help-pop .el-popper__arrow::before {
  border: 0;
  background: #26302c;
}
</style>
