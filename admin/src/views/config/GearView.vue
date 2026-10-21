<template>
  <div class="gear-page">
    <PageHeader title="装备配置" desc="上面是生成公式参数，改完保存会按公式重算 90 件装备的攻、防、血、速；下面是生成出的装备，可以单独改名称、描述、图标和掉率倍数。">
      <template #actions>
        <el-button :loading="regenerating" @click="regenerate">重新生成全部装备</el-button>
      </template>
    </PageHeader>
    <DataState :loading="loading" :error="error" :has-data="majors.length > 0" empty-text="还没有境界，生成不了装备" @retry="reload">
      <SectionCard title="生成参数" desc="单件装备战力 = 大境界预算 × 部位占比 × 品质系数">
        <template #extra>
          <CustomTag v-if="paramsDirty" kind="custom">未保存</CustomTag>
        </template>
        <div class="two-col">
          <FormRow
            label="装备预算比例"
            help="每个大境界的装备总预算 = 该大境界第一层的累计属性 × 这个比例。越大，装备相对境界越强。保存后重算全部装备。"
            :help-meta="`默认 ${DEFAULT_RATIO} · 范围 0.01–10`"
          >
            <NumInput v-model="params.gearBudgetRatio" unit="倍" :precision="2" :step="0.05" :min="0.01" :max="10" :custom="params.gearBudgetRatio !== DEFAULT_RATIO" />
          </FormRow>
          <FormRow
            label="装备速度比例"
            help="鞋子、饰品上的速度 = 按预算算出的值 × 这个比例；省下的战力补到同部位的其他属性，单件战力不变。1 = 不压速度。"
            help-meta="范围 0–1"
          >
            <NumInput v-model="params.gearSpeedFactor" unit="倍" :precision="2" :step="0.05" :max="1" />
          </FormRow>
        </div>
        <FormRow label="品质系数" help="同部位、同大境界，不同品质的战力倍数。白 1.0 为基准。" class="row-gap">
          <div class="cells">
            <div v-for="quality in QUALITIES" :key="quality.key" class="cell">
              <span class="q-label"><i class="dot" :style="{ background: quality.color }" />{{ quality.name }}</span>
              <NumInput v-model="params.qualityFactors[quality.key]" :width="120" unit="倍" :precision="2" :step="0.05" :min="0.01" />
            </div>
          </div>
        </FormRow>
        <FormRow label="部位属性占比" help="一个大境界的装备预算按这个比例分给 6 个部位，合计必须 100%。" class="row-gap">
          <div class="cells">
            <div v-for="slot in slots" :key="slot.key" class="cell">
              <span class="q-label">{{ slot.name }}</span>
              <NumInput v-model="shares[slot.key]" :width="120" unit="%" :precision="1" :max="100" />
            </div>
          </div>
          <template #note>
            <span :class="shareOk ? 'ok' : 'bad'">合计 {{ shareTotal.toFixed(1) }}% {{ shareOk ? "✓" : "（要等于 100%）" }}</span>
          </template>
        </FormRow>
        <FormRow label="战力权重" class="row-gap">
          <div class="inline">
            <span class="readonly-text">攻 {{ weightsText.attack }} · 防 {{ weightsText.defense }} · 血 {{ weightsText.hp }} · 速 {{ weightsText.speed }}</span>
            <CustomTag kind="readonly">只读</CustomTag>
            <el-button link type="primary" @click="router.push('/config/overview#power')">在配置概览中修改 ›</el-button>
          </div>
        </FormRow>
      </SectionCard>

      <SectionCard title="各大境界预算" desc="取值境界的累计面板 × 预算比例；速度取第二层">
        <el-table :data="majors" size="small" class="budget">
          <el-table-column prop="majorName" label="大境界" width="110" />
          <el-table-column label="取值境界" width="200">
            <template #default="{ row }">{{ row.budgetRealm }}<span class="muted">（速度：{{ row.speedRealm }}）</span></template>
          </el-table-column>
          <el-table-column v-for="key in STAT_KEYS" :key="key" :label="STAT_NAMES[key]" align="right">
            <template #default="{ row }">{{ row.budget ? fmt(row.budget[key]) : "—" }}</template>
          </el-table-column>
          <el-table-column label="预算战力" align="right" width="130">
            <template #default="{ row }"><strong>{{ row.budgetPower ?? "—" }}</strong></template>
          </el-table-column>
        </el-table>
      </SectionCard>

      <SectionCard title="装备列表" :desc="`共 ${allPieces.length} 件`">
        <div class="info-bar">ⓘ 重新生成只更新攻、防、血、速和战力；改过的名称、描述、图标、掉率倍数不动。</div>
        <div class="filters">
          <el-input v-model="query" placeholder="搜索名称" clearable class="f160" />
          <el-select v-model="filterMajor" placeholder="大境界" clearable class="f120">
            <el-option v-for="major in majors" :key="major.majorKey" :label="major.majorName" :value="major.majorKey" />
          </el-select>
          <el-select v-model="filterSlot" placeholder="部位" clearable class="f120">
            <el-option v-for="slot in slots" :key="slot.key" :label="slot.name" :value="slot.key" />
          </el-select>
          <el-select v-model="filterQuality" placeholder="品质" clearable class="f120">
            <el-option v-for="quality in QUALITIES" :key="quality.key" :label="quality.name" :value="quality.key" />
          </el-select>
          <el-checkbox v-model="onlyCustom">只看已自定义</el-checkbox>
          <span class="spacer" />
          <span class="muted">{{ filtered.length }} 件</span>
        </div>
        <el-table :data="paged" row-key="id" :row-class-name="rowClass" class="pieces" @row-click="openPiece">
          <el-table-column label="图标" width="72">
            <template #default="{ row }">
              <span class="icon-box" :style="{ background: bgOf(row.quality) }">
                <img v-if="iconOf(row)" :src="iconOf(row)" alt="" />
              </span>
            </template>
          </el-table-column>
          <el-table-column label="名称" min-width="240">
            <template #default="{ row }">
              <div class="name-cell">
                <span>{{ row.displayName }}<CustomTag v-if="row.nameCustom" kind="custom" class="ml">已自定义</CustomTag></span>
                <span v-if="row.nameCustom" class="muted small">默认名 {{ row.defaultName }}</span>
              </div>
            </template>
          </el-table-column>
          <el-table-column prop="majorName" label="大境界" width="90" />
          <el-table-column prop="slotName" label="部位" width="80" />
          <el-table-column label="品质" width="80">
            <template #default="{ row }"><span class="q-tag" :style="{ color: colorOf(row.quality), borderColor: colorOf(row.quality) }">{{ row.qualityName }}</span></template>
          </el-table-column>
          <el-table-column v-for="key in STAT_KEYS" :key="key" :label="STAT_NAMES[key]" width="80" align="right">
            <template #default="{ row }"><span :class="{ zero: !row[key] }">{{ row[key] ? fmt(row[key]) : "—" }}</span></template>
          </el-table-column>
          <el-table-column label="战力" width="90" align="right">
            <template #default="{ row }"><strong>{{ row.power ?? "—" }}</strong></template>
          </el-table-column>
          <el-table-column width="150" align="right">
            <template #header>掉率倍数<HelpTip title="掉率倍数" text="同大境界、同品质的 6 件按倍数分被抽中的机会：本件概率 = 掉装备 × 抽到这个品质 × 本件倍数 ÷ 同组倍数合计。普通怪掉落和首领重复奖励都按它。" meta="默认 ×1.00 · 0 = 不掉" /></template>
            <template #default="{ row }">
              <CustomTag v-if="row.dropMult !== 1" kind="custom">已自定义 ×{{ row.dropMult.toFixed(2) }}</CustomTag>
              <span v-else class="muted">×1.00</span>
            </template>
          </el-table-column>
          <el-table-column label="操作" width="150" align="right">
            <template #default="{ row }">
              <el-button link type="primary" @click.stop="openPiece(row)">编辑</el-button>
              <el-button v-if="isCustom(row)" link type="primary" @click.stop="resetPiece(row)">恢复默认</el-button>
            </template>
          </el-table-column>
        </el-table>
        <el-pagination
          v-model:current-page="page"
          v-model:page-size="pageSize"
          class="pager"
          :page-sizes="[15, 30, 90]"
          :total="filtered.length"
          layout="total, sizes, prev, pager, next, jumper"
        />
      </SectionCard>
      <SaveBar :dirty="paramsDirty" :saving="savingParams" save-text="保存并重算装备" @save="saveParams" @cancel="resetParams" />
    </DataState>

    <EditDrawer
      v-model="drawer"
      :title="`编辑装备：${editing?.displayName ?? ''}`"
      :subtitle="editing?.id"
      :dirty="pieceDirty"
      :change-count="pieceChangeCount"
      :saving="savingPiece"
      :size="drawerSize"
      @save="savePiece"
    >
      <template v-if="editing">
        <SectionCard title="基本信息">
          <div class="piece-head">
            <span class="icon-box big" :style="{ background: QUALITY_BG[editing.quality] }">
              <img v-if="pieceIconUrl" :src="pieceIconUrl" alt="" />
            </span>
            <div class="facts">
              <span><em>大境界</em>{{ editing.majorName }}</span>
              <span><em>部位</em>{{ editing.slotName }}</span>
              <span><em>品质</em>{{ editing.qualityName }}</span>
              <span><em>需求境界</em>{{ editing.requiredRealmName }}</span>
            </div>
          </div>
          <div class="stack">
            <FormRow label="图标" help="游戏里显示的图标。不选 = 自动：按部位用通用图（同部位 5 个品质共用，只换品质色底）。选了就优先用这张，客户端找不到这张图时退回自动。" help-meta="需要新版客户端（0.15.0 起）">
              <div class="icon-picker">
                <button type="button" class="pick" :class="{ on: !form.iconKey }" @click="form.iconKey = ''">
                  <span class="icon-box" :style="{ background: QUALITY_BG[editing.quality] }"><img :src="iconUrl(icons, autoGearIcon(editing.slot))" alt="" /></span>
                  <span>自动</span>
                </button>
                <button v-for="icon in pickerIcons" :key="icon.key" type="button" class="pick" :class="{ on: form.iconKey === icon.key }" :title="icon.key" @click="form.iconKey = icon.key">
                  <span class="icon-box" :style="{ background: QUALITY_BG[editing.quality] }"><img :src="iconUrl(icons, icon.key)" alt="" /></span>
                  <span>{{ icon.key.replace(/^gear_/, "") }}</span>
                </button>
              </div>
              <template #note>
                <CustomTag v-if="form.iconKey" kind="custom">已自定义</CustomTag>
                <span v-else class="muted">跟随默认（{{ autoGearIcon(editing.slot) }}）</span>
              </template>
            </FormRow>
            <FormRow label="名称" required>
              <div class="inline">
                <el-input v-model="form.displayName" class="w320" :class="{ custom: form.displayName !== editing.defaultName }" />
                <template v-if="form.displayName !== editing.defaultName">
                  <CustomTag kind="custom">已自定义</CustomTag>
                  <el-button link type="primary" @click="form.displayName = editing.defaultName">↺ 恢复默认</el-button>
                </template>
              </div>
              <template #note>默认名 {{ editing.defaultName }}</template>
            </FormRow>
            <FormRow label="描述">
              <div class="inline">
                <el-input v-model="form.description" type="textarea" :autosize="{ minRows: 2, maxRows: 4 }" class="w560" :class="{ inherit: form.description === editing.defaultDescription }" />
                <template v-if="form.description !== editing.defaultDescription">
                  <CustomTag kind="custom">已自定义</CustomTag>
                  <el-button link type="primary" @click="form.description = editing.defaultDescription">↺ 恢复默认</el-button>
                </template>
              </div>
              <template #note>默认「{{ editing.defaultDescription }}」</template>
            </FormRow>
          </div>
        </SectionCard>
        <SectionCard title="属性" desc="按生成公式算出，只读">
          <div class="cells">
            <div v-for="key in STAT_KEYS" :key="key" class="cell">
              <span class="q-label">{{ STAT_NAMES[key] }}</span>
              <NumInput :model-value="editing[key]" :width="120" readonly />
            </div>
            <div class="cell">
              <span class="q-label">战力</span>
              <NumInput :model-value="editing.power" :width="120" readonly unit="战力" />
            </div>
          </div>
          <p class="muted small formula">{{ formulaText }}</p>
        </SectionCard>
        <SectionCard title="掉落">
          <FormRow label="掉率倍数" help="同大境界、同品质的 6 件按倍数分被抽中的机会。普通怪掉落和首领重复奖励用同一规则。0 = 这件不掉。" help-meta="默认 ×1.00 · 范围 0–100">
            <div class="inline">
              <NumInput v-model="form.dropMult" prefix="×" :precision="2" :step="0.1" :max="100" :inherit-value="1" :custom="form.dropMult != null && form.dropMult !== 1" />
              <template v-if="form.dropMult != null && form.dropMult !== 1">
                <CustomTag kind="custom">已自定义</CustomTag>
                <el-button link type="primary" @click="form.dropMult = null">↺ 恢复默认</el-button>
              </template>
            </div>
            <template #note>同组（{{ editing.majorName }} · {{ editing.qualityName }}）6 件合计 ×{{ groupTotal.toFixed(2) }}，本件占 {{ (groupShare * 100).toFixed(1) }}%</template>
          </FormRow>
          <h4 class="sub-title">在各关卡的实际掉率</h4>
          <el-table :data="dropRows" size="small" empty-text="没有关卡会掉这件">
            <el-table-column prop="stage" label="关卡" min-width="140" />
            <el-table-column prop="source" label="来源" width="130" />
            <el-table-column label="掉装备" width="100" align="right"><template #default="{ row }">{{ pct(row.drop) }}</template></el-table-column>
            <el-table-column label="抽到这个品质" width="120" align="right"><template #default="{ row }">{{ pct(row.quality) }}</template></el-table-column>
            <el-table-column label="抽到本件" width="100" align="right"><template #default>{{ pct(groupShare) }}</template></el-table-column>
            <el-table-column label="本件概率" width="110" align="right"><template #default="{ row }"><strong>{{ pct(row.drop * row.quality * groupShare, 3) }}</strong></template></el-table-column>
            <el-table-column label="平均出 1 件" width="130" align="right"><template #default="{ row }">{{ every(row.drop * row.quality * groupShare, row.unit) }}</template></el-table-column>
          </el-table>
        </SectionCard>
      </template>
    </EditDrawer>
  </div>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { computed, onBeforeUnmount, onMounted, reactive, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { api } from "../../api";
import CustomTag from "../../components/CustomTag.vue";
import DataState from "../../components/DataState.vue";
import EditDrawer from "../../components/EditDrawer.vue";
import FormRow from "../../components/FormRow.vue";
import HelpTip from "../../components/HelpTip.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SaveBar from "../../components/SaveBar.vue";
import SectionCard from "../../components/SectionCard.vue";
import { useCrumbTail } from "../../composables/crumbs";
import { useDirtyGuard } from "../../composables/dirty";
import { autoGearIcon, iconUrl, useItemIcons } from "../../composables/itemIcons";

type Quality = "white" | "green" | "blue" | "purple" | "orange";
type StatKey = "attack" | "defense" | "hp" | "speed";
type Piece = {
  id: string;
  displayName: string;
  description: string;
  defaultName: string;
  defaultDescription: string;
  nameCustom: boolean;
  descriptionCustom: boolean;
  iconKey: string;
  dropMult: number;
  slot: string;
  slotName: string;
  quality: Quality;
  qualityName: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  power: number | null;
  missing: boolean;
};
type Major = {
  majorName: string;
  majorKey: string;
  requiredRealmOrder: number;
  budgetRealm: string;
  speedRealm: string;
  budget: Record<StatKey, number> | null;
  budgetPower: number | null;
  pieces: Piece[];
};
type Row = Piece & { majorKey: string; majorName: string; requiredRealmOrder: number; requiredRealmName: string };
type GearList = {
  majors: Major[];
  params: { gearBudgetRatio: number; gearSpeedFactor: number; slotShares: Record<string, number>; qualityFactors: Record<Quality, number>; powerWeights: Record<StatKey, number> | null };
  slots: { key: string; name: string }[];
};
type StageDrop = {
  id: string;
  displayName: string;
  realmCode: number;
  monsters: unknown[];
  monsterDrop: { chancePercent: number | null; weights: Record<string, number | null> };
  dropDefaults: { chancePercent: number; weights: Record<string, number>; orangeChancePercent: number };
  bosses: { name: string; repeat: { gear: boolean; orangeChancePercent: number | null } | null }[];
};

const DEFAULT_RATIO = 0.55;
const QUALITIES: { key: Quality; name: string; color: string }[] = [
  { key: "white", name: "白", color: "#9aa09b" },
  { key: "green", name: "绿", color: "#4f9a5e" },
  { key: "blue", name: "蓝", color: "#3f78b5" },
  { key: "purple", name: "紫", color: "#8a5bb8" },
  { key: "orange", name: "橙", color: "#d9822b" },
];
const QUALITY_COLOR = Object.fromEntries(QUALITIES.map((quality) => [quality.key, quality.color])) as Record<Quality, string>;
const QUALITY_BG: Record<Quality, string> = { white: "#eceeea", green: "#e3f1e5", blue: "#e2ecf7", purple: "#efe6f7", orange: "#fbeadb" };
const STAT_KEYS: StatKey[] = ["attack", "defense", "hp", "speed"];
const STAT_NAMES: Record<StatKey, string> = { attack: "攻", defense: "防", hp: "血", speed: "速" };

const router = useRouter();
const icons = useItemIcons();
const loading = ref(false);
const error = ref("");
const majors = ref<Major[]>([]);
const slots = ref<{ key: string; name: string }[]>([]);
const realms = ref<{ code: number; displayName: string; majorName: string }[]>([]);
const stages = ref<StageDrop[]>([]);
const weights = ref<Record<StatKey, number> | null>(null);
const params = reactive({ gearBudgetRatio: DEFAULT_RATIO as number | null, gearSpeedFactor: 0.3 as number | null, qualityFactors: { white: 1, green: 1, blue: 1, purple: 1, orange: 1 } as Record<Quality, number | null> });
const shares = reactive<Record<string, number | null>>({});
const savedParams = ref("");
const savingParams = ref(false);
const regenerating = ref(false);

const query = ref("");
const filterMajor = ref("");
const filterSlot = ref("");
const filterQuality = ref("");
const onlyCustom = ref(false);
const page = ref(1);
const pageSize = ref(15);

const drawer = ref(false);
const editing = ref<Row | null>(null);
const form = reactive({ displayName: "", description: "", iconKey: "", dropMult: null as number | null });
const formOriginal = ref("");
const savingPiece = ref(false);
const highlightId = ref("");
let highlightTimer = 0;
const viewWidth = ref(window.innerWidth);
const drawerSize = computed(() => (viewWidth.value < 1400 ? "calc(100vw - 220px)" : 1080));
const setCrumbTail = useCrumbTail();

const paramsSnapshot = () => JSON.stringify({ ...params, shares });
const paramsDirty = computed(() => savedParams.value !== "" && paramsSnapshot() !== savedParams.value);
useDirtyGuard(paramsDirty, async () => saveParams());

const shareTotal = computed(() => slots.value.reduce((sum, slot) => sum + (shares[slot.key] ?? 0), 0));
const shareOk = computed(() => Math.abs(shareTotal.value - 100) < 0.01);
const weightsText = computed(() => weights.value ?? { attack: "—", defense: "—", hp: "—", speed: "—" });

const allPieces = computed<Row[]>(() =>
  majors.value.flatMap((major) =>
    major.pieces.map((piece) => ({
      ...piece,
      majorKey: major.majorKey,
      majorName: major.majorName,
      requiredRealmOrder: major.requiredRealmOrder,
      requiredRealmName: realms.value.find((realm) => realm.code === major.requiredRealmOrder)?.displayName ?? `境界 ${major.requiredRealmOrder}`,
    })),
  ),
);
const filtered = computed(() =>
  allPieces.value.filter(
    (row) =>
      (!query.value || row.displayName.includes(query.value) || row.id.includes(query.value)) &&
      (!filterMajor.value || row.majorKey === filterMajor.value) &&
      (!filterSlot.value || row.slot === filterSlot.value) &&
      (!filterQuality.value || row.quality === filterQuality.value) &&
      (!onlyCustom.value || isCustom(row)),
  ),
);
const paged = computed(() => filtered.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value));
const pickerIcons = computed(() => icons.value.filter((icon) => icon.key.startsWith("gear_")));

