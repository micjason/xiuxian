<template>
  <SectionCard title="新手设置" anchor="newbie" desc="新注册的玩家从哪个境界开始、背包里先放什么">
    <FormRow label="初始境界" help="新玩家注册时所在的境界；后台「清空进度」也回到这个境界。" required>
      <el-select v-model="model.startingRealmSlug" class="w320" placeholder="选择境界">
        <el-option v-for="realm in realms" :key="realm.slug" :label="realm.displayName" :value="realm.slug" />
      </el-select>
    </FormRow>
    <FormRow label="新手物品" class="row-gap" help="注册时直接放进背包的物品。装备每件一个实例（走发放接口，来源 event）；材料、丹药按数量叠加。已经注册的玩家不受影响。" :help-meta="`最多 ${limits.maxRows} 行 · 每行 1–${limits.maxQuantity}`">
      <div class="starter">
        <div v-if="model.starterItems.length === 0" class="muted small empty">没有新手物品，新玩家空背包开始</div>
        <div v-for="(row, index) in model.starterItems" :key="index" class="row">
          <el-select v-model="row.itemSlug" filterable class="w320" placeholder="选择物品">
            <el-option-group v-for="group in groups" :key="group.label" :label="group.label">
              <el-option v-for="item in group.items" :key="item.id" :label="item.displayName" :value="item.id" :disabled="item.id !== row.itemSlug && model.starterItems.some((other) => other.itemSlug === item.id)" />
            </el-option-group>
          </el-select>
          <NumInput v-model="row.quantity" :width="120" unit="个" :precision="0" :min="1" :max="limits.maxQuantity" />
          <el-button link type="danger" @click="model.starterItems.splice(index, 1)">删除</el-button>
        </div>
        <el-button size="small" :disabled="model.starterItems.length >= limits.maxRows" @click="model.starterItems.push({ itemSlug: '', quantity: 1 })">＋ 添加物品</el-button>
      </div>
    </FormRow>
  </SectionCard>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { api } from "../../../api";
import FormRow from "../../../components/FormRow.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";

/** 配置概览「新手设置」（批次②）：初始境界 + 新手物品。数据由父页面持有，跟父页面一起保存。 */
export type Newbie = { startingRealmSlug: string; starterItems: { itemSlug: string; quantity: number | null }[] };

const model = defineModel<Newbie>({ required: true });
defineProps<{ realms: { slug: string; displayName: string }[]; limits: { maxRows: number; maxQuantity: number } }>();

const items = ref<{ id: string; displayName: string }[]>([]);
const gear = ref<{ id: string; displayName: string }[]>([]);
const groups = computed(() => [
  { label: "材料 / 丹药", items: items.value },
  { label: "装备", items: gear.value },
]);

onMounted(async () => {
  const [itemList, gearList] = await Promise.all([
    api<{ id: string; displayName: string }[]>("/admin/draft/items"),
    api<{ majors: { majorName: string; pieces: { id: string; displayName: string }[] }[]; manual: { id: string; displayName: string }[] }>("/admin/draft/gear"),
  ]);
  items.value = itemList;
  gear.value = [...(gearList.manual ?? []), ...gearList.majors.flatMap((major) => major.pieces)];
});
</script>

<style scoped>
.row-gap {
  margin-top: 18px;
}
.starter {
  display: grid;
  gap: 8px;
  justify-items: start;
}
.row {
  display: flex;
  align-items: center;
  gap: 10px;
}
.empty {
  padding: 4px 0;
}
.w320 {
  width: 320px;
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
</style>
