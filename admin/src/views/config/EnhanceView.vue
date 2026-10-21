<template>
  <div>
    <PageHeader title="装备强化" desc="玩家在分解界面自己勾选装备分解，得到「炼器精粹」（可堆叠材料，没有上限），精粹用来给任意装备升强化等级，只升不失败、不掉级。每个品质有自己的等级上限、精粹消耗、属性加成和突破节点；已穿戴的装备不能分解。下面所有数字都是起始值，可以随时调整。">
      <template #actions><el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button></template>
    </PageHeader>
    <el-alert type="info" :closable="false" show-icon class="moved-banner">
      <template #title>强化上限、品质倍数和精粹产出也能在「配置概览 → 强化与分解」里改（同一份数据）；突破节点、每级消耗表、部位倍数和经验迁移只在这一页。<el-button link type="primary" @click="$router.push('/config/overview#enhance')">去配置概览 ›</el-button></template>
    </el-alert>

    <DataState :loading="loading && !loaded" :error="error" :has-data="loaded" empty-text="" @retry="load">
      <div class="savebar" :class="{ dirty }">
        <span v-if="!hasSaved" class="state">还没有保存过强化规则：游戏端强化和分解会直接报错，请先填写并保存。</span>
        <span v-else-if="dirty" class="state">有未保存的改动。下面的表和曲线按你正在填的数字实时计算。</span>
        <span v-else class="state ok">已和草稿一致。保存后还要到「发布中心」发布，玩家才会看到。</span>
        <span class="spacer" />
        <el-button @click="fillStarting">填入建议起始值</el-button>
        <el-button :disabled="!dirty" @click="revert">还原</el-button>
        <el-button type="primary" :disabled="!dirty || problems.length > 0" :loading="saving" @click="save">保存到草稿</el-button>
      </div>

      <el-alert v-if="problems.length > 0 && touched" type="warning" :closable="false" show-icon class="gap" title="有几项还没填对">
        <ul class="problems"><li v-for="item in problems" :key="item">{{ item }}</li></ul>
      </el-alert>

      <div class="grid">
        <section class="xx-card">
          <h2>通用规则</h2>
          <p class="hint">基础经验 / 经验增长倍数 / 分解返还比例 是以前「强化经验」的规则：现在只用来算一次性迁移的比例下限（下面「炼器精粹」一节），游戏不再按它们结算。</p>
          <el-form label-position="top" class="form">
            <el-form-item label="基础经验（经验倍数为 1 时，0→1 级）" :error="fieldError('expBase')">
              <el-input-number v-model="form.expBase" :min="1" :step="10" :precision="0" controls-position="right" @change="touched = true" />
              <p class="hint">升第一级要多少强化经验。其他等级、其他品质都由它算出来。</p>
            </el-form-item>
            <el-form-item label="每级经验增长倍数（通用）" :error="fieldError('expGrowth')">
              <el-input-number v-model="form.expGrowth" :min="1" :step="0.05" :precision="2" controls-position="right" @change="touched = true" />
              <p class="hint">每升一级，下一级所需经验乘以它。1.25 表示每级贵 25%。右边的表里某个品质填了自己的值，就用自己的。</p>
            </el-form-item>
            <el-form-item label="每级属性加成（通用，万分比）" :error="fieldError('statGrowthBp')">
              <el-input-number v-model="form.statGrowthBp" :min="1" :step="50" :precision="0" controls-position="right" @change="touched = true" />
              <p class="hint">600 表示每强化一级，装备基础属性 +6%。强化会同时放大这件装备的所有属性。品质可以单独覆盖。</p>
            </el-form-item>
            <el-form-item label="分解返还比例（万分比）" :error="fieldError('refundBp')">
              <el-input-number v-model="form.refundBp" :min="0" :max="10000" :step="500" :precision="0" controls-position="right" @change="touched = true" />
              <p class="hint">分解已强化装备时，退回已投入经验的这一部分。8000 表示退 80%。不要填 10000，否则强化没有成本。</p>
            </el-form-item>
          </el-form>
          <p class="hint">强化经验池没有上限，所以这里没有「经验上限」这一项。已穿戴的装备不能分解，要先脱下。</p>
        </section>

        <section class="xx-card">
          <h2>按品质设置</h2>
          <el-table :data="qualityRows" size="default" class="qtable">
            <el-table-column label="品质" width="70">
              <template #default="{ row }"><RarityTag :name="row.name" /></template>
            </el-table-column>
            <el-table-column label="等级上限" width="115">
              <template #default="{ row }"><el-input-number v-model="rule(row.key).cap" :min="1" :max="LIMITS.maxCap" :precision="0" size="small" controls-position="right" @change="touched = true" /></template>
            </el-table-column>
            <el-table-column label="经验倍数" width="115">
              <template #default="{ row }"><el-input-number v-model="rule(row.key).costMult" :min="0.1" :step="0.05" :precision="2" size="small" controls-position="right" @change="touched = true" /></template>
            </el-table-column>
            <el-table-column label="经验增长倍数" width="125">
              <template #default="{ row }"><el-input-number v-model="rule(row.key).expGrowth" :min="1" :step="0.05" :precision="2" size="small" controls-position="right" placeholder="用通用" @change="touched = true" /></template>
            </el-table-column>
            <el-table-column label="每级属性加成" width="125">
              <template #default="{ row }"><el-input-number v-model="rule(row.key).statGrowthBp" :min="1" :step="50" :precision="0" size="small" controls-position="right" placeholder="用通用" @change="touched = true" /></template>
            </el-table-column>
            <el-table-column label="分解基础经验" min-width="125">
              <template #default="{ row }"><el-input-number v-model="rule(row.key).decomposeExp" :min="1" :step="10" :precision="0" size="small" controls-position="right" @change="touched = true" /></template>
            </el-table-column>
          </el-table>
          <p class="hint">经验倍数：这个品质每一级所需经验再乘以它。「经验增长倍数」「每级属性加成」留空表示用左边的通用值，填了就只对这个品质生效。</p>
        </section>
      </div>

      <section class="xx-card gap essence">
        <header class="head">
          <div>
            <h2>炼器精粹 · 分解产出与强化消耗</h2>
            <p class="hint">分解得到 = 品质产出（× 部位倍数，或单独指定）+ 强化等级 × 每级返还；强化 +L→+L+1 消耗 = round(基础消耗 × 增长倍数^L × 品质倍数)，也可以按级单独指定。游戏端的分解预览和强化卡都读这里，和服务器用同一份公式。</p>
          </div>
          <el-button v-if="!form.essence" type="primary" @click="fillEssence">填入建议起始值</el-button>
        </header>
        <template v-if="form.essence">
          <div class="essence-grid">
            <el-form label-position="top" class="form">
              <el-form-item label="精粹对应的物品">
                <el-select v-model="form.essence.itemSlug" filterable placeholder="选择物品" class="material-select" @change="touched = true">
                  <el-option v-for="option in essenceOptions" :key="option.value" :label="option.label" :value="option.value" />
                </el-select>
                <p class="hint">可堆叠材料，默认「炼器精粹」（refine_essence）。没有的话保存时自动创建。</p>
              </el-form-item>
              <el-form-item label="每级强化返还（精粹）">
                <el-input-number v-model="form.essence.refundPerLevel" :min="0" :step="10" :precision="0" controls-position="right" @change="touched = true" />
                <p class="hint">分解 +N 的装备额外得到 N × 这个数。</p>
              </el-form-item>
              <el-form-item label="强化基础消耗（0→1 级，品质倍数为 1 时）">
                <el-input-number v-model="form.essence.costBase" :min="1" :step="5" :precision="0" controls-position="right" @change="touched = true" />
              </el-form-item>
              <el-form-item label="每级消耗增长倍数">
                <el-input-number v-model="form.essence.costGrowth" :min="1" :step="0.05" :precision="2" controls-position="right" @change="touched = true" />
                <p class="hint">品质倍数用上面「按品质设置」里的「经验倍数」一列。</p>
              </el-form-item>
            </el-form>
            <div>
              <el-table :data="qualityRows" size="small" class="qtable">
                <el-table-column label="品质" width="64"><template #default="{ row }"><RarityTag :name="row.name" /></template></el-table-column>
                <el-table-column label="分解产出" width="120">
                  <template #default="{ row }"><el-input-number v-model="form.essence.yields[row.key as QualityKey]" :min="0" :step="10" :precision="0" size="small" controls-position="right" @change="touched = true" /></template>
                </el-table-column>
                <el-table-column v-for="slot in SLOTS" :key="slot.key" :label="`${slot.name}单独指定`" min-width="98">
                  <template #default="{ row }">
                    <el-input-number :model-value="overrideOf(row.key, slot.key)" :min="0" :precision="0" size="small" controls-position="right" placeholder="—" @update:model-value="(value: number | null | undefined) => setOverride(row.key, slot.key, value)" />
                  </template>
                </el-table-column>
              </el-table>
              <div class="slot-mults">
                <span class="hint">部位倍数（%）：</span>
                <span v-for="slot in SLOTS" :key="slot.key" class="slot-mult">
                  {{ slot.name }}
                  <el-input-number :model-value="slotPercent(slot.key)" :min="0" :max="10000" :step="10" :precision="0" size="small" controls-position="right" @update:model-value="(value: number | null | undefined) => setSlotPercent(slot.key, value)" />
                </span>
              </div>
              <p class="hint">「单独指定」填了就用这个数（不再乘部位倍数），留空 = 品质产出 × 部位倍数。部位倍数留 100% 就是不区分部位。</p>
            </div>
          </div>
          <div class="migrate">
            <div>
              <h3>强化经验 → 炼器精粹（一次性迁移）</h3>
              <p class="hint">
                老玩家剩下的强化经验 × 这个比例（向上取整）换成精粹，每人只换一次（有记录，不会重复）；玩家下次上线结算时自动换，也可以点右边一次换完。已强化装备的等级不变。
                <template v-if="minSafeRatio !== null">按现在的数字，比例不低于 <b>{{ minSafeRatio }}</b>（{{ (minSafeRatio / 100).toFixed(2) }}%）就保证没人变弱：每一级的精粹消耗 ≤ 旧经验消耗 × 比例。</template>
              </p>
              <el-input-number v-model="form.essence.migrationRatioBp" :min="0" :step="100" :precision="0" controls-position="right" @change="touched = true" />
              <span class="hint">万分比（7000 = 1 点经验换 0.7 精粹）</span>
              <el-alert v-if="minSafeRatio !== null && (form.essence.migrationRatioBp ?? 0) < minSafeRatio" type="warning" :closable="false" show-icon class="gap" :title="`比例低于 ${minSafeRatio}：有的老玩家换完后买不回原来能升的等级`" />
            </div>
            <div v-if="migration" class="migrate-status">
              <div><span>已换</span><strong>{{ migration.migratedPlayers }} 人</strong></div>
              <div><span>换掉的经验</span><strong>{{ migration.migratedEnhanceExp }}</strong></div>
              <div><span>发出的精粹</span><strong>{{ migration.migratedEssence }}</strong></div>
              <div><span>还没换</span><strong>{{ migration.pendingPlayers }} 人</strong></div>
              <el-button :disabled="dirty || migration.pendingPlayers === 0" :loading="migrating" @click="migrateAll">现在全部换完</el-button>
            </div>
          </div>
        </template>
        <p v-else class="hint">还没有炼器精粹规则：游戏端分解和强化会报错。点右上角「填入建议起始值」再保存。</p>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <div>
            <h2>突破节点</h2>
            <p class="hint">装备强化到节点等级后，要先交齐材料「突破」才能继续升级。材料从玩家行囊里扣，突破不会失败。节点等级必须小于这个品质的等级上限；等级已经超过节点的老装备不受影响。</p>
          </div>
        </header>
        <el-tabs v-model="nodeQuality" class="node-tabs">
          <el-tab-pane v-for="row in qualityRows" :key="row.key" :name="row.key">
            <template #label>
              <span class="tab-label"><RarityTag :name="row.name" /><span class="count">{{ rule(row.key).breakthroughs.length }} 个节点</span></span>
            </template>
          </el-tab-pane>
        </el-tabs>
        <el-table :data="nodeRows" size="default" class="ntable" empty-text="这个品质没有突破节点：强化可以一路升到等级上限。">
          <el-table-column label="节点等级" width="150">
            <template #default="{ row }">
              <el-input-number v-model="row.level" :min="1" :max="LIMITS.maxCap" :precision="0" size="small" controls-position="right" @change="onNodeLevel" />
            </template>
          </el-table-column>
          <el-table-column label="需要的材料（从行囊扣除）" min-width="360">
            <template #default="{ row }">
              <div v-for="(material, index) in row.materials" :key="index" class="material-row">
                <el-select v-model="material.itemSlug" filterable placeholder="选择材料" size="small" class="material-select" @change="touched = true">
                  <el-option v-for="option in materialOptions" :key="option.value" :label="option.label" :value="option.value" />
                </el-select>
                <span class="times">×</span>
                <el-input-number v-model="material.count" :min="1" :max="LIMITS.maxBreakCount" :precision="0" size="small" controls-position="right" @change="touched = true" />
                <el-button link type="danger" :disabled="row.materials.length <= 1" @click="removeMaterial(row, index)">删除</el-button>
              </div>
              <el-button link type="primary" @click="addMaterial(row)">+ 添加一种材料</el-button>
            </template>
          </el-table-column>
          <el-table-column label="" width="90">
            <template #default="{ $index }"><el-button link type="danger" @click="removeNode($index)">删除节点</el-button></template>
          </el-table-column>
        </el-table>
        <div class="node-actions">
          <el-button @click="addNode">+ 添加节点</el-button>
          <span class="sep" />
          <span class="hint">批量：每隔</span>
          <el-input-number v-model="fillEvery" :min="1" :max="LIMITS.maxCap" :precision="0" size="small" controls-position="right" class="mini" />
          <span class="hint">级加一个节点，材料</span>
          <el-select v-model="fillMaterial" filterable placeholder="选择材料" size="small" class="material-select">
            <el-option v-for="option in materialOptions" :key="option.value" :label="option.label" :value="option.value" />
          </el-select>
          <span class="times">×</span>
          <el-input-number v-model="fillCount" :min="1" :precision="0" size="small" controls-position="right" class="mini" />
          <el-button :disabled="!fillMaterial" @click="fillNodes">补齐节点</el-button>
        </div>
        <p v-if="willCreateMaterials.length > 0" class="hint">用到的 {{ willCreateMaterials.join("、") }} 在「物品」里还没有，保存时会自动创建。</p>
      </section>

      <section class="xx-card gap">
        <header class="head">
          <h2>效果预览</h2>
          <el-radio-group v-model="previewQuality" size="small">
            <el-radio-button v-for="row in qualityRows" :key="row.key" :value="row.key">{{ row.name }}</el-radio-button>
          </el-radio-group>
        </header>
        <div v-if="summary" class="summary">
          <div><span>满级</span><strong>+{{ summary.cap }}</strong></div>
          <div><span>满级总投入</span><strong>{{ summary.total }} 精粹</strong></div>
          <div><span>满级属性</span><strong>×{{ summary.statMult }}（+{{ summary.statPercent }}%）</strong></div>
          <div><span>满级分解可得</span><strong>{{ summary.decompose }} 精粹</strong></div>
          <div><span>约等于分解白装</span><strong>{{ summary.whiteCount }} 件</strong></div>
          <div class="wide"><span>升满共需突破材料</span><strong>{{ summary.materials }}</strong></div>
        </div>
        <el-table :data="curve" size="small" max-height="420" class="curve" :row-class-name="curveRowClass">
          <el-table-column prop="level" label="强化到" width="90"><template #default="{ row }">+{{ row.level }}</template></el-table-column>
          <el-table-column label="这一级消耗精粹" width="200">
            <template #default="{ row }">
              <el-input-number :model-value="tableCostOf(row.level - 1)" :min="1" :precision="0" size="small" controls-position="right" :placeholder="String(row.formulaCost)" @update:model-value="(value: number | null | undefined) => setTableCost(row.level - 1, value)" />
            </template>
          </el-table-column>
          <el-table-column prop="cost" label="实际消耗" width="100" />
          <el-table-column prop="oldCost" label="旧·经验" width="90" />
          <el-table-column prop="total" label="累计投入" width="120" />
          <el-table-column label="属性倍数" width="100"><template #default="{ row }">×{{ row.mult }}</template></el-table-column>
          <el-table-column prop="decompose" label="此时分解可得" width="130" />
          <el-table-column label="继续升级前要突破">
            <template #default="{ row }"><span v-if="row.node" class="node-tag">突破节点 · {{ row.node }}</span><span v-else class="muted">—</span></template>
          </el-table-column>
        </el-table>
        <p class="hint">「这一级消耗精粹」留空 = 按公式（灰字）；填了就用填的数（只对这个品质）。分解可得 = 品质产出（武器部位）+ 等级 × 每级返还。「旧·经验」是以前的强化经验消耗，只用来对照迁移比例。强化永远不会失败，也不会掉级；突破材料不会在分解时返还。</p>
      </section>
    </DataState>
  </div>