function bgOf(quality: string): string {
  return QUALITY_BG[quality as Quality] ?? "#eceeea";
}

function colorOf(quality: string): string {
  return QUALITY_COLOR[quality as Quality] ?? "#9aa09b";
}

function isCustom(row: Piece): boolean {
  return row.nameCustom || row.descriptionCustom || Boolean(row.iconKey) || row.dropMult !== 1;
}

function iconOf(row: Piece): string {
  return iconUrl(icons.value, row.iconKey || autoGearIcon(row.slot));
}

const pieceIconUrl = computed(() => (editing.value ? iconUrl(icons.value, form.iconKey || autoGearIcon(editing.value.slot)) : ""));

function rowClass({ row }: { row: Row }): string {
  return row.id === highlightId.value ? "editing-row" : "";
}

function fmt(value: number): string {
  return Number.isInteger(value) ? String(value) : value.toFixed(2).replace(/\.?0+$/, "");
}

function pct(value: number, digits = 2): string {
  return `${(value * 100).toFixed(digits).replace(/\.?0+$/, "")}%`;
}

function every(p: number, unit: string): string {
  return p > 0 ? `约 ${Math.round(1 / p).toLocaleString()} ${unit}` : "不会掉";
}

// ---------- 生成参数 ----------
function applyParams(list: GearList): void {
  params.gearBudgetRatio = list.params.gearBudgetRatio;
  params.gearSpeedFactor = list.params.gearSpeedFactor;
  for (const quality of QUALITIES) params.qualityFactors[quality.key] = list.params.qualityFactors[quality.key];
  for (const slot of list.slots) shares[slot.key] = Math.round((list.params.slotShares[slot.key] ?? 0) * 1000) / 10;
  weights.value = list.params.powerWeights;
  savedParams.value = paramsSnapshot();
}

