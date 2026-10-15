<template>
  <div>
    <PageHeader title="版本历史" desc="每次发布都会留下一个不可修改的快照。可以对比任意两个版本（或版本与草稿），查看每次发布改了什么。">
      <template #actions><el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button></template>
    </PageHeader>

    <section class="xx-card block">
      <h2>版本对比</h2>
      <div class="compare">
        <el-select v-model="from" placeholder="起点（旧）" style="width: 200px"><el-option v-for="option in refOptions" :key="option.value" :label="option.label" :value="option.value" /></el-select>
        <span>→</span>
        <el-select v-model="to" placeholder="终点（新）" style="width: 200px"><el-option v-for="option in refOptions" :key="option.value" :label="option.label" :value="option.value" /></el-select>
        <el-button type="primary" :loading="diffing" :disabled="!from || !to || from === to" @click="compare">对比</el-button>
      </div>
      <p v-if="from && to && from === to" class="hint">请选择两个不同的版本。</p>
      <ChangeList v-if="diff" :diff="diff" empty-text="这两个版本之间没有差别" class="diff" />
    </section>

    <section class="block">
      <h2>历史版本（{{ versions.length }}）</h2>
      <DataState :loading="loading" :error="error" :has-data="versions.length > 0" empty-text="还没有发布过任何版本" @retry="load">
        <el-table :data="versions">
          <el-table-column label="版本" width="110">
            <template #default="{ row }"><strong>v{{ row.version }}</strong> <el-tag v-if="row.isCurrent" type="success" size="small" effect="light">线上</el-tag></template>
          </el-table-column>
          <el-table-column prop="note" label="发布说明" min-width="260" show-overflow-tooltip />
          <el-table-column label="发布时间" width="160"><template #default="{ row }">{{ formatTime(row.publishedAt) }}</template></el-table-column>
          <el-table-column label="发布人" width="110"><template #default="{ row }">{{ row.publishedBy ? "管理员" : "—" }}</template></el-table-column>
          <el-table-column label="校验和" width="120" class-name="mono"><template #default="{ row }">{{ String(row.checksum).slice(0, 10) }}</template></el-table-column>
          <el-table-column label="操作" prop="__a" width="110" fixed="right" align="right">
            <template #default="{ row }">
              <el-button link type="primary" @click="viewChanges(row)">本次改动</el-button>
            </template>
          </el-table-column>
        </el-table>
      </DataState>
    </section>

    <el-dialog v-model="changeOpen" :title="`版本 v${shown?.version} 的改动`" width="720px">
      <ChangeList v-if="shownDiff" :diff="shownDiff" empty-text="这个版本相对上一版没有字段变化" />
    </el-dialog>

  </div>
</template>

<script setup lang="ts">
import { Refresh } from "@element-plus/icons-vue";
import { ElMessage } from "element-plus";
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import ChangeList from "../../components/ChangeList.vue";
import PageHeader from "../../components/PageHeader.vue";
import type { DiffResult } from "../../composables/draftStatus";
import { formatTime } from "../../composables/format";

type Version = { version: number; checksum: string; note: string; publishedBy: string | null; publishedAt: string; sourceVersion: number | null; isCurrent: boolean };

const versions = ref<Version[]>([]);
const loading = ref(false);
const error = ref("");
const from = ref<string>("");
const to = ref<string>("");
const diff = ref<DiffResult | null>(null);
const diffing = ref(false);
const changeOpen = ref(false);
const shown = ref<Version | null>(null);
const shownDiff = ref<DiffResult | null>(null);

const refOptions = computed(() => [
  { label: "草稿（正在编辑）", value: "draft" },
  ...versions.value.map((row) => ({ label: `v${row.version}${row.isCurrent ? "（线上）" : ""}`, value: String(row.version) })),
]);

async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const result = await api<{ currentVersion: number | null; versions: Version[] }>("/admin/draft/versions");
    versions.value = result.versions;
    to.value ||= "draft";
    from.value ||= result.currentVersion ? String(result.currentVersion) : "";
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function diffUrl(a: string, b: string): string {
  return `/admin/draft/diff?from=${encodeURIComponent(a)}&to=${encodeURIComponent(b)}`;
}

async function compare(): Promise<void> {
  diffing.value = true;
  try {
    diff.value = await api<DiffResult>(diffUrl(from.value, to.value));
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "对比失败");
  } finally {
    diffing.value = false;
  }
}

async function viewChanges(row: Version): Promise<void> {
  shown.value = row;
  shownDiff.value = null;
  changeOpen.value = true;
  try {
    const index = versions.value.findIndex((item) => item.version === row.version);
    const prev = versions.value[index + 1];
    if (!prev) {
      ElMessage.info("这是最早的版本，没有更早的版本可比较");
      changeOpen.value = false;
      return;
    }
    shownDiff.value = await api<DiffResult>(diffUrl(String(prev.version), String(row.version)));
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  }
}

onMounted(load);
</script>

<style scoped>
.block {
  margin-bottom: var(--xx-space-4);
}
.block h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-lg);
}
.compare {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
}
.diff {
  margin-top: var(--xx-space-4);
}
.hint {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
</style>
