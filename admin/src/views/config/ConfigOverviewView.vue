<template>
  <div class="overview-page">
    <PageHeader title="配置概览" desc="所有会被关卡、装备、技能继承的默认数值都在这一页。关卡没单独改的项跟随这里；改了的关卡显示「已自定义」，可以一键恢复。">
      <template #actions>
        <el-button @click="reload">重新读取</el-button>
      </template>
    </PageHeader>
    <DataState :loading="loading" :error="error" :has-data="!!data" empty-text="还没有内容" @retry="reload">
      <div v-if="data" class="layout">
        <div class="main">
          <SectionCard title="战力公式" anchor="power" desc="战斗伤害、出手间隔和战力怎么算">
            <SchemaForm v-model="rules" :schema="powerSchema" :hidden-keys="hiddenExcept(powerSchema)" class="grid-form" />
            <p class="formula">每下伤害 = 攻击 × 攻击 ÷（攻击 + {{ rules.defenseConstant }} × 对方防御）；出手间隔 = {{ rules.baseInterval ?? 1.5 }} × {{ rules.speedBase }} ÷（{{ rules.speedBase }} + 速度），不短于 {{ rules.minInterval }} 秒；<br />战力 = 攻 × {{ rules.attackWeight }} + 防 × {{ rules.defenseWeight }} + 血 × {{ rules.hpWeight }} + 速 × {{ rules.speedWeight }}；推荐战力 = 首领（无首领按普通怪）战力 × {{ rules.recommendedPowerMargin }}</p>
          </SectionCard>

          <SectionCard title="装备掉落默认" anchor="drop" desc="普通怪每只击杀；关卡没单独改就用这里">
            <template #extra>
              <CustomTag kind="info">被 {{ data.stages.total - data.stages.customized.length }} 个关卡使用</CustomTag>
              <CustomTag v-if="data.stages.customized.length" kind="custom">{{ data.stages.customized.length }} 个关卡已自定义</CustomTag>
            </template>
            <FormRow label="每只击杀掉落率" help="每打死一只普通怪，掉一件本境界阶装备的概率。关卡可以单独改。" :help-meta="`范围 0–100% · 出厂值 ${data.tuningDefaults.monsterDropChanceBp / 100}%`">
              <NumInput v-model="dropChance" unit="%" :precision="2" :max="100" />
            </FormRow>
            <FormRow label="品质权重" help="掉出来的装备是什么品质：权重 ÷ 总和 = 概率。橙装只由首领掉，普通怪固定 0。" class="row-gap">
              <div class="cells">
                <div v-for="quality in QUALITIES" :key="quality.key" class="cell">
                  <span class="q-label"><i class="dot" :style="{ background: quality.color }" />{{ quality.name }}</span>
                  <NumInput v-if="quality.key !== 'orange'" v-model="tuning.monsterQualityWeights[quality.key]" :width="120" :precision="0" />
                  <NumInput v-else :model-value="0" :width="120" readonly />
                  <span class="share">占 {{ shareOf(quality.key) }}</span>
                </div>
              </div>
              <template #note>
                <div class="ratio"><span v-for="quality in QUALITIES" :key="quality.key" :style="{ flex: weightOf(quality.key), background: quality.color }" /></div>
                按比例抽品质，不用凑 100。橙装只由首领掉（见下方「首领规则」）。
              </template>
            </FormRow>
            <h4 class="sub-title">已自定义的关卡</h4>
            <el-table :data="data.stages.customized" size="small" empty-text="所有关卡都跟随默认">
              <el-table-column prop="displayName" label="关卡" min-width="140" />
              <el-table-column label="所需境界" width="120"><template #default="{ row }">{{ realmName(row.realmCode) }}</template></el-table-column>
              <el-table-column label="掉落率" width="100" align="right">
                <template #default="{ row }"><span :class="{ own: row.override?.chanceBp != null }">{{ row.effective.chanceBp / 100 }}%</span></template>
              </el-table-column>
              <el-table-column v-for="quality in QUALITIES.slice(0, 4)" :key="quality.key" :label="quality.name" width="70" align="right">
                <template #default="{ row }"><span :class="{ own: row.override?.qualityWeights?.[quality.key] != null }">{{ row.effective.qualityWeights[quality.key] }}</span></template>
              </el-table-column>
              <el-table-column label="改了" width="80"><template #default="{ row }"><CustomTag kind="custom">{{ row.customCount }} 项</CustomTag></template></el-table-column>
              <el-table-column label="操作" width="160" align="right">
                <template #default="{ row }">
                  <el-button link type="primary" @click="router.push({ path: '/config/stages', query: { open: row.id } })">编辑</el-button>
                  <el-button link type="primary" @click="resetStage(row)">恢复默认</el-button>
                </template>
              </el-table-column>
            </el-table>
            <p class="muted small">金色数字 = 关卡自己的值；其余跟随上面的默认。</p>
          </SectionCard>

          <BossRulesSection ref="bossSection" v-model:rules="tuning.bossRules" :defaults="data.tuningDefaults.bossRules" />

          <SeedDropsSection v-model="seedDropRows" />

          <SectionCard title="装备生成" anchor="gear" desc="只读摘要，在「装备配置」里改">
            <template #extra><el-button link type="primary" @click="router.push('/config/gear')">在装备配置中修改 ›</el-button></template>
            <dl class="summary">
              <dt>装备预算比例</dt><dd>{{ data.gear.gearBudgetRatio }}</dd>
              <dt>装备速度比例</dt><dd>{{ data.gear.gearSpeedFactor }}</dd>
              <dt>品质系数</dt><dd><span v-for="quality in QUALITIES" :key="quality.key" class="chip"><i class="dot" :style="{ background: quality.color }" />{{ quality.name }} {{ data.gear.qualityFactors?.[quality.key] ?? "—" }}</span></dd>
              <dt>部位属性占比</dt><dd><span v-for="(value, key) in data.gear.slotShares" :key="key" class="chip">{{ SLOT_NAMES[key] ?? key }} {{ Math.round(value * 1000) / 10 }}%</span></dd>
            </dl>
          </SectionCard>

          <SectionCard title="强化与分解" anchor="enhance">
            <template #extra><el-button link type="primary" @click="router.push('/config/enhance')">突破节点与材料在「装备强化」 ›</el-button></template>
            <FormRow label="行囊满时不发装备的来源" help="行囊满时，这些来源的装备直接不发（挂机 / 离线同样），游戏端在历练页显示「行囊已满」提示，玩家点开自己选装备分解。没勾的来源满包照发（可以超出容量）。不再有自动分解。" :help-meta="`出厂值 ${(data.tuningDefaults.bagFullSkipSources ?? []).map((key) => GRANT_SOURCE_NAMES[key] ?? key).join(' / ')}`">
              <el-checkbox-group v-model="tuning.bagFullSkipSources">
                <el-checkbox v-for="(label, key) in GRANT_SOURCE_NAMES" :key="key" :value="key">{{ label }}</el-checkbox>
              </el-checkbox-group>
            </FormRow>
            <template v-if="enhance">
              <div class="two-col row-gap">

                <FormRow label="每级属性加成" help="每级强化给装备基础属性增加的百分比。"><NumInput :model-value="enhance.statGrowthBp / 100" unit="%" :precision="2" @update:model-value="(value: number | null) => enhance && (enhance.statGrowthBp = Math.round((value ?? 0) * 100))" /></FormRow>
                <template v-if="enhance.essence">
                  <FormRow label="每级强化返还（金丹基准）" help="分解 +N 的装备额外得到 N × round(这个数 × 该装备大境界倍率) 的炼器精粹。默认 40 → 炼气每级 10 / 筑基 18 / 金丹 40。"><NumInput v-model="enhance.essence.refundPerLevel" unit="精粹" :precision="0" :min="0" /></FormRow>
                  <FormRow label="强化基础消耗" help="强化 0→1 级消耗的炼器精粹（品质倍数为 1 时）；每级再乘「消耗增长倍数」。强化消耗不跟大境界走。"><NumInput v-model="enhance.essence.costBase" unit="精粹" :precision="0" :min="1" /></FormRow>
                  <FormRow label="消耗增长倍数" help="每升一级，精粹消耗乘以这个倍数。按级单独指定在「装备强化」页。"><NumInput v-model="enhance.essence.costGrowth" unit="倍" :precision="2" :min="1" /></FormRow>
                </template>
              </div>
              <FormRow v-if="enhance.essence" label="大境界倍率" help="一口价是金丹档（×1）。炼气 0.25、筑基 0.45，元婴到大乘出厂为 1，可改。产出 = round(一口价 × 倍率 × 部位)；返还每级 = round(返还基准 × 倍率)。" class="row-gap">
                <div class="cells">
                  <div v-for="major in REALM_MAJORS" :key="major.key" class="cell">
                    <span class="q-label">{{ major.name }}</span>
                    <NumInput :model-value="realmMultOf(major.key)" :width="120" unit="倍" :precision="2" :min="0.01" @update:model-value="(value: number | null) => setRealmMult(major.key, value)" />
                  </div>
                </div>
              </FormRow>
              <div v-if="enhance.essence" class="abs-preview row-gap">
                <div class="sub-title">绝对产出预览（只读）= round(一口价 × 大境界倍率)</div>
                <table class="grid">
                  <thead>
                    <tr>
                      <th>大境界</th>
                      <th v-for="quality in ENHANCE_QUALITIES" :key="quality.key" class="num">{{ quality.name }}</th>
                      <th class="num">每级返还</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="major in REALM_MAJORS" :key="major.key">
                      <td>{{ major.name }}（×{{ realmMultOf(major.key) }}）</td>
                      <td v-for="quality in ENHANCE_QUALITIES" :key="quality.key" class="num">{{ absYield(quality.key, major.key) }}</td>
                      <td class="num">{{ absRefund(major.key) }}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <div class="xx-table-scroll row-gap">
              <table class="grid enhance-quality-grid">
                <thead>
                  <tr>
                    <th class="col-quality">品质</th>
                    <th class="num col-cap">强化上限<HelpTip title="强化上限" text="这个品质的装备最多强化到几级。" /></th>
                    <th class="num col-mult">品质倍数<HelpTip title="品质倍数" text="这个品质每一级的精粹消耗再乘以它。右边「每级精粹消耗」按公式实时算出具体整数，不用心算。" /></th>
                    <th class="num col-yield">分解产出（金丹基准）<HelpTip title="分解产出" text="金丹档一口价。实际产出再乘大境界倍率（见上方）。部位倍数 / 单独指定在「装备强化」页。" /></th>
                    <th class="col-cost">每级精粹消耗<HelpTip title="每级精粹消耗" text="按「基础消耗 × 增长倍数^当前等级 × 品质倍数」算出（有单独指定表时用表）。只读预览，改左边数字会立刻更新。完整可编辑表在「装备强化」。" /></th>
                    <th class="col-break">突破节点</th>
                  </tr>
                </thead>
                <tbody>
                  <tr v-for="quality in ENHANCE_QUALITIES" :key="quality.key">
                    <template v-if="enhance.qualities[quality.key]">
                      <td><i class="dot" :style="{ background: quality.color }" /> {{ quality.name }}</td>
                      <td class="num"><NumInput v-model="enhance.qualities[quality.key]!.cap" :width="120" unit="级" :precision="0" /></td>
                      <td class="num"><NumInput v-model="enhance.qualities[quality.key]!.costMult" :width="120" unit="倍" :precision="2" /></td>
                      <td class="num">
                        <NumInput v-if="enhance.essence" v-model="enhance.essence.yields[quality.key]" :width="120" unit="精粹" :precision="0" />
                        <span v-else class="muted small">先在「装备强化」填精粹规则</span>
                      </td>
                      <td class="cost-preview-cell">
                        <template v-if="!enhance.essence">
                          <span class="muted small">先填精粹规则</span>
                        </template>
                        <template v-else-if="essenceCostPreview(quality.key).length === 0">
                          <span class="muted small">—</span>
                        </template>
                        <template v-else>
                          <div class="cost-preview">
                            <span v-for="step in essenceCostPreview(quality.key)" :key="step.level" class="cost-chip">
                              +{{ step.level }} <b>{{ step.cost }}</b>
                            </span>
                          </div>
                          <div class="cost-total muted small">满级累计 <b>{{ essenceCostTotal(quality.key) }}</b> 精粹</div>
                        </template>
                      </td>
                      <td class="muted small break-nodes">
                        <template v-if="!enhance.qualities[quality.key]!.breakthroughs?.length">无</template>
                        <template v-else>
                          <span v-for="(node, ni) in enhance.qualities[quality.key]!.breakthroughs" :key="node.level">
                            <template v-if="ni">；</template>+{{ node.level }} 需
                            <span v-for="(mat, mi) in node.materials" :key="mat.itemSlug + '-' + mi">
                              <template v-if="mi">、</template>
                              <span
                                :class="{ 'break-unknown': !itemDisplayName(mat.itemSlug) }"
                                :title="itemDisplayName(mat.itemSlug) ? undefined : `未找到物品名称，显示 id：${mat.itemSlug}`"
                              >{{ materialLabel(mat.itemSlug) }} ×{{ mat.count }}</span>
                            </span>
                          </span>
                        </template>
                      </td>
                    </template>
                  </tr>
                </tbody>
              </table>
              </div>
            </template>
            <p v-else class="muted">强化规则还没配置，请到「装备强化」页填入起始值。</p>
          </SectionCard>

          <SectionCard title="技能层数系数" anchor="skill" desc="技能加成 = 基础百分比 × 层数系数">
            <FormRow label="层数系数" help="技能每层的加成倍数，分四档：第 1 层 / 第 2–3 层 / 第 4–6 层 / 第 7 层起。">
              <div class="cells">
                <div v-for="(label, index) in LAYER_LABELS" :key="label" class="cell">
                  <span class="q-label">{{ label }}</span>
                  <NumInput v-model="tuning.skillLayerFactors[index]" :width="120" unit="倍" :precision="2" :min="0.01" />
                </div>
              </div>
            </FormRow>
            <div class="two-col row-gap">
              <FormRow label="技能满层" help="技能最多修到第几层。满层后再用技能书会折算成修为。客户端 0.15.0 起按这里显示。" :help-meta="`出厂值 ${data.tuningDefaults.skillMaxLayers}`">
                <NumInput v-model="tuning.skillMaxLayers" unit="层" :precision="0" :min="1" :max="99" />
              </FormRow>
              <FormRow label="多余技能书折算" help="满层后再用技能书：得到 秒数 × 当前每秒修为 × 品阶系数 的修为。">
                <NumInput v-model="tuning.bookOverflowSeconds" unit="秒" :precision="0" />
              </FormRow>
            </div>
            <FormRow label="品阶系数" help="多余技能书折算修为时，按技能品阶乘的系数。" class="row-gap">
              <div class="cells">
                <div v-for="rank in RANKS" :key="rank.key" class="cell">
                  <span class="q-label">{{ rank.name }}</span>
                  <NumInput v-model="tuning.bookOverflowRankFactors[rank.key]" :width="120" unit="倍" :precision="2" />
                </div>
              </div>
            </FormRow>
          </SectionCard>

          <SkillSlotsSection v-model="skillSlots" :realms="realms" :max="data.skillSlots?.max ?? 6" />

          <NewbieSection v-model="newbie" :realms="realms.map((realm) => ({ slug: realm.slug, displayName: realm.displayName }))" :limits="data.newbie?.limits ?? { maxRows: 20, maxQuantity: 9999 }" />

          <CatalogSection v-if="data.catalog" :slots="data.catalog.slots" :qualities="data.catalog.qualities" />

          <SectionCard title="挂机与战斗节奏" anchor="pace">
            <SchemaForm v-model="rules" :schema="paceSchema" :hidden-keys="hiddenExcept(paceSchema)" class="grid-form" />
          </SectionCard>
        </div>
        <nav class="side-anchors">
          <a v-for="item in ANCHORS" :key="item.id" :class="{ on: activeAnchor === item.id }" @click="go(item.id)">{{ item.label }}</a>
        </nav>
      </div>
      <SaveBar :dirty="dirty" :saving="saving" :change-count="changeCount" @save="save" @cancel="reload" />
    </DataState>
  </div>