function resetParams(): void {
  void reload();
}

async function saveParams(): Promise<boolean> {
  if (!shareOk.value) {
    ElMessage.error(`部位属性占比合计要等于 100%（现在 ${shareTotal.value.toFixed(1)}%）`);
    return false;
  }
  savingParams.value = true;
  try {
    await api("/admin/draft/gear-params", {
      method: "PUT",
      body: JSON.stringify({
        gearBudgetRatio: params.gearBudgetRatio,
        gearSpeedFactor: params.gearSpeedFactor,
        qualityFactors: params.qualityFactors,
        slotShares: Object.fromEntries(slots.value.map((slot) => [slot.key, (shares[slot.key] ?? 0) / 100])),
      }),
    });
    ElMessage.success("已保存到草稿，装备已按新参数重算");
    await reload();
    return true;
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
    return false;
  } finally {
    savingParams.value = false;
  }
}

async function regenerate(): Promise<void> {
  regenerating.value = true;
  try {
    await api("/admin/draft/gear/regenerate", { method: "POST" });
    ElMessage.success("已重新生成；改过的名称、描述、图标、掉率倍数保持不变");
    await reload();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "生成失败");
  } finally {
    regenerating.value = false;
  }
}

// ---------- 单件 ----------
const groupPieces = computed(() => (editing.value ? allPieces.value.filter((row) => row.majorKey === editing.value!.majorKey && row.quality === editing.value!.quality) : []));
const groupTotal = computed(() => groupPieces.value.reduce((sum, row) => sum + (row.id === editing.value?.id ? (form.dropMult ?? 1) : row.dropMult), 0));
const groupShare = computed(() => (groupTotal.value > 0 ? (form.dropMult ?? 1) / groupTotal.value : 0));
const pieceDirty = computed(() => drawer.value && JSON.stringify(form) !== formOriginal.value);
const pieceChangeCount = computed(() => {
  if (!pieceDirty.value) return 0;
  const before = JSON.parse(formOriginal.value) as Record<string, unknown>;
  return (Object.keys(form) as (keyof typeof form)[]).filter((key) => before[key] !== form[key]).length;
});
const formulaText = computed(() => {
  const row = editing.value;
  if (!row) return "";
  const major = majors.value.find((item) => item.majorKey === row.majorKey);
  const share = shares[row.slot] ?? 0;
  const factor = params.qualityFactors[row.quality] ?? 1;
  return `预算战力 ${major?.budgetPower ?? "—"} × 部位占比 ${share}% × 品质系数 ${factor} ≈ ${major?.budgetPower ? Math.round(major.budgetPower * (share / 100) * factor) : "—"}；${row.slot === "shoes" || row.slot === "accessory" ? `速度 × ${params.gearSpeedFactor}，省下的补到其他属性；` : ""}战力 = 攻 × ${weights.value?.attack ?? "—"} + 防 × ${weights.value?.defense ?? "—"} + 血 × ${weights.value?.hp ?? "—"} + 速 × ${weights.value?.speed ?? "—"}`;
});