</template>

<script setup lang="ts">
import { useRevisions } from "../../composables/revisions";
import { isConflictAbort } from "../../composables/conflict";
import { Refresh } from "@element-plus/icons-vue";
import { useRefetchOnActivate } from "../../composables/dataVersion";
import { ElMessage } from "element-plus";
import { computed, onMounted, ref } from "vue";
import { api } from "../../api";
import DataState from "../../components/DataState.vue";
import PageHeader from "../../components/PageHeader.vue";
import RarityTag from "../../components/RarityTag.vue";
import { useDirtyGuard } from "../../composables/dirty";
import { refreshDraftStatus } from "../../composables/draftStatus";

type QualityKey = "white" | "green" | "blue" | "purple" | "orange";
type Material = { itemSlug: string; count: number | null };
type Node = { level: number | null; materials: Material[] };
type QualityRule = { cap: number | null; costMult: number | null; decomposeExp: number | null; expGrowth?: number | null; statGrowthBp?: number | null; breakthroughs: Node[] };
type SlotKey = "weapon" | "clothes" | "helmet" | "gloves" | "shoes" | "accessory";
type Essence = {
  itemSlug: string;
  yields: Record<QualityKey, number | null>;
  slotMultBp: Partial<Record<SlotKey, number>>;
  slotOverrides: Partial<Record<QualityKey, Partial<Record<SlotKey, number>>>>;
  refundPerLevel: number | null;
  costBase: number | null;
  costGrowth: number | null;
  costTable: Partial<Record<QualityKey, (number | null)[]>>;
  migrationRatioBp: number | null;
};
type Rules = { expBase: number | null; expGrowth: number | null; statGrowthBp: number | null; refundBp: number | null; qualities: Record<QualityKey, QualityRule>; essence: Essence | null };
type StartingMaterial = { slug: string; displayName: string };
type Migration = { migratedPlayers: number; migratedEnhanceExp: number; migratedEssence: number; pendingPlayers: number };
type View = { rules: Partial<Rules> | null; starting: Rules; startingMaterials: StartingMaterial[]; essenceItem?: StartingMaterial; minSafeRatioBp?: number | null; migration?: Migration; createdMaterials?: string[] };
type ItemRow = { id: string; displayName: string };