</template>

<script setup lang="ts">
import { useRevisions } from "../../composables/revisions";
import { isConflictAbort } from "../../composables/conflict";
import { ElMessage, ElMessageBox } from "element-plus";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { computed, onBeforeUnmount, onMounted, ref, watch } from "vue";
import { useRoute, useRouter } from "vue-router";
import { api } from "../../api";
import CustomTag from "../../components/CustomTag.vue";
import DataState from "../../components/DataState.vue";
import FormRow from "../../components/FormRow.vue";
import HelpTip from "../../components/HelpTip.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SaveBar from "../../components/SaveBar.vue";
import SchemaForm from "../../components/SchemaForm.vue";
import SectionCard from "../../components/SectionCard.vue";
import BossRulesSection from "./overview/BossRulesSection.vue";
import SeedDropsSection, { type SeedDropFormRow } from "./overview/SeedDropsSection.vue";
import CatalogSection from "./overview/CatalogSection.vue";
import NewbieSection, { type Newbie } from "./overview/NewbieSection.vue";
import SkillSlotsSection, { type SlotRule } from "./overview/SkillSlotsSection.vue";
import type { BossRules } from "../../composables/bossRules";
import { useDirtyGuard } from "../../composables/dirty";
import { rulesSchema } from "../../schema/resources";
import type { FormValues, Schema } from "../../schema/types";

