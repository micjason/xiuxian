<template>
  <div class="tabs-bar" role="tablist" aria-label="已打开的页面">
    <div ref="strip" class="strip" @wheel.prevent="onWheel">
      <div
        v-for="tab in tabs"
        :key="tab.path"
        class="tab"
        :class="{ active: tab.path === activePath, home: tab.path === HOME_PATH }"
        role="tab"
        :aria-selected="tab.path === activePath"
        :data-path="tab.path"
        @click="go(tab)"
        @click.middle.prevent="close(tab)"
        @contextmenu.prevent="openMenu($event, tab)"
      >
        <span v-if="tab.path === HOME_PATH" class="home-icon" aria-hidden="true">⌂</span>
        <span class="title">{{ tab.title }}</span>
        <span v-if="dirtyPaths.has(tab.path)" class="dirty" title="有未保存的改动" />
        <button v-if="tab.path !== HOME_PATH" class="x" type="button" :aria-label="`关闭 ${tab.title}`" @click.stop="close(tab)">×</button>
      </div>
    </div>
    <div class="ends">
      <el-tooltip content="刷新当前页" placement="bottom"><button class="end-btn" type="button" aria-label="刷新当前页" @click="refresh(activePath)">⟳</button></el-tooltip>
      <el-dropdown trigger="click" placement="bottom-end" @command="onListCommand">
        <button class="end-btn" type="button" aria-label="全部标签">▾</button>
        <template #dropdown>
          <el-dropdown-menu class="tab-list">
            <el-dropdown-item v-for="tab in tabs" :key="tab.path" :command="`go:${tab.path}`">
              <span class="check">{{ tab.path === activePath ? "✓" : "" }}</span>{{ tab.title }}
            </el-dropdown-item>
            <el-dropdown-item divided command="others">关闭其他</el-dropdown-item>
            <el-dropdown-item command="all">关闭全部</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>
    <ul v-if="menu.open" class="ctx" :style="{ left: `${menu.x}px`, top: `${menu.y}px` }" role="menu" @click.stop>
      <li role="menuitem" @click="onMenu('refresh')">刷新页面</li>
      <li role="menuitem" :class="{ off: menu.tab?.path === HOME_PATH }" @click="onMenu('close')">关闭当前</li>
      <li role="menuitem" @click="onMenu('others')">关闭其他</li>
      <li role="menuitem" @click="onMenu('left')">关闭左侧</li>
      <li role="menuitem" @click="onMenu('right')">关闭右侧</li>
      <li role="menuitem" @click="onMenu('all')">关闭全部</li>
    </ul>
  </div>
</template>

<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { closeTabs, dirtyPaths, HOME_PATH, refreshTab, tabs, type Tab } from "../composables/tabs";

const props = defineProps<{ activePath: string }>();
const router = useRouter();
const strip = ref<HTMLElement | null>(null);
const menu = reactive<{ open: boolean; x: number; y: number; tab: Tab | null }>({ open: false, x: 0, y: 0, tab: null });

function go(tab: Tab): void {
  if (tab.path !== props.activePath) {
    void router.push(tab.fullPath);
  }
}

function close(tab: Tab): void {
  void closeTabs(router, [tab], props.activePath);
}

function refresh(path: string): void {
  void refreshTab(path);
}

function onWheel(event: WheelEvent): void {
  if (strip.value) {
    strip.value.scrollLeft += event.deltaY + event.deltaX;
  }
}

function openMenu(event: MouseEvent, tab: Tab): void {
  menu.open = true;
  menu.x = event.clientX;
  menu.y = event.clientY;
  menu.tab = tab;
}

function onMenu(command: string): void {
  const tab = menu.tab;
  menu.open = false;
  if (!tab) {
    return;
  }
  const index = tabs.indexOf(tab);
  const targets: Record<string, Tab[]> = {
    close: [tab],
    others: tabs.filter((item) => item !== tab),
    left: tabs.slice(0, index),
    right: tabs.slice(index + 1),
    all: [...tabs],
  };
  if (command === "refresh") {
    if (tab.path !== props.activePath) {
      void router.push(tab.fullPath);
    }
    refresh(tab.path);
    return;
  }
  void closeTabs(router, targets[command] ?? [], props.activePath);
}

