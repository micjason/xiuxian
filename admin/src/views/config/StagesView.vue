<template>
  <div>
    <PageHeader title="关卡与首领" desc="每关都有首领：普通关卡是精英，每章最后一关是章末大首领。关卡按章节分组，章节顺序 + 关卡顺序 = 解锁顺序。点一行在右侧抽屉里改：普通怪、装备掉落（默认跟随「配置概览」）、首领与规则、试打。" />
    <ConfigListPage
      :schema="stageSchema"
      :rows="rows"
      :loading="loading"
      :error="error"
      id-key="id"
      entity-name="关卡"
      :search-keys="['displayName', 'realmName', 'bossText', 'chapterName']"
      search-placeholder="搜索关卡、境界、首领"
      :filters="filters"
      :columns="columns"
      :options-map="{ realmCode: realmOptions }"
      creatable
      deletable
      cloneable
      selectable
      :new-row="newRow"
      :save-fn="save"
      :remove-fn="remove"
      :drawer-size="drawerSize"
      :drawer-subtitle="subtitleOf"
      :title-of="titleOf"
      export-name="关卡"
      span-key="chapterName"
      @reload="reload"
    >
      <template #cell-chapterName="{ row }">
        <span class="chapter-cell">{{ row.chapterName }}</span>
      </template>
      <template #cell-bossText="{ row }">
        <span class="boss-cell">{{ row.bossText }}<TierTag :tier="row.tier as BossTier" /></span>
      </template>
      <template #cell-realmName="{ row }">
        <el-tag v-if="row.realmMissing" type="danger" effect="light" size="small">境界 {{ row.realmCode }} 不存在</el-tag>
        <span v-else>{{ row.realmCode }} {{ row.realmName }}</span>
      </template>
      <template #cell-dropCustomCount="{ row }">
        <CustomTag v-if="Number(row.dropCustomCount) > 0" kind="custom">已自定义 {{ row.dropCustomCount }} 项</CustomTag>
        <CustomTag v-else kind="default">默认</CustomTag>
      </template>
      <template #cell-effectivePower="{ row }">
        <el-tooltip v-if="row.powerProblem" :content="String(row.powerProblem)" placement="top">
          <el-tag type="warning" effect="light" size="small">算不出</el-tag>
        </el-tooltip>
        <span v-else-if="row.effectivePower == null" class="muted">—</span>
        <span v-else class="power-cell">{{ row.effectivePower }}<CustomTag v-if="row.recommendedPower == null" kind="auto">自动</CustomTag><CustomTag v-else kind="custom">手动</CustomTag></span>
      </template>
      <template #form="{ form }">
        <div class="stage-form">
          <DrawerAnchors :items="anchors" />

          <SectionCard title="基础信息" anchor="sec-base">
            <div class="two-col">
              <FormRow label="关卡名称" required>
                <el-input v-model="(form as StageForm).displayName" class="w320" placeholder="例如 黑风岭·一" />
              </FormRow>
              <FormRow label="所需境界" required>
                <el-select v-model="(form as StageForm).realmCode" class="w320" placeholder="选择境界">
                  <el-option v-for="option in realmOptions" :key="option.value" :label="option.label" :value="option.value" />
                </el-select>
              </FormRow>
              <FormRow
                label="推荐战力"
                help="玩家在历练页、首领战前看到的参考战力。默认按公式自动算：首领战力 × 推荐战力倍数；没有首领的关卡按普通怪算。点「手动覆盖」才能自己填。"
                :help-meta="`推荐战力倍数 ${rules.recommendedPowerMargin}（战力公式）`"
              >
                <div class="inline">
                  <NumInput
                    v-if="(form as StageForm).recommendedPower == null"
                    :model-value="(form as StageForm).autoPower ?? null"
                    unit="战力"
                    readonly
                    placeholder="算不出"
                  />
                  <NumInput v-else v-model="(form as StageForm).recommendedPower" unit="战力" :min="1" :precision="0" custom />
                  <template v-if="(form as StageForm).recommendedPower == null">
                    <CustomTag kind="auto">自动</CustomTag>
                    <el-button link type="primary" @click="(form as StageForm).recommendedPower = (form as StageForm).autoPower ?? 1">手动覆盖</el-button>
                  </template>
                  <template v-else>
                    <CustomTag kind="custom">已自定义</CustomTag>
                    <el-button link type="primary" @click="(form as StageForm).recommendedPower = null">恢复自动</el-button>
                  </template>
                </div>
                <template #note>
                  <template v-if="(form as StageForm).recommendedPower == null">{{ (form as StageForm).autoFormula ?? (form as StageForm).powerProblem ?? "保存后按首领或普通怪自动算" }}</template>
                  <template v-else>自动值 {{ (form as StageForm).autoPower ?? "—" }}</template>
                </template>
              </FormRow>
              <FormRow label="所属章节" help="关卡按章节分组；章节顺序 + 章内顺序 = 解锁顺序。每章最后一关（或章节里指定的一关）是章末大首领。">
                <el-select v-model="(form as StageForm).chapterSlug" class="w320" placeholder="选择章节" clearable>
                  <el-option v-for="chapter in chapters" :key="chapter.id" :label="`${chapter.sortOrder} · ${chapter.displayName}`" :value="chapter.id" />
                </el-select>
              </FormRow>
              <FormRow label="章内顺序" help="同一章里小的在前。新建时不填 = 排到本章最后。">
                <NumInput v-model="(form as StageForm).sortOrder" :precision="0" :max="99999" />
                <template #note>{{ tierNote(form as StageForm) }}</template>
              </FormRow>
              <FormRow label="下一关">
                <el-input :model-value="nextStageName(form as StageForm)" class="w320" disabled />
                <template #note>按章节和章内顺序自动衔接</template>
              </FormRow>
            </div>
          </SectionCard>

          <SectionCard title="普通怪" anchor="sec-monsters" desc="玩家在线时在这里刷怪，每只击杀给固定修为">
            <template #extra><span class="muted">每波 {{ rules.waveSize ?? 3 }} 只 · 取自配置概览</span></template>
            <table class="grid">
              <thead>
                <tr>
                  <th class="name">名称</th>
                  <th class="art">立绘<HelpTip title="怪物立绘" text="游戏里用的怪物贴图（Q 版 sprites 目录下 mon_ 开头的图）。不选按名字匹配。本关精英默认也用第一只怪的立绘。" /></th>
                  <th class="num">攻击</th>
                  <th class="num">防御</th>
                  <th class="num">气血</th>
                  <th class="num">攻击间隔<HelpTip title="普通怪攻击间隔" text="每次出手相隔的秒数，越小越快。" /></th>
                  <th class="num">击杀修为<HelpTip title="击杀修为" text="每只击杀直接给的修为（整数）。" /></th>
                  <th class="ops">操作</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(monster, mIndex) in (form as StageForm).monsters" :key="mIndex">
                  <td class="name"><el-input v-model="monster.name" placeholder="名称" /></td>
                  <td class="art"><ArtKeySelect v-model="monster.artKey" :width="120" clearable /></td>
                  <td class="num"><NumInput v-model="monster.attack" :width="120" /></td>
                  <td class="num"><NumInput v-model="monster.defense" :width="120" /></td>
                  <td class="num"><NumInput v-model="monster.hp" :width="120" :min="1" /></td>
                  <td class="num"><NumInput v-model="monster.interval" :width="120" unit="秒" :min="0.1" :step="0.05" :precision="2" /></td>
                  <td class="num"><NumInput v-model="monster.killCultivation" :width="120" unit="修为" :precision="0" /></td>
                  <td class="ops"><el-button link type="danger" @click="(form as StageForm).monsters.splice(mIndex, 1)">删除</el-button></td>
                </tr>
              </tbody>
            </table>
            <p v-if="(form as StageForm).monsters.length === 0" class="muted pad">没有普通怪：这个关卡不能刷怪（只有首领）。</p>
            <button type="button" class="add-row" @click="addMonster(form as StageForm)">＋ 添加怪物</button>
          </SectionCard>

          <SectionCard title="装备掉落" anchor="sec-drop" desc="只对普通怪生效；首领的装备看下方「首领」">
            <template #extra>
              <template v-if="customCount(form as StageForm) > 0">
                <CustomTag kind="custom">已自定义 {{ customCount(form as StageForm) }} 项</CustomTag>
                <el-button link type="primary" @click="resetDrop(form as StageForm)">全部恢复默认</el-button>
              </template>
              <template v-else>
                <CustomTag kind="default">使用默认值</CustomTag>
                <el-button link type="primary" @click="goOverview">在配置概览中修改 ›</el-button>
              </template>
            </template>
            <FormRow
              label="每只击杀掉落率"
              help="每打死一只普通怪，掉一件本境界阶装备的概率。不改就跟随配置概览。"
              :help-meta="`范围 0–100% · 默认 ${defaults.chancePercent}%（配置概览）`"
            >
              <div class="inline">
                <NumInput
                  v-model="(form as StageForm).monsterDrop.chancePercent"
                  unit="%"
                  :precision="2"
                  :max="100"
                  :inherit-value="defaults.chancePercent"
                  :custom="(form as StageForm).monsterDrop.chancePercent != null"
                />
                <template v-if="(form as StageForm).monsterDrop.chancePercent != null">
                  <span class="muted">默认 {{ defaults.chancePercent }}%</span>
                  <el-button link type="primary" @click="(form as StageForm).monsterDrop.chancePercent = null">↺ 恢复</el-button>
                </template>
              </div>
            </FormRow>
            <FormRow
              label="品质权重"
              help="掉出来的装备是什么品质：按权重抽，权重 ÷ 总和 = 概率。橙装只由首领掉，普通怪固定为 0。不改就跟随配置概览。"
              :help-meta="`默认 白 ${defaults.weights.white} / 绿 ${defaults.weights.green} / 蓝 ${defaults.weights.blue} / 紫 ${defaults.weights.purple}`"
            >
              <div class="weights">
                <div v-for="quality in QUALITIES" :key="quality.key" class="weight">
                  <span class="q-label"><i class="dot" :style="{ background: quality.color }" />{{ quality.name }}</span>
                  <NumInput
                    v-if="quality.key !== 'orange'"
                    v-model="(form as StageForm).monsterDrop.weights[quality.key as MonsterQuality]"
                    :width="120"
                    :precision="0"
                    :inherit-value="defaults.weights[quality.key as MonsterQuality]"
                    :custom="(form as StageForm).monsterDrop.weights[quality.key as MonsterQuality] != null"
                  />
                  <NumInput v-else :model-value="0" :width="120" readonly />
                  <span class="share">
                    <template v-if="quality.key !== 'orange' && (form as StageForm).monsterDrop.weights[quality.key as MonsterQuality] != null">
                      默认 {{ defaults.weights[quality.key as MonsterQuality] }} ·
                    </template>
                    占 {{ shareText(form as StageForm, quality.key) }}
                    <el-button
                      v-if="quality.key !== 'orange' && (form as StageForm).monsterDrop.weights[quality.key as MonsterQuality] != null"
                      link
                      type="primary"
                      class="mini"
                      @click="(form as StageForm).monsterDrop.weights[quality.key as MonsterQuality] = null"
                    >↺</el-button>
                  </span>
                </div>
              </div>
              <template #note>
                <div class="ratio">
                  <span v-for="quality in QUALITIES" :key="quality.key" :style="{ flex: effectiveWeight(form as StageForm, quality.key), background: quality.color }" />
                </div>
                按比例抽品质，不用凑 100。灰字 = 跟随配置概览；改了的格子金边，旁边 ↺ 恢复默认。
              </template>
            </FormRow>
          </SectionCard>

          <SectionCard title="首领" anchor="sec-boss" :desc="tierOf(form as StageForm) === 'chief' ? '本章最后一关：章末大首领，属性默认手填' : '普通关卡：小首领（精英），属性默认 = 本关普通怪 × 倍率'">
            <template #extra>
              <TierTag :tier="tierOf(form as StageForm)" long />
            </template>
            <BossEditor
              v-model="(form as StageForm).bosses"
              :items="items"
              :weapons="weapons"
              :skills="skills"
              :power-of="(boss: BossRow) => bossPowerOf(boss, (form as StageForm).realmCode)"
              :weights="weights"
              :tier="tierOf(form as StageForm)"
              :defaults="bossRules[tierOf(form as StageForm)]"
              :monster="(form as StageForm).monsters[0] ?? null"
              @trial="openTrial"
              @open-overview="goOverviewBoss"
            />
          </SectionCard>

          <StageDesignatedDrops v-model="(form as StageForm).designatedDrops" />
        </div>
      </template>
    </ConfigListPage>
    <TrialDialog v-model="trialOpen" :boss="trialBoss" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onBeforeUnmount, ref } from "vue";
