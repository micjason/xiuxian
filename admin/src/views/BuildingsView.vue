<template>
  <DraftPage title="洞府建筑" resource="buildings" :fields="fields" />
</template>

<script setup lang="ts">
import DraftPage from "./DraftPage.vue";

const fields = [
  { key: "displayName", label: "名称", kind: "text" as const },
  { key: "maxLevel", label: "等级上限", kind: "number" as const },
  { key: "laborBonus", label: "劳作加成", kind: "number" as const },
  { key: "cultivateBonusPerLevel", label: "每级修炼加成", kind: "number" as const },
];
</script>
