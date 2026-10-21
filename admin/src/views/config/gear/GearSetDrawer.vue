<template>
  <EditDrawer
    v-model="open"
    :title="editing ? `编辑套装：${form.displayName || editing.displayName}` : '新建套装'"
    :subtitle="editing ? `${editing.id} · ${form.members.length} / 6 件 · ${form.tiers.length} 档加成` : '只有手动装备能进套装'"
    :dirty="dirty"
    :saving="saving"
    :size="size"
    :save-text="editing ? '保存' : '创建'"
    :always-savable="!editing"
    @save="save"
  >
    <DrawerAnchors :items="anchors" />
    <SectionCard title="基本信息" anchor="set-basic">
      <div class="two-col">
        <FormRow label="套装名称" required>
          <el-input v-model="form.displayName" maxlength="20" class="w320" placeholder="例如：青云套" />
        </FormRow>
        <FormRow label="大境界" help="跟随成员：套装成员都要是同一个大境界。">
          <el-input :model-value="majorText" readonly class="w320 readonly" />
        </FormRow>
      </div>
      <FormRow label="说明" class="row-gap">
        <el-input v-model="form.description" maxlength="200" class="w560" placeholder="游戏内套装栏标题下显示；可留空" />
      </FormRow>
    </SectionCard>

    <SectionCard title="成员" anchor="set-members" desc="每个部位最多 1 件；按部位排好，空位点击从装备里选">
      <template #extra><strong>{{ form.members.length }} / 6 件</strong></template>
      <div class="member-grid">
        <div v-for="slot in slots" :key="slot.key" class="member" :class="{ empty: !memberOf(slot.key) }">
          <template v-if="memberOf(slot.key)">
            <span class="icon-box" :style="{ background: QUALITY_BG[memberOf(slot.key)!.quality] }"><img v-if="iconUrl(icons, memberOf(slot.key)!.iconKey)" :src="iconUrl(icons, memberOf(slot.key)!.iconKey)" alt="" /></span>
            <div class="member-text">
              <div>{{ memberOf(slot.key)!.displayName }} <span class="q-tag" :style="qStyle(memberOf(slot.key)!.quality)">{{ qShort(memberOf(slot.key)!.quality) }}</span></div>
              <div class="muted small">{{ slot.name }} · {{ statLine(memberOf(slot.key)!) }}</div>
            </div>
            <el-button link class="x" @click="remove(slot.key)">×</el-button>
          </template>
          <el-select v-else :model-value="''" class="picker" filterable :placeholder="`＋ 选择${slot.name}`" @change="(id: string) => add(id)">
            <el-option v-for="piece in candidates(slot.key)" :key="piece.id" :label="piece.displayName" :value="piece.id">
              <span>{{ piece.displayName }}</span>
              <span class="muted small"> · {{ piece.realmName }} · {{ qShort(piece.quality) }}</span>
            </el-option>
            <template #empty><div class="muted small pad">没有可选的：只能选 {{ majorText || "同一大境界" }} · {{ slot.name }} · 手动装备（不在别的套装里）</div></template>
          </el-select>
          <span v-if="!memberOf(slot.key)" class="muted tiny hint">只能选 {{ majorText || "同大境界" }} · {{ slot.name }} · 手动装备</span>
        </div>
      </div>
    </SectionCard>

    <SectionCard title="套装加成" anchor="set-tiers" desc="档位可增删，件数 2–6 不能重复；穿够件数的各档同时生效（叠加）">
      <div class="tiers">
        <div v-for="(tier, index) in form.tiers" :key="index" class="tier">
          <div class="tier-head">
            <span>穿满</span>
            <NumInput v-model="tier.pieces" :width="88" unit="件" :precision="0" :min="2" :max="6" />
            <span>时生效</span>
            <span class="spacer" />
            <el-button link type="danger" @click="form.tiers.splice(index, 1)">删除这一档</el-button>
          </div>
          <div class="tier-rows">
            <div class="row labels"><span class="w160">属性</span><span class="w120">加成方式 <HelpTip title="加成方式" text="百分比按角色总属性（境界 + 功法 + 装备）算；固定值直接加。" /></span><span>数值</span></div>
            <div v-for="(row, rowIndex) in tier.stats" :key="rowIndex" class="row">
              <el-select v-model="row.stat" class="w160">
                <el-option v-for="key in STAT_KEYS" :key="key" :label="STAT_LABEL[key]" :value="key" />
              </el-select>
              <el-select v-model="row.mode" class="w120">
                <el-option label="百分比" value="pct" />
                <el-option label="固定值" value="flat" />
              </el-select>
              <NumInput v-model="row.value" :width="120" :unit="row.mode === 'pct' ? '%' : '点'" :precision="2" :min="0" />
              <el-button link @click="tier.stats.splice(rowIndex, 1)">×</el-button>
            </div>
            <el-button link type="primary" :disabled="tier.stats.length >= 4" @click="tier.stats.push({ stat: 'attack', mode: 'pct', value: 5 })">＋ 添加属性</el-button>
          </div>
        </div>
        <div class="inline">
          <el-button :disabled="form.tiers.length >= 5" @click="addTier">＋ 添加档位</el-button>
          <span class="muted small">属性可选：攻击 / 防御 / 气血 / 速度；百分比按角色总属性算，固定值直接加</span>
        </div>
        <div class="total-bar">穿满 6 件合计：{{ totalText || "—" }} <span class="muted">（游戏内详情弹窗按这三档显示，已达成的亮绿色）</span></div>
      </div>
    </SectionCard>

    <template #footer-left>
      <span class="muted small">玩家已拥有的套装件会按新加成生效</span>
      <el-button v-if="editing" type="danger" plain size="small" @click="remove_">删除套装</el-button>
    </template>
  </EditDrawer>
