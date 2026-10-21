<template>
  <div class="boss-editor">
    <div v-if="bosses.length === 0" class="empty">
      <p>本关还没有首领（每关都要有首领：普通关卡是小首领 · 精英，章末是大首领）</p>
      <el-button size="small" @click="addBoss">＋ 添加首领</el-button>
    </div>
    <template v-else>
      <div v-for="(boss, index) in bosses.slice(0, 1)" :key="`b${index}`">
        <!-- 属性方式 / 倍率 / 立绘 -->
        <div class="rrow">
          <span class="rl">属性<HelpTip title="首领属性" :text="RULE_HELP.statMode" /></span>
          <el-radio-group :model-value="eff(boss).statMode" size="small" @update:model-value="(value: string | number | boolean | undefined) => setStatMode(boss, value as 'auto' | 'manual')">
            <el-radio-button value="auto">自动 · 普通怪 × 倍率</el-radio-button>
            <el-radio-button value="manual">手填</el-radio-button>
          </el-radio-group>
          <RuleMark :custom="isCustom(boss, 'statMode')" @reset="resetKey(boss, 'statMode')" />
        </div>
        <div v-if="eff(boss).statMode === 'auto'" class="rrow top">
          <span class="rl">属性倍率<HelpTip title="属性倍率" :text="RULE_HELP.statMul" /></span>
          <div class="mults">
            <div v-for="stat in STAT_MULS" :key="stat.key" class="mult">
              <span class="mini">{{ stat.name }} ×</span>
              <NumInput
                :model-value="boss.rules?.statMul?.[stat.key] ?? null"
                :inherit-value="defaults.statMul[stat.key]"
                :custom="isSubCustom(boss, 'statMul', stat.key)"
                :width="120"
                unit="倍"
                :precision="2"
                :min="0.1"
                :max="100"
                @update:model-value="(value: number | null) => setSub(boss, 'statMul', stat.key, value)"
              />
            </div>
          </div>
          <RuleMark :custom="subCount(boss, 'statMul') > 0" :count="subCount(boss, 'statMul')" class="mt" @reset="resetKey(boss, 'statMul')" />
          <span class="side-note">攻防血 = 本关第一只普通怪 × 倍数，自动算（灰字）；直接改某项属性会变成已自定义</span>
        </div>
        <div class="rrow">
          <span class="rl">立绘<HelpTip title="首领立绘" text="游戏里首领用的怪物贴图（精英会自动放大 1.2 倍并加金边金光，章末首领加红边红光）。不选：精英跟随本关第一只普通怪，章末首领按名字匹配。" /></span>
          <ArtKeySelect v-model="boss.artKey" :tier="tier" :inherit-key="tier === 'elite' ? monster?.artKey : null" :width="240" clearable />
          <span v-if="!boss.artKey" class="side-note inline">{{ tier === "elite" ? (monster?.artKey ? "跟随本关普通怪" : "本关普通怪也没选立绘，按名字匹配") : "没选时游戏按名字匹配" }}</span>
        </div>

        <table class="grid">
          <thead>
            <tr>
              <th class="name">名称</th>
              <th class="num">攻击</th>
              <th class="num">防御</th>
              <th class="num">气血</th>
              <th class="num">攻击间隔<HelpTip title="首领攻击间隔" text="每次出手相隔的秒数，越小越快；比境界基础间隔快的部分会折算成速度，计入首领战力。自动模式下跟本关普通怪一样。" /></th>
              <th class="num">首领战力<HelpTip title="首领战力（只读）" :text="`攻击 × ${weights.attack} + 防御 × ${weights.defense} + 气血 × ${weights.hp} + 速度 × ${weights.speed}`" /></th>
              <th class="ops">操作</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td class="name"><el-input v-model="boss.name" placeholder="首领名称" /></td>
              <td v-for="stat in STAT_KEYS" :key="stat.key" class="num">
                <NumInput
                  v-if="eff(boss).statMode === 'auto' && autoStats(boss)"
                  :model-value="statCustom(boss, stat.key) ? boss[stat.key] : null"
                  :inherit-value="autoStats(boss)![stat.key]"
                  :custom="statCustom(boss, stat.key)"
                  :width="120"
                  :unit="stat.unit"
                  :precision="stat.precision"
                  :min="stat.min"
                  @update:model-value="(value: number | null) => setStat(boss, stat.key, value)"
                />
                <NumInput v-else v-model="boss[stat.key]" :width="120" :unit="stat.unit" :precision="stat.precision" :min="stat.min" :step="stat.key === 'interval' ? 0.05 : 1" />
              </td>
              <td class="num"><NumInput :model-value="powerOf(effectiveBoss(boss))" :width="120" unit="战力" readonly /></td>
              <td class="ops">
                <el-button link type="primary" :disabled="!(effectiveBoss(boss).hp > 0 && effectiveBoss(boss).interval > 0)" @click="$emit('trial', effectiveBoss(boss))">试打</el-button>
                <el-button v-if="(boss.statsCustom?.length ?? 0) > 0 && eff(boss).statMode === 'auto'" link type="primary" @click="boss.statsCustom = []">↺ 属性</el-button>
                <el-button v-else link type="danger" @click="bosses.splice(index, 1)">删除</el-button>
              </td>
            </tr>
          </tbody>
        </table>
        <p v-if="eff(boss).statMode === 'auto' && !autoStats(boss)" class="warn pad">自动属性需要本关至少有一只普通怪；现在按手填数值显示，发布校验会报错。</p>
        <p v-if="bosses.length > 1" class="muted pad">玩家点「挑战」打第一个首领，其余首领不会出场。</p>

        <!-- 首领规则（跟随配置概览，改了算已自定义） -->
        <div class="sub-card">
          <header class="sub-head">
            <strong>首领规则</strong><span class="muted">灰字 = 跟随配置概览；改动后变为已自定义</span>
            <span class="spacer" />
            <template v-if="overrideCount(boss.rules)">
              <CustomTag kind="custom">已自定义 {{ overrideCount(boss.rules) }} 项</CustomTag>
              <el-button link type="primary" @click="boss.rules = null">全部恢复默认</el-button>
            </template>
            <CustomTag v-else kind="default">跟随默认</CustomTag>
            <el-button link type="primary" @click="$emit('open-overview')">配置概览 · {{ tier === "chief" ? "大首领" : "小首领" }} ›</el-button>
          </header>
          <div class="rules">
            <div class="rrow">
              <span class="rl">允许重打<HelpTip title="允许重打" :text="RULE_HELP.allowRepeat" /></span>
              <el-switch :model-value="eff(boss).allowRepeat" :class="{ cus: isCustom(boss, 'allowRepeat') }" @update:model-value="(value: string | number | boolean) => setKey(boss, 'allowRepeat', !!value)" />
              <span class="sw-text" :class="{ faint: !isCustom(boss, 'allowRepeat') }">{{ eff(boss).allowRepeat ? "允许" : "不允许" }}</span>
              <RuleMark :custom="isCustom(boss, 'allowRepeat')" @reset="resetKey(boss, 'allowRepeat')" />
            </div>
            <div class="rrow">
              <span class="rl">重打给奖励<HelpTip title="重打给奖励" :text="RULE_HELP.repeatRewards" /></span>
              <el-switch :model-value="eff(boss).repeatRewards" :disabled="!eff(boss).allowRepeat" @update:model-value="(value: string | number | boolean) => setKey(boss, 'repeatRewards', !!value)" />
              <span class="sw-text" :class="{ faint: !isCustom(boss, 'repeatRewards') }">{{ eff(boss).repeatRewards ? "给 · 消耗每日次数" : "不给 · 只有首通奖励" }}</span>
              <RuleMark :custom="isCustom(boss, 'repeatRewards')" @reset="resetKey(boss, 'repeatRewards')" />
            </div>
            <div class="rrow">
              <span class="rl">每日次数<HelpTip title="每日次数" :text="RULE_HELP.dailyRewardLimit" /></span>
              <NumInput
                :model-value="boss.rules?.dailyRewardLimit ?? null"
                :inherit-value="defaults.dailyRewardLimit"
                :custom="isCustom(boss, 'dailyRewardLimit')"
                :readonly="!eff(boss).repeatRewards"
                :width="120"
                unit="次"
                :precision="0"
                :max="99"
                @update:model-value="(value: number | null) => setKey(boss, 'dailyRewardLimit', value)"
              />
              <span class="side-note inline">{{ eff(boss).repeatRewards ? `每天前 ${eff(boss).dailyRewardLimit} 次胜利有奖励` : "0 = 不限、不给" }}</span>
              <RuleMark :custom="isCustom(boss, 'dailyRewardLimit')" @reset="resetKey(boss, 'dailyRewardLimit')" />
            </div>
            <div class="rrow top">
              <span class="rl">装备品质掉率<HelpTip title="装备品质掉率" :text="RULE_HELP.gearQualityPct" /></span>
              <div>
                <div class="mults">
                  <div v-for="quality in GEAR_QUALITIES" :key="quality.key" class="mult">
                    <span class="mini"><i class="dot" :style="{ background: quality.color }" />{{ quality.name }}</span>
                    <NumInput
                      :model-value="boss.rules?.gearQualityPct?.[quality.key] ?? null"
                      :inherit-value="defaults.gearQualityPct[quality.key]"
                      :custom="isSubCustom(boss, 'gearQualityPct', quality.key)"
                      :width="88"
                      unit="%"
                      :precision="2"
                      :max="100"
                      @update:model-value="(value: number | null) => setSub(boss, 'gearQualityPct', quality.key, value)"
                    />
                  </div>
                </div>
                <span class="side-note" :class="{ bad: qualityTotal(eff(boss).gearQualityPct) !== 100 }">合计 {{ qualityTotal(eff(boss).gearQualityPct) }}%{{ qualityTotal(eff(boss).gearQualityPct) !== 100 ? "，必须 100%" : "" }}</span>
              </div>
              <RuleMark :custom="subCount(boss, 'gearQualityPct') > 0" :count="subCount(boss, 'gearQualityPct')" class="mt" @reset="resetKey(boss, 'gearQualityPct')" />
            </div>
            <div class="rrow">
              <span class="rl">允许自动挑战<HelpTip title="允许自动挑战" :text="RULE_HELP.autoChallenge" /></span>
              <el-switch :model-value="eff(boss).autoChallenge" @update:model-value="(value: string | number | boolean) => setKey(boss, 'autoChallenge', !!value)" />
              <span class="sw-text" :class="{ faint: !isCustom(boss, 'autoChallenge') }">{{ eff(boss).autoChallenge ? "允许 · 挂机时满足条件自动打" : "不允许 · 只能手动点挑战" }}</span>
              <RuleMark :custom="isCustom(boss, 'autoChallenge')" @reset="resetKey(boss, 'autoChallenge')" />
            </div>
            <div class="rrow">
              <span class="rl">自动挑战条件<HelpTip title="自动挑战条件" :text="RULE_HELP.autoChallengePowerPct" /></span>
              <span class="mini">战力 ≥ 推荐战力 ×</span>
              <NumInput
                :model-value="boss.rules?.autoChallengePowerPct ?? null"
                :inherit-value="defaults.autoChallengePowerPct"
                :custom="isCustom(boss, 'autoChallengePowerPct')"
                :readonly="!eff(boss).autoChallenge"
                :width="100"
                unit="%"
                :precision="0"
                :min="1"
                :max="1000"
                @update:model-value="(value: number | null) => setKey(boss, 'autoChallengePowerPct', value)"
              />
              <span v-if="!eff(boss).autoChallenge" class="side-note inline">关闭自动挑战时不生效</span>
              <RuleMark :custom="isCustom(boss, 'autoChallengePowerPct')" @reset="resetKey(boss, 'autoChallengePowerPct')" />
            </div>
            <div class="rrow">
              <span class="rl">解锁下一关<HelpTip title="解锁下一关" :text="RULE_HELP.unlock" /></span>
              <el-switch :model-value="eff(boss).unlockNeedsBossWin" @update:model-value="(value: string | number | boolean) => setKey(boss, 'unlockNeedsBossWin', !!value)" />
              <span class="sw-text" :class="{ faint: !isCustom(boss, 'unlockNeedsBossWin') }">需要击败本关首领</span>
              <el-switch :model-value="eff(boss).unlockNeedsRealm" class="gap" @update:model-value="(value: string | number | boolean) => setKey(boss, 'unlockNeedsRealm', !!value)" />
              <span class="sw-text" :class="{ faint: !isCustom(boss, 'unlockNeedsRealm') }">需要达到下一关境界</span>
              <RuleMark :custom="isCustom(boss, 'unlockNeedsBossWin') || isCustom(boss, 'unlockNeedsRealm')" @reset="resetKey(boss, 'unlockNeedsBossWin'); resetKey(boss, 'unlockNeedsRealm')" />
            </div>
          </div>
        </div>

        <!-- 首通奖励 -->
        <div class="sub-card">
          <header class="sub-head"><strong>首通奖励</strong><span class="muted">第一次击败时全部发放</span></header>
          <table class="grid">
            <thead>
              <tr>
                <th class="type">类型</th>
                <th>内容</th>
                <th class="num">数量</th>
                <th class="ops">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(entry, entryIndex) in boss.firstClear ?? []" :key="entryIndex">
                <td class="type">
                  <el-select :model-value="entryKind(entry)" class="w100" @update:model-value="(kind: string) => setKind(boss, entryIndex, kind)">
                    <el-option label="随机装备" value="randomGear" />
                    <el-option label="指定装备" value="gear" />
                    <el-option label="物品" value="item" />
                    <el-option label="功法" value="skill" />
                    <el-option label="修为" value="cultivation" />
                    <el-option label="灵石" value="spiritStones" />
                  </el-select>
                </td>
                <td>
                  <el-select v-if="entry.kind === 'item'" v-model="entry.itemId" filterable placeholder="选择" class="w320">
                    <el-option v-for="option in optionsFor(entryKind(entry))" :key="option.id" :label="option.displayName || '名称缺失'" :value="option.id" />
                  </el-select>
                  <span v-else-if="entry.kind === 'gear'" class="muted">本境界随机部位，品质按上面「装备品质掉率」抽</span>
                  <span v-else-if="entry.kind === 'spiritStones'" class="muted">直接加到灵石</span>
                  <span v-else class="muted">直接加到修为</span>
                </td>
                <td class="num">
                  <NumInput v-if="entry.kind === 'item'" v-model="entry.quantity" :width="100" :min="1" :precision="0" :unit="entryKind(entry) === 'skill' ? '本' : entryKind(entry) === 'gear' ? '件' : '个'" />
                  <NumInput v-else v-model="entry.amount" :width="100" :min="1" :precision="0" :unit="entry.kind === 'gear' ? '件' : entry.kind === 'spiritStones' ? '灵石' : '修为'" />
                </td>
                <td class="ops"><el-button link type="danger" @click="firstClear(boss).splice(entryIndex, 1)">删除</el-button></td>
              </tr>
            </tbody>
          </table>
          <button type="button" class="add-row" @click="firstClear(boss).push({ kind: 'item', itemId: '', quantity: 1 })">＋ 添加奖励</button>
        </div>

        <!-- 重复奖励（只有规则允许重打且给奖励时生效） -->
        <div v-if="eff(boss).allowRepeat && eff(boss).repeatRewards" class="sub-card">
          <header class="sub-head"><strong>重复奖励</strong><span class="muted">之后每次胜利；每日前 {{ eff(boss).dailyRewardLimit }} 次有奖励</span></header>
          <div class="repeat-line">
            <el-switch :model-value="!!boss.repeat?.gear" @update:model-value="(on: string | number | boolean) => (repeat(boss).gear = !!on)" />
            <span>每次给 1 件本境界装备</span>
            <span class="muted">品质按上面「装备品质掉率」抽（橙 {{ eff(boss).gearQualityPct.orange }}%）</span>
          </div>
          <table class="grid">
            <thead>
              <tr>
                <th>额外物品</th>
                <th class="num">概率<HelpTip title="额外物品概率" text="每样物品各自独立掷骰。" /></th>
                <th class="range">数量范围</th>
                <th class="ops">操作</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(extra, extraIndex) in boss.repeat?.extras ?? []" :key="extraIndex">
                <td>
                  <el-select v-model="extra.itemId" filterable placeholder="选择物品" class="w320">
                    <el-option v-for="item in items" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
                  </el-select>
                </td>
                <td class="num"><NumInput v-model="extra.chancePercent" :width="120" unit="%" :precision="2" :max="100" /></td>
                <td class="range">
                  <NumInput v-model="extra.minQty" :width="88" :min="1" :precision="0" unit="个" />
                  <span class="dash">–</span>
                  <NumInput v-model="extra.maxQty" :width="88" :min="1" :precision="0" unit="个" />
                </td>
                <td class="ops"><el-button link type="danger" @click="repeat(boss).extras.splice(extraIndex, 1)">删除</el-button></td>
              </tr>
            </tbody>
          </table>
          <button type="button" class="add-row" @click="repeat(boss).extras.push({ itemId: '', chancePercent: 30, minQty: 1, maxQty: 1 })">＋ 添加额外物品</button>
        </div>
        <div v-else class="dashed-note">
          重复奖励：本关{{ tier === "chief" ? "大首领" : "小首领" }}{{ eff(boss).allowRepeat ? "重打不给奖励（只有首通奖励）" : "不能重打" }}。要给的话，在上面「首领规则」打开「重打给奖励」，或在配置概览改默认。
        </div>

        <!-- 旧版按概率掉落（老内容才有；新内容走首通 / 重复奖励） -->
        <div v-if="boss.drops.length > 0" class="sub-card">
          <header class="sub-head"><strong>旧版掉落</strong><span class="muted">老内容的按概率掉落，已配了首通 / 重复奖励时不再生效</span></header>
          <div v-for="(drop, dropIndex) in boss.drops" :key="dropIndex" class="repeat-line">
            <el-select v-model="drop.itemId" filterable class="w320">
              <el-option v-for="item in [...weapons, ...items, ...skills]" :key="item.id" :label="item.displayName || '名称缺失'" :value="item.id" />
            </el-select>
            <NumInput v-model="drop.chancePercent" :width="120" unit="%" :precision="2" :max="100" />
            <el-button link type="danger" @click="boss.drops.splice(dropIndex, 1)">删除</el-button>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup lang="ts">