type Quality = "white" | "green" | "blue" | "purple" | "orange";
type Rank = "yellow" | "xuan" | "earth" | "heaven";
type Tuning = {
  gearBudgetRatio: number;
  slotShares: Record<string, number>;
  skillLayerFactors: [number, number, number, number];
  skillMaxLayers: number;
  bagFullSkipSources: string[];
  bookOverflowSeconds: number;
  bookOverflowRankFactors: Record<Rank, number>;
  monsterDropChanceBp: number;
  monsterQualityWeights: Record<Quality, number>;
  bossRules: BossRules;
  seedDrops?: { itemSlug: string; chanceBp: number; minCount: number; maxCount: number }[];
};
type EnhanceQuality = { cap: number; costMult: number; decomposeExp: number; breakthroughs: { level: number; materials: { itemSlug: string; count: number }[] }[] };
type RealmMajor = "qi" | "foundation" | "core" | "nascent" | "spirit" | "void" | "unity" | "mahayana";
type Essence = { itemSlug: string; yields: Record<Quality, number>; refundPerLevel: number; realmYieldMult?: Partial<Record<RealmMajor, number>>; costBase: number; costGrowth: number; costTable?: Partial<Record<Quality, (number | null)[]>>; migrationRatioBp: number; [key: string]: unknown };
type Enhance = { expBase: number; expGrowth: number; statGrowthBp: number; refundBp: number; qualities: Record<string, EnhanceQuality | undefined>; essence?: Essence };
type StageRow = { id: string; displayName: string; realmCode: number; customCount: number; override: { chanceBp?: number; qualityWeights?: Record<string, number> } | null; effective: { chanceBp: number; qualityWeights: Record<string, number> } };
type Overview = {
  rules: FormValues;
  tuning: Tuning;
  tuningDefaults: Tuning;
  enhance: { rules: Enhance | null };
  gear: { gearBudgetRatio: number; gearSpeedFactor: number; slotShares: Record<string, number>; qualityFactors: Record<Quality, number> | null };
  stages: { total: number; customized: StageRow[] };
  newbie?: Newbie & { limits: { maxRows: number; maxQuantity: number } };
  skillSlots?: { rules: SlotRule[]; max: number };
  catalog?: { slots: { key: string; name: string }[]; qualities: { key: Quality; name: string; short: string; color: string }[] };
};