import { useRouter } from "vue-router";
import { api } from "../../api";
import ArtKeySelect from "../../components/ArtKeySelect.vue";
import type { BossRow, BossStatKey, FirstClearRow } from "../../components/BossEditor.vue";
import BossEditor from "../../components/BossEditor.vue";
import TierTag from "../../components/TierTag.vue";
import { cloneRules, loadBossRules, loadChapters, type BossRuleOverride, type BossRules, type BossTier, type ChapterRow } from "../../composables/bossRules";
import ConfigListPage from "../../components/ConfigListPage.vue";
import CustomTag from "../../components/CustomTag.vue";
import DrawerAnchors from "../../components/DrawerAnchors.vue";
import FormRow from "../../components/FormRow.vue";
import HelpTip from "../../components/HelpTip.vue";
import NumInput from "../../components/NumInput.vue";
import PageHeader from "../../components/PageHeader.vue";
import SectionCard from "../../components/SectionCard.vue";
import TrialDialog from "../../components/TrialDialog.vue";
import StageDesignatedDrops, { type DesignatedRow } from "./stages/StageDesignatedDrops.vue";
import { loadWeapons, type Named } from "../../composables/lookups";
import { stageSchema } from "../../schema/resources";

type MonsterQuality = "white" | "green" | "blue" | "purple";
type MonsterRow = { name: string; attack: number; defense: number; hp: number; interval: number; killCultivation: number; artKey?: string | null };
type DropForm = { chancePercent: number | null; weights: Record<MonsterQuality, number | null> };
type StageForm = {
  id?: string;
  displayName: string;
  realmCode: number | undefined;
  chapterSlug: string | null;
  sortOrder: number | null;
  tier?: BossTier | null;
  recommendedPower: number | null;
  autoPower?: number | null;
  autoFormula?: string | null;
  powerProblem?: string | null;
  bosses: BossRow[];
  monsters: MonsterRow[];
  monsterDrop: DropForm;
  designatedDrops: DesignatedRow[];
};
type DropDefaults = { chancePercent: number; weights: Record<MonsterQuality, number>; orangeChancePercent: number };
type ApiBoss = {
  name: string;
  attack: number;
  defense: number;
  hp: number;
  interval: number;
  drops: { itemId: string; chancePercent: number }[];
  firstClear: FirstClearRow[];
  repeat: { gear: boolean; extras: { itemId: string; chancePercent: number; minQty: number; maxQty: number }[] } | null;
  artKey: string | null;
  ruleOverride: BossRuleOverride | null;
  statsCustom: BossStatKey[];
};
type ApiStage = {
  id: string;
  displayName: string;
  realmCode: number;
  realmName: string;
  realmMissing: boolean;
  chapterSlug: string | null;
  sortOrder: number;
  tier: BossTier | null;
  recommendedPower: number | null;
  effectivePower: number | null;
  autoPower: number | null;
  autoFormula: string | null;
  powerProblem: string | null;
  bosses: ApiBoss[];
  monsters: MonsterRow[];
  monsterDrop: DropForm;
  dropCustomCount: number;
  dropDefaults: DropDefaults;
};
type Rules = {
  attackWeight: number;
  defenseWeight: number;
  hpWeight: number;
  speedWeight: number;
  speedBase: number;
  recommendedPowerMargin: number;
  waveSize?: number;
};

