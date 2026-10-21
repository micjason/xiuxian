<template>
  <SectionCard title="首领规则" anchor="boss" desc="每关都有首领：普通关卡是小首领（精英），每章最后一关是大首领。">
    <template #extra>
      <CustomTag kind="info">被 {{ usedBy }} 个关卡使用</CustomTag>
      <CustomTag v-if="customizedTotal" kind="custom">{{ customizedTotal }} 个已自定义</CustomTag>
    </template>
    <div v-if="rules" class="boss-grid">
      <div class="head label" />
      <div v-for="tier in TIERS" :key="tier" class="head" :class="tier">
        <div class="head-title"><TierTag :tier="tier" long /><span class="head-sub">{{ tier === "elite" ? "非章末关卡" : "每章最后一关" }}</span></div>
        <div class="head-meta">
          被 {{ usage?.[tier].stages ?? "—" }} 关使用 ·
          <el-popover v-if="usage?.[tier].customized" placement="bottom" :width="260" trigger="hover">
            <template #reference><span class="lnk">{{ usage[tier].customized }} 关已自定义</span></template>
            <div v-for="stage in usage[tier].customizedStages" :key="stage.id" class="pop-row">
              <span>{{ stage.displayName }}</span><CustomTag kind="custom">{{ stage.customCount }} 项</CustomTag>
            </div>
          </el-popover>
          <span v-else>0 关已自定义</span>
        </div>
      </div>

      <RuleLabel text="属性" :help="RULE_HELP.statMode" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <el-radio-group v-model="rules[tier].statMode" size="small">
          <el-radio-button value="auto">自动 · 按倍率</el-radio-button>
          <el-radio-button value="manual">每关手填</el-radio-button>
        </el-radio-group>
      </div>

      <RuleLabel text="属性倍率" :help="RULE_HELP.statMul" top />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <div v-if="rules[tier].statMode === 'auto'" class="mults">
          <div v-for="stat in STAT_MULS" :key="stat.key" class="mult">
            <span class="mini">{{ stat.name }} ×</span>
            <NumInput v-model="rules[tier].statMul[stat.key]" :width="120" unit="倍" :precision="2" :min="0.1" :max="100" :custom="changed(tier, `statMul.${stat.key}`)" />
          </div>
        </div>
        <span v-else class="muted">不用倍率，每关手填属性</span>
      </div>

      <RuleLabel text="允许重打" :help="RULE_HELP.allowRepeat" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <el-switch v-model="rules[tier].allowRepeat" /><span class="sw-text">{{ rules[tier].allowRepeat ? "允许" : "不允许" }}</span>
      </div>

      <RuleLabel text="重打给奖励" :help="RULE_HELP.repeatRewards" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <el-switch v-model="rules[tier].repeatRewards" :disabled="!rules[tier].allowRepeat" />
        <span class="sw-text">{{ rules[tier].repeatRewards ? "给 · 消耗每日次数" : "不给 · 只有首通奖励" }}</span>
      </div>

      <RuleLabel text="每日次数" :help="RULE_HELP.dailyRewardLimit" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <NumInput v-model="rules[tier].dailyRewardLimit" :width="120" unit="次" :precision="0" :max="99" :readonly="!rules[tier].repeatRewards" />
        <span class="hint">{{ rules[tier].repeatRewards ? `每天前 ${rules[tier].dailyRewardLimit} 次胜利有奖励` : "0 = 不限、不给" }}</span>
      </div>

      <RuleLabel text="装备品质掉率" :help="RULE_HELP.gearQualityPct" top />
      <div v-for="tier in TIERS" :key="tier" class="cell col">
        <div class="rates">
          <div v-for="quality in GEAR_QUALITIES" :key="quality.key" class="rate">
            <span class="mini"><i class="dot" :style="{ background: quality.color }" />{{ quality.name }}</span>
            <NumInput v-model="rules[tier].gearQualityPct[quality.key]" :width="88" unit="%" :precision="2" :max="100" />
          </div>
        </div>
        <span class="hint" :class="{ bad: qualityTotal(rules[tier].gearQualityPct) !== 100 }">合计 {{ qualityTotal(rules[tier].gearQualityPct) }}%{{ qualityTotal(rules[tier].gearQualityPct) !== 100 ? "，必须 100%" : "" }}</span>
      </div>

      <RuleLabel text="允许自动挑战" :help="RULE_HELP.autoChallenge" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <el-switch v-model="rules[tier].autoChallenge" /><span class="sw-text">{{ rules[tier].autoChallenge ? "允许 · 挂机时满足条件自动打" : "不允许 · 只能手动点挑战" }}</span>
      </div>

      <RuleLabel text="自动挑战条件" :help="RULE_HELP.autoChallengePowerPct" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <span class="mini">战力 ≥ 推荐战力 ×</span>
        <NumInput v-model="rules[tier].autoChallengePowerPct" :width="100" unit="%" :precision="0" :min="1" :max="1000" :readonly="!rules[tier].autoChallenge" />
        <span class="hint">{{ rules[tier].autoChallenge ? "" : "关闭自动挑战时不生效" }}</span>
      </div>

      <RuleLabel text="输了再试间隔" :help="RULE_HELP.autoChallengeRetrySeconds" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <NumInput v-model="rules[tier].autoChallengeRetrySeconds" :width="120" unit="秒" :precision="0" :max="86400" :readonly="!rules[tier].autoChallenge" />
      </div>

      <RuleLabel text="解锁下一关" :help="RULE_HELP.unlock" />
      <div v-for="tier in TIERS" :key="tier" class="cell">
        <el-switch v-model="rules[tier].unlockNeedsBossWin" /><span class="sw-text">需要击败本关首领</span>
        <el-switch v-model="rules[tier].unlockNeedsRealm" class="gap" /><span class="sw-text">需要达到下一关境界</span>
      </div>
    </div>
    <p class="muted small">关卡里单独改过的项显示「已自定义」，在「关卡与Boss」抽屉的首领规则里可以一键恢复默认。</p>
  </SectionCard>
