<template>
  <div class="chapters-page">
    <PageHeader title="章节" desc="关卡按章节分组，章节顺序 + 关卡顺序 = 游戏里的解锁顺序。每章最后一关（或手动指定的一关）是章末大首领，其余关卡是小首领（精英）。">
      <template #actions>
        <el-button @click="reload">重新读取</el-button>
        <el-button type="primary" @click="openCreate">＋ 新建章节</el-button>
      </template>
    </PageHeader>
    <DataState :loading="loading" :error="error" :has-data="rows.length > 0" empty-text="还没有章节（没有章节时按境界顺序排关卡）" @retry="reload">
      <el-table :data="rows" class="grid" row-key="id" @row-click="openEdit">
        <el-table-column label="顺序" width="70" align="right"><template #default="{ row }">{{ row.sortOrder }}</template></el-table-column>
        <el-table-column label="章节" min-width="200">
          <template #default="{ row }">
            <div class="name-cell">
              <img :src="chapterBgThumb(row.bgKey)" class="bg-thumb" alt="" />
              <div>
                <div class="name">{{ row.displayName }}<CustomTag v-if="!row.enabled" kind="default" class="ml">已停用</CustomTag></div>
                <div class="sub">{{ row.id }}</div>
              </div>
            </div>
          </template>
        </el-table-column>
        <el-table-column label="背景" width="120"><template #default="{ row }">{{ bgName(row.bgKey) }}</template></el-table-column>
        <el-table-column label="首领特效" width="140"><template #default="{ row }">{{ fxName(row.bossFx) }}</template></el-table-column>
        <el-table-column label="关卡" min-width="320">
          <template #default="{ row }">
            <span v-if="!row.stages.length" class="muted">还没有关卡</span>
            <span v-for="stage in row.stages" :key="stage.id" class="stage-chip">{{ stage.displayName }}<TierTag :tier="stage.chief ? 'chief' : 'elite'" /></span>
          </template>
        </el-table-column>
        <el-table-column label="章末首领关" width="150">
          <template #default="{ row }">
            {{ stageName(row, row.effectiveChiefStageSlug) }}
            <CustomTag v-if="row.chiefStageSlug" kind="custom">指定</CustomTag><CustomTag v-else-if="row.effectiveChiefStageSlug" kind="default">最后一关</CustomTag>
          </template>
        </el-table-column>
        <el-table-column label="操作" width="120" align="right" fixed="right">
          <template #default="{ row }">
            <el-button link type="primary" @click.stop="openEdit(row)">编辑</el-button>
            <el-button link type="danger" @click.stop="remove(row)">删除</el-button>
          </template>
        </el-table-column>
      </el-table>
    </DataState>

    <EditDrawer v-model="drawer" :title="mode === 'create' ? '新建章节' : `编辑章节：${original?.displayName ?? ''}`" :subtitle="mode === 'edit' ? `${form.id} · ${original?.stages.length ?? 0} 关` : ''" :dirty="dirty" :saving="saving" :size="760" @save="save">
      <SectionCard title="基础信息">
        <div class="rows">
          <FormRow v-if="mode === 'create'" label="章节编号" help="小写字母、数字、下划线，字母开头；不填自动生成。关卡用它归属章节，建好后不能改。">
            <el-input v-model="form.id" style="width: 320px" placeholder="例如 heifeng" />
          </FormRow>
          <FormRow label="章节名" required><el-input v-model="form.displayName" style="width: 320px" maxlength="20" show-word-limit /></FormRow>
          <FormRow label="顺序" help="小的在前；游戏里按章节顺序 → 关卡顺序解锁。"><NumInput v-model="form.sortOrder" :precision="0" :max="9999" /></FormRow>
          <FormRow label="启用" help="停用的章节和它的关卡不出现在游戏里。"><el-switch v-model="form.enabled" /></FormRow>
        </div>
      </SectionCard>
      <SectionCard title="战斗区" desc="历练页上半部（0–960）的背景，和本章首领的光圈 / 描边特效">
        <div class="rows">
          <FormRow label="背景" help="游戏里是 bg/bg_{key}_1080x960.webp；没配时用黑风岭。">
            <div class="bg-options">
              <button v-for="bg in art?.chapterBackgrounds ?? []" :key="bg.key" type="button" class="bg-option" :class="{ on: form.bgKey === bg.key }" @click="form.bgKey = bg.key">
                <img :src="chapterBgThumb(bg.key)" alt="" />
                <span>{{ bg.name }} <em>{{ bg.key }}</em></span>
              </button>
            </div>
          </FormRow>
          <FormRow label="首领特效" help="精英 / 大首领脚下光圈和描边的配色。背景偏红黄（赤炎火山）时用「赤炎」，光圈加深色描边，不会融进背景。">
            <el-select v-model="form.bossFx" style="width: 320px">
              <el-option v-for="fx in art?.bossFx ?? []" :key="fx.key" :label="`${fx.name} · ${fx.key}`" :value="fx.key" />
            </el-select>
          </FormRow>
        </div>
      </SectionCard>
      <SectionCard title="关卡" desc="关卡归属和顺序在「关卡与Boss」里改">
        <div class="rows">
          <FormRow label="章末首领关" help="这一关的首领是大首领（章末），其余是小首领（精英）。不指定 = 本章顺序最后的一关。">
            <el-select v-model="form.chiefStageSlug" style="width: 320px" clearable placeholder="默认：本章最后一关">
              <el-option v-for="stage in original?.stages ?? []" :key="stage.id" :label="stage.displayName" :value="stage.id" />
            </el-select>
          </FormRow>
          <FormRow label="本章关卡">
            <div v-if="original?.stages.length" class="stage-list">
              <div v-for="(stage, index) in original.stages" :key="stage.id" class="stage-line">
                <span class="idx">{{ index + 1 }}</span>{{ stage.displayName }}
                <TierTag :tier="(form.chiefStageSlug || lastSlug) === stage.id ? 'chief' : 'elite'" />
              </div>
            </div>
            <span v-else class="muted">还没有关卡</span>
          </FormRow>
        </div>
      </SectionCard>
    </EditDrawer>
  </div>
