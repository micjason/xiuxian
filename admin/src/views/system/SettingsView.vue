<template>
  <div>
    <PageHeader title="设置" desc="只影响当前浏览器，不影响游戏和其他管理员。" />
    <section class="xx-card">
      <el-form label-width="140px">
        <el-form-item label="深色模式"><el-switch v-model="dark" @change="applyTheme(dark)" /></el-form-item>
        <el-form-item label="全局搜索">按 Ctrl + K（Mac：⌘ + K）。</el-form-item>
      </el-form>
    </section>
  </div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import PageHeader from "../../components/PageHeader.vue";
import { applyTheme, isDark } from "../../theme";

const dark = ref(isDark());
</script>