const QUALITIES = [
  { key: "white", name: "白", color: "#b9bdb8" },
  { key: "green", name: "绿", color: "#4f9a5e" },
  { key: "blue", name: "蓝", color: "#3f78b5" },
  { key: "purple", name: "紫", color: "#8a5bb8" },
  { key: "orange", name: "橙", color: "#d9822b" },
] as const;
/** 读不到首领规则时的占位（和服务端 DEFAULT_BOSS_RULES 一样） */
const FALLBACK_RULES: BossRules = {
  elite: { statMode: "auto", statMul: { hp: 5, attack: 1.3, defense: 1.2 }, allowRepeat: true, repeatRewards: false, dailyRewardLimit: 0, gearQualityPct: { white: 0, green: 70, blue: 25, purple: 5, orange: 0 }, autoChallenge: true, autoChallengePowerPct: 100, autoChallengeRetrySeconds: 60, unlockNeedsBossWin: true, unlockNeedsRealm: true },
  chief: { statMode: "manual", statMul: { hp: 8.5, attack: 1.15, defense: 1.2 }, allowRepeat: true, repeatRewards: true, dailyRewardLimit: 5, gearQualityPct: { white: 0, green: 50, blue: 35, purple: 13, orange: 2 }, autoChallenge: false, autoChallengePowerPct: 100, autoChallengeRetrySeconds: 60, unlockNeedsBossWin: true, unlockNeedsRealm: true },
};
const anchors = [
  { id: "sec-base", label: "基础信息" },
  { id: "sec-monsters", label: "普通怪" },
  { id: "sec-drop", label: "装备掉落" },
  { id: "sec-boss", label: "首领与掉落" },
  { id: "sec-designated", label: "指定掉落" },
];