const dropRows = computed(() => {
  const row = editing.value;
  if (!row) return [];
  const majorOfRealm = (code: number) => realms.value.find((realm) => realm.code === code)?.majorName ?? "";
  const out: { stage: string; source: string; drop: number; quality: number; unit: string }[] = [];
  for (const stage of stages.value) {
    if (majorOfRealm(stage.realmCode) !== row.majorName) continue;
    const effective = (key: string) => stage.monsterDrop.weights[key] ?? stage.dropDefaults.weights[key] ?? 0;
    if (stage.monsters.length > 0 && row.quality !== "orange") {
      const total = ["white", "green", "blue", "purple"].reduce((sum, key) => sum + effective(key), 0);
      out.push({
        stage: stage.displayName,
        source: "普通怪每只",
        drop: (stage.monsterDrop.chancePercent ?? stage.dropDefaults.chancePercent) / 100,
        quality: total > 0 ? effective(row.quality) / total : 0,
        unit: "只",
      });
    }
    const boss = stage.bosses[0];
    if (boss?.repeat?.gear) {
      const orange = (boss.repeat.orangeChancePercent ?? stage.dropDefaults.orangeChancePercent) / 100;
      // 重复奖励：先判橙装，没中再按本关权重抽（白改为绿）
      const repeatWeights: Record<string, number> = { white: 0, green: effective("white") + effective("green"), blue: effective("blue"), purple: effective("purple") };
      const total = Object.values(repeatWeights).reduce((sum, value) => sum + value, 0);
      const quality = row.quality === "orange" ? orange : total > 0 ? (1 - orange) * ((repeatWeights[row.quality] ?? 0) / total) : 0;
      out.push({ stage: stage.displayName, source: `首领 ${boss.name} 重复奖励`, drop: 1, quality, unit: "次胜利" });
    }
  }
  return out.filter((item) => item.quality > 0);
});