</template>

<script setup lang="ts">
/** 章节列表 + 编辑（第三批，ADMIN_SPEC §8）：名称、顺序、背景（缩略图）、首领特效、章末首领关、启用。 */
import { ElMessage, ElMessageBox } from "element-plus";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import CustomTag from "../../components/CustomTag.vue";
import DataState from "../../components/DataState.vue";
import EditDrawer from "../../components/EditDrawer.vue";
import FormRow from "../../components/FormRow.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SectionCard from "../../components/SectionCard.vue";
import TierTag from "../../components/TierTag.vue";
import { chapterBgThumb, loadArtKeys, loadChapters, type ArtCatalog, type ChapterRow } from "../../composables/bossRules";
import { refreshDraftStatus } from "../../composables/draftStatus";

type Form = { id: string; displayName: string; sortOrder: number | null; bgKey: string; bossFx: string; chiefStageSlug: string | null; enabled: boolean };

const loading = ref(false);
const saving = ref(false);
const error = ref("");
const rows = ref<ChapterRow[]>([]);
const art = ref<ArtCatalog | null>(null);
const drawer = ref(false);
const mode = ref<"create" | "edit">("edit");
const original = ref<ChapterRow | null>(null);
const form = ref<Form>(blank());
const baseline = ref("");
const dirty = computed(() => JSON.stringify(form.value) !== baseline.value);
const lastSlug = computed(() => original.value?.stages.at(-1)?.id ?? "");

