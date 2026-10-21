<template>
  <el-container class="shell">
    <el-aside class="side" :width="collapsed ? '64px' : 'var(--xx-side-width)'">
      <div class="brand" @click="router.push('/dashboard')">
        <span class="brand-seal" aria-hidden="true">道</span>
        <span v-if="!collapsed" class="brand-text"><strong>修仙后台</strong><small>内容与运营管理</small></span>
      </div>
      <el-menu class="nav" :default-active="activePath" :collapse="collapsed" :collapse-transition="false" :default-openeds="openGroups" router>
        <el-sub-menu v-for="group in navTree" :key="group.key" :index="group.key">
          <template #title>
            <el-icon><component :is="icons[group.icon]" /></el-icon>
            <span>{{ group.title }}</span>
          </template>
          <el-menu-item v-for="item in group.items" :key="item.path" :index="item.path">
            <span>{{ item.label }}</span>
            <em v-if="item.isNew" class="new-tag">新</em>
          </el-menu-item>
        </el-sub-menu>
      </el-menu>
      <div v-if="!collapsed" class="planned" aria-label="后续阶段规划，暂不可用">
        <span class="planned-title">后续阶段（暂未开发）</span>
        <span v-for="item in plannedFeatures" :key="item.label" class="planned-item">{{ item.label }}<em>{{ item.phase }} 期</em></span>
      </div>
      <div class="side-foot"><el-button link class="collapse" @click="collapsed = !collapsed">{{ collapsed ? "展开" : "收起菜单" }}</el-button></div>
    </el-aside>

    <el-container class="body">
      <el-header class="header">
        <!-- 面包屑只按菜单层级生成；每一级都能点（一级跳组首页，二级跳列表页），最后一级是当前页 -->
        <nav class="crumb" aria-label="面包屑">
          <template v-if="current">
            <router-link class="crumb-link" :to="groupHome(current.group) ?? current.path">{{ current.group }}</router-link>
            <span class="sep">/</span>
            <router-link v-if="crumbTail" class="crumb-link" :to="current.path">{{ current.label }}</router-link>
            <strong v-else class="crumb-here">{{ current.label }}</strong>
            <template v-if="crumbTail">
              <span class="sep">/</span>
              <strong class="crumb-here">{{ crumbTail }}</strong>
            </template>
          </template>
        </nav>
        <div class="tools">
          <el-button class="search-btn" @click="searchOpen = true"><el-icon><Search /></el-icon><span>搜索</span><kbd>Ctrl K</kbd></el-button>
          <el-tooltip :content="draftTip" placement="bottom">
            <el-button :type="draft.changes > 0 || errorCount > 0 ? 'warning' : 'default'" plain :loading="draft.loading && !draft.loaded" @click="router.push('/publish')">
              <template v-if="errorCount > 0">{{ errorCount }} 个配置错误</template>
              <template v-else-if="draft.diffAvailable && draft.changes > 0">{{ draft.changes }} 项未发布</template>
              <template v-else>草稿已同步</template>
            </el-button>
          </el-tooltip>
          <el-dropdown trigger="click" @command="onCommand">
            <span class="who">{{ name || "管理员" }}<el-icon><ArrowDown /></el-icon></span>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item command="theme">{{ dark ? "切换浅色模式" : "切换深色模式" }}</el-dropdown-item>
                <el-dropdown-item command="settings">设置</el-dropdown-item>
                <el-dropdown-item command="logout" divided>退出登录</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>
      </el-header>
      <TabsBar :active-path="activePath" />
      <el-main ref="mainRef" class="app-main">
        <div class="content">
          <router-view v-slot="{ Component, route: viewRoute }">
            <keep-alive :include="cachedNames" :max="16">
              <component :is="wrap(Component, viewRoute.path)" v-if="Component && refreshingPath !== viewRoute.path" :key="viewRoute.path" />
            </keep-alive>
          </router-view>
        </div>
      </el-main>
    </el-container>
    <GlobalSearch v-model="searchOpen" />
  </el-container>
</template>

