<template>
  <el-container class="shell">
    <el-aside width="200px">
      <div class="brand">修仙后台</div>
      <el-menu :default-active="route.path" router>
        <el-menu-item index="/rules">规则</el-menu-item>
        <el-menu-item index="/realms">境界</el-menu-item>
        <el-menu-item index="/stages">关卡</el-menu-item>
        <el-menu-item index="/puppets">人偶</el-menu-item>
        <el-menu-item index="/weapons">装备</el-menu-item>
        <el-menu-item index="/items">物品</el-menu-item>
        <el-menu-item index="/skills">技能</el-menu-item>
        <el-menu-item index="/buildings">洞府</el-menu-item>
        <el-menu-item index="/publish">发布</el-menu-item>
        <el-menu-item index="/releases">版本更新</el-menu-item>
        <el-menu-item index="/announcements">公告</el-menu-item>
        <el-menu-item index="/popups">弹窗</el-menu-item>
        <el-menu-item index="/players">用户</el-menu-item>
        <el-menu-item index="/operations">操作记录</el-menu-item>
      </el-menu>
    </el-aside>
    <el-container>
      <el-header class="header">
        <span>{{ name }}</span>
        <el-button link type="primary" @click="logout">退出</el-button>
      </el-header>
      <el-main>
        <router-view />
      </el-main>
    </el-container>
  </el-container>
</template>

<script setup lang="ts">
import { useRoute, useRouter } from "vue-router";
import { adminName, clearSession } from "../api";

const route = useRoute();
const router = useRouter();
const name = adminName();

function logout(): void {
  clearSession();
  void router.push("/login");
}
</script>

<style scoped>
.shell {
  min-height: 100vh;
}
.brand {
  height: 56px;
  line-height: 56px;
  padding: 0 20px;
  font-weight: 600;
}
.header {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  border-bottom: 1px solid var(--el-border-color);
}
</style>