// 只是填写时防止手滑的范围，和服务器的校验范围一致，不是玩法数值。
const LIMITS = { maxCap: 200, maxBreakCount: 9999 } as const;

const QUALITIES: { key: QualityKey; name: string }[] = [
  { key: "white", name: "白" },
  { key: "green", name: "绿" },
  { key: "blue", name: "蓝" },
  { key: "purple", name: "紫" },
  { key: "orange", name: "橙" },
];

const SLOTS: { key: SlotKey; name: string }[] = [
  { key: "weapon", name: "武器" },
  { key: "clothes", name: "衣服" },
  { key: "helmet", name: "头冠" },
  { key: "gloves", name: "护手" },
  { key: "shoes", name: "鞋子" },
  { key: "accessory", name: "饰品" },
];

function emptyQuality(): QualityRule {
  return { cap: null, costMult: null, decomposeExp: null, expGrowth: null, statGrowthBp: null, breakthroughs: [] };
}

function emptyRules(): Rules {
  const qualities = {} as Rules["qualities"];
  for (const quality of QUALITIES) qualities[quality.key] = emptyQuality();
  return { expBase: null, expGrowth: null, statGrowthBp: null, refundBp: null, qualities, essence: null };
}

function normalizeEssence(raw: Partial<Essence> | null | undefined): Essence | null {
  if (!raw) return null;
  const yields = {} as Essence["yields"];
  for (const quality of QUALITIES) yields[quality.key] = raw.yields?.[quality.key] ?? null;
  return {
    itemSlug: raw.itemSlug ?? "",
    yields,
    slotMultBp: { ...(raw.slotMultBp ?? {}) },
    slotOverrides: JSON.parse(JSON.stringify(raw.slotOverrides ?? {})),
    refundPerLevel: raw.refundPerLevel ?? null,
    costBase: raw.costBase ?? null,
    costGrowth: raw.costGrowth ?? null,
    costTable: JSON.parse(JSON.stringify(raw.costTable ?? {})),
    migrationRatioBp: raw.migrationRatioBp ?? null,
  };
}

