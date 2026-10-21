<template>
  <div>
    <PageHeader title="装备强化" desc="分解装备得到强化经验（经验池没有上限），经验用来给任意装备升强化等级，只升不失败、不掉级。每个品质有自己的等级上限、经验曲线、属性加成和突破节点；已穿戴的装备不能分解。下面所有数字都是起始值，可以随时调整。">
      <template #actions><el-button :icon="Refresh" :loading="loading" @click="load">刷新</el-button></template>
    </PageHeader>
    <el-alert type="info" :closable="false" show-icon class="moved-banner">
      <template #title>强化上限、经验倍数、分解经验和自动分解范围也能在「配置概览 → 强化与分解」里改（同一份数据）；突破节点和材料只在这一页。<el-button link type="primary" @click="$router.push('/config/overview#enhance')">去配置概览 ›</el-button></template>
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
          <div><span>满级总投入</span><strong>{{ summary.total }} 经验</strong></div>
          <div><span>满级属性</span><strong>×{{ summary.statMult }}（+{{ summary.statPercent }}%）</strong></div>
          <div><span>满级分解可得</span><strong>{{ summary.decompose }} 经验</strong></div>
          <div><span>约等于分解白装</span><strong>{{ summary.whiteCount }} 件</strong></div>
          <div class="wide"><span>升满共需突破材料</span><strong>{{ summary.materials }}</strong></div>
        </div>
        <el-table :data="curve" size="small" max-height="420" class="curve" :row-class-name="curveRowClass">
          <el-table-column prop="level" label="强化到" width="90"><template #default="{ row }">+{{ row.level }}</template></el-table-column>
          <el-table-column prop="cost" label="这一级所需经验" width="140" />
          <el-table-column prop="total" label="累计投入" width="120" />
          <el-table-column label="属性倍数" width="100"><template #default="{ row }">×{{ row.mult }}</template></el-table-column>
          <el-table-column prop="decompose" label="此时分解可得" width="130" />
          <el-table-column label="继续升级前要突破">
            <template #default="{ row }"><span v-if="row.node" class="node-tag">突破节点 · {{ row.node }}</span><span v-else class="muted">—</span></template>
          </el-table-column>
        </el-table>
        <p class="hint">分解可得 = 品质基础经验 + 已投入经验 × 返还比例。强化永远不会失败，也不会掉级；突破材料不会在分解时返还。</p>
      </section>
    </DataState>
  </div>
</template>

<script setup lang="ts">
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
type Rules = { expBase: number | null; expGrowth: number | null; statGrowthBp: number | null; refundBp: number | null; qualities: Record<QualityKey, QualityRule> };
type StartingMaterial = { slug: string; displayName: string };
type View = { rules: Partial<Rules> | null; starting: Rules; startingMaterials: StartingMaterial[]; createdMaterials?: string[] };
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

function emptyQuality(): QualityRule {
  return { cap: null, costMult: null, decomposeExp: null, expGrowth: null, statGrowthBp: null, breakthroughs: [] };
}

function emptyRules(): Rules {
  const qualities = {} as Rules["qualities"];
  for (const quality of QUALITIES) qualities[quality.key] = emptyQuality();
  return { expBase: null, expGrowth: null, statGrowthBp: null, refundBp: null, qualities };
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
  return { expBase: rules.expBase, expGrowth: rules.expGrowth, statGrowthBp: rules.statGrowthBp, refundBp: rules.refundBp, qualities };
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

function invested(level: number, quality: QualityKey): number {
  let total = 0;
  for (let step = 0; step < level; step += 1) total += cost(step, quality);
  return total;
}

function decomposeOf(level: number, quality: QualityKey): number {
  const base = form.value.qualities[quality].decomposeExp ?? 0;
  return base + Math.floor((invested(level, quality) * (form.value.refundBp ?? 0)) / 10000);
}

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
    return { level, cost: cost(index, quality), total: invested(level, quality), mult: multOf(level, quality), decompose: decomposeOf(level, quality), node: node ? nodeText(node) : "" };
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
  const white = form.value.qualities.white.decomposeExp ?? 1;
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

async function load(): Promise<void> {
  loading.value = true;
  error.value = "";
  try {
    const [view] = await Promise.all([api<View>("/admin/draft/enhance"), loadItems()]);
    starting.value = view.starting;
    startingMaterials.value = view.startingMaterials ?? [];
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
    const view = await api<View>("/admin/draft/enhance", { method: "PUT", body: JSON.stringify(payload(form.value)) });
    hasSaved.value = view.rules !== null;
    if (view.rules) form.value = normalize(view.rules);
    original.value = JSON.stringify(form.value);
    const created = view.createdMaterials ?? [];
    if (created.length > 0) await loadItems();
    ElMessage.success(created.length > 0 ? `已保存到草稿，并创建了 ${created.length} 个突破材料物品；发布后玩家生效` : "已保存到草稿，发布后玩家生效");
    void refreshDraftStatus();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
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
</style>
