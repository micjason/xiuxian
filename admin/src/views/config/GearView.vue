<template>
  <div class="gear-page">
    <PageHeader title="装备配置" desc="公式装备 90 件按境界属性自动生成；手动装备由策划新建、数值手填，可以组成套装。发给玩家统一走「发放指定装备」接口。">
      <template #actions>
        <el-button @click="router.push('/system/audit?tab=grants')">发放记录</el-button>
        <el-button @click="grantOpen = true">补发装备</el-button>
        <el-button v-if="segment === 'gear'" :loading="regenerating" @click="regenerate">重新生成数值</el-button>
        <el-button v-if="segment === 'gear'" type="primary" @click="openManual(null)">＋ 新建装备</el-button>
        <el-button v-else type="primary" @click="openSet(null)">＋ 新建套装</el-button>
      </template>
    </PageHeader>
    <el-radio-group v-model="segment" class="segment">
      <el-radio-button value="gear">装备 <span class="seg-n">{{ allRows.length }} 件</span></el-radio-button>
      <el-radio-button value="sets">套装 <span class="seg-n">{{ sets.length }} 套</span></el-radio-button>
    </el-radio-group>
    <DataState :loading="loading" :error="error" :has-data="majors.length > 0" empty-text="还没有境界，生成不了装备" @retry="reload">
      <template v-if="segment === 'sets'">
        <SectionCard title="套装列表" desc="一件装备最多属于一个套装；只有手动装备能进套装">
          <el-table :data="sets" row-key="id" class="pieces" empty-text="还没有套装，点右上角「＋ 新建套装」" @row-click="openSet">
            <el-table-column prop="displayName" label="套装名称" min-width="120" />
            <el-table-column label="大境界" width="90"><template #default="{ row }">{{ row.majorName || "—" }}</template></el-table-column>
            <el-table-column label="品质" width="80">
              <template #default="{ row }">
                <span v-if="row.quality && row.quality !== 'mixed'" class="q-tag" :style="{ color: colorOf(row.quality), borderColor: colorOf(row.quality) }">{{ qualityShort(row.quality) }}</span>
                <span v-else class="muted">{{ row.quality === "mixed" ? "混合" : "—" }}</span>
              </template>
            </el-table-column>
            <el-table-column label="成员" width="230">
              <template #default="{ row }">
                <div class="mini-icons">
                  <template v-for="slot in slots" :key="slot.key">
                    <span v-if="memberIn(row, slot.key)" class="icon-box mini" :style="{ background: bgOf(memberIn(row, slot.key)!.quality) }" :title="memberIn(row, slot.key)!.displayName"><img v-if="iconUrl(icons, memberIn(row, slot.key)!.iconKey)" :src="iconUrl(icons, memberIn(row, slot.key)!.iconKey)" alt="" /></span>
                    <span v-else class="icon-box mini empty" :title="`${slot.name}：空`" />
                  </template>
                </div>
              </template>
            </el-table-column>
            <el-table-column label="件数" width="70"><template #default="{ row }"><strong>{{ row.members.length }} / 6</strong></template></el-table-column>
            <el-table-column label="套装加成" min-width="320">
              <template #default="{ row }">
                <div v-for="tier in row.tiers" :key="tier.pieces" class="tier-line"><span class="tier-tag">{{ tier.pieces }} 件</span>{{ tierText(tier) }}</div>
              </template>
            </el-table-column>
            <el-table-column label="更新时间" width="160"><template #default="{ row }">{{ new Date(row.updatedAt).toLocaleString("zh-CN", { hour12: false }) }}</template></el-table-column>
            <el-table-column label="操作" width="120" align="right">
              <template #default="{ row }">
                <el-button link type="primary" @click.stop="openSet(row)">编辑</el-button>
                <el-button link type="danger" @click.stop="deleteSet(row)">删除</el-button>
              </template>
            </el-table-column>
          </el-table>
        </SectionCard>
      </template>
      <template v-else>
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

      <SectionCard title="装备列表" :desc="`共 ${allRows.length} 件 · 公式 ${allPieces.length} · 手动 ${manual.length}`">
        <div class="info-bar">ⓘ 「重新生成数值」只更新公式装备的攻、防、血、速和战力（改过的名称、描述、图标、掉率倍数不动）；手动装备永远不被覆盖。手动装备默认不参与随机掉落，只靠关卡指定掉落和补发获得。</div>
        <div class="filters">
          <el-input v-model="query" placeholder="搜索名称" clearable class="f160" />
          <el-select v-model="filterOrigin" placeholder="来源" clearable class="f100">
            <el-option label="公式" value="formula" />
            <el-option label="手动" value="manual" />
          </el-select>
          <el-select v-model="filterSet" placeholder="套装" clearable class="f100">
            <el-option v-for="set in sets" :key="set.id" :label="set.displayName" :value="set.id" />
          </el-select>
          <el-select v-model="filterMajor" placeholder="大境界" clearable class="f120">
            <el-option v-for="major in majors" :key="major.majorKey" :label="major.majorName" :value="major.majorKey" />
          </el-select>
          <el-select v-model="filterSlot" placeholder="部位" clearable class="f120">
            <el-option v-for="slot in slots" :key="slot.key" :label="slot.name" :value="slot.key" />
          </el-select>
          <el-select v-model="filterQuality" placeholder="品质" clearable class="f120">
            <el-option v-for="quality in qualities" :key="quality.key" :label="quality.short" :value="quality.key" />
          </el-select>
          <el-checkbox v-model="onlyCustom">只看已自定义</el-checkbox>
          <span class="spacer" />
          <span class="muted">{{ filtered.length }} 件</span>
        </div>
        <el-table :data="paged" row-key="id" :row-class-name="rowClass" class="pieces" @row-click="openRow">
          <el-table-column label="图标" width="72">
            <template #default="{ row }">
              <span class="icon-box" :style="{ background: bgOf(row.quality) }">
                <img v-if="iconOf(row)" :src="iconOf(row)" alt="" />
              </span>
            </template>
          </el-table-column>
          <el-table-column label="名称" min-width="200">
            <template #default="{ row }">
              <div class="name-cell">
                <span>{{ row.displayName }}<CustomTag v-if="row.nameCustom && row.origin !== 'manual'" kind="custom" class="ml">已自定义</CustomTag></span>
                <span v-if="row.nameCustom && row.origin !== 'manual'" class="muted small">默认名 {{ row.defaultName }}</span>
              </div>
            </template>
          </el-table-column>
          <el-table-column label="来源" width="76">
            <template #default="{ row }"><span class="origin" :class="row.origin">{{ row.origin === "manual" ? "手动" : "公式" }}</span></template>
          </el-table-column>
          <el-table-column label="套装" width="96">
            <template #default="{ row }">
              <el-button v-if="row.setSlug" link type="primary" @click.stop="openSet(sets.find((set) => set.id === row.setSlug) ?? null)">{{ setName(row.setSlug) }}</el-button>
              <span v-else class="muted">—</span>
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
              <span v-if="row.origin === 'manual' && !row.randomDrop" class="muted">不参与随机</span>
              <CustomTag v-else-if="row.dropMult !== 1" kind="custom">已自定义 ×{{ row.dropMult.toFixed(2) }}</CustomTag>
              <span v-else class="muted">×1.00</span>
            </template>
          </el-table-column>
          <el-table-column label="操作" width="150" align="right">
            <template #default="{ row }">
              <el-button link type="primary" @click.stop="openRow(row)">编辑</el-button>
              <el-button v-if="row.origin !== 'manual' && isCustom(row)" link type="primary" @click.stop="resetPiece(row)">恢复默认</el-button>
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
      </template>
    </DataState>

    <ManualGearDrawer
      v-model="manualOpen"
      :editing="manualEditing"
      :majors="majors"
      :realms="realms"
      :sets="sets"
      :slots="slots"
      :qualities="qualities"
      :weights="weights"
      :next-id="nextManualId"
      :enhance="enhanceRules"
      :size="drawerSize"
      :revisions="itemRev"
      :reload-fn="reloadManual"
      @saved="reload"
    />
    <GearSetDrawer v-model="setOpen" :editing="setEditing" :manual="manual" :slots="slots" :qualities="qualities" :size="drawerSize" :revisions="setRev" :reload-fn="reloadSet" @saved="reload" />
    <GrantDrawer v-model="grantOpen" :size="drawerSize" />

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
import { useRevisions } from "../../composables/revisions";
import { isConflictAbort } from "../../composables/conflict";
import { ElMessage, ElMessageBox } from "element-plus";
import { useRefetchOnActivate } from "../../composables/dataVersion";
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
import GrantDrawer from "../../components/GrantDrawer.vue";
import GearSetDrawer from "./gear/GearSetDrawer.vue";
import ManualGearDrawer from "./gear/ManualGearDrawer.vue";
import { tierText, type GearSet, type ManualPiece, type QualityRow } from "./gear/types";

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
  origin?: "formula" | "manual";
  setSlug?: string | null;
  randomDrop?: boolean;
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
  manual: ManualPiece[];
  sets: GearSet[];
  qualities: QualityRow[];
  nextManualId: string;
};
type StageDrop = {
  id: string;
  displayName: string;
  realmCode: number;
  monsters: unknown[];
  monsterDrop: { chancePercent: number | null; weights: Record<string, number | null> };
  dropDefaults: { chancePercent: number; weights: Record<string, number> };
  // rules = 生效的首领规则（配置概览「首领规则」默认 + 本关覆盖，服务端算好）
  bosses: {
    name: string;
    tier: "elite" | "chief" | null;
    rules: { repeatRewards: boolean; gearQualityPct: Record<string, number>; repeatGearQualityPct?: Record<string, number>; idleSpawn?: boolean; idleSpawnWaves?: number } | null;
    firstClear: { kind: string; amount?: number }[];
    repeat: { gear: boolean } | null;
  }[];
};