const router = useRouter();
const rows = ref<Record<string, unknown>[]>([]);
const loading = ref(false);
const error = ref("");
const realms = ref<{ code: number; displayName: string; interval: number }[]>([]);
const chapters = ref<ChapterRow[]>([]);
const bossRules = ref<BossRules>(cloneRules(FALLBACK_RULES));
const items = ref<Named[]>([]);
const weapons = ref<Named[]>([]);
const skills = ref<Named[]>([]);
const trialOpen = ref(false);
const trialBoss = ref<BossRow | null>(null);
const rules = ref<Rules>({ attackWeight: 0, defenseWeight: 0, hpWeight: 0, speedWeight: 0, speedBase: 100, recommendedPowerMargin: 1.05 });
const defaults = ref<DropDefaults>({ chancePercent: 5, weights: { white: 70, green: 25, blue: 5, purple: 0 }, orangeChancePercent: 2 });
const viewWidth = ref(window.innerWidth);
const drawerSize = computed(() => (viewWidth.value < 1400 ? "calc(100vw - 220px)" : 1080));
const weights = computed(() => ({ attack: rules.value.attackWeight, defense: rules.value.defenseWeight, hp: rules.value.hpWeight, speed: rules.value.speedWeight }));

function onResize(): void {
  viewWidth.value = window.innerWidth;
}

