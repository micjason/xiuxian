<template>
  <div>
    <PageHeader title="运营概览" :desc="`你好，${name || '管理员'}。这里是今天需要关心的事。`">
      <template #actions><el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button></template>
    </PageHeader>

    <div class="tiles">
      <router-link to="/publish/versions" class="xx-card tile">
        <span class="cap">线上内容版本</span>
        <strong class="big">{{ draft.contentVersion === null ? "未发布" : `v${draft.contentVersion}` }}</strong>
      </router-link>
      <router-link to="/publish" class="xx-card tile" :class="{ warn: draft.changes > 0 }">
        <span class="cap">待发布改动</span>
        <strong class="big">{{ draft.diffAvailable ? draft.changes : "—" }}</strong>
      </router-link>
      <router-link to="/publish" class="xx-card tile" :class="{ bad: errorCount > 0 }">
        <span class="cap">配置体检</span>
        <strong class="big">{{ errorCount }} 错误 / {{ warnCount }} 提醒</strong>
      </router-link>
      <router-link to="/players" class="xx-card tile">
        <span class="cap">玩家总数</span>
        <strong class="big">{{ players === null ? "—" : players.length }}</strong>
      </router-link>
      <router-link to="/publish/client" class="xx-card tile">
        <span class="cap">当前客户端</span>
        <strong class="big">{{ currentRelease ? currentRelease.versionName : "未上传" }}</strong>
      </router-link>
    </div>

    <div class="cols">
      <section class="xx-card">
        <h2>待办</h2>
        <DataState :loading="loading && !draft.loaded" :error="''" :has-data="todos.length > 0" empty-text="没有待办，一切正常。">
          <ul class="todos">
            <li v-for="todo in todos" :key="todo.text" :class="todo.level">
              <el-tag :type="todo.level === 'error' ? 'danger' : todo.level === 'warn' ? 'warning' : 'info'" effect="light" size="small">{{ todo.tag }}</el-tag>
              <span class="text">{{ todo.text }}</span>
              <el-button link type="primary" @click="router.push(todo.to)">{{ todo.action }}</el-button>
            </li>
          </ul>
        </DataState>
      </section>

      <section class="xx-card">
        <h2>玩家境界分布</h2>
        <DataState :loading="loading" :error="playersError" :has-data="distribution.length > 0" empty-text="还没有玩家">
          <div v-for="item in distribution" :key="item.name" class="bar-row">
            <span class="bar-name">{{ item.name }}</span>
            <span class="bar"><i :style="{ width: `${(item.count / maxCount) * 100}%` }" /></span>
            <span class="bar-count">{{ item.count }}</span>
          </div>
        </DataState>
      </section>
    </div>

    <div class="cols">
      <section class="xx-card">
        <header class="head"><h2>最近 24 小时操作</h2><el-button link type="primary" @click="router.push('/system/audit')">全部日志</el-button></header>
        <DataState :loading="loading" :error="opsError" :has-data="ops.length > 0" empty-text="最近 24 小时没有操作记录">
          <el-table :data="ops.slice(0, 8)" size="small">
            <el-table-column label="时间" width="150"><template #default="{ row }">{{ relativeTime(row.at) }}</template></el-table-column>
            <el-table-column prop="actorName" label="谁" min-width="120" show-overflow-tooltip />
            <el-table-column label="动作" width="100"><template #default="{ row }">{{ actionText(row.action) }}</template></el-table-column>
            <el-table-column label="结果" min-width="80"><template #default="{ row }">{{ row.result === "success" ? "成功" : row.result }}</template></el-table-column>
          </el-table>
        </DataState>
      </section>

      <section class="xx-card">
        <h2>快捷入口</h2>
        <div class="quick">
          <el-button v-for="item in quick" :key="item.to" @click="router.push(item.to)">{{ item.label }}</el-button>
        </div>
        <p class="tip">按 <kbd>Ctrl</kbd>+<kbd>K</kbd> 可以搜索任意页面、玩家、物品或关卡。</p>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { Refresh } from "@element-plus/icons-vue";
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { adminName, api } from "../../api";
import DataState from "../../components/DataState.vue";
import PageHeader from "../../components/PageHeader.vue";
import { draft, refreshDraftStatus } from "../../composables/draftStatus";
import { relativeTime } from "../../composables/format";
import { actionText } from "../../composables/lookups";

type Player = { username: string; realmName: string; power: number | null };
type Release = { versionName: string; isCurrent: boolean };
type Op = { at: string; actorName: string; action: string; result: string };

const router = useRouter();
const name = adminName();
const loading = ref(false);
const players = ref<Player[] | null>(null);
const playersError = ref("");
const releases = ref<Release[]>([]);
const announcements = ref<{ enabled: boolean }[] | null>(null);
const ops = ref<Op[]>([]);
const opsError = ref("");

const errorCount = computed(() => draft.problems.filter((item) => item.level === "error").length);
const warnCount = computed(() => draft.problems.filter((item) => item.level === "warn").length);
const currentRelease = computed(() => releases.value.find((item) => item.isCurrent) ?? null);