const DEFAULT_RATIO = 0.55;
// 品质表由服务端统一下发（catalog.ts）；这里只放加载前的占位
const qualities = ref<QualityRow[]>([
  { key: "white", name: "凡品", short: "白", color: "#9aa3a0" },
  { key: "green", name: "良品", short: "绿", color: "#3c9a4e" },
  { key: "blue", name: "精品", short: "蓝", color: "#2e7fc4" },
  { key: "purple", name: "珍品", short: "紫", color: "#8a4fc0" },
  { key: "orange", name: "绝品", short: "橙", color: "#e07b1f" },
]);
const QUALITIES = computed(() => qualities.value.map((row) => ({ key: row.key, name: row.short, color: row.color })));
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
const manual = ref<ManualPiece[]>([]);
const sets = ref<GearSet[]>([]);
const nextManualId = ref("gear_m_0001");
const enhanceRules = ref<null | { qualities?: Record<string, { cap: number; costMult: number; decomposeExp: number; breakthroughs: { level: number; materials: { itemSlug: string; count: number }[] }[] }> }>(null);
const segment = ref<"gear" | "sets">("gear");
const filterOrigin = ref("");
const filterSet = ref("");
const manualOpen = ref(false);
const manualEditing = ref<ManualPiece | null>(null);
const setOpen = ref(false);
const setEditing = ref<GearSet | null>(null);
const grantOpen = ref(false);
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
// 手动装备排在前面
const allRows = computed<Row[]>(() => [
  ...manual.value.map(
    (row) =>
      ({
        ...row,
        defaultName: row.displayName,
        defaultDescription: row.description,
        nameCustom: false,
        descriptionCustom: false,
        missing: false,
        requiredRealmName: row.realmName,
        majorKey: row.majorKey ?? "",
      }) as unknown as Row,
  ),
  ...allPieces.value.map((row) => ({ ...row, origin: "formula" as const })),
]);
const filtered = computed(() =>
  allRows.value.filter(
    (row) =>
      (!query.value || row.displayName.includes(query.value) || row.id.includes(query.value)) &&
      (!filterMajor.value || row.majorKey === filterMajor.value) &&
      (!filterSlot.value || row.slot === filterSlot.value) &&
      (!filterQuality.value || row.quality === filterQuality.value) &&
      (!filterOrigin.value || (row.origin ?? "formula") === filterOrigin.value) &&
      (!filterSet.value || row.setSlug === filterSet.value) &&
      (!onlyCustom.value || isCustom(row)),
  ),
);
const paged = computed(() => filtered.value.slice((page.value - 1) * pageSize.value, page.value * pageSize.value));
const pickerIcons = computed(() => icons.value.filter((icon) => icon.key.startsWith("gear_")));