/**
 * 关卡抽屉 · 首领（ADMIN_SPEC §11，第三批）：属性方式（自动 = 普通怪 × 倍率 / 手填）、立绘、首领规则覆盖（灰字跟随配置概览，
 * 改了算「已自定义」可恢复）、首通奖励（含随机装备 / 灵石）、重复奖励（规则允许时才有）。
 * 旧的「首领每日奖励次数」（rules.bossDailyRewardCount）和单首领「橙装概率」已停用。
 */
import { defineComponent, h } from "vue";
import { GEAR_QUALITIES, RULE_HELP, STAT_MULS, overrideCount, qualityTotal, resolveRules, type BossRuleOverride, type BossRuleSet, type BossTier, type GearQuality, type ScalarRuleKey, type StatMulKey } from "../composables/bossRules";
import type { Named } from "../composables/lookups";
import ArtKeySelect from "./ArtKeySelect.vue";
import CustomTag from "./CustomTag.vue";
import HelpTip from "./HelpTip.vue";
import NumInput from "./NumInput.vue";

export type DropRow = { itemId: string; chancePercent: number | undefined };
export type FirstClearRow = { kind: "item"; itemId: string; quantity: number } | { kind: "cultivation"; amount: number } | { kind: "spiritStones"; amount: number } | { kind: "gear"; amount: number };
export type RepeatRow = { gear: boolean; extras: { itemId: string; chancePercent: number; minQty: number; maxQty: number }[] };
export type BossStatKey = "attack" | "defense" | "hp" | "interval";
export type BossRow = {
  name: string;
  attack: number;
  defense: number;
  hp: number;
  interval: number;
  drops: DropRow[];
  firstClear?: FirstClearRow[];
  repeat?: RepeatRow | null;
  artKey?: string | null;
  rules?: BossRuleOverride | null;
  statsCustom?: BossStatKey[];
};
export type MonsterLike = { attack: number; defense: number; hp: number; interval: number; artKey?: string | null };

