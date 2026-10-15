<template>
  <div>
    <PageHeader title="战斗公式与参数" desc="伤害、出手、战力权重、挑战与行囊参数都在这里；改动实时画出影响，保存后进入草稿，发布后玩家才生效。" />
    <el-tabs v-model="tab" class="tabs" @tab-change="onTab">
      <el-tab-pane label="公式与参数" name="formula"><FormulaTab /></el-tab-pane>
      <el-tab-pane label="试炼模拟（人偶）" name="sim" lazy><SimPanel /></el-tab-pane>
    </el-tabs>
  </div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import PageHeader from "../../components/PageHeader.vue";
import FormulaTab from "./combat/FormulaTab.vue";
import SimPanel from "./combat/SimPanel.vue";

const route = useRoute();
const router = useRouter();
const tab = ref(route.query.tab === "sim" ? "sim" : "formula");

function onTab(name: string | number): void {
  void router.replace({ query: { ...route.query, tab: String(name) } });
}
</script>

<style scoped>
.tabs :deep(.el-tabs__header) {
  margin-bottom: var(--xx-space-4);
}
</style>