const realmOptions = computed(() => realms.value.map((realm) => ({ label: `${realm.code} · ${realm.displayName}`, value: realm.code })));
const chapterOptions = computed(() => chapters.value.map((chapter) => ({ label: chapter.displayName, value: chapter.id })));
const filters = computed(() => [
  { key: "chapterSlug", label: "章节", options: chapterOptions.value },
  { key: "realmCode", label: "境界", options: realmOptions.value },
]);
const columns = [
  { key: "chapterName", label: "章节", width: 120 },
  { key: "displayName", label: "关卡", minWidth: 160 },
  { key: "realmName", label: "所需境界", width: 150 },
  { key: "bossText", label: "首领", minWidth: 180 },
  { key: "dropCustomCount", label: "普通怪掉落", width: 130 },
  { key: "effectivePower", label: "推荐战力", width: 150, sortable: true },
];

function realmOf(code: number | undefined) {
  return realms.value.find((realm) => realm.code === code);
}

function titleOf(form: Record<string, unknown>, mode: "create" | "edit"): string {
  return mode === "create" ? "新建关卡" : `编辑关卡：${String(form.displayName || "未命名")}`;
}

function subtitleOf(form: Record<string, unknown>): string {
  const stage = form as unknown as StageForm;
  const realm = realmOf(stage.realmCode);
  const chapter = chapters.value.find((row) => row.id === stage.chapterSlug);
  const index = chapter ? chapter.stages.findIndex((row) => row.id === stage.id) : -1;
  const boss = stage.bosses?.[0]?.name;
  return [chapter?.displayName ?? "未分章节", index >= 0 ? `第 ${index + 1} 关` : "新关卡", realm?.displayName ?? "未选境界", boss ? `首领 ${boss}` : "无首领"].join(" · ");
}

/** 首领档次：已保存的关卡用服务端算的；换了章节 / 新关卡按「排在本章最后 = 章末」估算（保存后以服务端为准） */
function tierOf(form: StageForm): BossTier {
  const chapter = chapters.value.find((row) => row.id === form.chapterSlug);
  const saved = rows.value.find((row) => row.id === form.id) as { chapterSlug?: string | null; sortOrder?: number; tier?: BossTier | null } | undefined;
  if (saved && saved.chapterSlug === form.chapterSlug && saved.sortOrder === form.sortOrder && saved.tier) return saved.tier;
  if (!chapter) return form.tier ?? "elite";
  if (chapter.chiefStageSlug) return chapter.chiefStageSlug === form.id ? "chief" : "elite";
  const others = chapter.stages.filter((row) => row.id !== form.id);
  const last = others.reduce((max, row) => Math.max(max, row.sortOrder), Number.NEGATIVE_INFINITY);
  return form.sortOrder == null || form.sortOrder > last ? "chief" : "elite";
}