const props = defineProps<{
  items: Named[];
  weapons: Named[];
  skills: Named[];
  showAllErrors?: boolean;
  powerOf: (boss: BossRow) => number | null;
  weights: { attack: number; defense: number; hp: number; speed: number };
  /** 本关首领档次（精英 / 章末），决定跟随哪一列默认规则 */
  tier: BossTier;
  /** 配置概览里这一档的默认规则 */
  defaults: BossRuleSet;
  /** 本关第一只普通怪（自动属性的基准） */
  monster?: MonsterLike | null;
}>();
const bosses = defineModel<BossRow[]>({ required: true });
defineEmits<{ trial: [boss: BossRow]; "open-overview": [] }>();

const STAT_KEYS: { key: BossStatKey; unit?: string; precision?: number; min: number }[] = [
  { key: "attack", min: 0 },
  { key: "defense", min: 0 },
  { key: "hp", min: 1 },
  { key: "interval", unit: "秒", precision: 2, min: 0.1 },
];

/** 右侧「已自定义 · ↺ 恢复默认」 */
const RuleMark = defineComponent({
  props: { custom: Boolean, count: { type: Number, default: 0 } },
  emits: ["reset"],
  setup(markProps, { emit }) {
    return () =>
      markProps.custom
        ? h("span", { class: "rule-mark" }, [
            h(CustomTag, { kind: "custom" }, () => (markProps.count > 1 ? `已自定义 ${markProps.count} 项` : "已自定义")),
            h("button", { type: "button", class: "reset-link", onClick: () => emit("reset") }, "恢复默认"),
          ])
        : null;
  },
});

