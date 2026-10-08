<template>
  <div>
    <DraftPage
      title="物品"
      resource="items"
      :fields="fields"
      filter-key="kind"
      :filter-options="filters"
    />
    <DropLinkForm />
  </div>
</template>

<script setup lang="ts">
import DraftPage from "./DraftPage.vue";
import DropLinkForm from "./DropLinkForm.vue";

const filters = [
  { label: "装备", value: "equipment" },
  { label: "功法书", value: "skill_book" },
  { label: "丹药", value: "pill" },
  { label: "材料", value: "material" },
];

const fields = [
  { key: "displayName", label: "名称", kind: "text" as const },
  { key: "description", label: "描述", kind: "text" as const },
  { key: "kind", label: "种类", kind: "text" as const },
  { key: "quality", label: "品质", kind: "text" as const },
  { key: "slot", label: "部位", kind: "text" as const },
  { key: "attack", label: "攻击", kind: "number" as const },
  { key: "defense", label: "防御", kind: "number" as const },
  { key: "hp", label: "气血", kind: "number" as const },
  { key: "speed", label: "速度", kind: "number" as const },
  { key: "skillSlug", label: "对应技能", kind: "text" as const },
  { key: "grantable", label: "可由游戏发放", kind: "bool" as const },
];
</script>
