<template>
  <EditDrawer
    v-model="open"
    :title="editing ? `编辑装备：${editing.displayName}` : '新建装备'"
    :subtitle="editing ? `${editing.id} · 手动装备` : '手动装备 · 数值手填'"
    :dirty="dirty"
    :change-count="changeCount"
    :saving="saving"
    :size="size"
    :save-text="editing ? '保存' : '创建'"
    :always-savable="!editing"
    @save="save(false)"
  >
    <SectionCard title="基本信息">
      <div class="stack">
        <FormRow label="图标" required help="游戏里显示的图标，底色按品质自动加。图标库来自游戏的 icons/eq_*；美术把新图放进 icons 并登记后，这里自动出现。">
          <div class="inline">
            <span class="icon-box big" :style="{ background: QUALITY_BG[form.quality] }"><img v-if="iconSrc" :src="iconSrc" alt="" /></span>
            <el-popover v-model:visible="picking" placement="bottom-start" :width="560" trigger="click">
              <template #reference>
                <el-button size="small">更换图标 ▾</el-button>
              </template>
              <div class="picker-head"><strong>选择图标</strong><span class="muted small">来自游戏图标库 icons/eq_*，共 {{ eqIcons.length }} 张</span></div>
              <div class="icon-grid">
                <button v-for="icon in eqIcons" :key="icon.key" type="button" class="pick" :class="{ on: form.iconKey === icon.key }" :title="icon.key" @click="pickIcon(icon.key)">
                  <span class="icon-box" :style="{ background: QUALITY_BG[form.quality] }"><img :src="iconUrl(icons, icon.key)" alt="" /></span>
                  <span>{{ ICON_NAMES[icon.key] ?? icon.key.replace(/^eq_/, "") }}</span>
                </button>
              </div>
              <p class="muted small">要用新图标：美术把图放进 icons/ 并登记，这里会自动出现</p>
            </el-popover>
            <span class="muted small">底色 = 品质色，自动</span>
          </div>
        </FormRow>
        <div class="two-col">
          <FormRow label="名称" required>
            <el-input v-model="form.displayName" maxlength="40" class="w320" placeholder="例如：青云剑" />
          </FormRow>
          <FormRow label="所属套装" help="一件装备最多属于一个套装；只有手动装备能进套装。选了套装后，部位不能和套装里已有的成员重复，大境界也要一样。">
            <el-select v-model="form.setSlug" clearable placeholder="不属于套装" class="w320">
              <el-option v-for="set in sets" :key="set.id" :label="`${set.displayName}（已有 ${memberCount(set)} / 6 件）`" :value="set.id" />
            </el-select>
          </FormRow>
          <FormRow label="大境界" required>
            <el-select v-model="form.majorName" class="w320" placeholder="选择大境界" @change="onMajor">
              <el-option v-for="major in majorNames" :key="major" :label="major" :value="major" />
            </el-select>
          </FormRow>
          <FormRow label="需求境界" required help="穿戴需要达到的境界。同一个大境界里选哪一层都可以。">
            <el-select v-model="form.requiredRealmOrder" class="w320" placeholder="选择需求境界">
              <el-option v-for="realm in majorRealms" :key="realm.code" :label="realm.displayName" :value="realm.code" />
            </el-select>
          </FormRow>
          <FormRow label="部位" required>
            <el-select v-model="form.slot" class="w320" placeholder="选择部位">
              <el-option v-for="slot in slots" :key="slot.key" :label="slot.name" :value="slot.key" :disabled="slotTaken(slot.key)">
                <span>{{ slot.name }}</span><span v-if="slotTaken(slot.key)" class="muted small"> · 套装里已有</span>
              </el-option>
            </el-select>
          </FormRow>
          <FormRow label="品质" required>
            <el-select v-model="form.quality" class="w320">
              <el-option v-for="quality in qualities" :key="quality.key" :label="`${quality.short}（${quality.name}）`" :value="quality.key">
                <span class="q-tag" :style="{ color: quality.color, borderColor: quality.color }">{{ quality.short }}</span> {{ quality.name }}
              </el-option>
            </el-select>
          </FormRow>
        </div>
        <FormRow label="描述">
          <el-input v-model="form.description" type="textarea" maxlength="200" :autosize="{ minRows: 2, maxRows: 4 }" class="w656" placeholder="玩家在物品详情弹窗里看到；可留空" />
        </FormRow>
      </div>
    </SectionCard>

    <SectionCard title="属性" desc="手填；保存后不会被「重新生成数值」改动">
      <FormRow label="数值" help="攻击、防御、气血、速度至少填一项。下面灰字是同大境界、同部位、同品质公式装备的数值，供参考。">
        <div class="stats">
          <div v-for="key in STAT_KEYS" :key="key" class="cell">
            <span class="q-label">{{ STAT_LABEL[key] }}</span>
            <NumInput v-model="form[key]" :width="120" :precision="2" :step="1" :min="0" :max="1000000" />
            <span class="muted small">公式 {{ reference ? fmtStat(reference[key]) || "—" : "—" }}</span>
          </div>
          <div class="cell power">
            <span class="q-label">战力（实时）</span>
            <div class="inline">
              <strong class="big-num">{{ power ?? "—" }}</strong>
              <span v-if="diffText" class="diff" :class="diffKind">{{ diffText }}</span>
            </div>
          </div>
        </div>
      </FormRow>
      <div v-if="reference" class="ref-bar">
        参考 · 同境界同部位同品质的公式装备 <strong>{{ reference.displayName }}</strong>：{{ referenceText }} · 战力 {{ reference.power ?? "—" }}
        <span class="muted">（套装件建议比公式低 5–10%，差额由套装加成补）</span>
      </div>
    </SectionCard>

    <SectionCard title="掉落与养成">
      <div class="two-col">
        <FormRow label="参与随机掉落" help="关 = 只通过关卡的指定掉落、后台补发获得。开 = 加入「需求境界所在大境界 + 品质」的随机池，和同组公式装备按掉率倍数分被抽中的机会。">
          <div class="inline">
            <el-switch v-model="form.randomDrop" />
            <span class="muted small">{{ form.randomDrop ? "开 · 加入本境界本品质的随机池" : "关 · 只通过指定掉落、补发获得" }}</span>
          </div>
        </FormRow>
        <FormRow label="掉率倍数" help="同大境界、同品质的装备按倍数分被抽中的机会。0 = 不掉。只有参与随机掉落时能填。" help-meta="默认 ×1.00 · 范围 0–100">
          <NumInput v-model="form.dropMult" prefix="×" :precision="2" :step="0.1" :max="100" :readonly="!form.randomDrop" />
          <template #note><span class="muted small">打开「参与随机掉落」后才能填</span></template>
        </FormRow>
      </div>
      <FormRow label="强化与分解" class="row-gap">
        <div class="inline">
          <CustomTag kind="readonly">可以强化、分解</CustomTag>
          <span class="small">{{ enhanceText }}</span>
          <el-button link type="primary" @click="router.push('/config/overview#enhance')">配置概览 ›</el-button>
        </div>
        <template #note>和公式装备完全一样，按品质读强化规则；不单独配置</template>
      </FormRow>
      <FormRow v-if="editing && editing.designated.length > 0" label="指定掉落" class="row-gap">
        <div class="small">
          <div v-for="use in editing.designated" :key="`${use.stageId}-${use.trigger}`">{{ use.stageName }} · {{ TRIGGER_NAMES[use.trigger] ?? use.trigger }} · {{ use.chancePercent }}% × {{ use.count }}</div>
        </div>
      </FormRow>
    </SectionCard>

    <template #footer-left>
      <span class="muted small">{{ editing ? `编号 ${editing.id}` : `编号保存后自动生成（${nextId}）` }}</span>
      <el-button v-if="!editing" :loading="saving" @click="save(true)">保存并继续新建</el-button>
    </template>
  </EditDrawer>