function eff(boss: BossRow): BossRuleSet {
  return resolveRules(props.defaults, boss.rules);
}
function isCustom(boss: BossRow, key: ScalarRuleKey): boolean {
  return boss.rules?.[key] !== undefined && boss.rules?.[key] !== null;
}
function isSubCustom(boss: BossRow, group: "statMul" | "gearQualityPct", key: string): boolean {
  const value = (boss.rules?.[group] as Record<string, number | undefined> | undefined)?.[key];
  return value !== undefined && value !== null;
}
function subCount(boss: BossRow, group: "statMul" | "gearQualityPct"): number {
  return Object.values((boss.rules?.[group] as Record<string, number | undefined> | undefined) ?? {}).filter((value) => value !== undefined && value !== null).length;
}
function commit(boss: BossRow, next: BossRuleOverride): void {
  boss.rules = overrideCount(next) > 0 ? next : null;
}
function setKey<K extends ScalarRuleKey>(boss: BossRow, key: K, value: BossRuleSet[K] | null): void {
  const next: BossRuleOverride = { ...(boss.rules ?? {}) };
  if (value === null || value === props.defaults[key]) delete next[key];
  else next[key] = value;
  commit(boss, next);
}
function setSub(boss: BossRow, group: "statMul" | "gearQualityPct", key: StatMulKey | GearQuality, value: number | null): void {
  const next: BossRuleOverride = { ...(boss.rules ?? {}) };
  const part: Record<string, number> = { ...((next[group] as Record<string, number> | undefined) ?? {}) };
  if (value === null || value === (props.defaults[group] as Record<string, number>)[key]) delete part[key];
  else part[key] = value;
  if (Object.keys(part).length) (next as Record<string, unknown>)[group] = part;
  else delete next[group];
  commit(boss, next);
}
function resetKey(boss: BossRow, key: keyof BossRuleSet): void {
  const next: BossRuleOverride = { ...(boss.rules ?? {}) };
  delete next[key];
  commit(boss, next);
}
function setStatMode(boss: BossRow, mode: "auto" | "manual"): void {
  // 自动 → 手填：先把当前生效的数值填进去，免得一切换就变成旧的手填值
  if (mode === "manual" && eff(boss).statMode === "auto") {
    const auto = autoStats(boss);
    if (auto) {
      for (const stat of STAT_KEYS) if (!statCustom(boss, stat.key)) boss[stat.key] = auto[stat.key];
    }
  }
  setKey(boss, "statMode", mode);
}

