<template>
  <SectionCard title="首领规则" anchor="boss" desc="每关一个首领、一套规则。这里是默认值，关卡里可以单独改（「关卡与Boss」抽屉 · 首领规则）。">
    <template #extra>
      <CustomTag kind="info">被 {{ usage?.stages ?? "—" }} 个关卡使用</CustomTag>
      <el-popover v-if="usage?.customized" placement="bottom" :width="260" trigger="hover">
        <template #reference><span><CustomTag kind="custom">{{ usage.customized }} 个已自定义</CustomTag></span></template>
        <div v-for="stage in usage.customizedStages" :key="stage.id" class="pop-row">
          <span>{{ stage.displayName }}</span><CustomTag kind="custom">{{ stage.customCount }} 项</CustomTag>
        </div>
      </el-popover>
    </template>
    <div v-if="rules" class="boss-grid">
      <div class="group">属性</div>
      <RuleLabel text="属性" :help="RULE_HELP.statMode" />
      <div class="cell">
        <el-radio-group v-model="rules.statMode" size="small">
          <el-radio-button value="auto">自动 · 按倍率</el-radio-button>
          <el-radio-button value="manual">每关手填</el-radio-button>
        </el-radio-group>
      </div>
      <RuleLabel text="属性倍率" :help="RULE_HELP.statMul" top />
      <div class="cell">
        <div v-if="rules.statMode === 'auto'" class="mults">
          <div v-for="stat in STAT_MULS" :key="stat.key" class="mult">
            <span class="mini">{{ stat.name }} ×</span>
            <NumInput v-model="rules.statMul[stat.key]" :width="120" unit="倍" :precision="2" :min="0.1" :max="100" :custom="changed(`statMul.${stat.key}`)" />
          </div>
        </div>
        <span v-else class="muted">不用倍率，每关手填属性</span>
      </div>

      <div class="group">奖励与次数</div>
      <RuleLabel text="首通装备品质" :help="RULE_HELP.gearQualityPct" top />
      <div class="cell col">
        <QualityRates :pct="rules.gearQualityPct" @set="(key: GearQuality, value: number) => (rules!.gearQualityPct[key] = value)" />
      </div>
      <RuleLabel text="允许手动重打" :help="RULE_HELP.allowRepeat" />
      <div class="cell">
        <el-switch v-model="rules.allowRepeat" /><span class="sw-text">{{ rules.allowRepeat ? "允许" : "不允许" }}</span>
      </div>
      <RuleLabel text="重复奖励" :help="RULE_HELP.repeatRewards" />
      <div class="cell">
        <el-switch v-model="rules.repeatRewards" /><span class="sw-text">{{ rules.repeatRewards ? "给 · 手动重打和挂机首领都有" : "不给 · 只有首通奖励" }}</span>
      </div>
      <RuleLabel text="重复奖励装备品质" :help="RULE_HELP.repeatGearQualityPct" top />
      <div class="cell col">
        <QualityRates :pct="rules.repeatGearQualityPct" :readonly="!rules.repeatRewards" @set="(key: GearQuality, value: number) => (rules!.repeatGearQualityPct[key] = value)" />
      </div>
      <RuleLabel text="每日首领挑战总次数" :help="RULE_HELP.dailyChallengeTotal" />
      <div class="cell">
        <NumInput v-model="rules.dailyChallengeTotal" :width="120" unit="次" :precision="0" :max="999" :custom="changed('dailyChallengeTotal')" />
        <span class="hint">所有首领合计 · 首次挑战不算 · 只能在这里改</span>
      </div>

      <div class="group">挂机刷首领</div>
      <RuleLabel text="挂机刷首领" :help="RULE_HELP.idleSpawn" />
      <div class="cell">
        <el-switch v-model="rules.idleSpawn" /><span class="sw-text">{{ rules.idleSpawn ? "开 · 已击败的首领挂机时定期刷出" : "关" }}</span>
      </div>
      <RuleLabel text="每多少波刷一次" :help="RULE_HELP.idleSpawnWaves" />
      <div class="cell">
        <span class="mini">每</span>
        <NumInput v-model="rules.idleSpawnWaves" :width="160" unit="波" :precision="0" :min="1" :max="1000000" :readonly="!rules.idleSpawn" :custom="changed('idleSpawnWaves')" />
        <span class="hint">小怪刷一次首领（离线也算）</span>
      </div>
      <RuleLabel text="算每日次数" :help="RULE_HELP.idleSpawnCountsDaily" />
      <div class="cell">
        <el-switch v-model="rules.idleSpawnCountsDaily" :disabled="!rules.idleSpawn" />
        <span class="sw-text">{{ rules.idleSpawnCountsDaily ? "算 · 用完后挂机首领没奖励" : "不算 · 挂机首领不消耗次数，一直有奖励" }}</span>
      </div>
      <RuleLabel text="一次结算最多" :help="RULE_HELP.idleSpawnMaxPerSettle" />
      <div class="cell">
        <NumInput v-model="rules.idleSpawnMaxPerSettle" :width="120" unit="只" :precision="0" :min="1" :max="1000" :readonly="!rules.idleSpawn" />
        <span class="hint">只能在这里改</span>
      </div>

      <div class="group">自动挑战（还没击败的首领）</div>
      <RuleLabel text="允许自动挑战" :help="RULE_HELP.autoChallenge" />
      <div class="cell">
        <el-switch v-model="rules.autoChallenge" /><span class="sw-text">{{ rules.autoChallenge ? "允许 · 挂机时满足条件自动打" : "不允许 · 只能手动点挑战" }}</span>
      </div>
      <RuleLabel text="自动挑战条件" :help="RULE_HELP.autoChallengePowerPct" />
      <div class="cell">
        <span class="mini">战力 ≥ 推荐战力 ×</span>
        <NumInput v-model="rules.autoChallengePowerPct" :width="100" unit="%" :precision="0" :min="1" :max="1000" :readonly="!rules.autoChallenge" />
      </div>
      <RuleLabel text="输了再试间隔" :help="RULE_HELP.autoChallengeRetrySeconds" />
      <div class="cell">
        <NumInput v-model="rules.autoChallengeRetrySeconds" :width="120" unit="秒" :precision="0" :max="86400" :readonly="!rules.autoChallenge" />
      </div>

      <div class="group">解锁</div>
      <RuleLabel text="解锁下一关" :help="RULE_HELP.unlock" />
      <div class="cell">
        <el-switch v-model="rules.unlockNeedsBossWin" /><span class="sw-text">需要击败本关首领</span>
        <el-switch v-model="rules.unlockNeedsRealm" class="gap" /><span class="sw-text">需要达到下一关境界</span>
      </div>
    </div>
    <p class="muted small">战斗技能全自动释放（无冷却条、无手动施法）。关卡里单独改过的项显示「已自定义」，在关卡抽屉的首领规则里可以一键恢复默认。</p>
  </SectionCard>