</template>

<script setup lang="ts">
import { isConflictAbort, type Revisions } from "../../../composables/conflict";
import { ElMessage } from "element-plus";
import { computed, nextTick, reactive, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { api } from "../../../api";
import CustomTag from "../../../components/CustomTag.vue";
import EditDrawer from "../../../components/EditDrawer.vue";
import FormRow from "../../../components/FormRow.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";
import { iconUrl, useItemIcons } from "../../../composables/itemIcons";
import { fmtStat, powerOf, QUALITY_BG, STAT_KEYS, STAT_LABEL, type GearSet, type MajorInfo, type ManualPiece, type Quality, type QualityRow, type RealmInfo, type SlotRow, type StatKey } from "./types";

const props = defineProps<{
  editing: ManualPiece | null;
  majors: MajorInfo[];
  realms: RealmInfo[];
  sets: GearSet[];
  slots: SlotRow[];
  qualities: QualityRow[];
  weights: Record<StatKey, number> | null;
  nextId: string;
  enhance: { qualities?: Record<string, { cap: number; costMult: number; decomposeExp: number; breakthroughs: { level: number; materials: { itemSlug: string; count: number }[] }[] }> } | null;
  size: string | number;
  /** 旧表单覆盖保护：GearView 的版本号和「重新读取」 */
  revisions?: Revisions;
  reloadFn?: (id: string) => Promise<void>;
}>();
const open = defineModel<boolean>({ required: true });
const emit = defineEmits<{ saved: [id: string] }>();

const ICON_NAMES: Record<string, string> = { eq_sword: "剑", eq_robe: "袍", eq_crown: "冠", eq_bracers: "护手", eq_boots: "靴", eq_pendant: "佩" };
const TRIGGER_NAMES: Record<string, string> = { monster: "普通怪每只", boss_first: "首领首通", boss_repeat: "首领重复" };
const MATERIAL_NAMES: Record<string, string> = { enh_stone_low: "突破石·下品", enh_stone_mid: "突破石·中品", enh_stone_high: "突破石·上品" };

const router = useRouter();
const icons = useItemIcons();
const picking = ref(false);
const saving = ref(false);
const blank = () => ({
  iconKey: "",
  displayName: "",
  setSlug: "" as string,
  majorName: "",
  requiredRealmOrder: null as number | null,
  slot: "",
  quality: "blue" as Quality,
  description: "",
  attack: null as number | null,
  defense: null as number | null,
  hp: null as number | null,
  speed: null as number | null,
  randomDrop: false,
  dropMult: 1 as number | null,
});
const form = reactive(blank());
const original = ref("");

const eqIcons = computed(() => icons.value.filter((icon) => icon.key.startsWith("eq_")));
const iconSrc = computed(() => (form.iconKey ? iconUrl(icons.value, form.iconKey) : ""));
const majorNames = computed(() => [...new Set(props.realms.map((realm) => realm.majorName))]);
const majorRealms = computed(() => props.realms.filter((realm) => realm.majorName === form.majorName));
const majorKey = computed(() => props.majors.find((major) => major.majorName === form.majorName)?.majorKey ?? null);
const reference = computed(() => props.majors.find((major) => major.majorKey === majorKey.value)?.pieces.find((piece) => piece.slot === form.slot && piece.quality === form.quality) ?? null);
const referenceText = computed(() => (reference.value ? STAT_KEYS.filter((key) => reference.value![key]).map((key) => `${STAT_LABEL[key].slice(0, 1)} ${fmtStat(reference.value![key])}`).join(" · ") : ""));
const power = computed(() => powerOf(form, props.weights));
const diffPct = computed(() => (reference.value?.power && power.value != null ? Math.round(((power.value - reference.value.power) / reference.value.power) * 100) : null));
const diffText = computed(() => (diffPct.value == null ? "" : diffPct.value === 0 ? "和公式持平" : diffPct.value < 0 ? `比公式低 ${-diffPct.value}%` : `比公式高 ${diffPct.value}%`));
const diffKind = computed(() => (diffPct.value != null && diffPct.value > 0 ? "up" : "down"));
const enhanceText = computed(() => {
  const rule = props.enhance?.qualities?.[form.quality];
  const quality = props.qualities.find((row) => row.key === form.quality);
  if (!rule) return "按品质默认值";
  const nodes = rule.breakthroughs.map((node) => `+${node.level} ${node.materials.map((m) => `${MATERIAL_NAMES[m.itemSlug] ?? m.itemSlug} ×${m.count}`).join("、")}`).join(" · ");
  return `按 ${quality?.short ?? ""}（${quality?.name ?? ""}）默认：强化上限 +${rule.cap} · 经验倍数 ${rule.costMult} · 分解 ${rule.decomposeExp} 经验${nodes ? ` · ${nodes}` : ""}`;
});
const snapshot = () => JSON.stringify(form);
const dirty = computed(() => open.value && snapshot() !== original.value);
const changeCount = computed(() => {
  if (!dirty.value) return 0;
  const before = JSON.parse(original.value) as Record<string, unknown>;
  return (Object.keys(form) as (keyof typeof form)[]).filter((key) => before[key] !== form[key]).length;
});

function memberCount(set: GearSet): number {
  return set.members.length;
}

function slotTaken(slot: string): boolean {
  const set = props.sets.find((row) => row.id === form.setSlug);
  return Boolean(set?.members.some((member) => member.slot === slot && member.id !== props.editing?.id));
}

function pickIcon(key: string): void {
  form.iconKey = key;
  picking.value = false;
}

function onMajor(): void {
  form.requiredRealmOrder = majorRealms.value[0]?.code ?? null;
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
    latest: async () => ((await api<{ manual?: { id: string }[] }>("/admin/draft/gear")).manual ?? []).find((row) => row.id === id),
  };
}