<script setup lang="ts">
import { ArrowDown, Odometer, Present, Promotion, Search, Setting, SetUp, User } from "@element-plus/icons-vue";
import { computed, defineComponent, h, markRaw, nextTick, onActivated, onBeforeUnmount, onMounted, ref, watch, type Component as VueComponent, type VNode } from "vue";
import { useRoute, useRouter } from "vue-router";
import TabsBar from "../components/TabsBar.vue";
import { tailFor } from "../composables/crumbs";
import { cachedNames, openTab, refreshingPath } from "../composables/tabs";
import { adminName, clearSession } from "../api";
import GlobalSearch from "../components/GlobalSearch.vue";
import { draft, refreshDraftStatus } from "../composables/draftStatus";
import { groupHome, navOf, navTree, plannedFeatures } from "../nav";
import { applyTheme, isDark } from "../theme";

const icons: Record<string, unknown> = { Odometer, User, SetUp, Promotion, Present, Setting };
const route = useRoute();
const router = useRouter();
const name = adminName();
const dark = ref(isDark());
const collapsed = ref(false);
const searchOpen = ref(false);
const openGroups = navTree.map((group) => group.key);

const current = computed(() => navOf(route.path));
const crumbTail = computed(() => tailFor(route.path));

// 每个页签记住自己的滚动位置：离开前记下内容区 scrollTop，切回来（onActivated）再滚回去。
// 内容区是 el-main 自己滚（不是整页），所以 keep-alive 本身不会保留滚动，要手动存取。
const mainRef = ref<{ $el: HTMLElement } | null>(null);
const scrollPos = new Map<string, number>();
const scroller = (): HTMLElement | null => mainRef.value?.$el ?? null;
const stopScrollGuard = router.beforeEach((to, from) => {
  const el = scroller();
  if (el && to.path !== from.path) scrollPos.set(from.path, el.scrollTop);
});
onBeforeUnmount(stopScrollGuard);
function restoreScroll(path: string): void {
  const target = scrollPos.get(path) ?? 0;
  let tries = 0;
  // 页面可能还在重新读取数据、高度不够，最多重试约 1 秒直到滚到位
  const step = (): void => {
    const el = scroller();
    if (!el) return;
    el.scrollTop = target;
    if (Math.abs(el.scrollTop - target) > 1 && tries++ < 60) requestAnimationFrame(step);
  };
  void nextTick(step);
}

// 每个页面包一层按路径命名的组件，<keep-alive :include> 才能按标签缓存 / 释放
const wrappers = new Map<string, VueComponent>();
function wrap(view: VNode, path: string): VueComponent {
  let wrapper = wrappers.get(path);
  if (!wrapper || (wrapper as { __inner?: unknown }).__inner !== view.type) {
    const inner = view.type as VueComponent;
    wrapper = markRaw(
      Object.assign(
        defineComponent({
          name: path,
          setup: () => {
            onActivated(() => restoreScroll(path));
            return () => h(inner);
          },
        }),
        { __inner: inner },
      ),
    );
    wrappers.set(path, wrapper);
  }
  return wrapper;
}

watch(
  () => route.fullPath,
  () => openTab(route.path, route.fullPath),
  { immediate: true },
);
const activePath = computed(() => current.value?.path ?? route.path);
const errorCount = computed(() => draft.problems.filter((item) => item.level === "error").length);
const draftTip = computed(() => `线上内容版本：${draft.contentVersion ?? "未发布"}。点击进入发布中心。`);

function onCommand(command: string): void {
  if (command === "theme") {
    dark.value = !dark.value;
    applyTheme(dark.value);
  } else if (command === "settings") {
    void router.push("/system/settings");
  } else {
    clearSession();
    void router.push("/login");
  }
}

onMounted(() => void refreshDraftStatus());
</script>