</template>

<script setup lang="ts">
import { isConflictAbort, type Revisions } from "../../../composables/conflict";
import { ElMessage, ElMessageBox } from "element-plus";
import { computed, nextTick, reactive, ref, watch } from "vue";
import { api } from "../../../api";
import DrawerAnchors from "../../../components/DrawerAnchors.vue";
import EditDrawer from "../../../components/EditDrawer.vue";
import FormRow from "../../../components/FormRow.vue";
import HelpTip from "../../../components/HelpTip.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";
import { iconUrl, useItemIcons } from "../../../composables/itemIcons";
import { fmtStat, QUALITY_BG, STAT_KEYS, STAT_LABEL, type GearSet, type ManualPiece, type QualityRow, type SetTier, type SlotRow, type StatKey } from "./types";

const props = defineProps<{ editing: GearSet | null; manual: ManualPiece[]; slots: SlotRow[]; qualities: QualityRow[]; size: string | number; revisions?: Revisions; reloadFn?: (id: string) => Promise<void> }>();
const open = defineModel<boolean>({ required: true });
const emit = defineEmits<{ saved: [] }>();

const anchors = [
  { id: "set-basic", label: "基本信息" },
  { id: "set-members", label: "成员" },
  { id: "set-tiers", label: "套装加成" },
];
const icons = useItemIcons();
const saving = ref(false);
const form = reactive({ displayName: "", description: "", members: [] as string[], tiers: [] as SetTier[] });
const original = ref("");
const snapshot = () => JSON.stringify(form);
const dirty = computed(() => open.value && snapshot() !== original.value);

const pieces = computed(() => form.members.map((id) => props.manual.find((row) => row.id === id)).filter((row): row is ManualPiece => Boolean(row)));
const majorText = computed(() => pieces.value[0]?.majorName ?? "");
const totalText = computed(() => {
  const sum: Record<string, number> = {};
  for (const tier of form.tiers) for (const row of tier.stats) sum[`${row.stat}:${row.mode}`] = (sum[`${row.stat}:${row.mode}`] ?? 0) + (Number(row.value) || 0);
  return Object.entries(sum)
    .map(([key, value]) => {
      const [stat, mode] = key.split(":") as [StatKey, string];
      return `${STAT_LABEL[stat]} +${fmtStat(value)}${mode === "pct" ? "%" : ""}`;
    })
    .join(" · ");
});

function memberOf(slot: string): ManualPiece | undefined {
  return pieces.value.find((row) => row.slot === slot);
}

function candidates(slot: string): ManualPiece[] {
  const major = pieces.value[0]?.majorKey;
  return props.manual.filter((row) => row.slot === slot && (!row.setSlug || row.setSlug === props.editing?.id) && !form.members.includes(row.id) && (!major || row.majorKey === major));
}

function add(id: string): void {
  if (id) form.members.push(id);
}

function remove(slot: string): void {
  const row = memberOf(slot);
  if (row) form.members = form.members.filter((id) => id !== row.id);
}

function qShort(key: string): string {
  return props.qualities.find((row) => row.key === key)?.short ?? key;
}

function qStyle(key: string): Record<string, string> {
  const color = props.qualities.find((row) => row.key === key)?.color ?? "#999";
  return { color, borderColor: color };
}

function statLine(row: { attack: number; defense: number; hp: number; speed: number }): string {
  const names: Record<StatKey, string> = { attack: "攻", defense: "防", hp: "血", speed: "速" };
  return STAT_KEYS.filter((key) => row[key]).map((key) => `${names[key]} ${fmtStat(row[key])}`).join(" · ");
}