/** 服务器存的规则可能缺突破节点（老草稿），补成表单能编辑的样子。品质统一白→橙 5 档（红已去掉）。 */
function normalize(rules: Partial<Rules> | null): Rules {
  const base = emptyRules();
  if (!rules) return base;
  const merged: Rules = {
    expBase: rules.expBase ?? null,
    expGrowth: rules.expGrowth ?? null,
    statGrowthBp: rules.statGrowthBp ?? null,
    refundBp: rules.refundBp ?? null,
    qualities: base.qualities,
    essence: normalizeEssence(rules.essence),
  };
  for (const quality of QUALITIES) {
    const stored = rules.qualities?.[quality.key];
    if (stored) {
      merged.qualities[quality.key] = {
        ...emptyQuality(),
        ...stored,
        expGrowth: stored.expGrowth ?? null,
        statGrowthBp: stored.statGrowthBp ?? null,
        breakthroughs: (stored.breakthroughs ?? []).map((node) => ({ level: node.level, materials: node.materials.map((row) => ({ ...row })) })),
      };
    }
  }
  return merged;
}

/** 发给服务器的样子：去掉空的覆盖值。 */
function payload(rules: Rules): unknown {
  const qualities: Record<string, unknown> = {};
  for (const quality of QUALITIES) {
    const row = rules.qualities[quality.key];
    const out: Record<string, unknown> = { cap: row.cap, costMult: row.costMult, decomposeExp: row.decomposeExp, breakthroughs: row.breakthroughs };
    if (row.expGrowth !== null && row.expGrowth !== undefined) out.expGrowth = row.expGrowth;
    if (row.statGrowthBp !== null && row.statGrowthBp !== undefined) out.statGrowthBp = row.statGrowthBp;
    qualities[quality.key] = out;
  }
  const out: Record<string, unknown> = { expBase: rules.expBase, expGrowth: rules.expGrowth, statGrowthBp: rules.statGrowthBp, refundBp: rules.refundBp, qualities };
  if (rules.essence) {
    const costTable: Record<string, (number | null)[]> = {};
    for (const [key, list] of Object.entries(rules.essence.costTable)) {
      const trimmed = [...(list ?? [])];
      while (trimmed.length > 0 && (trimmed[trimmed.length - 1] === null || trimmed[trimmed.length - 1] === undefined)) trimmed.pop();
      if (trimmed.length > 0) costTable[key] = trimmed.map((value) => value ?? null);
    }
    out.essence = { ...rules.essence, costTable };
  }
  return out;
}