const QUALITIES: { key: Quality; name: string; color: string }[] = [
  { key: "white", name: "白", color: "#b9bdb8" },
  { key: "green", name: "绿", color: "#4f9a5e" },
  { key: "blue", name: "蓝", color: "#3f78b5" },
  { key: "purple", name: "紫", color: "#8a5bb8" },
  { key: "orange", name: "橙", color: "#d9822b" },
];
/** 装备发放来源（和后台「发放流水」同名）。 */
const GRANT_SOURCE_NAMES: Record<string, string> = { stage_drop: "关卡掉落", boss_first: "首领首通", boss_repeat: "首领重复", admin_grant: "后台补发", mail: "邮件", event: "活动" };
// 品质统一白→橙 5 档（红已去掉）
const ENHANCE_QUALITIES = QUALITIES;
const REALM_MAJORS: { key: RealmMajor; name: string }[] = [
  { key: "qi", name: "炼气" },
  { key: "foundation", name: "筑基" },
  { key: "core", name: "金丹" },
  { key: "nascent", name: "元婴" },
  { key: "spirit", name: "化神" },
  { key: "void", name: "炼虚" },
  { key: "unity", name: "合体" },
  { key: "mahayana", name: "大乘" },
];
const DEFAULT_REALM_MULT: Record<RealmMajor, number> = { qi: 0.25, foundation: 0.45, core: 1, nascent: 1, spirit: 1, void: 1, unity: 1, mahayana: 1 };
const RANKS: { key: Rank; name: string }[] = [
  { key: "yellow", name: "黄阶" },
  { key: "xuan", name: "玄阶" },
  { key: "earth", name: "地阶" },
  { key: "heaven", name: "天阶" },
];
const LAYER_LABELS = ["第 1 层", "第 2–3 层", "第 4–6 层", "第 7 层起"];
const SLOT_NAMES = computed<Record<string, string>>(() => Object.fromEntries((data.value?.catalog?.slots ?? []).map((slot) => [slot.key, slot.name])));
const ANCHORS = [
  { id: "power", label: "战力公式" },
  { id: "drop", label: "装备掉落默认" },
  { id: "boss", label: "首领规则" },
  { id: "gear", label: "装备生成" },
  { id: "enhance", label: "强化与分解" },
  { id: "skill", label: "技能层数系数" },
  { id: "slots", label: "技能栏位" },
  { id: "newbie", label: "新手设置" },
  { id: "catalog", label: "部位与品质" },
  { id: "pace", label: "挂机与战斗节奏" },
];