function fill(): void {
  Object.assign(form, blank());
  const row = props.editing;
  if (row) {
    Object.assign(form, {
      iconKey: row.iconKey,
      displayName: row.displayName,
      setSlug: row.setSlug ?? "",
      majorName: props.realms.find((realm) => realm.code === row.requiredRealmOrder)?.majorName ?? row.majorName,
      requiredRealmOrder: row.requiredRealmOrder,
      slot: row.slot,
      quality: row.quality,
      description: row.description,
      attack: row.attack,
      defense: row.defense,
      hp: row.hp,
      speed: row.speed,
      randomDrop: row.randomDrop,
      dropMult: row.dropMult,
    });
  } else {
    form.majorName = majorNames.value[0] ?? "";
    form.requiredRealmOrder = majorRealms.value[0]?.code ?? null;
    form.slot = props.slots[0]?.key ?? "";
    form.iconKey = eqIcons.value[0]?.key ?? "";
  }
  original.value = snapshot();
}

async function save(again: boolean): Promise<void> {
  saving.value = true;
  try {
    const body = JSON.stringify({ ...form, setSlug: form.setSlug || null, dropMult: form.randomDrop ? form.dropMult : 1 });
    const result = props.editing
      ? await api<{ id: string }>(`/admin/draft/gear/manual/${props.editing.id}`, { method: "PUT", body, guard: guardOf(props.editing.id, `手动装备「${props.editing.displayName}」`) })
      : await api<{ id: string }>("/admin/draft/gear/manual", { method: "POST", body });
    ElMessage.success(props.editing ? "已保存，已生效" : `已创建 ${result.id}`);
    emit("saved", result.id);
    if (again) {
      const keep = { majorName: form.majorName, requiredRealmOrder: form.requiredRealmOrder, quality: form.quality, setSlug: form.setSlug };
      Object.assign(form, blank(), keep);
      original.value = snapshot();
    } else {
      original.value = snapshot();
      open.value = false;
    }
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

watch(open, (value) => value && fill(), { immediate: true });
</script>

<style scoped>
.stack {
  display: grid;
  gap: 18px;
}
.two-col {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 18px 32px;
}
.row-gap {
  margin-top: 18px;
}
.inline {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
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
.icon-box.big {
  width: 64px;
  height: 64px;
}
.icon-box.big img {
  width: 56px;
  height: 56px;
}
.picker-head {
  display: flex;
  gap: 10px;
  align-items: baseline;
  margin-bottom: 10px;
}
.icon-grid {
  display: grid;
  grid-template-columns: repeat(6, 76px);
  gap: 8px;
  margin-bottom: 8px;
}
.pick {
  display: grid;
  justify-items: center;
  gap: 2px;
  padding: 6px 2px;
  border: 1px solid var(--xx-border);
  border-radius: 6px;
  background: var(--xx-bg-surface);
  color: var(--xx-text-secondary);
  font-size: 11px;
  cursor: pointer;
}
.pick .icon-box {
  width: 64px;
  height: 64px;
}
.pick .icon-box img {
  width: 56px;
  height: 56px;
}
.pick.on {
  border: 2px solid #1f8a8a;
  color: #1f6b6b;
}
.stats {
  display: flex;
  gap: 16px;
  align-items: flex-start;
  flex-wrap: wrap;
}
.cell {
  display: grid;
  gap: 4px;
}
.cell.power {
  margin-left: 12px;
}
.q-label {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.big-num {
  font-size: 26px;
  color: #2f6b4f;
}
.diff {
  padding: 1px 8px;
  border-radius: 4px;
  font-size: 12px;
}
.diff.down {
  background: #fbeadb;
  color: #a85a12;
}
.diff.up {
  background: #e3f1e5;
  color: #2f6b3f;
}
.ref-bar {
  margin-top: 14px;
  padding: 8px 12px;
  border-radius: 6px;
  background: #f4f6f3;
  font-size: 13px;
}
.q-tag {
  padding: 0 6px;
  border: 1px solid;
  border-radius: 4px;
  font-size: 12px;
}
.w320 {
  width: 320px;
}
.w656 {
  width: 656px;
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
</style>
