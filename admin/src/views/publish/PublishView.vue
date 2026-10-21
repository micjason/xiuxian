<template>
  <div>
    <PageHeader title="草稿与发布" desc="发布前先体检、再看改动清单、最后确认。玩家读的是已发布的版本；草稿里的改动发布后才算数。">
      <template #actions>
        <el-button :icon="Refresh" :loading="draft.loading" @click="refreshDraftStatus">重新检查</el-button>
      </template>
    </PageHeader>

    <div class="status-row">
      <div class="xx-card tile">
        <span class="cap">线上内容版本</span>
        <strong class="big">{{ draft.contentVersion ?? "还没有发布" }}</strong>
      </div>
      <div class="xx-card tile">
        <span class="cap">待发布改动</span>
        <strong class="big">{{ draft.diffAvailable ? draft.changes : "未知" }}</strong>
        <span v-if="!draft.diffAvailable" class="sub">后端未提供变更清单接口</span>
      </div>
      <div class="xx-card tile" :class="{ bad: errors.length > 0 }">
        <span class="cap">体检</span>
        <strong class="big">{{ errors.length }} 个错误 · {{ warns.length }} 个提醒</strong>
      </div>
    </div>

    <el-steps :active="step" finish-status="success" align-center class="steps">
      <el-step title="① 体检" description="发现会让玩家卡住的问题" />
      <el-step title="② 改动清单" description="确认这次要发布什么" />
      <el-step title="③ 发布" description="填写说明并确认" />
    </el-steps>

    <section class="xx-card block">
      <header class="block-head">
        <h2>① 体检</h2>
        <el-button v-if="step !== 0" link type="primary" @click="step = 0">回到这一步</el-button>
      </header>
      <el-result v-if="draft.problems.length === 0 && draft.loaded" icon="success" title="没有发现问题" sub-title="境界、关卡、技能和战斗参数都已填写完整。" />
      <el-table v-else :data="draft.problems" size="small" :row-class-name="({ row }: { row: Problem }) => (row.level === 'error' ? 'row-error' : '')">
        <el-table-column label="级别" width="80">
          <template #default="{ row }"><el-tag :type="row.level === 'error' ? 'danger' : 'warning'" effect="light" size="small">{{ row.level === "error" ? "错误" : "提醒" }}</el-tag></template>
        </el-table-column>
        <el-table-column prop="area" label="位置" width="110" />
        <el-table-column prop="message" label="问题" min-width="320" />
        <el-table-column label="" width="90" align="right">
          <template #default="{ row }"><el-button link type="primary" @click="router.push(row.to)">去修改</el-button></template>
        </el-table-column>
      </el-table>
      <p v-if="draft.error" class="warn">{{ draft.error }}</p>
      <footer class="foot">
        <el-button type="primary" @click="step = 1">{{ errors.length > 0 ? "仍然继续查看改动" : "下一步：查看改动" }}</el-button>
        <span v-if="errors.length > 0" class="warn">有错误时，服务器会拒绝发布；建议先修改。</span>
      </footer>
    </section>

    <section v-if="step >= 1" class="xx-card block">
      <header class="block-head"><h2>② 改动清单（当前线上版本 → 草稿）</h2></header>
      <el-alert v-if="!draft.diffAvailable" type="warning" :closable="false" show-icon title="后端还没有提供改动清单接口（GET /admin/draft/diff），无法列出具体改动。仍可发布，但请先自行确认。" />
      <ChangeList v-else-if="draft.diff" :diff="draft.diff" empty-text="草稿和线上版本完全一致，不需要发布。" />
      <footer class="foot">
        <el-button @click="step = 0">上一步</el-button>
        <el-button type="primary" @click="step = 2">下一步：填写发布说明</el-button>
      </footer>
    </section>

    <section v-if="step >= 2" class="xx-card block">
      <header class="block-head"><h2>③ 发布</h2></header>
      <el-form label-position="top" class="pub-form">
        <el-form-item label="发布说明（必填，会记入版本历史）" :error="noteError">
          <el-input v-model="note" type="textarea" :rows="3" maxlength="200" show-word-limit placeholder="例如：把炼气期三个境界的修炼速度调到 2/秒" @input="noteError = ''" />
        </el-form-item>
      </el-form>
      <p v-if="rejected.length > 0" class="warn">发布被服务器拒绝：</p>
      <ul v-if="rejected.length > 0" class="rejected"><li v-for="item in rejected" :key="item">{{ item }}</li></ul>
      <footer class="foot">
        <el-button @click="step = 1">上一步</el-button>
        <el-button type="primary" :loading="publishing" @click="publish">发布版本 {{ (draft.contentVersion ?? 0) + 1 }}</el-button>
      </footer>
    </section>
  </div>