/** 自动属性：本关第一只普通怪 × 倍率（和服务端 expandBossStats 一样四舍五入；出手间隔同普通怪） */
function autoStats(boss: BossRow): Record<BossStatKey, number> | null {
  const monster = props.monster;
  if (!monster) return null;
  const mul = eff(boss).statMul;
  return { attack: Math.round(monster.attack * mul.attack), defense: Math.round(monster.defense * mul.defense), hp: Math.round(monster.hp * mul.hp), interval: monster.interval };
}
function statCustom(boss: BossRow, key: BossStatKey): boolean {
  return boss.statsCustom?.includes(key) ?? false;
}
function setStat(boss: BossRow, key: BossStatKey, value: number | null): void {
  const custom = new Set(boss.statsCustom ?? []);
  if (value === null) custom.delete(key);
  else {
    boss[key] = value;
    custom.add(key);
  }
  boss.statsCustom = STAT_KEYS.map((stat) => stat.key).filter((stat) => custom.has(stat));
}
/** 生效数值（战力、试打用） */
function effectiveBoss(boss: BossRow): BossRow {
  const auto = eff(boss).statMode === "auto" ? autoStats(boss) : null;
  if (!auto) return boss;
  const pick = (key: BossStatKey) => (statCustom(boss, key) ? boss[key] : auto[key]);
  return { ...boss, attack: pick("attack"), defense: pick("defense"), hp: pick("hp"), interval: pick("interval") };
}