const pick = (keys: string[], title: string): Schema => ({ title, fields: rulesSchema.fields.filter((field) => keys.includes(field.key)).map((field) => ({ ...field, group: undefined })) });
const powerSchema = pick(["defenseConstant", "baseInterval", "speedBase", "minInterval", "attackWeight", "defenseWeight", "hpWeight", "speedWeight", "recommendedPowerMargin"], "战力公式");
const paceSchema = pick(["waveSize", "waveTransitionSeconds", "reviveSeconds", "onlineGapSeconds", "offlineCapSeconds", "offlinePopupMinSeconds", "dayStartHour", "bagCapacity", "challengeCooldownSeconds", "timeLimitSeconds", "ultAutoCastWindowSeconds"], "挂机与战斗节奏");

const route = useRoute();
const router = useRouter();
const loading = ref(false);
const saving = ref(false);
const error = ref("");
const data = ref<Overview | null>(null);
const rules = ref<FormValues>({});
const tuning = ref<Tuning>({} as Tuning);
const enhance = ref<Enhance | null>(null);
const realms = ref<{ code: number; displayName: string; slug: string }[]>([]);
const itemNames = ref<Map<string, string>>(new Map());
const newbie = ref<Newbie>({ startingRealmSlug: "", starterItems: [] });
const skillSlots = ref<SlotRule[]>([]);
const original = ref("");
const activeAnchor = ref("power");
const bossSection = ref<{ reloadUsage: () => Promise<void> } | null>(null);