</template>

<script setup lang="ts">
import { Refresh } from "@element-plus/icons-vue";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { ElMessage } from "element-plus";
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import { ApiError, api } from "../../api";
import ChangeList from "../../components/ChangeList.vue";
import PageHeader from "../../components/PageHeader.vue";
import { confirmAction } from "../../composables/confirm";
import { draft, refreshDraftStatus } from "../../composables/draftStatus";
import type { Problem } from "../../composables/healthCheck";

const router = useRouter();
const step = ref(0);
const note = ref("");
const noteError = ref("");
const publishing = ref(false);
const rejected = ref<string[]>([]);

const errors = computed(() => draft.problems.filter((row) => row.level === "error"));
const warns = computed(() => draft.problems.filter((row) => row.level === "warn"));

async function publish(): Promise<void> {
  if (!note.value.trim()) {
    noteError.value = "请填写发布说明";
    return;
  }
  const count = draft.diffAvailable ? `${draft.changes} 项改动` : "当前草稿";
  const ok = await confirmAction(`确认把${count}发布为版本 ${(draft.contentVersion ?? 0) + 1}？发布后玩家会读取新版本，发布记录会写入操作日志。`, "确认发布", "确认发布");
  if (!ok) return;
  publishing.value = true;
  rejected.value = [];
  try {
    const result = await api<{ version: number }>("/admin/draft/publish", { method: "POST", body: JSON.stringify({ note: note.value.trim() }) });
    ElMessage.success(`已发布版本 ${result.version}`);
    note.value = "";
    step.value = 0;
    await refreshDraftStatus();
  } catch (cause) {
    if (cause instanceof ApiError && Array.isArray((cause.details as { errors?: unknown[] } | undefined)?.errors)) {
      rejected.value = ((cause.details as { errors: { message?: string; kind?: string; slug?: string }[] }).errors).map((item) => item.message ?? `${item.kind} ${item.slug}`);
    }
    ElMessage.error(cause instanceof Error ? cause.message : "发布失败");
  } finally {
    publishing.value = false;
  }
}

useRefetchOnActivate(refreshDraftStatus);
onMounted(refreshDraftStatus);
</script>

<style scoped>
.status-row {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: var(--xx-space-4);
  margin-bottom: var(--xx-space-4);
}
.tile {
  display: grid;
  gap: 2px;
}
.tile.bad {
  border-color: var(--xx-danger);
}
.cap,
.sub {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.big {
  font-family: var(--xx-font-serif);
  font-size: var(--xx-fs-xl);
}
.steps {
  margin: var(--xx-space-5) 0;
}
.block {
  margin-bottom: var(--xx-space-4);
}
.block-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.block h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-lg);
}
.foot {
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  margin-top: var(--xx-space-4);
}
.warn {
  color: var(--xx-warning);
  font-size: var(--xx-fs-sm);
}
.rejected {
  color: var(--xx-danger);
}
.pub-form {
  max-width: 640px;
}
:deep(.row-error td) {
  background: var(--xx-danger-bg) !important;
}
</style>
