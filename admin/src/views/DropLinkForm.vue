<template>
  <div class="drops">
    <h3>掉落</h3>
    <el-form inline>
      <el-form-item label="关卡">
        <el-select v-model="stageSlug" placeholder="选择关卡" style="width: 180px">
          <el-option v-for="stage in stages" :key="stage.slug" :label="stage.displayName || stage.slug" :value="stage.slug" />
        </el-select>
      </el-form-item>
      <el-form-item label="物品">
        <el-select v-model="itemSlug" placeholder="选择物品" style="width: 180px">
          <el-option v-for="item in items" :key="item.slug" :label="item.displayName || item.slug" :value="item.slug" />
        </el-select>
      </el-form-item>
      <el-form-item label="概率">
        <el-input-number v-model="chance" :min="0" :max="100" :step="1" />
      </el-form-item>
      <el-form-item label="数量">
        <el-input-number v-model="quantity" :min="1" :step="1" />
      </el-form-item>
      <el-button type="primary" :loading="saving" @click="save">保存同一条掉落</el-button>
    </el-form>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, ref } from "vue";
import { api } from "../api";

type Named = { slug: string; displayName: string };

const stages = ref<Named[]>([]);
const items = ref<Named[]>([]);
const stageSlug = ref("");
const itemSlug = ref("");
const chance = ref(0);
const quantity = ref(1);
const saving = ref(false);

async function load(): Promise<void> {
  stages.value = await api<Named[]>("/admin/content/stages");
  items.value = await api<Named[]>("/admin/content/items");
}

async function save(): Promise<void> {
  if (!stageSlug.value || !itemSlug.value) {
    ElMessage.error("请选择关卡和物品");
    return;
  }
  saving.value = true;
  try {
    await api(`/admin/content/stages/${stageSlug.value}/drops`, {
      method: "PUT",
      body: JSON.stringify({ itemSlug: itemSlug.value, chance: chance.value, quantity: quantity.value }),
    });
    ElMessage.success("已写入草稿");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
.drops {
  margin-top: 28px;
}
</style>
