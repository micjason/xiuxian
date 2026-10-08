<template>
  <div>
    <DraftPage title="关卡" resource="stages" :fields="fields" />
    <DropLinkForm />
  </div>
</template>

<script setup lang="ts">
import DraftPage from "./DraftPage.vue";
import DropLinkForm from "./DropLinkForm.vue";

const fields = [
  { key: "displayName", label: "关卡名", kind: "text" as const },
  { key: "bossName", label: "Boss", kind: "text" as const },
  { key: "attack", label: "攻击", kind: "number" as const },
  { key: "defense", label: "防御", kind: "number" as const },
  { key: "hp", label: "气血", kind: "number" as const },
  { key: "interval", label: "攻击间隔", kind: "number" as const },
];
</script>