<style scoped>
/* 整页不滚：左侧菜单固定在视口里（菜单项多了在菜单内部滚），右侧只有内容区自己滚动。 */
.shell {
  height: 100vh;
  overflow: hidden;
}
.side {
  display: flex;
  flex-direction: column;
  height: 100vh;
  overflow: hidden;
  background: var(--xx-side-bg);
  color: var(--xx-side-text);
  transition: width 0.15s;
}
.brand {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  height: var(--xx-header-height);
  padding: 0 var(--xx-space-4);
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  cursor: pointer;
}
.brand-seal {
  display: grid;
  flex: none;
  place-items: center;
  width: 32px;
  height: 32px;
  border: 1.5px solid var(--xx-gold-300);
  border-radius: 50%;
  color: var(--xx-gold-300);
  font-family: var(--xx-font-serif);
  font-size: 18px;
  font-weight: 700;
}
.brand-text {
  display: grid;
  line-height: 1.25;
}
.brand-text strong {
  color: var(--xx-side-text);
  font-family: var(--xx-font-serif);
  font-size: var(--xx-fs-md);
  letter-spacing: 0.12em;
}
.brand-text small {
  color: var(--xx-side-muted);
  font-size: var(--xx-fs-xs);
}
.nav {
  flex: 1;
  min-height: 0;
  padding: var(--xx-space-2);
  overflow-y: auto;
  border-right: 0;
  background: transparent;
  --el-menu-bg-color: transparent;
  --el-menu-text-color: var(--xx-side-text);
  --el-menu-hover-bg-color: var(--xx-side-hover);
  --el-menu-active-color: var(--xx-side-active-text);
  --el-menu-item-height: 40px;
  --el-menu-sub-item-height: 38px;
}
.nav :deep(.el-sub-menu__title) {
  height: 42px;
  border-radius: var(--xx-radius-md);
  color: var(--xx-side-muted);
  font-size: var(--xx-fs-sm);
  letter-spacing: 0.1em;
}
.nav :deep(.el-sub-menu__title:hover) {
  background: var(--xx-side-hover);
}
.nav :deep(.el-menu-item) {
  margin: 2px 0;
  border-radius: var(--xx-radius-md);
  font-size: var(--xx-fs-base);
}
.nav :deep(.el-sub-menu .el-menu-item) {
  padding-left: 48px !important;
}
.nav :deep(.el-menu-item.is-active) {
  background: var(--xx-side-active-bg);
  box-shadow: inset 3px 0 0 var(--xx-gold-300);
  font-weight: 600;
}
.planned {
  display: grid;
  gap: 4px;
  margin-top: auto;
  padding: var(--xx-space-3) var(--xx-space-4);
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  color: var(--xx-side-muted);
  font-size: var(--xx-fs-sm);
  cursor: default;
  user-select: none;
}
.planned-title {
  margin-bottom: 2px;
  font-size: 12px;
  letter-spacing: 0.08em;
  opacity: 0.75;
}
.planned-item {
  display: flex;
  justify-content: space-between;
  opacity: 0.55;
}
.planned-item em {
  font-style: normal;
  font-size: 12px;
}
.side-foot {
  padding: var(--xx-space-2) var(--xx-space-3);
  border-top: 1px solid rgba(255, 255, 255, 0.08);
}
.collapse {
  color: var(--xx-side-muted);
}
.body {
  min-width: 0;
  height: 100vh;
  overflow: hidden;
}
.app-main {
  min-height: 0;
  overflow-y: auto;
  overscroll-behavior: contain;
}
.header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: var(--xx-header-height);
  padding: 0 var(--xx-space-5);
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-surface);
}
.crumb {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: var(--xx-fs-base);
}
.crumb-link {
  color: var(--xx-text-secondary);
  text-decoration: none;
}
.crumb-link:hover {
  color: var(--xx-jade-600);
  text-decoration: underline;
}
.crumb-here {
  color: var(--xx-text-primary);
}
.sep {
  color: var(--xx-text-placeholder);
}
.new-tag {
  margin-left: 6px;
  padding: 0 5px;
  border-radius: 3px;
  background: var(--xx-cinnabar-600);
  color: #fff;
  font-size: 11px;
  font-style: normal;
  line-height: 16px;
}
.tools {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
}
.search-btn {
  min-width: 190px;
  justify-content: flex-start;
  color: var(--xx-text-secondary);
}
.search-btn kbd {
  margin-left: auto;
  padding: 0 6px;
  border: 1px solid var(--xx-border-strong);
  border-radius: 4px;
  font-family: var(--xx-font-mono);
  font-size: 11px;
}
.who {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: var(--xx-text-regular);
  cursor: pointer;
}
</style>
