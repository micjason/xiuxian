<template>
  <div>
    <PageHeader title="客户端安装包" desc="上传新的 Android 安装包并设为当前版本。玩家启动时会提示更新；强制更新会让旧版本无法继续使用。" />

    <section class="xx-card block">
      <h2>上传新版本</h2>
      <el-form ref="formRef" :model="form" :rules="rules" label-width="110px" class="form">
        <el-form-item label="安装包" prop="file">
          <el-upload
            ref="uploadRef"
            drag
            :auto-upload="false"
            :limit="1"
            accept=".apk"
            :on-change="(f: UploadFile) => (form.file = f.raw ?? null)"
            :on-remove="() => (form.file = null)"
            :on-exceed="replaceFile"
            class="upload"
          >
            <div class="drop"><strong>拖入 .apk，或点击选择</strong><span>文件大小约 {{ form.file ? (form.file.size / 1048576).toFixed(1) + " MB" : "—" }}</span></div>
          </el-upload>
        </el-form-item>
        <el-form-item label="版本名称" prop="versionName"><el-input v-model="form.versionName" placeholder="例如 0.6.8" style="width: 240px" /></el-form-item>
        <el-form-item label="版本号" prop="versionCode">
          <el-input-number v-model="form.versionCode" :min="1" :step="1" :precision="0" :controls="false" />
          <span class="hint">必须大于已有的最大版本号 {{ maxCode }}，Android 靠它判断是否升级。</span>
        </el-form-item>
        <el-form-item label="更新说明"><el-input v-model="form.releaseNotes" type="textarea" :rows="3" placeholder="玩家更新时看到的说明" /></el-form-item>
        <el-form-item label="强制更新"><el-switch v-model="form.forceUpdate" /><span class="hint">打开后，低于此版本的客户端必须更新才能继续玩。</span></el-form-item>
        <el-form-item><el-button type="primary" :loading="uploading" @click="upload">上传并设为当前版本</el-button></el-form-item>
      </el-form>
    </section>

    <section class="block">
      <h2>历史安装包（{{ rows.length }}）</h2>
      <DataState :loading="loading" :error="error" :has-data="rows.length > 0" empty-text="还没有上传过安装包" @retry="load">
        <el-table :data="rows">
          <el-table-column prop="versionName" label="版本名称" min-width="120" />
          <el-table-column prop="versionCode" label="版本号" width="100" sortable />
          <el-table-column label="更新方式" width="100"><template #default="{ row }"><el-tag :type="row.forceUpdate ? 'danger' : 'info'" effect="light" size="small">{{ row.forceUpdate ? "强制" : "可选" }}</el-tag></template></el-table-column>
          <el-table-column label="状态" width="90"><template #default="{ row }"><el-tag v-if="row.isCurrent" type="success" effect="light" size="small">当前</el-tag></template></el-table-column>
          <el-table-column prop="sha256" label="SHA-256" min-width="260" show-overflow-tooltip class-name="mono" />
        </el-table>
      </DataState>
    </section>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, type FormInstance, type FormRules, type UploadFile, type UploadInstance, type UploadRawFile, genFileId } from "element-plus";
import { computed, onMounted, reactive, ref } from "vue";
import { api, getToken } from "../../api";
import DataState from "../../components/DataState.vue";
import PageHeader from "../../components/PageHeader.vue";
import { confirmAction } from "../../composables/confirm";

type ReleaseRow = { versionName: string; versionCode: number; forceUpdate: boolean; isCurrent: boolean; sha256: string };

const rows = ref<ReleaseRow[]>([]);
const loading = ref(false);
const error = ref("");
const uploading = ref(false);
const formRef = ref<FormInstance>();
const uploadRef = ref<UploadInstance>();
const form = reactive({ versionName: "", versionCode: 1, releaseNotes: "", forceUpdate: false, file: null as File | null });
const maxCode = computed(() => (rows.value.length ? Math.max(...rows.value.map((row) => row.versionCode)) : 0));

const rules = computed<FormRules>(() => ({
  file: [{ validator: (_r, _v, cb) => (form.file ? cb() : cb(new Error("请选择安装包"))), trigger: "change" }],
  versionName: [{ required: true, message: "请填写版本名称", trigger: "blur" }],
  versionCode: [{ validator: (_r, v: number, cb) => (v > maxCode.value ? cb() : cb(new Error(`版本号必须大于 ${maxCode.value}`))), trigger: "blur" }],
}));

function replaceFile(files: File[]): void {
  uploadRef.value?.clearFiles();
  const file = files[0] as UploadRawFile;
  file.uid = genFileId();
  uploadRef.value?.handleStart(file);
  form.file = file;
}

async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    rows.value = await api<ReleaseRow[]>("/admin/releases");
    form.versionCode = maxCode.value + 1;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

async function upload(): Promise<void> {
  if (!(await formRef.value?.validate().catch(() => false))) return;
  const ok = await confirmAction(`确认把 ${form.versionName}（版本号 ${form.versionCode}）设为当前版本？${form.forceUpdate ? "这是强制更新，旧版本玩家必须更新。" : ""}`, "设为当前版本", "确认上传");
  if (!ok || !form.file) return;
  // 字段必须先于文件，服务器按顺序读取 multipart。
  const body = new FormData();
  body.append("versionName", form.versionName);
  body.append("versionCode", String(form.versionCode));
  body.append("releaseNotes", form.releaseNotes);
  body.append("forceUpdate", form.forceUpdate ? "true" : "false");
  body.append("file", form.file);
  uploading.value = true;
  try {
    const response = await fetch("/admin/releases", { method: "POST", headers: { authorization: `Bearer ${getToken()}` }, body });
    if (!response.ok) throw new Error("上传失败，请检查版本号是否重复");
    ElMessage.success("已设为当前版本");
    form.versionName = "";
    form.releaseNotes = "";
    form.file = null;
    uploadRef.value?.clearFiles();
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
.block {
  margin-bottom: var(--xx-space-5);
}
.block h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-lg);
}
.form {
  max-width: 720px;
}
.upload {
  width: 100%;
}
.drop {
  display: grid;
  gap: 4px;
  padding: var(--xx-space-4);
  color: var(--xx-text-secondary);
}
.hint {
  margin-left: var(--xx-space-3);
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
</style>