const loading = ref(false);
const loaded = ref(false);
const error = ref("");
const saving = ref(false);
const touched = ref(false);
const hasSaved = ref(false);
const form = ref<Rules>(emptyRules());
const starting = ref<Rules | null>(null);
const startingMaterials = ref<StartingMaterial[]>([]);
const items = ref<ItemRow[]>([]);
const essenceItem = ref<StartingMaterial | null>(null);
const minSafeRatioServer = ref<number | null>(null);
const migration = ref<Migration | null>(null);
const migrating = ref(false);
const original = ref("");
const previewQuality = ref<QualityKey>("orange");
const nodeQuality = ref<QualityKey>("orange");
const fillEvery = ref<number | null>(5);
const fillMaterial = ref("");
const fillCount = ref<number | null>(1);

const qualityRows = QUALITIES;
function rule(key: string): QualityRule {
  return form.value.qualities[key as QualityKey];
}
const dirty = computed(() => JSON.stringify(form.value) !== original.value);
useDirtyGuard(dirty);

const materialOptions = computed(() => {
  const known = new Map<string, string>();
  for (const item of items.value) known.set(item.id, item.displayName);
  for (const material of startingMaterials.value) if (!known.has(material.slug)) known.set(material.slug, `${material.displayName}（保存时创建）`);
  return [...known.entries()].map(([value, label]) => ({ value, label }));
});

function materialName(slug: string): string {
  return materialOptions.value.find((option) => option.value === slug)?.label.replace("（保存时创建）", "") ?? slug;
}

const essenceOptions = computed(() => {
  const list = items.value.map((item) => ({ value: item.id, label: item.displayName }));
  if (essenceItem.value && !list.some((option) => option.value === essenceItem.value!.slug)) list.unshift({ value: essenceItem.value.slug, label: `${essenceItem.value.displayName}（保存时创建）` });
  return list;
});

function overrideOf(quality: QualityKey, slot: SlotKey): number | undefined {
  return form.value.essence?.slotOverrides[quality]?.[slot];
}

function setOverride(quality: QualityKey, slot: SlotKey, value: number | null | undefined): void {
  const essence = form.value.essence;
  if (!essence) return;
  const row = { ...(essence.slotOverrides[quality] ?? {}) };
  if (value === null || value === undefined || Number.isNaN(value)) delete row[slot];
  else row[slot] = value;
  if (Object.keys(row).length > 0) essence.slotOverrides[quality] = row;
  else delete essence.slotOverrides[quality];
  touched.value = true;
}

function slotPercent(slot: SlotKey): number {
  return (form.value.essence?.slotMultBp[slot] ?? 10000) / 100;
}

function setSlotPercent(slot: SlotKey, value: number | null | undefined): void {
  const essence = form.value.essence;
  if (!essence) return;
  if (value === null || value === undefined || Math.round(value * 100) === 10000) delete essence.slotMultBp[slot];
  else essence.slotMultBp[slot] = Math.round(value * 100);
  touched.value = true;
}

function tableCostOf(level: number): number | undefined {
  const value = form.value.essence?.costTable[previewQuality.value]?.[level];
  return value === null ? undefined : value;
}

