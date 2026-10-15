<template>
  <div class="login">
    <el-card class="card" shadow="never">
      <div class="mark" aria-hidden="true">道</div>
      <h1>修仙后台</h1>
      <p class="sub">内容配置 · 数值调整 · 发布运营</p>
      <el-form label-position="top" @submit.prevent="submit">
        <el-form-item label="用户名">
          <el-input v-model="username" size="large" autocomplete="username" />
        </el-form-item>
        <el-form-item label="密码">
          <el-input v-model="password" type="password" size="large" show-password autocomplete="current-password" />
        </el-form-item>
        <el-button type="primary" size="large" native-type="submit" :loading="loading" class="submit">登录</el-button>
        <p v-if="error" class="error" role="alert">{{ error }}</p>
      </el-form>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref } from "vue";
import { useRouter } from "vue-router";
import { api, setSession } from "../api";

const router = useRouter();
const username = ref("");
const password = ref("");
const loading = ref(false);
const error = ref("");

async function submit(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const result = await api<{ token: string }>("/admin/auth/login", {
      method: "POST",
      body: JSON.stringify({ username: username.value, password: password.value }),
    });
    setSession(result.token, username.value);
    await router.push("/dashboard");
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "登录失败";
  } finally {
    loading.value = false;
  }
}
</script>

<style scoped>
.login {
  min-height: 100vh;
  display: grid;
  place-items: center;
  background:
    radial-gradient(ellipse at 20% 0%, color-mix(in srgb, var(--xx-jade-600) 14%, transparent), transparent 55%),
    radial-gradient(ellipse at 90% 100%, color-mix(in srgb, var(--xx-gold-500) 16%, transparent), transparent 50%),
    var(--xx-bg-page);
}
.card {
  width: 400px;
  max-width: calc(100vw - 32px);
  padding: var(--xx-space-4) var(--xx-space-3);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-lg);
  box-shadow: var(--xx-shadow-pop);
}
.mark {
  display: grid;
  place-items: center;
  width: 56px;
  height: 56px;
  margin: 0 auto var(--xx-space-3);
  border: 2px solid var(--xx-gold-500);
  border-radius: 50%;
  color: var(--xx-gold-500);
  font-family: var(--xx-font-serif);
  font-size: 30px;
  font-weight: 700;
}
h1 {
  margin: 0;
  text-align: center;
  font-family: var(--xx-font-serif);
  font-size: var(--xx-fs-xl);
  letter-spacing: 0.2em;
}
.sub {
  margin: var(--xx-space-1) 0 var(--xx-space-5);
  text-align: center;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.submit {
  width: 100%;
  margin-top: var(--xx-space-2);
}
.error {
  margin: var(--xx-space-3) 0 0;
  padding: var(--xx-space-2) var(--xx-space-3);
  border-radius: var(--xx-radius-md);
  background: var(--xx-danger-bg);
  color: var(--xx-danger);
  font-size: var(--xx-fs-sm);
}
</style>
