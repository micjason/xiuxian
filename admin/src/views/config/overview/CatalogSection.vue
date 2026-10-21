<template>
  <SectionCard title="部位与品质" anchor="catalog" desc="服务端统一的一份表，游戏和后台都按这里的名字显示">
    <template #extra><CustomTag kind="readonly">只读</CustomTag></template>
    <div class="two">
      <div>
        <h4 class="sub-title">部位（{{ slots.length }} 个）</h4>
        <el-table :data="slots" size="small">
          <el-table-column prop="key" label="编号" width="110" />
          <el-table-column prop="name" label="名称" />
        </el-table>
      </div>
      <div>
        <h4 class="sub-title">品质（{{ qualities.length }} 档，白→橙）</h4>
        <el-table :data="qualities" size="small">
          <el-table-column prop="key" label="编号" width="100" />
          <el-table-column label="简称" width="70"><template #default="{ row }"><span class="q-tag" :style="{ color: row.color, borderColor: row.color }">{{ row.short }}</span></template></el-table-column>
          <el-table-column prop="name" label="名称" />
          <el-table-column label="颜色"><template #default="{ row }"><i class="dot" :style="{ background: row.color }" /> {{ row.color }}</template></el-table-column>
        </el-table>
      </div>
    </div>
    <p class="muted small">加部位或品质需要改服务端的表（catalog.ts）并发新客户端；装备生成系数、强化规则、掉落权重都按编号读。</p>
  </SectionCard>
</template>

<script setup lang="ts">
import CustomTag from "../../../components/CustomTag.vue";
import SectionCard from "../../../components/SectionCard.vue";

defineProps<{ slots: { key: string; name: string }[]; qualities: { key: string; name: string; short: string; color: string }[] }>();
</script>

<style scoped>
.two {
  display: grid;
  grid-template-columns: 1fr 1.4fr;
  gap: 24px;
}
.sub-title {
  margin: 0 0 8px;
  font-size: 14px;
}
.q-tag {
  padding: 0 6px;
  border: 1px solid;
  border-radius: 4px;
  font-size: 12px;
}
.dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
</style>
