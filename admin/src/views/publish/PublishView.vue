<template>
  <div>
    <PageHeader title="内容体检" desc="开发阶段：配置页点保存后立刻对玩家生效，没有草稿态，也不用再点发布。本页只做配置体检，方便提前发现会卡住玩家的问题。正式上线后再恢复草稿/发布双轨。">
      <template #actions>
        <el-button :icon="Refresh" :loading="draft.loading" @click="refreshDraftStatus">重新检查</el-button>
      </template>
    </PageHeader>

    <el-alert type="success" :closable="false" show-icon class="banner" title="保存即生效（开发阶段）">
      <p>玩家读的是当前配置表（与后台编辑同一份数据）。客户端安装包仍走「客户端安装包」页单独发布。</p>
    </el-alert>

    <div class="status-row">
      <div class="xx-card tile">
        <span class="cap">内容快照版本</span>
        <strong class="big">{{ draft.contentVersion ?? "—" }}</strong>
        <span class="sub">可选历史快照；不阻挡玩家读当前配置</span>
      </div>
      <div class="xx-card tile" :class="{ bad: errors.length > 0 }">
        <span class="cap">体检</span>
        <strong class="big">{{ errors.length }} 个错误 · {{ warns.length }} 个提醒</strong>
      </div>
    </div>

    <section class="xx-card block">
      <header class="block-head"><h2>配置体检</h2></header>
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
    </section>
  </div>
</template>

<script setup lang="ts">
import { Refresh } from "@element-plus/icons-vue";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { computed, onMounted } from "vue";
import { useRouter } from "vue-router";
import PageHeader from "../../components/PageHeader.vue";
import { draft, refreshDraftStatus } from "../../composables/draftStatus";
import type { Problem } from "../../composables/healthCheck";

const router = useRouter();
const errors = computed(() => draft.problems.filter((row) => row.level === "error"));
const warns = computed(() => draft.problems.filter((row) => row.level === "warn"));

useRefetchOnActivate(refreshDraftStatus);
onMounted(refreshDraftStatus);
</script>

<style scoped>
.banner {
  margin-bottom: var(--xx-space-4);
}
.status-row {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: var(--xx-space-4);
  margin-bottom: var(--xx-space-4);
}
.tile {
  padding: var(--xx-space-4);
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.cap {
  color: var(--el-text-color-secondary);
  font-size: 13px;
}
.big {
  font-size: 22px;
}
.sub {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.block {
  padding: var(--xx-space-4);
}
.block-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: var(--xx-space-3);
}
.block-head h2 {
  margin: 0;
  font-size: 16px;
}
.warn {
  color: var(--el-color-warning);
  margin-top: var(--xx-space-3);
}
:deep(.row-error) {
  --el-table-tr-bg-color: var(--el-color-danger-light-9);
}
@media (max-width: 900px) {
  .status-row {
    grid-template-columns: 1fr;
  }
}
</style>