function openPiece(row: Row): void {
  editing.value = row;
  form.displayName = row.displayName;
  form.description = row.description;
  form.iconKey = row.iconKey;
  form.dropMult = row.dropMult === 1 ? null : row.dropMult;
  formOriginal.value = JSON.stringify(form);
  highlightId.value = row.id;
  drawer.value = true;
  setCrumbTail(`编辑装备：${row.displayName}`);
}

async function savePiece(): Promise<void> {
  const row = editing.value;
  if (!row) return;
  if (!form.displayName.trim()) {
    ElMessage.error("请填写名称");
    return;
  }
  savingPiece.value = true;
  try {
    await api(`/admin/draft/gear/${row.id}`, {
      method: "PUT",
      body: JSON.stringify({
        displayName: form.displayName === row.defaultName ? null : form.displayName,
        description: form.description === row.defaultDescription ? null : form.description,
        iconKey: form.iconKey || null,
        dropMult: form.dropMult,
      }),
    });
    ElMessage.success("已保存到草稿");
    formOriginal.value = JSON.stringify(form);
    drawer.value = false;
    await reload();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    savingPiece.value = false;
  }
}

async function resetPiece(row: Row): Promise<void> {
  try {
    await ElMessageBox.confirm(`把「${row.displayName}」的名称、描述、图标、掉率倍数恢复成默认？`, "恢复默认", { type: "warning" });
  } catch {
    return;
  }
  await api(`/admin/draft/gear/${row.id}/reset`, { method: "POST" });
  ElMessage.success("已恢复默认");
  await reload();
}

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const [list, realmList, stageList] = await Promise.all([
      api<GearList>("/admin/draft/gear"),
      api<{ code: number; displayName: string; majorName: string }[]>("/admin/draft/realms"),
      api<StageDrop[]>("/admin/draft/stages"),
    ]);
    majors.value = list.majors;
    slots.value = list.slots;
    realms.value = realmList;
    stages.value = stageList;
    applyParams(list);
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function onResize(): void {
  viewWidth.value = window.innerWidth;
}

