<template>
  <div>
    <div class="toolbar">
      <h2>装备</h2>
      <el-button type="primary" :disabled="!loaded || savingFactors" @click="saveFactors">保存品质系数</el-button>
    </div>
    <p>
      品质系数是根数据，默认白 1、绿 1.15、蓝 1.3、紫 1.5、橙 1.8。装备属性按「这一阶的装备预算 × 部位占比 × 品质系数」计算，不能手填。
      保存系数之后，每一件装备的攻击、防御、气血、速度会跟着重算。名字、描述和图标不动。
    </p>
    <el-form label-width="120px" class="factors">
      <el-form-item v-for="quality in qualities" :key="quality.key" :label="quality.name">
        <el-input-number v-model="factors[quality.key]" :min="0.01" :step="0.05" :controls="false" />
      </el-form-item>
    </el-form>

    <p v-if="majors.length === 0">先在境界里填写同一个大境界的名字，保存后会生成这一阶的 25 件装备。</p>
    <section v-for="major in majors" :key="major.majorKey" class="major">
      <h3>{{ major.majorName }}</h3>
      <p>到达编号 {{ major.requiredRealmOrder }} 就能穿。高阶的先放在背包里。</p>
      <el-table :data="major.pieces">
        <el-table-column prop="displayName" label="名称" width="220" />
        <el-table-column prop="slotName" label="部位" width="90" />
        <el-table-column prop="qualityName" label="品质" width="80" />
        <el-table-column prop="attack" label="攻击" width="90" />
        <el-table-column prop="defense" label="防御" width="90" />
        <el-table-column prop="hp" label="气血" width="90" />
        <el-table-column prop="speed" label="速度" width="90" />
        <el-table-column label="战力" width="100">
          <template #default="{ row }">{{ row.power ?? "规则未填" }}</template>
        </el-table-column>
        <el-table-column label="" width="100">
          <template #default="{ row }">
            <el-button link type="primary" @click="openPiece(row)">编辑</el-button>
          </template>
        </el-table-column>
      </el-table>
    </section>

    <el-dialog v-model="pieceOpen" title="编辑装备" width="480px">
      <el-form label-width="80px">
        <el-form-item label="名称">
          <el-input v-model="form.displayName" />
        </el-form-item>
        <el-form-item label="描述">
          <el-input v-model="form.description" />
        </el-form-item>
        <el-form-item label="图标">
          <el-input v-model="form.iconKey" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="pieceOpen = false">取消</el-button>
        <el-button type="primary" @click="savePiece">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { onMounted, reactive, ref } from "vue";
import { api } from "../api";

type QualityKey = "white" | "green" | "blue" | "purple" | "orange";
type Piece = {
  id: string;
  displayName: string;
  description: string;
  iconKey: string;
  slotName: string;
  qualityName: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  power: number | null;
};
type Major = {
  majorName: string;
  majorKey: string;
  requiredRealmOrder: number;
  pieces: Piece[];
};

const qualities: { key: QualityKey; name: string }[] = [
  { key: "white", name: "白" },
  { key: "green", name: "绿" },
  { key: "blue", name: "蓝" },
  { key: "purple", name: "紫" },
  { key: "orange", name: "橙" },
];

const factors = reactive<Record<QualityKey, number>>({ white: 1, green: 1.15, blue: 1.3, purple: 1.5, orange: 1.8 });
const majors = ref<Major[]>([]);
const loaded = ref(false);
const savingFactors = ref(false);
const pieceOpen = ref(false);
const pieceId = ref("");
const form = reactive({ displayName: "", description: "", iconKey: "" });

async function load(): Promise<void> {
  const page = await api<{ factors: Record<QualityKey, number>; majors: Major[] }>("/admin/draft/gear");
  for (const quality of qualities) {
    factors[quality.key] = page.factors[quality.key];
  }
  majors.value = page.majors;
  loaded.value = true;
}

async function saveFactors(): Promise<void> {
  savingFactors.value = true;
  try {
    await api("/admin/draft/gear-qualities", { method: "PUT", body: JSON.stringify({ ...factors }) });
    ElMessage.success("已保存，装备属性已重算");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    savingFactors.value = false;
  }
}

function openPiece(row: Piece): void {
  pieceId.value = row.id;
  form.displayName = row.displayName;
  form.description = row.description;
  form.iconKey = row.iconKey;
  pieceOpen.value = true;
}

async function savePiece(): Promise<void> {
  try {
    await api(`/admin/draft/gear/${pieceId.value}`, { method: "PUT", body: JSON.stringify({ ...form }) });
    pieceOpen.value = false;
    ElMessage.success("已保存");
    await load();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  }
}

onMounted(() => {
  void load().catch((cause: unknown) => {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  });
});
</script>

<style scoped>
.toolbar {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.factors {
  display: grid;
  grid-template-columns: repeat(2, minmax(240px, 360px));
  max-width: 760px;
}
.major {
  margin-top: 28px;
}
</style>
