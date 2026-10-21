<template>
  <el-select
    :model-value="modelValue ?? ''"
    :class="['art-select', { inherit: !modelValue && !!inheritKey }]"
    :style="{ width: `${width}px` }"
    :placeholder="inheritKey ? `跟随 ${nameOf(inheritKey)}` : '选择立绘'"
    filterable
    :clearable="clearable"
    @update:model-value="(value: string) => emit('update:modelValue', value || null)"
  >
    <template #prefix>
      <img v-if="modelValue || inheritKey" :src="monsterThumb(modelValue || inheritKey)" class="thumb" alt="" />
    </template>
    <el-option v-for="option in options" :key="option.key" :label="`${option.name} · ${option.key}`" :value="option.key">
      <span class="option"><img :src="monsterThumb(option.key)" class="thumb big" alt="" />{{ option.name }}<span class="key">{{ option.key }}</span></span>
    </el-option>
  </el-select>
</template>

<script setup lang="ts">
/** 立绘下拉（怪物 / 首领 artKey，带缩略图）。null = 没选（精英跟随本关普通怪，inheritKey 灰显）。 */
import { onMounted, ref } from "vue";
import { loadArtKeys, monsterThumb, type ArtCatalog } from "../composables/bossRules";

withDefaults(defineProps<{ modelValue: string | null | undefined; inheritKey?: string | null; width?: number; clearable?: boolean }>(), { width: 200, clearable: false });
const emit = defineEmits<{ "update:modelValue": [value: string | null] }>();
const options = ref<ArtCatalog["monsters"]>([]);

function nameOf(key: string): string {
  return options.value.find((row) => row.key === key)?.name ?? key;
}

onMounted(async () => {
  options.value = (await loadArtKeys()).monsters;
});
</script>

<style scoped>
.thumb {
  width: 22px;
  height: 22px;
  object-fit: contain;
}
.thumb.big {
  width: 32px;
  height: 32px;
  margin-right: 8px;
}
.option {
  display: flex;
  align-items: center;
}
.key {
  margin-left: auto;
  padding-left: 12px;
  color: var(--xx-text-placeholder);
  font-size: 12px;
}
.inherit :deep(.el-select__placeholder) {
  color: #98a19c;
}
:global(.el-select-dropdown__item:has(.option)) {
  height: 40px;
  line-height: 40px;
}
</style>
