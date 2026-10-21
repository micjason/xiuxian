<template>
  <el-dialog
    :model-value="state.open"
    class="xx-conflict"
    width="720px"
    append-to-body
    :z-index="4000"
    :close-on-click-modal="false"
    title="这条内容在你打开后被保存过"
    @update:model-value="(open: boolean) => !open && choose('cancel')"
  >
    <p class="lead">
      <strong v-if="state.title">{{ state.title }}</strong>
      在你打开之后<template v-if="state.details?.updatedBy">被「{{ state.details.updatedBy }}」</template>
      <template v-if="savedAt">于 {{ savedAt }}</template>保存过。直接保存会把那次的改动覆盖掉。
    </p>
    <ul class="hints">
      <li><b>重新读取</b>：丢掉你这次的改动，换成服务器上最新的内容。</li>
      <li><b>查看差异</b>：对比「服务器上现在的值」和「你要保存的值」。</li>
      <li><b>仍然覆盖</b>：用你的内容覆盖服务器上的。</li>
    </ul>
    <div v-if="showDiff" class="diff">
      <div v-if="diffLoading" class="muted">正在读取服务器上的最新内容…</div>
      <div v-else-if="diffError" class="muted">读不到最新内容：{{ diffError }}</div>
      <template v-else>
        <p v-if="rows.length === 0" class="muted">你要保存的字段和服务器上现在的完全一样（对方改的是你没动的部分）。可以放心「仍然覆盖」，或「重新读取」。</p>
        <el-table v-else :data="rows" size="small" max-height="300" class="diff-table">
          <el-table-column label="字段" min-width="200"><template #default="{ row }"><code>{{ label(row.path) }}</code></template></el-table-column>
          <el-table-column label="服务器上现在的值" min-width="180"><template #default="{ row }"><span class="server">{{ show(row.server) }}</span></template></el-table-column>
          <el-table-column label="你要保存的值" min-width="180"><template #default="{ row }"><span class="mine">{{ show(row.mine) }}</span></template></el-table-column>
        </el-table>
        <p v-if="rows.length" class="muted small">共 {{ rows.length }} 处不同。「仍然覆盖」后，服务器上的值会变成右边这一列。</p>
      </template>
    </div>
    <template #footer>
      <el-button @click="choose('cancel')">取消</el-button>
      <el-button @click="choose('reload')">重新读取</el-button>
      <el-button :type="showDiff ? 'default' : 'primary'" plain @click="openDiff">查看差异</el-button>
      <el-button type="warning" @click="choose('overwrite')">仍然覆盖</el-button>
    </template>
  </el-dialog>
</template>

<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { conflictRows, conflictState as state, type ConflictChoice } from "../composables/conflict";
import { fieldLabel } from "../schema/resources";

const showDiff = ref(false);
const diffLoading = ref(false);
const diffError = ref("");
const latest = ref<unknown>(undefined);

const savedAt = computed(() => {
  const raw = state.details?.updatedAt;
  if (!raw) return "";
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? "" : date.toLocaleString("zh-CN", { hour12: false });
});
const rows = computed(() => conflictRows(state.mine, latest.value));

watch(
  () => state.open,
  (open) => {
    if (open) {
      showDiff.value = false;
      latest.value = undefined;
      diffError.value = "";
    }
  },
);

async function openDiff(): Promise<void> {
  showDiff.value = true;
  if (latest.value !== undefined || !state.latest) {
    if (!state.latest) diffError.value = "这一页没有提供对比";
    return;
  }
  diffLoading.value = true;
  try {
    latest.value = await state.latest();
  } catch (cause) {
    diffError.value = cause instanceof Error ? cause.message : "读取失败";
  } finally {
    diffLoading.value = false;
  }
}

function choose(choice: ConflictChoice): void {
  state.resolve?.(choice);
}

function label(path: string): string {
  const [head, ...rest] = path.split(/(?=[.[])/);
  const name = fieldLabel(head ?? path);
  return rest.length ? `${name}${rest.join("")}` : name;
}

function show(value: unknown): string {
  if (value === undefined) return "（没有）";
  if (value === null || value === "") return "（空）";
  if (typeof value === "boolean") return value ? "是" : "否";
  if (typeof value === "object") return JSON.stringify(value);
  return String(value);
}
</script>

<style scoped>
.lead {
  margin: 0 0 8px;
  line-height: 1.7;
}
.hints {
  margin: 0 0 8px;
  padding-left: 18px;
  color: var(--xx-text-secondary);
  font-size: 13px;
  line-height: 1.8;
}
.diff {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px dashed var(--xx-border);
}
.server {
  color: var(--xx-text-secondary);
}
.mine {
  color: var(--xx-cinnabar-600, #b33);
  font-weight: 600;
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
code {
  font-size: 12px;
}
</style>