function setTableCost(level: number, value: number | null | undefined): void {
  const essence = form.value.essence;
  if (!essence) return;
  const list = [...(essence.costTable[previewQuality.value] ?? [])];
  while (list.length <= level) list.push(null);
  list[level] = value === null || value === undefined || Number.isNaN(value) ? null : value;
  while (list.length > 0 && list[list.length - 1] === null) list.pop();
  if (list.length > 0) essence.costTable[previewQuality.value] = list;
  else delete essence.costTable[previewQuality.value];
  touched.value = true;
}

function fillEssence(): void {
  if (!starting.value?.essence) return;
  form.value.essence = normalizeEssence(clone(starting.value.essence));
  touched.value = true;
  ElMessage.info("已填入炼器精粹建议起始值，还没有保存。");
}

async function migrateAll(): Promise<void> {
  migrating.value = true;
  try {
    const result = await api<Migration & { migrated: number }>("/admin/draft/enhance/migrate-exp", { method: "POST", body: "{}" });
    migration.value = result;
    ElMessage.success(`已给 ${result.migrated} 名玩家换成炼器精粹`);
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "迁移失败");
  } finally {
    migrating.value = false;
  }
}

const willCreateMaterials = computed(() => {
  const existing = new Set(items.value.map((item) => item.id));
  const used = new Set(QUALITIES.flatMap((quality) => rule(quality.key).breakthroughs.flatMap((node) => node.materials.map((row) => row.itemSlug))));
  return startingMaterials.value.filter((material) => used.has(material.slug) && !existing.has(material.slug)).map((material) => material.displayName);
});

const problems = computed(() => {
  const list: string[] = [];
  const need = (value: number | null | undefined, label: string, min = 0, max = Infinity): void => {
    if (value === null || value === undefined || Number.isNaN(value)) list.push(`请填写${label}`);
    else if (value < min || value > max) list.push(`${label}要在 ${min} 到 ${max === Infinity ? "更大" : max} 之间`);
  };
  need(form.value.expBase, "基础经验", 1);
  need(form.value.expGrowth, "每级经验增长倍数", 1);
  need(form.value.statGrowthBp, "每级属性加成", 1);
  need(form.value.refundBp, "分解返还比例", 0, 10000);
  const essence = form.value.essence;
  if (!essence) list.push("请填写炼器精粹规则（点「填入建议起始值」）");
  else {
    if (!essence.itemSlug) list.push("请选择炼器精粹对应的物品");
    for (const quality of QUALITIES) need(essence.yields[quality.key], `${quality.name}品质分解产出`, 0);
    need(essence.refundPerLevel, "每级强化返还", 0);
    need(essence.costBase, "强化基础消耗", 1);
    need(essence.costGrowth, "每级消耗增长倍数", 1);
    need(essence.migrationRatioBp, "强化经验转精粹比例", 0);
  }
  for (const quality of QUALITIES) {
    const row = form.value.qualities[quality.key];
    need(row.cap, `${quality.name}品质等级上限`, 1, LIMITS.maxCap);
    need(row.costMult, `${quality.name}品质经验倍数`, 0.1);
    need(row.decomposeExp, `${quality.name}品质分解基础经验`, 1);
    if (row.expGrowth !== null && row.expGrowth !== undefined) need(row.expGrowth, `${quality.name}品质经验增长倍数`, 1);
    if (row.statGrowthBp !== null && row.statGrowthBp !== undefined) need(row.statGrowthBp, `${quality.name}品质每级属性加成`, 1);
    const seen = new Set<number>();
    for (const node of row.breakthroughs) {
      const label = `${quality.name}品质突破节点`;
      if (node.level === null || Number.isNaN(node.level)) {
        list.push(`${label}有一行没填等级`);
        continue;
      }
      if (row.cap !== null && node.level >= row.cap) list.push(`${label} +${node.level} 必须小于等级上限 +${row.cap}`);
      if (seen.has(node.level)) list.push(`${label} +${node.level} 重复了`);
      seen.add(node.level);
      const slugs = new Set<string>();
      for (const material of node.materials) {
        if (!material.itemSlug) list.push(`${label} +${node.level} 有一行没选材料`);
        else if (slugs.has(material.itemSlug)) list.push(`${label} +${node.level} 的「${materialName(material.itemSlug)}」选了两次`);
        else if (!materialOptions.value.some((option) => option.value === material.itemSlug)) list.push(`${label} +${node.level} 的材料已经不在物品里`);
        slugs.add(material.itemSlug);
        need(material.count, `${label} +${node.level} 的材料数量`, 1, LIMITS.maxBreakCount);
      }
    }
  }
  return list;
});

function fieldError(key: "expBase" | "expGrowth" | "statGrowthBp" | "refundBp"): string {
  if (!touched.value) return "";
  const value = form.value[key];
  return value === null || value === undefined ? "还没填" : "";
}

function growthOf(quality: QualityKey): number {
  return form.value.qualities[quality].expGrowth ?? form.value.expGrowth ?? 1;
}

function statBpOf(quality: QualityKey): number {
  return form.value.qualities[quality].statGrowthBp ?? form.value.statGrowthBp ?? 0;
}

// 公式和服务器 backend/src/modules/content/enhance.ts 保持一致
function cost(level: number, quality: QualityKey): number {
  const mult = form.value.qualities[quality].costMult ?? 1;
  return Math.max(1, Math.round((form.value.expBase ?? 0) * growthOf(quality) ** level * mult));
}

/** 精粹消耗（公式）。 */
function formulaEssenceCost(level: number, quality: QualityKey): number {
  const essence = form.value.essence;
  const mult = form.value.qualities[quality].costMult ?? 1;
  return Math.max(1, Math.round((essence?.costBase ?? 0) * (essence?.costGrowth ?? 1) ** level * mult));
}

