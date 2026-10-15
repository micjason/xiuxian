<template>
  <div>
    <PageHeader title="境界" desc="境界决定突破顺序、挂机修为产出，以及到达后永久增加的属性。点击一行直接在右侧抽屉里编辑。" />
    <ConfigListPage
      :schema="realmSchema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="code"
      entity-name="境界"
      :search-keys="['displayName', 'majorName', 'code']"
      search-placeholder="搜索境界名称、大境界、编号"
      :filters="filters"
      creatable
      deletable
      cloneable
      selectable
      danger-delete
      :new-row="newRow"
      :hidden-keys="['majorKey']"
      :save-fn="save"
      :remove-fn="remove"
      :delete-hint="deleteHint"
      export-name="境界"
      @reload="reload"
    >
      <template #extra-columns>
        <el-table-column label="状态" width="150">
          <template #default="{ row }">
            <el-tag v-for="tag in statusOf(row as Realm)" :key="tag" type="warning" effect="light" size="small" class="tag">{{ tag }}</el-tag>
            <el-tag v-if="statusOf(row as Realm).length === 0" type="success" effect="light" size="small">完整</el-tag>
          </template>
        </el-table-column>
      </template>
    </ConfigListPage>
  </div>
</template>

<script setup lang="ts">
import { computed } from "vue";
import { api } from "../../api";
import ConfigListPage from "../../components/ConfigListPage.vue";
import PageHeader from "../../components/PageHeader.vue";
import { useList } from "../../composables/useList";
import { realmSchema } from "../../schema/resources";
import { defaultsOf } from "../../schema/validate";

type Realm = {
  code: number;
  displayName: string;
  majorName: string;
  tickSeconds: number;
  gainPerTick: number;
  breakthroughCost: number;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  interval: number | null;
};

const { rows, loading, error, reload } = useList(async () => {
  const list = await api<Realm[]>("/admin/draft/realms");
  return list.map((row) => ({ ...row, interval: row.interval ?? undefined })) as unknown as Realm[];
});

const filters = computed(() => [
  {
    key: "majorName",
    label: "大境界",
    options: [...new Set(rows.value.map((row) => row.majorName).filter(Boolean))].map((name) => ({ label: name, value: name })),
  },
]);

function statusOf(row: Realm): string[] {
  const tags: string[] = [];
  if (!row.tickSeconds || !row.gainPerTick) tags.push("未设修炼速度");
  if (row.interval == null) tags.push("缺出手间隔");
  return tags;
}

function newRow(): Record<string, unknown> {
  const max = rows.value.length === 0 ? 0 : Math.max(...rows.value.map((row) => row.code));
  return { ...defaultsOf(realmSchema), code: max + 1, interval: 1.5 };
}

function bodyOf(values: Record<string, unknown>): string {
  const body: Record<string, unknown> = {};
  for (const field of realmSchema.fields) {
    body[field.key] = values[field.key];
  }
  return JSON.stringify(body);
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  if (mode === "create") {
    await api("/admin/draft/realms", { method: "POST", body: bodyOf(values) });
  } else {
    await api(`/admin/draft/realms/${editingId}`, { method: "PUT", body: bodyOf(values) });
  }
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/realms/${String(row.code)}`, { method: "DELETE" });
}

function deleteHint(row: Record<string, unknown>): string {
  return `将删除境界「${String(row.displayName)}」。已经在这个境界的测试账号需要你自己清掉（玩家管理里可清空进度）。`;
}
</script>

<style scoped>
.tag + .tag {
  margin-left: 4px;
}
</style>