</template>

<script setup lang="ts">
/**
 * 配置概览 · 首领规则（ADMIN_SPEC §11，第三批）：两列——小首领（精英，非章末关卡）/ 大首领（章末）。
 * 绑定 tuning.bossRules，跟配置概览一起保存（PUT /admin/draft/config-overview）；使用 / 自定义数量来自 GET /admin/draft/boss-rules。
 * 旧的「首领橙装概率」（tuning.bossOrangeChanceBp）已停用 → 橙装是「装备品质掉率」里的橙色一档。
 */
import { computed, defineComponent, h, onMounted, ref } from "vue";
import CustomTag from "../../../components/CustomTag.vue";
import HelpTip from "../../../components/HelpTip.vue";
import NumInput from "../../../components/NumInput.vue";
import SectionCard from "../../../components/SectionCard.vue";
import TierTag from "../../../components/TierTag.vue";
import { GEAR_QUALITIES, RULE_HELP, STAT_MULS, loadBossRules, qualityTotal, type BossRules, type BossRulesView, type BossTier } from "../../../composables/bossRules";

const rules = defineModel<BossRules | undefined>("rules", { required: true });
const props = defineProps<{ defaults?: BossRules }>();
const TIERS: BossTier[] = ["elite", "chief"];
const usage = ref<BossRulesView["usage"] | null>(null);

const usedBy = computed(() => (usage.value ? usage.value.elite.stages + usage.value.chief.stages : "—"));
const customizedTotal = computed(() => (usage.value ? usage.value.elite.customized + usage.value.chief.customized : 0));

function changed(tier: BossTier, path: string): boolean {
  if (!props.defaults || !rules.value) return false;
  const read = (root: unknown) => path.split(".").reduce<unknown>((value, key) => (value as Record<string, unknown> | undefined)?.[key], root);
  return read(rules.value[tier]) !== read(props.defaults[tier]);
}

const RuleLabel = defineComponent({
  props: { text: { type: String, required: true }, help: { type: String, default: "" }, top: Boolean },
  setup(labelProps) {
    return () => h("div", { class: ["rule-label", { top: labelProps.top }] }, [labelProps.text, labelProps.help ? h(HelpTip, { title: labelProps.text, text: labelProps.help }) : null]);
  },
});

async function reloadUsage(): Promise<void> {
  try {
    usage.value = (await loadBossRules()).usage;
  } catch {
    usage.value = null;
  }
}
onMounted(reloadUsage);
defineExpose({ reloadUsage });
</script>

<style scoped>
.boss-grid {
  display: grid;
  grid-template-columns: 136px minmax(0, 1fr) minmax(0, 1fr);
  column-gap: 16px;
  row-gap: 4px;
  align-items: center;
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
  margin-top: 34px;
}
.mults,
.rates {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}
.mult,
.rate {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.mini {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.dot {
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
.hint {
  color: var(--xx-text-placeholder);
  font-size: 12px;
}
.hint.bad {
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