</template>

<script setup lang="ts">
/**
 * 配置概览 · 首领规则（第四批：一套规则，不再分精英 / 章末两列）。
 * 绑定 tuning.bossRules，跟配置概览一起保存（PUT /admin/draft/config-overview）；使用 / 自定义数量来自 GET /admin/draft/boss-rules。
 * 「每日首领挑战总次数」「一次结算最多刷几只」只有全局，关卡里不能改。
 */
import { defineComponent, h, onMounted, ref, type PropType } from "vue";
import { useRefetchOnActivate } from "../../../composables/dataVersion";
import CustomTag from "../../../components/CustomTag.vue";
import HelpTip from "../../../components/HelpTip.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";
import { GEAR_QUALITIES, RULE_HELP, STAT_MULS, loadBossRules, qualityTotal, type BossRules, type BossRulesView, type GearQuality } from "../../../composables/bossRules";

const rules = defineModel<BossRules | undefined>("rules", { required: true });
const props = defineProps<{ defaults?: BossRules }>();
const usage = ref<BossRulesView["usage"] | null>(null);

function changed(path: string): boolean {
  if (!props.defaults || !rules.value) return false;
  const read = (root: unknown) => path.split(".").reduce<unknown>((value, key) => (value as Record<string, unknown> | undefined)?.[key], root);
  return read(rules.value) !== read(props.defaults);
}