const snapshot = () => JSON.stringify({ rules: rules.value, tuning: tuning.value, enhance: enhance.value, newbie: newbie.value, skillSlots: { rules: skillSlots.value } });
const dirty = computed(() => original.value !== "" && snapshot() !== original.value);
const changeCount = computed(() => {
  if (!dirty.value) return 0;
  const before = JSON.parse(original.value) as Record<string, Record<string, unknown> | null>;
  const now = JSON.parse(snapshot()) as Record<string, Record<string, unknown> | null>;
  let count = 0;
  for (const part of ["rules", "tuning", "enhance", "newbie", "skillSlots"]) {
    const left = before[part] ?? {};
    const right = now[part] ?? {};
    for (const key of new Set([...Object.keys(left), ...Object.keys(right)])) {
      if (JSON.stringify(left[key]) !== JSON.stringify(right[key])) count += 1;
    }
  }
  return count;
});
useDirtyGuard(dirty, async () => save());

const seedDropRows = ref<SeedDropFormRow[]>([]);

function seedRowsFromTuning(list: Tuning["seedDrops"] | undefined): SeedDropFormRow[] {
  return (list ?? []).map((row) => ({
    itemSlug: row.itemSlug,
    chancePercent: row.chanceBp / 100,
    minCount: row.minCount,
    maxCount: row.maxCount,
  }));
}

function applySeedRowsToTuning(): void {
  tuning.value.seedDrops = seedDropRows.value.map((row) => ({
    itemSlug: row.itemSlug,
    chanceBp: Math.round((Number(row.chancePercent) || 0) * 100),
    minCount: Number(row.minCount ?? 1),
    maxCount: Math.max(Number(row.minCount ?? 1), Number(row.maxCount ?? 1)),
  }));
}

watch(seedDropRows, applySeedRowsToTuning, { deep: true });

const dropChance = computed({
  get: () => (tuning.value.monsterDropChanceBp ?? 0) / 100,
  set: (value: number | null) => (tuning.value.monsterDropChanceBp = Math.round((value ?? 0) * 100)),
});

function hiddenExcept(schema: Schema): string[] {
  const keep = new Set(schema.fields.map((field) => field.key));
  return Object.keys(rules.value).filter((key) => !keep.has(key));
}

function weightOf(key: Quality): number {
  return key === "orange" ? 0 : (tuning.value.monsterQualityWeights?.[key] ?? 0);
}

function shareOf(key: Quality): string {
  const total = QUALITIES.reduce((sum, quality) => sum + weightOf(quality.key), 0);
  return total > 0 ? `${((weightOf(key) / total) * 100).toFixed(1)}%` : "—";
}

function realmName(code: number): string {
  const realm = realms.value.find((row) => row.code === code);
  return realm ? `${code} · ${realm.displayName}` : String(code);
}

/** 物品中文名；表里没有时返回空，由 materialLabel 回退 id。 */
function itemDisplayName(slug: string): string {
  return itemNames.value.get(slug) ?? "";
}

/** 突破节点材料展示：优先中文名，找不到再显示 id（模板里加 break-unknown 样式）。 */
function materialLabel(slug: string): string {
  return itemDisplayName(slug) || slug;
}

/** 与 backend enhance.ts essenceCost 一致：costTable 优先，否则 round(基础 × 增长^级 × 品质倍数)。只读预览。 */
function essenceCostAt(quality: Quality, level: number): number {
  const essence = enhance.value?.essence;
  const row = enhance.value?.qualities[quality];
  if (!essence || !row) return 0;
  const fixed = essence.costTable?.[quality]?.[level];
  if (typeof fixed === "number" && fixed > 0) return fixed;
  return Math.max(1, Math.round((essence.costBase ?? 0) * (essence.costGrowth ?? 1) ** level * (row.costMult ?? 1)));
}

function essenceCostPreview(quality: Quality): { level: number; cost: number }[] {
  const cap = enhance.value?.qualities[quality]?.cap ?? 0;
  if (!enhance.value?.essence || cap < 1) return [];
  return Array.from({ length: cap }, (_, index) => ({ level: index + 1, cost: essenceCostAt(quality, index) }));
}

function essenceCostTotal(quality: Quality): number {
  return essenceCostPreview(quality).reduce((sum, step) => sum + step.cost, 0);
}

function ensureRealmMult(): void {
  const essence = enhance.value?.essence;
  if (!essence) return;
  if (!essence.realmYieldMult) essence.realmYieldMult = { ...DEFAULT_REALM_MULT };
  for (const major of REALM_MAJORS) {
    if (essence.realmYieldMult[major.key] == null) essence.realmYieldMult[major.key] = DEFAULT_REALM_MULT[major.key];
  }
}

