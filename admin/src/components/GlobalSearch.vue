<template>
  <el-dialog v-model="open" width="560px" :show-close="false" class="gs" align-center @opened="focus" @closed="query = ''">
    <el-input ref="input" v-model="query" size="large" clearable placeholder="搜索页面、玩家、境界、物品、技能、关卡……" :prefix-icon="Search" @keydown.down.prevent="move(1)" @keydown.up.prevent="move(-1)" @keydown.enter.prevent="go(results[active])" />
    <div v-if="results.length === 0" class="none">没有找到「{{ query }}」。试试页面名称或玩家账号。</div>
    <ul v-else class="list">
      <li v-for="(item, index) in results" :key="item.group + item.to" :class="{ on: index === active }" @mouseenter="active = index" @click="go(item)">
        <span class="g">{{ item.group }}</span>
        <span class="t">{{ item.title }}</span>
        <span v-if="item.sub" class="s">{{ item.sub }}</span>
      </li>
    </ul>
    <template #footer><span class="keys">↑↓ 选择 · Enter 打开 · Esc 关闭</span></template>
  </el-dialog>
</template>

<script setup lang="ts">
import { Search } from "@element-plus/icons-vue";
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { api } from "../api";
import { flatNav } from "../nav";

type Hit = { group: string; title: string; sub?: string; to: string };
type Named = { id?: string; code?: number; slug?: string; displayName?: string; name?: string; username?: string };

const open = defineModel<boolean>({ default: false });
const router = useRouter();
const query = ref("");
const active = ref(0);
const input = ref<{ focus: () => void } | null>(null);
const entities = ref<Hit[]>([]);
let loaded = false;

const pages: Hit[] = flatNav.map((item) => ({ group: "页面", title: item.label, sub: `${item.group} · ${item.desc}`, to: item.path }));
const haystack = new Map(flatNav.map((item) => [item.path, `${item.label} ${item.group} ${item.desc} ${item.keywords ?? ""}`.toLowerCase()]));

const results = computed<Hit[]>(() => {
  const text = query.value.trim().toLowerCase();
  if (!text) return pages.slice(0, 8);
  const hitPages = pages.filter((item) => haystack.get(item.to)?.includes(text));
  const hitEntities = entities.value.filter((item) => `${item.title} ${item.sub ?? ""}`.toLowerCase().includes(text));
  return [...hitPages, ...hitEntities.slice(0, 12)];
});
watch(results, () => (active.value = 0));

async function loadEntities(): Promise<void> {
  if (loaded) return;
  loaded = true;
  const sources: { path: string; group: string; to: (slug: string) => string }[] = [
    { path: "/admin/draft/realms", group: "境界", to: (slug) => `/config/realms?open=${encodeURIComponent(slug)}` },
    { path: "/admin/draft/items", group: "物品", to: (slug) => `/config/items?open=${encodeURIComponent(slug)}` },
    { path: "/admin/draft/skills", group: "技能", to: (slug) => `/config/skills?open=${encodeURIComponent(slug)}` },
    { path: "/admin/draft/stages", group: "关卡", to: (slug) => `/config/stages?open=${encodeURIComponent(slug)}` },
  ];
  const lists = await Promise.all([
    ...sources.map(async (source) => {
      try {
        const rows = await api<Named[]>(source.path);
        return rows.map((row): Hit => {
          const key = String(row.id ?? row.code ?? row.slug ?? "");
          return { group: source.group, title: row.displayName ?? row.name ?? key, sub: key, to: source.to(key) };
        });
      } catch {
        return [];
      }
    }),
    api<Named[]>("/admin/players")
      .then((rows) => rows.map((row): Hit => ({ group: "玩家", title: row.username ?? "", to: `/players?open=${encodeURIComponent(row.username ?? "")}` })))
      .catch(() => []),
  ]);
  entities.value = lists.flat();
}

function focus(): void {
  input.value?.focus();
  void loadEntities();
}
function move(step: number): void {
  if (results.value.length === 0) return;
  active.value = (active.value + step + results.value.length) % results.value.length;
}
function go(item: Hit | undefined): void {
  if (!item) return;
  open.value = false;
  void nextTick(() => router.push(item.to));
}

function onKey(event: KeyboardEvent): void {
  if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    open.value = !open.value;
  }
}
onMounted(() => window.addEventListener("keydown", onKey));
onBeforeUnmount(() => window.removeEventListener("keydown", onKey));
</script>

<style scoped>
.none {
  padding: var(--xx-space-5);
  color: var(--xx-text-secondary);
  text-align: center;
}
.list {
  max-height: 360px;
  margin: var(--xx-space-3) 0 0;
  padding: 0;
  overflow: auto;
  list-style: none;
}
.list li {
  display: flex;
  align-items: baseline;
  gap: var(--xx-space-3);
  padding: var(--xx-space-2) var(--xx-space-3);
  border-radius: var(--xx-radius-md);
  cursor: pointer;
}
.list li.on {
  background: var(--xx-bg-hover);
}
.g {
  min-width: 36px;
  color: var(--xx-jade-600);
  font-size: var(--xx-fs-xs);
}
.t {
  font-weight: 600;
}
.s {
  overflow: hidden;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  text-overflow: ellipsis;
  white-space: nowrap;
}
.keys {
  color: var(--xx-text-placeholder);
  font-size: var(--xx-fs-xs);
}
</style>
