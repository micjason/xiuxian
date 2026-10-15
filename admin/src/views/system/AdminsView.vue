<template>
  <div>
    <PageHeader title="管理员" desc="当前版本只有「管理员」这一种角色，所有登录的管理员权限相同；每个操作都会记入操作日志。" />
    <section class="xx-card">
      <el-descriptions :column="1" border>
        <el-descriptions-item label="当前登录">{{ name || "管理员" }}</el-descriptions-item>
        <el-descriptions-item label="角色">管理员（唯一角色，拥有全部权限）</el-descriptions-item>
        <el-descriptions-item label="审计">发布、玩家操作等都会写入「系统 / 操作日志」</el-descriptions-item>
        <el-descriptions-item label="账号管理">后端没有管理员列表、新增和改密接口（当前由部署配置提供账号）。需要多人使用时再新增，页面已预留这个位置。</el-descriptions-item>
      </el-descriptions>
      <div class="foot">
        <el-button @click="router.push('/system/audit')">查看操作日志</el-button>
        <el-button type="danger" plain @click="logout">退出登录</el-button>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
import { useRouter } from "vue-router";
import { adminName, clearSession } from "../../api";
import PageHeader from "../../components/PageHeader.vue";

const router = useRouter();
const name = adminName();

function logout(): void {
  clearSession();
  void router.push("/login");
}
</script>

<style scoped>
.foot {
  display: flex;
  gap: var(--xx-space-3);
  margin-top: var(--xx-space-4);
}
</style>