function colorOfQuality(quality: string): string {
  return qualities.value.find((row) => row.key === quality)?.color ?? "#9aa09b";
}

function qualityShort(quality: string): string {
  return qualities.value.find((row) => row.key === quality)?.short ?? quality;
}

function setName(slug: string | null | undefined): string {
  return sets.value.find((set) => set.id === slug)?.displayName ?? "—";
}

function memberIn(set: GearSet, slot: string) {
  return set.members.find((member) => member.slot === slot);
}

function openRow(row: Row): void {
  if (row.origin === "manual") {
    openManual(manual.value.find((item) => item.id === row.id) ?? null);
  } else {
    openPiece(row);
  }
}

function openManual(row: ManualPiece | null): void {
  manualEditing.value = row;
  manualOpen.value = true;
  highlightId.value = row?.id ?? "";
}

function openSet(row: GearSet | null): void {
  setEditing.value = row;
  setOpen.value = true;
}

async function deleteSet(row: GearSet): Promise<void> {
  try {
    await ElMessageBox.confirm(`删除套装「${row.displayName}」？成员装备保留，只是不再属于套装。`, "删除套装", { type: "warning" });
  } catch {
    return;
  }
  await api(`/admin/draft/gear-sets/${row.id}`, { method: "DELETE" });
  ElMessage.success("已删除");
  await reload();
}

function bgOf(quality: string): string {
  return QUALITY_BG[quality as Quality] ?? "#eceeea";
}