/** 精粹消耗（单独指定的表优先）。 */
function essenceCost(level: number, quality: QualityKey): number {
  const fixed = form.value.essence?.costTable[quality]?.[level];
  return typeof fixed === "number" && fixed > 0 ? fixed : formulaEssenceCost(level, quality);
}

function invested(level: number, quality: QualityKey): number {
  let total = 0;
  for (let step = 0; step < level; step += 1) total += essenceCost(step, quality);
  return total;
}

function decomposeOf(level: number, quality: QualityKey, slot: SlotKey = "weapon"): number {
  const essence = form.value.essence;
  if (!essence) return 0;
  const override = essence.slotOverrides[quality]?.[slot];
  const base = override ?? Math.round(((essence.yields[quality] ?? 0) * (essence.slotMultBp[slot] ?? 10000)) / 10000);
  return base + level * (essence.refundPerLevel ?? 0);
}

/** 「没人变弱」的最低迁移比例（万分比）：每一级精粹消耗 / 旧经验消耗的最大值，和服务器 minSafeMigrationRatioBp 一样。 */
const minSafeRatio = computed(() => {
  if (!form.value.essence || problems.value.length > 0) return minSafeRatioServer.value;
  let worst = 0;
  for (const quality of QUALITIES) {
    const cap = form.value.qualities[quality.key].cap ?? 0;
    for (let level = 0; level < cap; level += 1) worst = Math.max(worst, essenceCost(level, quality.key) / cost(level, quality.key));
  }
  return Math.ceil(worst * 10000);
});

function multOf(level: number, quality: QualityKey): number {
  return Math.round((1 + (level * statBpOf(quality)) / 10000) * 100) / 100;
}

function nodeText(node: Node): string {
  return node.materials.map((row) => `${materialName(row.itemSlug)}×${row.count}`).join("、");
}

const ready = computed(() => problems.value.length === 0);

const curve = computed(() => {
  if (!ready.value) return [];
  const quality = previewQuality.value;
  const row = form.value.qualities[quality];
  const cap = row.cap ?? 0;
  return Array.from({ length: cap }, (_, index) => {
    const level = index + 1;
    const node = level < cap ? row.breakthroughs.find((candidate) => candidate.level === level) : undefined;
    return { level, cost: essenceCost(index, quality), formulaCost: formulaEssenceCost(index, quality), oldCost: cost(index, quality), total: invested(level, quality), mult: multOf(level, quality), decompose: decomposeOf(level, quality), node: node ? nodeText(node) : "" };
  });
});

function curveRowClass({ row }: { row: { node: string } }): string {
  return row.node ? "node-row" : "";
}

const summary = computed(() => {
  if (!ready.value) return null;
  const quality = previewQuality.value;
  const row = form.value.qualities[quality];
  const cap = row.cap ?? 0;
  const mult = multOf(cap, quality);
  const white = Math.max(1, form.value.essence?.yields.white ?? 1);
  const totals = new Map<string, number>();
  for (const node of row.breakthroughs) {
    if (node.level === null || node.level >= cap) continue;
    for (const material of node.materials) totals.set(material.itemSlug, (totals.get(material.itemSlug) ?? 0) + (material.count ?? 0));
  }
  const materials = [...totals.entries()].map(([slug, count]) => `${materialName(slug)}×${count}`).join("、") || "无";
  return {
    cap,
    total: invested(cap, quality),
    statMult: mult,
    statPercent: Math.round((mult - 1) * 100),
    decompose: decomposeOf(cap, quality),
    whiteCount: Math.ceil(invested(cap, quality) / white),
    materials,
  };
});

// ---- 突破节点编辑 ----
const nodeRows = computed(() => rule(nodeQuality.value).breakthroughs);

function firstMaterial(): string {
  return materialOptions.value[0]?.value ?? "";
}

function addNode(): void {
  const row = rule(nodeQuality.value);
  const last = row.breakthroughs[row.breakthroughs.length - 1]?.level ?? 0;
  row.breakthroughs.push({ level: last + 5, materials: [{ itemSlug: firstMaterial(), count: 1 }] });
  touched.value = true;
}

function removeNode(index: number): void {
  rule(nodeQuality.value).breakthroughs.splice(index, 1);
  touched.value = true;
}

function addMaterial(node: Node): void {
  node.materials.push({ itemSlug: "", count: 1 });
  touched.value = true;
}

function removeMaterial(node: Node, index: number): void {
  node.materials.splice(index, 1);
  touched.value = true;
}

function onNodeLevel(): void {
  touched.value = true;
  rule(nodeQuality.value).breakthroughs.sort((left, right) => (left.level ?? 0) - (right.level ?? 0));
}

function fillNodes(): void {
  const row = rule(nodeQuality.value);
  const every = fillEvery.value ?? 0;
  const cap = row.cap ?? 0;
  if (every < 1 || !fillMaterial.value) return;
  let added = 0;
  for (let level = every; level < cap; level += every) {
    if (row.breakthroughs.some((node) => node.level === level)) continue;
    row.breakthroughs.push({ level, materials: [{ itemSlug: fillMaterial.value, count: fillCount.value ?? 1 }] });
    added += 1;
  }
  row.breakthroughs.sort((left, right) => (left.level ?? 0) - (right.level ?? 0));
  touched.value = true;
  ElMessage.info(added > 0 ? `已补上 ${added} 个节点，还没有保存。` : "没有需要补的节点。");
}