function tierNote(form: StageForm): string {
  return tierOf(form) === "chief" ? "本关是本章最后一关 → 章末大首领" : "本关是普通关卡 → 小首领（精英）";
}

function nextStageName(form: StageForm): string {
  const index = rows.value.findIndex((row) => row.id === form.id);
  const next = index >= 0 ? rows.value[index + 1] : undefined;
  return next ? String(next.displayName) : "（最后一关）";
}

function bossPowerOf(boss: BossRow, realmCode: number | undefined): number | null {
  const realm = realmOf(realmCode);
  if (!realm?.interval || !(boss.interval > 0)) return null;
  const speed = Math.max(0, rules.value.speedBase * (realm.interval / boss.interval - 1));
  const raw = boss.attack * weights.value.attack + boss.defense * weights.value.defense + boss.hp * weights.value.hp + speed * weights.value.speed;
  return Math.round(raw);
}

function customCount(form: StageForm): number {
  const drop = form.monsterDrop;
  return (drop.chancePercent != null ? 1 : 0) + Object.values(drop.weights).filter((value) => value != null).length;
}

function resetDrop(form: StageForm): void {
  form.monsterDrop = { chancePercent: null, weights: { white: null, green: null, blue: null, purple: null } };
}

function effectiveWeight(form: StageForm, key: string): number {
  if (key === "orange") return 0;
  const own = form.monsterDrop.weights[key as MonsterQuality];
  return own ?? defaults.value.weights[key as MonsterQuality] ?? 0;
}

function shareText(form: StageForm, key: string): string {
  const total = QUALITIES.reduce((sum, quality) => sum + effectiveWeight(form, quality.key), 0);
  if (total <= 0) return "—";
  return `${((effectiveWeight(form, key) / total) * 100).toFixed(1)}%`;
}

function goOverview(): void {
  void router.push("/config/overview#drop");
}

function goOverviewBoss(): void {
  void router.push("/config/overview#boss");
}

function addMonster(form: StageForm): void {
  form.monsters.push({ name: "", attack: 0, defense: 0, hp: 100, interval: 1.5, killCultivation: 1, artKey: null });
}