function realmMultOf(key: RealmMajor): number {
  ensureRealmMult();
  return enhance.value?.essence?.realmYieldMult?.[key] ?? DEFAULT_REALM_MULT[key];
}

function setRealmMult(key: RealmMajor, value: number | null): void {
  ensureRealmMult();
  if (!enhance.value?.essence?.realmYieldMult) return;
  enhance.value.essence.realmYieldMult[key] = value == null || Number.isNaN(value) ? DEFAULT_REALM_MULT[key] : value;
}

function absYield(quality: Quality, major: RealmMajor): number {
  const base = enhance.value?.essence?.yields[quality] ?? 0;
  return Math.round(base * realmMultOf(major));
}

function absRefund(major: RealmMajor): number {
  return Math.round((enhance.value?.essence?.refundPerLevel ?? 0) * realmMultOf(major));
}

function go(id: string): void {
  activeAnchor.value = id;
  document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });
}

function onScroll(): void {
  let current = ANCHORS[0]!.id;
  for (const item of ANCHORS) {
    const element = document.getElementById(item.id);
    if (element && element.getBoundingClientRect().top <= 160) current = item.id;
  }
  activeAnchor.value = current;
}

const rev = useRevisions("globals");

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    // 先取版本号再读数据（旧表单覆盖保护）
    await rev.load();
    const [overview, realmList, itemList] = await Promise.all([
      api<Overview>("/admin/draft/config-overview"),
      api<{ code: number; displayName: string; slug: string }[]>("/admin/draft/realms"),
      api<{ id: string; displayName: string }[]>("/admin/draft/items"),
    ]);
    apply(overview);
    realms.value = realmList;
    itemNames.value = new Map(itemList.map((item) => [item.id, item.displayName]));
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function apply(overview: Overview): void {
  data.value = overview;
  rules.value = { ...overview.rules };
  tuning.value = JSON.parse(JSON.stringify(overview.tuning)) as Tuning;
  seedDropRows.value = seedRowsFromTuning(tuning.value.seedDrops);
  applySeedRowsToTuning();
  enhance.value = overview.enhance.rules ? (JSON.parse(JSON.stringify(overview.enhance.rules)) as Enhance) : null;
  if (enhance.value?.essence && !enhance.value.essence.realmYieldMult) {
    enhance.value.essence.realmYieldMult = { ...DEFAULT_REALM_MULT };
  }
  newbie.value = { startingRealmSlug: overview.newbie?.startingRealmSlug ?? "", starterItems: JSON.parse(JSON.stringify(overview.newbie?.starterItems ?? [])) };
  skillSlots.value = JSON.parse(JSON.stringify(overview.skillSlots?.rules ?? []));
  original.value = snapshot();
}

/** 「查看差异」用：服务器上现在的配置概览，形状和保存的 body 一样 */
async function latestOverview(): Promise<unknown> {
  const fresh = await api<Overview>("/admin/draft/config-overview");
  return { rules: fresh.rules, tuning: fresh.tuning, enhance: fresh.enhance?.rules, newbie: fresh.newbie, skillSlots: { rules: fresh.skillSlots?.rules } };
}

async function save(): Promise<boolean> {
  saving.value = true;
  try {
    applySeedRowsToTuning();
    const before = JSON.parse(original.value) as { enhance: unknown; newbie: unknown; skillSlots: { rules: unknown } };
    const body: Record<string, unknown> = { rules: rules.value, tuning: tuning.value };
    if (enhance.value && JSON.stringify(before.enhance) !== JSON.stringify(enhance.value)) body.enhance = enhance.value;
    if (JSON.stringify(before.newbie) !== JSON.stringify(newbie.value)) body.newbie = newbie.value;
    if (JSON.stringify(before.skillSlots.rules) !== JSON.stringify(skillSlots.value)) body.skillSlots = { rules: skillSlots.value };
    const overview = await api<Overview>("/admin/draft/config-overview", {
      method: "PUT",
      body: JSON.stringify(body),
      guard: { revisions: rev, id: 1, reload, latest: latestOverview, title: "配置概览" },
    });
    apply(overview);
    void bossSection.value?.reloadUsage();
    ElMessage.success("已保存到草稿；跟随默认的关卡立即生效");
    return true;
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败（没有任何改动被保存）");
    return false;
  } finally {
    saving.value = false;
  }
}

async function resetStage(row: StageRow): Promise<void> {
  try {
    await ElMessageBox.confirm(`把「${row.displayName}」的掉落率和品质权重恢复成跟随默认？`, "恢复默认", { type: "warning" });
  } catch {
    return;
  }
  await api(`/admin/draft/stages/${row.id}/reset-drop`, { method: "POST" });
  ElMessage.success("已恢复默认");
  if (data.value) {
    const fresh = await api<Overview>("/admin/draft/config-overview");
    data.value = { ...data.value, stages: fresh.stages };
  }
}

