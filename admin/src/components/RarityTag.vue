<template>
  <span class="xx-tag-rarity" :data-rarity="rarityOf(name)">{{ name }}</span>
</template>

<script setup lang="ts">
import { rarityOf } from "../rarity";

defineProps<{ name: string }>();
</script>