function addTier(): void {
  const used = new Set(form.tiers.map((tier) => tier.pieces));
  const pieces = [2, 3, 4, 5, 6].find((n) => !used.has(n)) ?? 6;
  form.tiers.push({ pieces, stats: [{ stat: "attack", mode: "pct", value: 5 }] });
}

/** 冲突保护参数：编辑已有的才带 */
function guardOf(id: string, title: string) {
  if (!props.revisions) return undefined;
  return {
    revisions: props.revisions,
    id,
    title,
    reload: async () => {
      await props.reloadFn?.(id);
      await nextTick();
      fill();
    },
    latest: async () => ((await api<{ sets?: { id: string }[] }>("/admin/draft/gear")).sets ?? []).find((row) => row.id === id),
  };
}

function fill(): void {
  const row = props.editing;
  form.displayName = row?.displayName ?? "";
  form.description = row?.description ?? "";
  form.members = row ? row.members.map((member) => member.id) : [];
  form.tiers = row ? JSON.parse(JSON.stringify(row.tiers)) : [{ pieces: 2, stats: [{ stat: "attack", mode: "pct", value: 6 }] }];
  original.value = snapshot();
}

async function save(): Promise<void> {
  saving.value = true;
  try {
    const body = JSON.stringify({ displayName: form.displayName, description: form.description, tiers: form.tiers, members: form.members });
    if (props.editing) await api(`/admin/draft/gear-sets/${props.editing.id}`, { method: "PUT", body, guard: guardOf(props.editing.id, `套装「${props.editing.displayName}」`) });
    else await api("/admin/draft/gear-sets", { method: "POST", body });
    ElMessage.success("已保存到草稿");
    original.value = snapshot();
    open.value = false;
    emit("saved");
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

async function remove_(): Promise<void> {
  if (!props.editing) return;
  try {
    await ElMessageBox.confirm(`删除套装「${props.editing.displayName}」？成员装备保留，只是不再属于套装。`, "删除套装", { type: "warning" });
  } catch {
    return;
  }
  await api(`/admin/draft/gear-sets/${props.editing.id}`, { method: "DELETE" });
  ElMessage.success("已删除");
  original.value = snapshot();
  open.value = false;
  emit("saved");
}

watch(open, (value) => value && fill(), { immediate: true });
</script>

<style scoped>
.two-col {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 18px 32px;
}
.row-gap {
  margin-top: 18px;
}
.member-grid {
  display: grid;
  grid-template-columns: repeat(3, 310px);
  gap: 12px;
}
.member {
  position: relative;
  display: flex;
  align-items: center;
  gap: 10px;
  height: 64px;
  padding: 0 10px;
  border: 1px solid var(--xx-border);
  border-radius: 8px;
  background: var(--xx-bg-surface);
}
.member.empty {
  display: grid;
  align-content: center;
  gap: 2px;
  border-style: dashed;
  background: #fafaf7;
}
.member-text {
  flex: 1;
  font-size: 13px;
}
.x {
  font-size: 16px;
}
.picker {
  width: 100%;
}
.hint {
  padding-left: 2px;
}
.tiny {
  font-size: 11px;
}
.pad {
  padding: 8px 12px;
}
.icon-box {
  display: inline-grid;
  place-items: center;
  width: 40px;
  height: 40px;
  border-radius: 8px;
  overflow: hidden;
}
.icon-box img {
  width: 34px;
  height: 34px;
  object-fit: contain;
}
.q-tag {
  padding: 0 6px;
  border: 1px solid;
  border-radius: 4px;
  font-size: 12px;
}
.tiers {
  display: grid;
  gap: 14px;
  max-width: 700px;
  margin: 0 auto;
}
.tier {
  border: 1px solid var(--xx-border);
  border-radius: 8px;
}
.tier-head {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 12px;
  border-bottom: 1px solid var(--xx-border);
  background: #fafaf7;
  font-size: 13px;
}
.tier-rows {
  display: grid;
  gap: 8px;
  padding: 10px 12px;
}
.row {
  display: flex;
  align-items: center;
  gap: 10px;
}
.row.labels {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.spacer {
  flex: 1;
}
.inline {
  display: flex;
  align-items: center;
  gap: 10px;
}
.total-bar {
  padding: 8px 12px;
  border-radius: 6px;
  background: #f4f6f3;
  font-size: 13px;
}
.w120 {
  width: 120px;
}
.w160 {
  width: 160px;
}
.w320 {
  width: 320px;
}
.w560 {
  width: 560px;
}
.readonly :deep(.el-input__wrapper) {
  background: #f4f5f2;
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
</style>
