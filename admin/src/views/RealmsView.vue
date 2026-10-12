<template>
  <div>
    <div class="toolbar">
      <h2>境界</h2>
      <el-button type="primary" @click="create">新建境界</el-button>
    </div>
    <p>编号用数字，不能重复，从小到大就是突破顺序。保存后游戏立刻使用。攻击、防御、气血、速度是到达这个境界时增加的量，会和更低境界的加在一起。填 0 就是这个境界不增加。基础出手间隔要填，出手快慢用它和规则页的速度基数一起算。</p>
    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="code" label="编号" width="100" />
      <el-table-column prop="displayName" label="名称" width="160" />
      <el-table-column prop="tickSeconds" label="多少秒" width="100" />
      <el-table-column prop="gainPerTick" label="获得修为" width="120" />
      <el-table-column prop="breakthroughCost" label="突破消耗" width="120" />
      <el-table-column prop="attack" label="攻击" width="90" />
      <el-table-column prop="defense" label="防御" width="90" />
      <el-table-column prop="hp" label="气血" width="90" />
      <el-table-column prop="speed" label="速度" width="90" />
      <el-table-column label="基础出手间隔" width="140">
        <template #default="{ row }">{{ row.interval == null ? "未填" : row.interval }}</template>
      </el-table-column>
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="edit(row)">编辑</el-button>
          <el-button link type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>
    <el-dialog v-model="open" :title="creating ? '新建境界' : '编辑境界'" width="480px">
      <el-form label-width="120px">
        <el-form-item label="编号">
          <el-input-number v-model="form.code" :min="1" :step="1" :precision="0" />
        </el-form-item>
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="多少秒">
          <el-input-number v-model="form.tickSeconds" :min="0" :step="1" />
        </el-form-item>
        <el-form-item label="获得修为">
          <el-input-number v-model="form.gainPerTick" :min="0" :step="1" />
        </el-form-item>
        <el-form-item label="突破消耗">
          <el-input-number v-model="form.breakthroughCost" :min="0" :step="1" />
        </el-form-item>
        <el-form-item label="攻击">
          <el-input-number v-model="form.attack" :min="0" :step="1" />
        </el-form-item>
        <el-form-item label="防御">
          <el-input-number v-model="form.defense" :min="0" :step="1" />
        </el-form-item>
        <el-form-item label="气血">
          <el-input-number v-model="form.hp" :min="0" :step="1" />
        </el-form-item>
        <el-form-item label="速度">
          <el-input-number v-model="form.speed" :min="0" :step="1" />
        </el-form-item>
        <el-form-item label="基础出手间隔">
          <el-input-number v-model="form.interval" :min="0" :step="0.1" :controls="false" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="open = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type Realm = {
  code: number;
  displayName: string;
  tickSeconds: number;
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  interval: number | null;
};

const loading = ref(false);
const open = ref(false);
const creating = ref(false);
const editingCode = ref(0);
const rows = ref<Realm[]>([]);
const form = reactive({
  code: 1,
  displayName: "",
  tickSeconds: 0,
  gainPerTick: 0,
  breakthroughCost: 0,
  attack: 0,
  defense: 0,
  hp: 0,
  speed: 0,
  interval: undefined as number | undefined,
});

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<Realm[]>("/admin/draft/realms");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function create(): void {
  creating.value = true;
  editingCode.value = 0;
  form.code = rows.value.length === 0 ? 1 : Math.max(...rows.value.map((row) => row.code)) + 1;
  form.displayName = "";
  form.tickSeconds = 0;
  form.gainPerTick = 0;
  form.breakthroughCost = 0;
  form.attack = 0;
  form.defense = 0;
  form.hp = 0;
  form.speed = 0;
  form.interval = undefined;
  open.value = true;
}

function edit(row: Realm): void {
  creating.value = false;
  editingCode.value = row.code;
  form.code = row.code;
  form.displayName = row.displayName;
  form.tickSeconds = row.tickSeconds;
  form.gainPerTick = row.gainPerTick;
  form.breakthroughCost = row.breakthroughCost;
  form.attack = row.attack;
  form.defense = row.defense;
  form.hp = row.hp;
  form.speed = row.speed;
  form.interval = row.interval ?? undefined;
  open.value = true;
}

async function save(): Promise<void> {
  const body = {
    code: form.code,
    displayName: form.displayName,
    tickSeconds: form.tickSeconds,
    gainPerTick: form.gainPerTick,
    breakthroughCost: form.breakthroughCost,
    attack: form.attack,
    defense: form.defense,
    hp: form.hp,
    speed: form.speed,
    interval: form.interval,
  };
  try {
    if (creating.value) {
      await api("/admin/draft/realms", { method: "POST", body: JSON.stringify(body) });
    } else {
      await api(`/admin/draft/realms/${editingCode.value}`, { method: "PUT", body: JSON.stringify(body) });
    }
    open.value = false;
    ElMessage.success("已保存，游戏会马上使用");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function remove(row: Realm): Promise<void> {
  await ElMessageBox.confirm(`删除境界「${row.displayName}」？已有的测试账号需要你自己清掉。`, "删除境界");
  await api(`/admin/draft/realms/${row.code}`, { method: "DELETE" });
  ElMessage.success("已删除");
  await load();
}

onMounted(load);
</script>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
</style>