async function loadItems(): Promise<void> {
  try {
    items.value = await api<ItemRow[]>("/admin/draft/items");
  } catch {
    items.value = [];
  }
}

function clone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

const rev = useRevisions("globals");

async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    await rev.load();
    const [view] = await Promise.all([api<View>("/admin/draft/enhance"), loadItems()]);
    starting.value = view.starting;
    startingMaterials.value = view.startingMaterials ?? [];
    essenceItem.value = view.essenceItem ?? null;
    minSafeRatioServer.value = view.minSafeRatioBp ?? null;
    migration.value = view.migration ?? null;
    hasSaved.value = view.rules !== null;
    form.value = normalize(view.rules);
    original.value = JSON.stringify(form.value);
    touched.value = false;
    loaded.value = true;
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : "加载失败";
  } finally {
    loading.value = false;
  }
}

function fillStarting(): void {
  if (!starting.value) return;
  form.value = normalize(clone(starting.value));
  touched.value = true;
  ElMessage.info("已填入建议起始值（含突破节点），还没有保存。");
}

function revert(): void {
  form.value = original.value ? (JSON.parse(original.value) as Rules) : emptyRules();
  touched.value = false;
}

async function save(): Promise<void> {
  touched.value = true;
  if (!ready.value) return;
  saving.value = true;
  try {
    const view = await api<View>("/admin/draft/enhance", {
      method: "PUT",
      body: JSON.stringify(payload(form.value)),
      guard: { revisions: rev, id: 1, reload: load, latest: async () => (await api<View>("/admin/draft/enhance")).rules, title: "装备强化规则" },
    });
    hasSaved.value = view.rules !== null;
    if (view.rules) form.value = normalize(view.rules);
    original.value = JSON.stringify(form.value);
    const created = view.createdMaterials ?? [];
    if (created.length > 0) await loadItems();
    ElMessage.success(created.length > 0 ? `已保存到草稿，并创建了 ${created.length} 个物品（突破材料 / 炼器精粹）；发布后玩家生效` : "已保存到草稿，发布后玩家生效");
    void refreshDraftStatus();
  } catch (cause) {
    if (isConflictAbort(cause)) {
      if (cause.action === "reload") ElMessage.info(cause.message);
    } else ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

useRefetchOnActivate(load);
onMounted(load);
</script>

<style scoped>
.savebar {
  position: sticky;
  top: 0;
  z-index: 5;
  display: flex;
  align-items: center;
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-4);
  padding: var(--xx-space-2) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-surface);
  box-shadow: var(--xx-shadow-card);
}
.savebar.dirty {
  border-color: var(--xx-warning);
  background: var(--xx-warning-bg);
}
.state {
  font-size: var(--xx-fs-sm);
}
.state.ok {
  color: var(--xx-text-secondary);
}
.spacer {
  flex: 1;
}
.grid {
  display: grid;
  grid-template-columns: minmax(280px, 3fr) minmax(0, 7fr);
  gap: var(--xx-space-4);
}
.gap {
  margin-top: var(--xx-space-4);
}
h2 {
  margin: 0 0 var(--xx-space-3);
  font-size: var(--xx-fs-lg);
}
.head {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.hint {
  margin: 4px 0 0;
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
  line-height: 1.5;
}
.form :deep(.el-input-number) {
  width: 200px;
}
.qtable :deep(.el-input-number) {
  width: 100%;
}
.problems {
  margin: 4px 0 0;
  padding-left: 18px;
}
.summary {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: var(--xx-space-3);
  margin-bottom: var(--xx-space-3);
}
.summary div {
  display: grid;
  gap: 2px;
  padding: var(--xx-space-2) var(--xx-space-3);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
  background: var(--xx-bg-subtle);
}
.summary span {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.summary strong {
  font-size: var(--xx-fs-md, 16px);
}
.summary .wide {
  grid-column: span 2;
}
.tab-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.count {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.material-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
}
.material-select {
  width: 220px;
}
.times {
  color: var(--xx-text-secondary);
}
.node-actions {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-top: var(--xx-space-3);
}
.node-actions .mini {
  width: 110px;
}
.sep {
  width: 1px;
  height: 20px;
  background: var(--xx-border);
}
.node-tag {
  color: var(--xx-warning);
  font-weight: 600;
}
.muted {
  color: var(--xx-text-secondary);
}
.curve :deep(.node-row) {
  --el-table-tr-bg-color: var(--xx-warning-bg);
}
.moved-banner {
  margin-bottom: 12px;
}
.essence-grid {
  display: grid;
  grid-template-columns: minmax(260px, 3fr) minmax(0, 7fr);
  gap: var(--xx-space-4);
}
.slot-mults {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px 16px;
  margin-top: var(--xx-space-3);
}
.slot-mult :deep(.el-input-number) {
  width: 110px;
  margin-left: 4px;
}
.migrate {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: var(--xx-space-4);
  margin-top: var(--xx-space-4);
  padding-top: var(--xx-space-3);
  border-top: 1px dashed var(--xx-border);
}
.migrate h3 {
  margin: 0 0 4px;
  font-size: var(--xx-fs-md, 16px);
}
.migrate-status {
  display: grid;
  grid-template-columns: repeat(4, auto);
  align-content: start;
  gap: var(--xx-space-2) var(--xx-space-4);
}
.migrate-status div {
  display: grid;
}
.migrate-status span {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.migrate-status .el-button {
  grid-column: span 4;
}
</style>