const RuleLabel = defineComponent({
  props: { text: { type: String, required: true }, help: { type: String, default: "" }, top: Boolean },
  setup(labelProps) {
    return () => h("div", { class: ["rule-label", { top: labelProps.top }] }, [labelProps.text, labelProps.help ? h(HelpTip, { title: labelProps.text, text: labelProps.help }) : null]);
  },
});

/** 5 档品质掉率 + 合计提示 */
const QualityRates = defineComponent({
  props: { pct: { type: Object as PropType<Record<GearQuality, number>>, required: true }, readonly: Boolean },
  emits: { set: (_key: GearQuality, _value: number) => true },
  setup(rateProps, { emit }) {
    return () => {
      const total = qualityTotal(rateProps.pct);
      return [
        h(
          "div",
          { class: "rates" },
          GEAR_QUALITIES.map((quality) =>
            h("div", { class: "rate", key: quality.key }, [
              h("span", { class: "mini" }, [h("i", { class: "dot", style: { background: quality.color } }), quality.name]),
              h(NumInput, {
                modelValue: rateProps.pct[quality.key],
                "onUpdate:modelValue": (value: number | null) => emit("set", quality.key, Number(value ?? 0)),
                width: 88,
                unit: "%",
                precision: 2,
                max: 100,
                readonly: rateProps.readonly,
              }),
            ]),
          ),
        ),
        h("span", { class: ["hint", { bad: total !== 100 }] }, `合计 ${total}%${total !== 100 ? "，必须 100%" : ""}`),
      ];
    };
  },
});

async function reloadUsage(): Promise<void> {
  try {
    usage.value = (await loadBossRules()).usage;
  } catch {
    usage.value = null;
  }
}
useRefetchOnActivate(reloadUsage);
onMounted(reloadUsage);
defineExpose({ reloadUsage });
</script>

<style scoped>
.boss-grid {
  display: grid;
  grid-template-columns: 160px minmax(0, 1fr);
  column-gap: 16px;
  row-gap: 4px;
  align-items: center;
}
.group {
  grid-column: 1 / -1;
  margin-top: 10px;
  padding: 6px 14px;
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-subtle);
  color: var(--xx-text-primary);
  font-size: 13px;
  font-weight: 600;
}
.group:first-child {
  margin-top: 0;
}
.head {
  padding: 10px 14px;
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-subtle);
  align-self: stretch;
}
.head.label {
  background: transparent;
  border-bottom-color: transparent;
}
.head-title {
  display: flex;
  align-items: center;
  gap: 8px;
}
.head-sub,
.head-meta {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.head-meta {
  margin-top: 4px;
}
.cell {
  display: flex;
  align-items: center;
  gap: 8px;
  min-height: 40px;
  padding: 6px 14px;
  flex-wrap: wrap;
}
.cell.col {
  flex-direction: column;
  align-items: flex-start;
}
:deep(.rule-label) {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 4px;
  color: var(--xx-text-regular);
  font-size: var(--xx-fs-sm);
  white-space: nowrap;
}
:deep(.rule-label.top) {
  align-self: start;
  margin-top: 28px;
}
.mults,
:deep(.rates) {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}
.mult,
:deep(.rate) {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.mini,
:deep(.mini) {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
:deep(.dot) {
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-right: 4px;
  border-radius: 50%;
}
.sw-text {
  color: var(--xx-text-regular);
  font-size: 13px;
}
.gap {
  margin-left: 16px;
}
.hint,
:deep(.hint) {
  color: var(--xx-text-placeholder);
  font-size: 12px;
}
:deep(.hint.bad) {
  color: var(--el-color-danger);
}
.muted {
  color: var(--xx-text-secondary);
  font-size: 13px;
}
.small {
  margin: 12px 0 0;
  font-size: 12px;
}
.lnk {
  color: var(--el-color-primary);
  cursor: pointer;
}
.pop-row {
  display: flex;
  justify-content: space-between;
  padding: 4px 0;
}
</style>