function firstClear(boss: BossRow): FirstClearRow[] {
  if (!boss.firstClear) boss.firstClear = [];
  return boss.firstClear;
}
function repeat(boss: BossRow): RepeatRow {
  if (!boss.repeat) boss.repeat = { gear: false, extras: [] };
  return boss.repeat;
}
function entryKind(entry: FirstClearRow): string {
  if (entry.kind === "cultivation") return "cultivation";
  if (entry.kind === "spiritStones") return "spiritStones";
  if (entry.kind === "gear") return "randomGear";
  if (props.skills.some((skill) => skill.id === entry.itemId) || entry.itemId.startsWith("book_")) return "skill";
  if (props.weapons.some((weapon) => weapon.id === entry.itemId) || entry.itemId.startsWith("gear_")) return "gear";
  return "item";
}
function optionsFor(kind: string): Named[] {
  if (kind === "skill") return props.skills;
  if (kind === "gear") return props.weapons;
  return props.items;
}
function setKind(boss: BossRow, index: number, kind: string): void {
  const list = firstClear(boss);
  if (kind === "cultivation") list[index] = { kind: "cultivation", amount: 1000 };
  else if (kind === "spiritStones") list[index] = { kind: "spiritStones", amount: 100 };
  else if (kind === "randomGear") list[index] = { kind: "gear", amount: 1 };
  else list[index] = { kind: "item", itemId: optionsFor(kind)[0]?.id ?? "", quantity: 1 };
}
function addBoss(): void {
  bosses.value.push({ name: "", attack: 0, defense: 0, hp: 1, interval: 1.5, drops: [], firstClear: [], repeat: { gear: true, extras: [] }, artKey: null, rules: null, statsCustom: [] });
}

