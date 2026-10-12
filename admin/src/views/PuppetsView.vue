<template>
  <div>
    <div class="toolbar">
      <h2>人偶</h2>
      <el-button type="primary" @click="create">新建人偶</el-button>
    </div>
    <p>人偶只用于试打，不进游戏。按配置算会跟着境界、武器、功法的数值变。手填属性直接用填进去的攻击、防御、气血、速度和出手间隔。类型建好后不能改。</p>
    <el-table :data="rows" v-loading="loading">
      <el-table-column prop="displayName" label="名称" width="180" />
      <el-table-column prop="kindName" label="类型" width="120" />
      <el-table-column label="内容">
        <template #default="{ row }">{{ summary(row) }}</template>
      </el-table-column>
      <el-table-column label="战力" width="100">
        <template #default="{ row }">{{ row.power == null ? "—" : row.power }}</template>
      </el-table-column>
      <el-table-column label="" width="160">
        <template #default="{ row }">
          <el-button link type="primary" @click="edit(row)">编辑</el-button>
          <el-button link type="danger" @click="remove(row)">删除</el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="open" :title="creating ? '新建人偶' : '编辑人偶'" width="560px">
      <el-form label-width="100px">
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="类型">
          <el-select v-if="creating" v-model="form.kind" placeholder="选择类型" style="width: 220px">
            <el-option label="按配置算" value="configured" />
            <el-option label="手填属性" value="manual" />
          </el-select>
          <span v-else>{{ form.kindName }}</span>
        </el-form-item>
        <p v-if="form.problem" class="problem">
          {{ form.problem }}<template v-if="form.kind === 'configured'">。保存会按你现在选中的重新记录。</template>
        </p>
        <template v-if="form.kind === 'configured'">
          <el-form-item label="境界">
            <el-select v-model="form.realmCode" placeholder="选择境界" style="width: 220px">
              <el-option v-for="realm in realms" :key="realm.code" :label="`${realm.code} ${realm.displayName}`" :value="realm.code" />
            </el-select>
          </el-form-item>
          <el-form-item label="武器">
            <el-select v-model="form.weaponIds" multiple placeholder="不穿" style="width: 100%">
              <el-option v-for="item in weapons" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
            </el-select>
          </el-form-item>
          <el-form-item label="功法">
            <el-select v-model="form.skillIds" multiple placeholder="不运转" style="width: 100%">
              <el-option v-for="skill in skills" :key="skill.id" :label="skill.displayName || '名称缺失'" :value="skill.id" />
            </el-select>
          </el-form-item>
        </template>
        <template v-if="form.kind === 'manual'">
          <el-form-item label="攻击">
            <el-input-number v-model="form.attack" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="防御">
            <el-input-number v-model="form.defense" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="气血">
            <el-input-number v-model="form.hp" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="速度">
            <el-input-number v-model="form.speed" :min="0" :controls="false" />
          </el-form-item>
          <el-form-item label="出手间隔">
            <el-input-number v-model="form.interval" :min="0" :controls="false" />
          </el-form-item>
        </template>
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

type Named = { id: string; displayName: string };
type Realm = { code: number; displayName: string };
type Gear = { id: string; displayName: string; missing: boolean };
type Puppet = {
  id: string;
  displayName: string;
  kind: "configured" | "manual";
  kindName: string;
  realmCode: number | null;
  realmName: string;
  realmMissing: boolean;
  weapons: Gear[];
  skills: Gear[];
  attack: number | null;
  defense: number | null;
  hp: number | null;
  speed: number | null;
  interval: number | null;
  power: number | null;
  problem: string | null;
};

const loading = ref(false);
const open = ref(false);
const creating = ref(false);
const editingId = ref("");
const rows = ref<Puppet[]>([]);
const realms = ref<Realm[]>([]);
const weapons = ref<Named[]>([]);
const skills = ref<Named[]>([]);
const form = reactive({
  displayName: "",
  kind: "" as "" | "configured" | "manual",
  kindName: "",
  problem: "",
  realmCode: undefined as number | undefined,
  weaponIds: [] as string[],
  skillIds: [] as string[],
  attack: undefined as number | undefined,
  defense: undefined as number | undefined,
  hp: undefined as number | undefined,
  speed: undefined as number | undefined,
  interval: undefined as number | undefined,
});

function summary(row: Puppet): string {
  if (row.problem) {
    return row.problem;
  }
  if (row.kind === "manual") {
    return `攻击 ${row.attack}，防御 ${row.defense}，气血 ${row.hp}，速度 ${row.speed}，每 ${row.interval} 秒出手`;
  }
  const gear = [...row.weapons.map((item) => item.displayName), ...row.skills.map((item) => item.displayName)];
  return gear.length > 0 ? `${row.realmName} · ${gear.join("、")}` : row.realmName;
}

async function load(): Promise<void> {
  loading.value = true;
  try {
    rows.value = await api<Puppet[]>("/admin/draft/puppets");
    realms.value = await api<Realm[]>("/admin/draft/realms");
    weapons.value = await api<Named[]>("/admin/draft/weapons");
    skills.value = await api<Named[]>("/admin/draft/skills");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  } finally {
    loading.value = false;
  }
}

function resetForm(): void {
  form.displayName = "";
  form.kind = "";
  form.kindName = "";
  form.problem = "";
  form.realmCode = undefined;
  form.weaponIds = [];
  form.skillIds = [];
  form.attack = undefined;
  form.defense = undefined;
  form.hp = undefined;
  form.speed = undefined;
  form.interval = undefined;
}

function create(): void {
  creating.value = true;
  editingId.value = "";
  resetForm();
  open.value = true;
}

function edit(row: Puppet): void {
  creating.value = false;
  editingId.value = row.id;
  resetForm();
  form.displayName = row.displayName;
  form.kind = row.kind;
  form.kindName = row.kindName;
  form.problem = row.problem ?? "";
  form.realmCode = row.realmMissing ? undefined : (row.realmCode ?? undefined);
  form.weaponIds = row.weapons.filter((item) => !item.missing).map((item) => item.id);
  form.skillIds = row.skills.filter((item) => !item.missing).map((item) => item.id);
  form.attack = row.attack ?? undefined;
  form.defense = row.defense ?? undefined;
  form.hp = row.hp ?? undefined;
  form.speed = row.speed ?? undefined;
  form.interval = row.interval ?? undefined;
  open.value = true;
}

async function save(): Promise<void> {
  const body =
    form.kind === "manual"
      ? {
          displayName: form.displayName,
          kind: form.kind,
          attack: form.attack,
          defense: form.defense,
          hp: form.hp,
          speed: form.speed,
          interval: form.interval,
        }
      : {
          displayName: form.displayName,
          kind: form.kind,
          realmCode: form.realmCode,
          weaponIds: form.weaponIds,
          skillIds: form.skillIds,
        };
  try {
    if (creating.value) {
      await api("/admin/draft/puppets", { method: "POST", body: JSON.stringify(body) });
    } else {
      await api(`/admin/draft/puppets/${editingId.value}`, { method: "PUT", body: JSON.stringify(body) });
    }
    open.value = false;
    ElMessage.success("已保存");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

async function remove(row: Puppet): Promise<void> {
  await ElMessageBox.confirm(`删除人偶「${row.displayName}」？`, "删除人偶");
  await api(`/admin/draft/puppets/${row.id}`, { method: "DELETE" });
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
.problem {
  color: var(--el-color-danger);
}
</style>
