<template>
  <DraftPage title="技能" resource="skills" :fields="fields" />
</template>

<script setup lang="ts">
import DraftPage from "./DraftPage.vue";

const fields = [
  { key: "displayName", label: "名称", kind: "text" as const },
  { key: "description", label: "描述", kind: "text" as const },
  { key: "role", label: "定位", kind: "text" as const },
  { key: "attack", label: "攻击", kind: "number" as const },
  { key: "defense", label: "防御", kind: "number" as const },
  { key: "hp", label: "气血", kind: "number" as const },
  { key: "speed", label: "速度", kind: "number" as const },
  { key: "cultivateBonus", label: "修炼加成", kind: "number" as const },
  { key: "minRealmOrder", label: "所需境界", kind: "number" as const },
  { key: "prerequisiteSlugs", label: "前置技能", kind: "text" as const },
];
</script>