const distribution = computed(() => {
  const map = new Map<string, number>();
  for (const player of players.value ?? []) map.set(player.realmName, (map.get(player.realmName) ?? 0) + 1);
  return [...map.entries()].map(([realm, count]) => ({ name: realm, count })).sort((a, b) => b.count - a.count).slice(0, 8);
});
const maxCount = computed(() => Math.max(1, ...distribution.value.map((item) => item.count)));

type Todo = { level: "error" | "warn" | "info"; tag: string; text: string; action: string; to: string };
const todos = computed<Todo[]>(() => {
  const list: Todo[] = [];
  for (const problem of draft.problems.filter((item) => item.level === "error").slice(0, 3)) {
    list.push({ level: "error", tag: "错误", text: problem.message, action: "去修改", to: problem.to });
  }
  if (draft.diffAvailable && draft.changes > 0) {
    list.push({ level: "warn", tag: "待发布", text: `草稿里有 ${draft.changes} 项改动还没有发布`, action: "去发布", to: "/publish" });
  }
  const broken = (players.value ?? []).filter((item) => item.power === null).length;
  if (broken > 0) list.push({ level: "warn", tag: "玩家", text: `${broken} 名玩家的战力算不出来`, action: "查看", to: "/players" });
  if (announcements.value && !announcements.value.some((item) => item.enabled)) {
    list.push({ level: "info", tag: "运营", text: "当前没有启用的公告", action: "去新增", to: "/ops/announcements" });
  }
  if (releases.value.length === 0) list.push({ level: "info", tag: "客户端", text: "还没有上传过安装包", action: "去上传", to: "/publish/client" });
  if (draft.contentVersion === null) list.push({ level: "warn", tag: "发布", text: "内容还没有发布过，玩家读不到配置", action: "去发布", to: "/publish" });
  return list;
});

const quick = [
  { label: "调整境界", to: "/config/realms" },
  { label: "配置掉落", to: "/config/stages" },
  { label: "调战斗公式", to: "/config/combat" },
  { label: "发布内容", to: "/publish" },
  { label: "上传安装包", to: "/publish/client" },
  { label: "查看玩家", to: "/players" },
];

async function safe<T>(call: () => Promise<T>, onError?: (message: string) => void): Promise<T | null> {
  try {
    return await call();
  } catch (cause) {
    onError?.(cause instanceof Error ? cause.message : "加载失败");
    return null;
  }
}

async function load(): Promise<void> {
  loading.value = true;
  const now = new Date();
  const params = new URLSearchParams({ from: new Date(now.getTime() - 86400_000).toISOString(), to: now.toISOString() });
  const [, list, rel, ann, log] = await Promise.all([
    refreshDraftStatus(),
    safe(() => api<Player[]>("/admin/players"), (m) => (playersError.value = m)),
    safe(() => api<Release[]>("/admin/releases")),
    safe(() => api<{ enabled: boolean }[]>("/admin/announcements")),
    safe(() => api<Op[]>(`/admin/operations?${params.toString()}`), (m) => (opsError.value = m)),
  ]);
  players.value = list;
  releases.value = rel ?? [];
  announcements.value = ann;
  ops.value = log ?? [];
  loading.value = false;
}

onMounted(load);
</script>

<style scoped>
.tiles {
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: var(--xx-space-4);
  margin-bottom: var(--xx-space-4);
}
.tile {
  display: grid;
  gap: 4px;
  color: inherit;
  text-decoration: none;
  transition: border-color 0.15s;
}
.tile:hover {
  border-color: var(--xx-jade-500);
}
.tile.warn {
  border-color: var(--xx-warning);
}
.tile.bad {
  border-color: var(--xx-danger);
}
.cap {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.big {
  font-family: var(--xx-font-serif);
  font-size: var(--xx-fs-lg);
}
.cols {
  display: grid;
  grid-template-columns: 3fr 2fr;
  gap: var(--xx-space-4);
  margin-bottom: var(--xx-space-4);
}
.cols h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-md);
}
.head {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
}
.todos {
  margin: 0;
  padding: 0;
  list-style: none;
}
.todos li {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  padding: var(--xx-space-2) 0;
  border-bottom: 1px dashed var(--xx-border);
}
.todos .text {
  flex: 1;
}
.bar-row {
  display: grid;
  grid-template-columns: 110px 1fr 36px;
  align-items: center;
  gap: var(--xx-space-2);
  margin-bottom: var(--xx-space-2);
  font-size: var(--xx-fs-sm);
}
.bar {
  height: 10px;
  border-radius: 5px;
  background: var(--xx-bg-subtle);
}
.bar i {
  display: block;
  height: 100%;
  border-radius: 5px;
  background: var(--xx-jade-600);
}
.bar-count {
  text-align: right;
}
.quick {
  display: flex;
  flex-wrap: wrap;
  gap: var(--xx-space-2);
}
.tip {
  margin-top: var(--xx-space-4);
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
kbd {
  padding: 1px 6px;
  border: 1px solid var(--xx-border-strong);
  border-radius: 4px;
  background: var(--xx-bg-subtle);
  font-family: var(--xx-font-mono);
  font-size: 12px;
}
</style>
