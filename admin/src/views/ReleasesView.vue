<template>
  <div>
    <h2>版本更新</h2>
    <el-form label-width="120px" class="form">
      <el-form-item label="安装包">
        <input type="file" accept=".apk" @change="onFile" />
      </el-form-item>
      <el-form-item label="版本名称">
        <el-input v-model="versionName" placeholder="0.6.4" />
      </el-form-item>
      <el-form-item label="版本号">
        <el-input-number v-model="versionCode" :min="1" :step="1" />
      </el-form-item>
      <el-form-item label="更新说明">
        <el-input v-model="releaseNotes" type="textarea" />
      </el-form-item>
      <el-form-item label="强制更新">
        <el-switch v-model="forceUpdate" />
      </el-form-item>
      <el-button type="primary" :loading="uploading" @click="upload">上传并设为当前版本</el-button>
    </el-form>
    <el-table :data="rows">
      <el-table-column prop="versionName" label="版本名称" />
      <el-table-column prop="versionCode" label="版本号" />
      <el-table-column prop="forceUpdate" label="强制" />
      <el-table-column prop="isCurrent" label="当前" />
      <el-table-column prop="sha256" label="SHA-256" />
    </el-table>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, ref } from "vue";
import { api, getToken } from "../api";

type ReleaseRow = {
  versionName: string;
  versionCode: number;
  forceUpdate: boolean;
  isCurrent: boolean;
  sha256: string;
};

const rows = ref<ReleaseRow[]>([]);
const versionName = ref("");
const versionCode = ref(1);
const releaseNotes = ref("");
const forceUpdate = ref(false);
const file = ref<File | null>(null);
const uploading = ref(false);

function onFile(event: Event): void {
  const input = event.target as HTMLInputElement;
  file.value = input.files?.[0] ?? null;
}

async function load(): Promise<void> {
  rows.value = await api<ReleaseRow[]>("/admin/releases");
}

async function upload(): Promise<void> {
  if (!file.value || !versionName.value || versionCode.value <= 0) {
    ElMessage.error("请选择安装包并填写版本");
    return;
  }
  const body = new FormData();
  body.append("versionName", versionName.value);
  body.append("versionCode", String(versionCode.value));
  body.append("releaseNotes", releaseNotes.value);
  body.append("forceUpdate", forceUpdate.value ? "true" : "false");
  body.append("file", file.value);
  uploading.value = true;
  try {
    const response = await fetch("/admin/releases", {
      method: "POST",
      headers: { authorization: `Bearer ${getToken()}` },
      body,
    });
    if (!response.ok) {
      throw new Error("上传失败");
    }
    ElMessage.success("已设为当前版本");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "上传失败");
  } finally {
    uploading.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
.form {
  max-width: 640px;
  margin-bottom: 24px;
}
</style>