function blank(): Form {
  const next = rows.value.reduce((max, row) => Math.max(max, row.sortOrder), 0) + 1;
  return { id: "", displayName: "", sortOrder: next, bgKey: "heifeng", bossFx: "default", chiefStageSlug: null, enabled: true };
}
function bgName(key: string): string {
  return art.value?.chapterBackgrounds.find((row) => row.key === key)?.name ?? key;
}
function fxName(key: string): string {
  return art.value?.bossFx.find((row) => row.key === key)?.name ?? key;
}
function stageName(row: ChapterRow, slug: string | null): string {
  return row.stages.find((stage) => stage.id === slug)?.displayName ?? "—";
}

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    [rows.value, art.value] = await Promise.all([loadChapters(), loadArtKeys()]);
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function openCreate(): void {
  mode.value = "create";
  original.value = null;
  form.value = blank();
  baseline.value = JSON.stringify(form.value);
  drawer.value = true;
}
function openEdit(row: ChapterRow): void {
  mode.value = "edit";
  original.value = row;
  form.value = { id: row.id, displayName: row.displayName, sortOrder: row.sortOrder, bgKey: row.bgKey, bossFx: row.bossFx, chiefStageSlug: row.chiefStageSlug, enabled: row.enabled };
  baseline.value = JSON.stringify(form.value);
  drawer.value = true;
}

async function save(): Promise<void> {
  if (!form.value.displayName.trim()) {
    ElMessage.error("请填写章节名");
    return;
  }
  saving.value = true;
  try {
    const body = { displayName: form.value.displayName, sortOrder: form.value.sortOrder, bgKey: form.value.bgKey, bossFx: form.value.bossFx, chiefStageSlug: form.value.chiefStageSlug ?? "", enabled: form.value.enabled };
    if (mode.value === "create") {
      await api("/admin/draft/chapters", { method: "POST", body: JSON.stringify({ ...body, slug: form.value.id || undefined }) });
    } else {
      await api(`/admin/draft/chapters/${encodeURIComponent(form.value.id)}`, { method: "PUT", body: JSON.stringify(body) });
    }
    baseline.value = JSON.stringify(form.value);
    drawer.value = false;
    ElMessage.success("已保存到草稿");
    void refreshDraftStatus();
    await reload();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

async function remove(row: ChapterRow): Promise<void> {
  try {
    await ElMessageBox.confirm(row.stages.length ? `「${row.displayName}」下还有 ${row.stages.length} 个关卡，要先把关卡移到别的章节才能删除。` : `删除章节「${row.displayName}」？`, "删除章节", { type: "warning", confirmButtonText: "删除" });
  } catch {
    return;
  }
  try {
    await api(`/admin/draft/chapters/${encodeURIComponent(row.id)}`, { method: "DELETE" });
    ElMessage.success("已删除");
    void refreshDraftStatus();
    await reload();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "删除失败");
  }
}

useRefetchOnActivate(reload);
onMounted(reload);
</script>

<style scoped>
.rows {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.name-cell {
  display: flex;
  align-items: center;
  gap: 12px;
}
.bg-thumb {
  width: 72px;
  height: 64px;
  border-radius: 4px;
  object-fit: cover;
}
.name {
  color: var(--xx-text-primary);
  font-weight: 600;
}
.sub,
.muted {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.ml {
  margin-left: 6px;
}
.stage-chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin: 2px 10px 2px 0;
}
.bg-options {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}
.bg-option {
  display: flex;
  flex-direction: column;
  gap: 6px;
  padding: 6px;
  border: 1px solid var(--xx-border);
  border-radius: 6px;
  background: #fff;
  cursor: pointer;
}
.bg-option img {
  width: 135px;
  height: 120px;
  border-radius: 4px;
  object-fit: cover;
}
.bg-option span {
  font-size: 13px;
}
.bg-option em {
  color: var(--xx-text-placeholder);
  font-size: 12px;
  font-style: normal;
}
.bg-option.on {
  border-color: var(--el-color-primary);
  box-shadow: 0 0 0 2px var(--el-color-primary-light-7);
}
.stage-list {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.stage-line {
  display: flex;
  align-items: center;
  gap: 8px;
}
.idx {
  width: 20px;
  color: var(--xx-text-placeholder);
  text-align: right;
}
</style>