useRefetchOnActivate(reload);
onMounted(async () => {
  window.addEventListener("scroll", onScroll, { passive: true, capture: true });
  await reload();
  const hash = route.hash.replace("#", "");
  if (hash) setTimeout(() => go(hash), 200);
});
onBeforeUnmount(() => window.removeEventListener("scroll", onScroll, { capture: true }));
</script>

<style scoped>
.layout {
  display: grid;
  grid-template-columns: minmax(0, 1240px) 168px;
  gap: 24px;
  align-items: start;
}
.side-anchors {
  position: sticky;
  top: 16px;
  display: grid;
  gap: 2px;
  padding: 8px 0;
  border-left: 1px solid var(--xx-border);
}
.side-anchors a {
  padding: 6px 14px;
  margin-left: -1px;
  border-left: 2px solid transparent;
  color: var(--xx-text-secondary);
  font-size: 13px;
  cursor: pointer;
}
.side-anchors a.on {
  border-left-color: var(--xx-jade-600);
  color: var(--xx-jade-600);
  font-weight: 600;
}
.grid-form :deep(.fields) {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0 64px;
}
.grid-form :deep(.group) {
  display: contents;
}
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
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.share {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.ratio {
  display: flex;
  width: 664px;
  max-width: 100%;
  height: 6px;
  margin: 2px 0 6px;
  border-radius: 3px;
  overflow: hidden;
  background: var(--xx-bg-subtle);
}
.formula {
  margin: 12px 0 0;
  padding: 10px 12px;
  border-radius: 6px;
  background: var(--xx-bg-subtle);
  color: var(--xx-text-secondary);
  font-family: var(--xx-font-mono);
  font-size: 12px;
  line-height: 1.8;
}
.sub-title {
  margin: 22px 0 8px;
  font-size: 14px;
}
.own {
  color: #8f5c0c;
  font-weight: 600;
}
.summary {
  display: grid;
  grid-template-columns: 136px 1fr;
  gap: 10px 16px;
  margin: 0;
  font-size: 13px;
}
.summary dt {
  color: var(--xx-text-secondary);
  text-align: right;
}
.summary dd {
  margin: 0;
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}
.chip {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 1px 8px;
  border-radius: 4px;
  background: var(--xx-bg-subtle);
}
.xx-table-scroll {
  width: 100%;
  overflow-x: auto;
}
.grid {
  width: 100%;
  min-width: max-content;
  border-collapse: collapse;
  font-size: var(--xx-fs-sm);
}
.grid th {
  height: 36px;
  padding: 0 10px;
  background: var(--xx-bg-subtle);
  color: var(--xx-text-secondary);
  font-weight: 500;
  text-align: left;
  white-space: nowrap;
  vertical-align: middle;
}
.grid th :deep(.help) {
  display: inline-grid;
  vertical-align: middle;
  flex-shrink: 0;
}
.grid td {
  height: 44px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--xx-border);
}
.grid .num {
  min-width: 136px;
  text-align: right;
}
.enhance-quality-grid .col-quality { min-width: 72px; }
.enhance-quality-grid .col-cap { min-width: 110px; }
.enhance-quality-grid .col-mult { min-width: 110px; }
.enhance-quality-grid .col-yield { min-width: 180px; }
.enhance-quality-grid .col-cost { min-width: 280px; }
.enhance-quality-grid .col-break { min-width: 160px; }
.muted {
  color: var(--xx-text-secondary);
  font-size: 13px;
}
.small {
  font-size: 12px;
}

.break-nodes .break-unknown {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  color: var(--el-color-warning);
  text-decoration: underline dotted;
}
.cost-preview-cell {
  min-width: 280px;
  max-width: 420px;
  vertical-align: top;
}
.cost-preview {
  display: flex;
  flex-wrap: wrap;
  gap: 4px 8px;
  line-height: 1.5;
}
.cost-chip {
  display: inline-flex;
  align-items: baseline;
  gap: 2px;
  padding: 0 6px;
  border-radius: 4px;
  background: var(--xx-bg-subtle);
  color: var(--xx-text-secondary);
  font-size: 12px;
  white-space: nowrap;
}
.cost-chip b {
  color: var(--xx-text);
  font-variant-numeric: tabular-nums;
}
.cost-total {
  margin-top: 4px;
}
.cost-total b {
  color: var(--xx-text);
  font-variant-numeric: tabular-nums;
}
.abs-preview .sub-title {
  margin: 12px 0 8px;
  font-size: 13px;
  color: var(--xx-text-secondary);
}
</style>