defineExpose({ addBoss });
</script>

<style scoped>
.empty {
  display: grid;
  place-items: center;
  gap: 8px;
  padding: 24px;
  border: 1px dashed var(--xx-border-strong);
  border-radius: 8px;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.empty p {
  margin: 0;
}
.rrow {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 6px 0;
  flex-wrap: wrap;
}
.rrow.top {
  align-items: flex-start;
}
.rl {
  display: flex;
  justify-content: flex-end;
  align-items: center;
  gap: 4px;
  width: 136px;
  flex: none;
  margin-right: 6px;
  color: var(--xx-text-regular);
  font-size: var(--xx-fs-sm);
}
.rrow.top .rl,
.mt {
  margin-top: 26px;
}
.mults {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
}
.mult {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.mini {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.side-note {
  max-width: 240px;
  margin: 26px 0 0 auto;
  color: var(--xx-text-placeholder);
  font-size: 12px;
}
.side-note.inline {
  max-width: none;
  margin: 0;
}
.side-note.bad,
.warn {
  color: var(--el-color-danger);
}
.dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  margin-right: 4px;
  border-radius: 50%;
}
.sw-text {
  font-size: 13px;
}
.sw-text.faint {
  color: #98a19c;
}
.gap {
  margin-left: 18px;
}
:deep(.rule-mark) {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
:deep(.reset-link) {
  padding: 0;
  border: 0;
  background: none;
  color: var(--el-color-primary);
  font-size: 12px;
  cursor: pointer;
}
.grid {
  width: 100%;
  margin-top: 8px;
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
  width: 180px;
}
.grid .type {
  width: 116px;
}
.grid .range {
  width: 220px;
  white-space: nowrap;
}
.grid .ops {
  width: 110px;
  text-align: right;
  white-space: nowrap;
}
.dash {
  margin: 0 6px;
  color: var(--xx-text-placeholder);
}
.w100 {
  width: 100px;
}
.w320 {
  width: 320px;
}
.sub-card {
  margin-top: 16px;
  border: 1px solid var(--xx-border);
  border-radius: 8px;
  background: var(--xx-bg-surface);
  overflow: hidden;
}
.sub-head {
  display: flex;
  align-items: center;
  gap: 10px;
  height: 40px;
  padding: 0 12px;
  border-bottom: 1px solid var(--xx-border);
  background: var(--xx-bg-subtle);
}
.spacer {
  flex: 1;
}
.rules {
  padding: 8px 12px;
}
.repeat-line {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px 12px;
  font-size: var(--xx-fs-sm);
}
.dashed-note {
  margin-top: 16px;
  padding: 12px 16px;
  border: 1px dashed var(--xx-border-strong);
  border-radius: 8px;
  color: var(--xx-text-secondary);
  font-size: 13px;
}
.add-row {
  display: block;
  width: calc(100% - 24px);
  margin: 10px 12px;
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
.muted {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.pad {
  margin: 8px 0 0;
  font-size: 12px;
}
</style>