function onListCommand(command: string): void {
  if (command.startsWith("go:")) {
    const tab = tabs.find((item) => item.path === command.slice(3));
    if (tab) {
      go(tab);
    }
    return;
  }
  const current = tabs.find((item) => item.path === props.activePath);
  void closeTabs(router, command === "others" ? tabs.filter((item) => item !== current) : [...tabs], props.activePath);
}

const hide = (): void => {
  menu.open = false;
};
onMounted(() => window.addEventListener("click", hide));
onBeforeUnmount(() => window.removeEventListener("click", hide));

// 当前标签滚到可见
watch(
  () => [props.activePath, tabs.length],
  async () => {
    await nextTick();
    strip.value?.querySelector<HTMLElement>(`[data-path="${props.activePath}"]`)?.scrollIntoView({ block: "nearest", inline: "nearest" });
  },
  { immediate: true },
);
</script>

<style scoped>
.tabs-bar {
  display: flex;
  align-items: flex-end;
  height: 40px;
  padding: 0 0 0 var(--xx-space-4);
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-surface);
}
.strip {
  display: flex;
  flex: 1;
  align-items: flex-end;
  gap: 2px;
  min-width: 0;
  overflow-x: auto;
  overflow-y: hidden;
  scrollbar-width: none;
}
.strip::-webkit-scrollbar {
  display: none;
}
.tab {
  position: relative;
  display: inline-flex;
  flex: none;
  align-items: center;
  gap: 6px;
  height: 32px;
  padding: 0 10px 0 14px;
  border: 1px solid transparent;
  border-bottom: 0;
  border-radius: 6px 6px 0 0;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  white-space: nowrap;
  cursor: pointer;
  user-select: none;
}
.tab.home {
  padding-right: 14px;
}
.tab:hover {
  background: var(--xx-bg-subtle);
}
.tab.active {
  height: 33px;
  margin-bottom: -1px;
  border-color: var(--xx-border);
  background: var(--xx-bg-page);
  color: var(--xx-jade-600);
  font-weight: 600;
  box-shadow: inset 0 2px 0 var(--xx-jade-600);
}
.home-icon {
  font-size: 13px;
}
.dirty {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--xx-gold-500);
}
.x {
  display: grid;
  place-items: center;
  width: 16px;
  height: 16px;
  padding: 0;
  border: 0;
  border-radius: 50%;
  background: transparent;
  color: var(--xx-text-placeholder);
  font-size: 14px;
  line-height: 1;
  cursor: pointer;
}
.x:hover {
  background: var(--xx-border);
  color: var(--xx-text-primary);
}
.ends {
  display: flex;
  align-self: center;
  gap: 4px;
  padding: 0 var(--xx-space-3);
}
.end-btn {
  width: 28px;
  height: 28px;
  border: 1px solid var(--xx-border);
  border-radius: 6px;
  background: var(--xx-bg-surface);
  color: var(--xx-text-secondary);
  cursor: pointer;
}
.end-btn:hover {
  color: var(--xx-jade-600);
}
.check {
  display: inline-block;
  width: 16px;
  color: var(--xx-jade-600);
}
.ctx {
  position: fixed;
  z-index: 3000;
  min-width: 120px;
  margin: 0;
  padding: 4px 0;
  border: 1px solid var(--xx-border);
  border-radius: 6px;
  background: var(--xx-bg-surface);
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.12);
  list-style: none;
  font-size: var(--xx-fs-sm);
}
.ctx li {
  padding: 6px 14px;
  cursor: pointer;
}
.ctx li:hover {
  background: var(--xx-bg-hover);
}
.ctx li.off {
  color: var(--xx-text-placeholder);
  pointer-events: none;
}
</style>