async function reload(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const [stages, realmList, itemList, weaponList, skillList, ruleView, chapterList, bossRuleView] = await Promise.all([
      api<ApiStage[]>("/admin/draft/stages"),
      api<{ code: number; displayName: string; interval: number }[]>("/admin/draft/realms"),
      api<Named[]>("/admin/draft/items"),
      loadWeapons(),
      api<Named[]>("/admin/draft/skills"),
      api<Rules>("/admin/draft/rules"),
      loadChapters(),
      loadBossRules(),
    ]);
    chapters.value = chapterList;
    bossRules.value = bossRuleView.rules;
    const chapterName = new Map(chapterList.map((chapter) => [chapter.id, chapter.displayName]));
    realms.value = realmList;
    items.value = itemList;
    weapons.value = weaponList;
    skills.value = skillList;
    rules.value = ruleView;
    if (stages[0]) defaults.value = stages[0].dropDefaults;
    rows.value = stages.map((stage) => ({
      ...stage,
      chapterName: stage.chapterSlug ? (chapterName.get(stage.chapterSlug) ?? stage.chapterSlug) : "未分章节",
      bossText: stage.bosses.length === 0 ? "—" : stage.bosses.map((boss) => boss.name).join("、"),
      bosses: stage.bosses.map((boss) => ({
        name: boss.name,
        attack: boss.attack,
        defense: boss.defense,
        hp: boss.hp,
        interval: boss.interval,
        drops: boss.drops.map((drop) => ({ itemId: drop.itemId, chancePercent: drop.chancePercent })),
        firstClear: boss.firstClear.map((entry) => ({ ...entry })),
        repeat: boss.repeat ? { gear: boss.repeat.gear, extras: boss.repeat.extras.map((extra) => ({ itemId: extra.itemId, chancePercent: extra.chancePercent, minQty: extra.minQty, maxQty: extra.maxQty })) } : null,
        artKey: boss.artKey ?? null,
        rules: boss.ruleOverride ? cloneRules(boss.ruleOverride) : null,
        statsCustom: [...(boss.statsCustom ?? [])],
      })),
      monsters: stage.monsters.map((monster) => ({ ...monster, artKey: monster.artKey ?? null })),
      monsterDrop: { chancePercent: stage.monsterDrop.chancePercent, weights: { white: stage.monsterDrop.weights.white ?? null, green: stage.monsterDrop.weights.green ?? null, blue: stage.monsterDrop.weights.blue ?? null, purple: stage.monsterDrop.weights.purple ?? null } },
    }));
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function newRow(): Record<string, unknown> {
  return {
    displayName: "",
    realmCode: realms.value[0]?.code,
    chapterSlug: chapters.value.at(-1)?.id ?? null,
    sortOrder: null,
    recommendedPower: null,
    autoPower: null,
    bosses: [] as BossRow[],
    monsters: [] as MonsterRow[],
    monsterDrop: { chancePercent: null, weights: { white: null, green: null, blue: null, purple: null } },
    designatedDrops: [] as DesignatedRow[],
  };
}

async function save(values: Record<string, unknown>, mode: "create" | "edit", editingId: string): Promise<void> {
  const form = values as unknown as StageForm;
  const body = JSON.stringify({
    displayName: form.displayName,
    realmCode: form.realmCode,
    chapterSlug: form.chapterSlug ?? "",
    sortOrder: form.sortOrder ?? undefined,
    recommendedPower: form.recommendedPower,
    // 首领：rules 只放改过的项（null = 全部跟随默认）；单首领橙装概率已停用，不再发送
    bosses: form.bosses.map((boss) => ({ ...boss, artKey: boss.artKey ?? null, rules: boss.rules && Object.keys(boss.rules).length ? boss.rules : null, statsCustom: boss.statsCustom ?? [] })),
    monsters: form.monsters,
    monsterDrop: form.monsterDrop,
    designatedDrops: (form.designatedDrops ?? []).map(({ itemId, trigger, chancePercent, count }) => ({ itemId, trigger, chancePercent, count })),
  });
  if (mode === "create") {
    await api("/admin/draft/stages", { method: "POST", body });
  } else {
    await api(`/admin/draft/stages/${editingId}`, { method: "PUT", body });
  }
}

async function remove(row: Record<string, unknown>): Promise<void> {
  await api(`/admin/draft/stages/${String(row.id)}`, { method: "DELETE" });
}

function openTrial(boss: BossRow): void {
  trialBoss.value = boss;
  trialOpen.value = true;
}

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
  gap: 18px 40px;
}
.w320 {
  width: 320px;
  max-width: 100%;
}
.inline {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}
.grid {
  width: 100%;
  border-collapse: collapse;
  font-size: var(--xx-fs-sm);
}
.grid th {
  height: 36px;
  padding: 0 8px;
  background: var(--xx-bg-subtle);
  color: var(--xx-text-secondary);
  font-weight: 500;
  text-align: left;
  white-space: nowrap;
}
.grid td {
  height: 44px;
  padding: 4px 8px;
  border-bottom: 1px solid var(--xx-border);
}
.grid .num {
  width: 136px;
  text-align: right;
}
.grid .name :deep(.el-input) {
  width: 200px;
}
.grid .ops {
  width: 64px;
  text-align: right;
}
.add-row {
  display: block;
  width: 100%;
  margin-top: 10px;
  padding: 6px;
  border: 1px dashed var(--xx-border-strong);
  border-radius: 6px;
  background: transparent;
  color: var(--xx-jade-600);
  cursor: pointer;
}
.add-row:hover {
  background: var(--xx-bg-hover);
}
.weights {
  display: flex;
  gap: 14px;
  flex-wrap: wrap;
}
.weight {
  display: grid;
  gap: 4px;
  width: 132px;
}
.q-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
}
.share {
  color: var(--xx-text-secondary);
  font-size: 12px;
  white-space: nowrap;
}
.mini {
  margin-left: 2px;
  padding: 0;
  height: auto;
}
.ratio {
  display: flex;
  width: 660px;
  max-width: 100%;
  height: 6px;
  margin: 2px 0 6px;
  border-radius: 3px;
  overflow: hidden;
  background: var(--xx-bg-subtle);
}
.grid .art {
  width: 136px;
}
.chapter-cell {
  color: var(--xx-text-primary);
  font-weight: 600;
}
.boss-cell {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.power-cell {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.muted {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.pad {
  margin: 8px 0 0;
}
</style>
