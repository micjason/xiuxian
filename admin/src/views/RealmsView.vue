<template>
  <DraftPage title="境界" resource="realms" :fields="fields" />
</template>

<script setup lang="ts">
import DraftPage from "./DraftPage.vue";

const fields = [
  { key: "displayName", label: "名称", kind: "text" as const },
  { key: "sortOrder", label: "顺序", kind: "number" as const },
  { key: "gainPerSecond", label: "每秒修为", kind: "number" as const },
  { key: "breakthroughCost", label: "突破消耗", kind: "number" as const },
  { key: "nextSlug", label: "下一境界", kind: "text" as const },
  { key: "attack", label: "攻击", kind: "number" as const },
  { key: "defense", label: "防御", kind: "number" as const },
  { key: "hp", label: "气血", kind: "number" as const },
  { key: "speed", label: "速度", kind: "number" as const },
];
</script>