watch(drawer, (open) => {
  if (!open) {
    setCrumbTail(null);
    window.clearTimeout(highlightTimer);
    highlightTimer = window.setTimeout(() => (highlightId.value = ""), 1500);
  }
});
watch([query, filterMajor, filterSlot, filterQuality, onlyCustom], () => (page.value = 1));

onMounted(() => {
  window.addEventListener("resize", onResize);
  void reload();
});
onBeforeUnmount(() => window.removeEventListener("resize", onResize));
</script>

<style scoped>
.two-col {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 18px 64px;
}
.row-gap {
  margin-top: 20px;
}
.cells {
  display: flex;
  flex-wrap: wrap;
  gap: 16px;
}
.cell {
  display: grid;
  gap: 4px;
}
.q-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  height: 22px;
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.ok {
  color: var(--xx-success);
}
.bad {
  color: var(--xx-danger);
}
.inline {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.readonly-text {
  color: var(--xx-text-regular);
  font-family: var(--xx-font-mono);
  font-size: 13px;
}
.info-bar {
  margin-bottom: 12px;
  padding: 8px 12px;
  border: 1px solid #c9dcf0;
  border-radius: 6px;
  background: #eef5fc;
  color: #2f5f8f;
  font-size: 13px;
}
.filters {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 12px;
}
.f160 {
  width: 160px;
}
.f120 {
  width: 120px;
}
.spacer {
  flex: 1;
}
.pieces :deep(.el-table__row) {
  height: 52px;
  cursor: pointer;
}
.pieces :deep(.el-table__row.editing-row > td.el-table__cell) {
  background: #eef5f1;
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
.name-cell {
  display: grid;
  gap: 2px;
}
.ml {
  margin-left: 6px;
}
.q-tag {
  padding: 1px 8px;
  border: 1px solid;
  border-radius: 4px;
  font-size: 12px;
}
.zero {
  color: var(--xx-text-placeholder);
}
.pager {
  justify-content: flex-end;
  margin-top: 12px;
}
.piece-head {
  display: flex;
  align-items: center;
  gap: 20px;
  margin-bottom: 18px;
}
.facts {
  display: grid;
  grid-template-columns: repeat(2, 220px);
  gap: 6px 24px;
  font-size: 13px;
}
.facts em {
  margin-right: 10px;
  color: var(--xx-text-secondary);
  font-style: normal;
}
.stack {
  display: grid;
  gap: 20px;
}
.icon-picker {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  max-width: 820px;
}
.pick {
  display: grid;
  justify-items: center;
  gap: 2px;
  width: 76px;
  padding: 6px 2px;
  border: 1px solid var(--xx-border);
  border-radius: 6px;
  background: var(--xx-bg-surface);
  color: var(--xx-text-secondary);
  font-size: 11px;
  cursor: pointer;
}
.pick.on {
  border-color: #d9b874;
  background: #fffcf3;
  color: #8f5c0c;
}
.w320 {
  width: 320px;
}
.w560 {
  width: 560px;
}
.custom :deep(.el-input__wrapper) {
  background: #fffcf3;
  box-shadow: 0 0 0 1px #d9b874 inset;
}
.inherit :deep(.el-textarea__inner) {
  background: #faf9f4;
  color: #98a19c;
}
.formula {
  margin: 10px 0 0;
}
.sub-title {
  margin: 20px 0 8px;
  font-size: 14px;
}
.muted {
  color: var(--xx-text-secondary);
  font-size: 13px;
}
.small {
  font-size: 12px;
}
</style>