function colorOf(quality: string): string {
  return colorOfQuality(quality);
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
  for (const quality of QUALITIES.value) params.qualityFactors[quality.key as Quality] = list.params.qualityFactors[quality.key as Quality];
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
      guard: { revisions: globalRev, id: 1, reload, latest: async () => (await latestGear()).params, title: "装备生成参数" },
    });
    ElMessage.success("已保存，已生效；装备已按新参数重算");
    await reload();
    return true;
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
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
    // 首领给的装备按首领规则的「首通 / 重复奖励装备品质」抽（配置概览 → 首领规则；关卡可单独覆盖）。第四批：一套规则
    const boss = stage.bosses[0];
    const pct = boss?.rules?.gearQualityPct;
    if (boss && pct) {
      const quality = (pct[row.quality] ?? 0) / 100;
      const repeatPct = boss.rules?.repeatGearQualityPct ?? pct;
      const repeatQuality = (repeatPct[row.quality] ?? 0) / 100;
      const label = "首领";
      const firstGear = boss.firstClear.filter((entry) => entry.kind === "gear").reduce((sum, entry) => sum + (entry.amount ?? 0), 0);
      if (firstGear > 0) {
        out.push({ stage: stage.displayName, source: `${label} ${boss.name} 首通（${firstGear} 件）`, drop: 1, quality, unit: "次首通" });
      }
      if (boss.repeat?.gear && boss.rules?.repeatRewards && repeatQuality > 0) {
        const idle = boss.rules.idleSpawn ? `；挂机每 ${boss.rules.idleSpawnWaves} 波 1 次` : "";
        out.push({ stage: stage.displayName, source: `${label} ${boss.name} 重复奖励（手动重打占每日次数${idle}）`, drop: 1, quality: repeatQuality, unit: "次胜利" });
      }
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
      guard: {
        revisions: itemRev,
        id: row.id,
        reload: async () => {
          await reload();
          drawer.value = false;
        },
        latest: async () => (await latestGear()).majors.flatMap((major) => major.pieces).find((piece) => piece.id === row.id),
        title: `装备「${row.displayName}」`,
      },
    });
    ElMessage.success("已保存，已生效");
    formOriginal.value = JSON.stringify(form);
    drawer.value = false;
    await reload();
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
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

const itemRev = useRevisions("item");
const setRev = useRevisions("gearSet");
const globalRev = useRevisions("globals");
const latestGear = () => api<GearList>("/admin/draft/gear");

/** 冲突时选「重新读取」：重读后把抽屉换成这一件 / 这一套的最新内容 */
async function reloadManual(id: string): Promise<void> {
  await reload();
  manualEditing.value = manual.value.find((row) => row.id === id) ?? null;
}
async function reloadSet(id: string): Promise<void> {
  await reload();
  setEditing.value = sets.value.find((row) => row.id === id) ?? null;
}

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    // 先取版本号再读数据（旧表单覆盖保护）
    await Promise.all([itemRev.load(), setRev.load(), globalRev.load()]);
    const [list, realmList, stageList, enhance] = await Promise.all([
      api<GearList>("/admin/draft/gear"),
      api<{ code: number; displayName: string; majorName: string }[]>("/admin/draft/realms"),
      api<StageDrop[]>("/admin/draft/stages"),
      api<{ rules: typeof enhanceRules.value }>("/admin/draft/enhance").catch(() => ({ rules: null })),
    ]);
    majors.value = list.majors;
    manual.value = list.manual ?? [];
    sets.value = list.sets ?? [];
    if (list.qualities?.length) qualities.value = list.qualities;
    nextManualId.value = list.nextManualId ?? nextManualId.value;
    enhanceRules.value = enhance.rules;
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
watch([query, filterMajor, filterSlot, filterQuality, filterOrigin, filterSet, onlyCustom], () => (page.value = 1));
watch(manualOpen, (value) => {
  if (!value) {
    window.clearTimeout(highlightTimer);
    highlightTimer = window.setTimeout(() => (highlightId.value = ""), 1500);
  }
});

useRefetchOnActivate(reload);
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
.f100 {
  width: 100px;
}
.segment {
  margin-bottom: 14px;
}
.seg-n {
  margin-left: 4px;
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.origin {
  padding: 1px 8px;
  border-radius: 4px;
  background: #eef0ec;
  color: #6b736e;
  font-size: 12px;
}
.origin.manual {
  background: #efe6f7;
  color: #7a45a8;
}
.mini-icons {
  display: flex;
  gap: 4px;
}
.icon-box.mini {
  width: 28px;
  height: 28px;
  border-radius: 6px;
}
.icon-box.mini img {
  width: 24px;
  height: 24px;
}
.icon-box.mini.empty {
  border: 1px dashed #c9cec8;
  background: transparent;
}
.tier-line {
  font-size: 12px;
  line-height: 22px;
}
.tier-tag {
  margin-right: 6px;
  padding: 0 6px;
  border-radius: 4px;
  background: #e3f1e5;
  color: #2f6b3f;
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
