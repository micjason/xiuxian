<template>
  <div class="formula-tab">
    <div class="savebar" :class="{ dirty }">
      <span v-if="dirty" class="state">有未保存的改动（{{ dirtyCount }} 项）。下面的图和数字是按你正在填的值实时算的。</span>
      <span v-else class="state ok">已和草稿一致。下面的图和数字是按当前值算的。</span>
      <span class="spacer" />
      <el-button :disabled="!dirty" @click="revert">还原</el-button>
      <el-button type="primary" :disabled="!dirty" :loading="saving" @click="save">保存到草稿</el-button>
    </div>
    <p v-if="previewError" class="hint">{{ previewError }}</p>
    <div class="layout">
      <div class="main">
        <el-collapse class="explain">
          <el-collapse-item title="公式说明：游戏里用了哪些公式，各有什么好处和缺点" name="f">
            
      
      <ol class="formulas">
        <li>
          <p class="formula">每下伤害 = 攻击 × 攻击 ÷（攻击 + k × 对方防御）</p>
          <p>攻击为 0 时伤害是 0。对方防御小于 0 时按 0 算。k 是攻击和防御的换算，k 越大，同样的防御挡掉越多。</p>
        </li>
        <li>
          <p class="formula">出手间隔 = 境界基础出手间隔 × 速度基数 ÷（速度基数 + 速度），不会短于最短出手间隔</p>
          <p>第一版每个境界的基础出手间隔都填 1.5 秒，所以下面的图用 1.5 来画。速度越高，间隔越短，短到最短出手间隔就不再缩短。</p>
        </li>
        <li>
          <p class="formula">面板攻击 = 境界基础攻击 ×（1 + 功法攻击百分比之和）+ 装备攻击之和</p>
          <p>防御、气血用同一条式子。速度只有境界和装备的固定值，功法不加百分比。百分比彼此相加，只乘境界基础，不乘装备。同一件装备的战力是固定数字，谁穿都加上一样多。</p>
        </li>
        <li>
          <p class="formula">功法实际百分比 = 基础百分比 × 层数系数</p>
          <p>层数按拿到的本数算：1 本是 1，2 本是 1.15，4 本是 1.35，7 本是 1.6。最多同时运转 3 门。</p>
        </li>
        <li>
          <p class="formula">战力 = 攻击 × 攻击权重 + 防御 × 防御权重 + 气血 × 气血权重 + 速度 × 速度权重，再四舍五入</p>
          <p>四个权重全游戏共用。标准角色是攻击 100、防御 100、气血 333、速度 20，四个权重按这个人的真实对打贡献反推，目标战力是 1000。</p>
        </li>
      </ol>
      <div class="split">
        <div>
          <h4>好处</h4>
          <ul>
            <li>攻防一起翻倍，伤害也正好翻倍，不会差一点点就几乎打不动。</li>
            <li>一件装备的战力是它自己的数字。空身穿上和穿满再穿上，总战力都加上同一截。</li>
            <li>同一个境界的人学同一门功法，加上的攻击、防御、气血一样。</li>
            <li>战力是四项相加。属性比例接近标准角色时，战力高过对手 5% 以上会赢，低过 5% 以上会输。</li>
          </ul>
        </div>
        <div>
          <h4>缺点</h4>
          <ul>
            <li>战力把一场打斗压成一次加法。攻击在伤害里是平方，同样的战力加在攻击上更能缩短击杀；加在防御或气血上，击杀时间不变，只是更耐打。</li>
            <li>速度越高，出手缩短得越少，还有最短间隔，权重却是一个固定数。</li>
            <li>属性比例离标准角色太远时，战力高不代表打得过。下面三个例子就是这种情况。</li>
            <li>改了 k 或速度基数之后，原来的四个权重就不再代表真实实力，装备上的战力也会一起偏。</li>
            <li>功法和装备不会互相放大。同一对面板，每次打斗用时都一样。</li>
          </ul>
        </div>
      </div>
    
          </el-collapse-item>
        </el-collapse>
      <section id="sec-伤害" class="block">
        <h2>伤害</h2>

      
      <p class="formula">每下伤害 = 攻击 × 攻击 ÷（攻击 + k × 对方防御）</p>
      <SchemaForm v-model="form" :schema="rulesSchema" :card="false" :only-groups="['damage']" show-all-errors @active="(f) => (active = f)" />
      <p v-if="preview">
        攻击 100 打防御 100，每下伤害 <strong>{{ round(preview.evenDamage) }}</strong>。两个属性一样的人互打，
        <strong>{{ preview.fightSeconds }}</strong> 秒结束。k 调到 {{ preview.raisedK.k }} 时，每下伤害变成
        {{ preview.raisedK.damage }}，用时变成 {{ preview.raisedK.durationSeconds }} 秒。k 越大，防御挡掉的越多，打斗越久。
      </p>
      <div v-if="damageChart" class="chart-wrap">
        <p class="chart-title">攻击 100 时，对方防御越高，每下伤害越低</p>
        <svg :viewBox="`0 0 ${damageChart.width} ${damageChart.height}`" class="chart">
          <line :x1="damageChart.pad" :y1="damageChart.height - damageChart.pad" :x2="damageChart.width - damageChart.pad" :y2="damageChart.height - damageChart.pad" class="axis" />
          <line :x1="damageChart.pad" :y1="damageChart.pad" :x2="damageChart.pad" :y2="damageChart.height - damageChart.pad" class="axis" />
          <polyline :points="damageChart.raised" class="line dashed" />
          <polyline :points="damageChart.current" class="line" />
          <text :x="damageChart.width / 2" :y="damageChart.height - 8" text-anchor="middle" class="axis-label">对方防御</text>
          <text :x="14" :y="16" class="axis-label">伤害</text>
        </svg>
        <p class="legend"><span class="swatch current"></span>现在的 k <span class="swatch raised"></span>k 调到 1.5 倍</p>
      </div>
      <div v-if="durationChart" class="chart-wrap">
        <p class="chart-title">同样两个人互打，k 越大用时越长</p>
        <svg :viewBox="`0 0 ${durationChart.width} ${durationChart.height}`" class="chart">
          <line :x1="durationChart.pad" :y1="durationChart.height - durationChart.pad" :x2="durationChart.width - durationChart.pad" :y2="durationChart.height - durationChart.pad" class="axis" />
          <line :x1="durationChart.pad" :y1="durationChart.pad" :x2="durationChart.pad" :y2="durationChart.height - durationChart.pad" class="axis" />
          <polyline :points="durationChart.line" class="line" />
          <circle :cx="durationChart.markerX" :cy="durationChart.markerY" r="5" class="marker" />
          <text :x="durationChart.width / 2" :y="durationChart.height - 8" text-anchor="middle" class="axis-label">防御常数 k</text>
          <text :x="14" :y="16" class="axis-label">用时（秒）</text>
        </svg>
        <p class="legend">圆点是你现在填的 k</p>
      </div>
    
      </section>
      <section id="sec-出手" class="block">
        <h2>出手</h2>

      
      <p class="formula">出手间隔 = 1.5 × 速度基数 ÷（速度基数 + 速度），不会短于最短出手间隔</p>
      <p>这里的 1.5 是境界基础出手间隔。图用这个数举例。</p>
      <SchemaForm v-model="form" :schema="rulesSchema" :card="false" :only-groups="['speed']" show-all-errors @active="(f) => (active = f)" />
      <p v-if="preview">
        速度 20 时，{{ preview.intervalAt20 }} 秒出手一次。速度基数调到 {{ preview.raisedSpeedBase.speedBase }} 时，同样的速度变成
        {{ preview.raisedSpeedBase.intervalAt20 }} 秒一次。基数越大，速度越不容易把出手缩短。线不会低于最短出手
        {{ preview.minInterval }} 秒。
      </p>
      <div v-if="intervalChart" class="chart-wrap">
        <p class="chart-title">速度越高，出手越快，快到最短间隔就不再缩短</p>
        <svg :viewBox="`0 0 ${intervalChart.width} ${intervalChart.height}`" class="chart">
          <line :x1="intervalChart.pad" :y1="intervalChart.height - intervalChart.pad" :x2="intervalChart.width - intervalChart.pad" :y2="intervalChart.height - intervalChart.pad" class="axis" />
          <line :x1="intervalChart.pad" :y1="intervalChart.pad" :x2="intervalChart.pad" :y2="intervalChart.height - intervalChart.pad" class="axis" />
          <polyline :points="intervalChart.raised" class="line dashed" />
          <polyline :points="intervalChart.current" class="line" />
          <text :x="intervalChart.width / 2" :y="intervalChart.height - 8" text-anchor="middle" class="axis-label">速度</text>
          <text :x="14" :y="16" class="axis-label">间隔（秒）</text>
        </svg>
        <p class="legend"><span class="swatch current"></span>现在的速度基数 <span class="swatch raised"></span>速度基数翻倍</p>
      </div>
    
      </section>
      <section id="sec-战力权重" class="block">
        <h2>战力权重</h2>

      
      <p class="formula">战力 = 攻击 × 攻击权重 + 防御 × 防御权重 + 气血 × 气血权重 + 速度 × 速度权重，再四舍五入</p>
      <SchemaForm v-model="form" :schema="rulesSchema" :card="false" :only-groups="['power']" show-all-errors @active="(f) => (active = f)" />
      <p v-if="preview">
        标准角色攻击 100、防御 100、气血 333、速度 20，战力是 <strong>{{ preview.standardPower }}</strong>。
        <template v-for="share in preview.shares" :key="share.key">{{ share.label }}占 {{ percent(share.ratio) }}。 </template>
        权重只决定战力这个数字怎么加总，不改变实际打出的伤害。
      </p>
      <div v-if="preview" class="stack" aria-hidden="true">
        <div
          v-for="share in preview.shares"
          :key="share.key"
          class="stack-part"
          :style="{ width: percent(share.ratio), background: shareColor[share.key] }"
        ></div>
      </div>
      <p v-if="preview" class="legend">
        <span v-for="share in preview.shares" :key="share.key"><i class="swatch" :style="{ background: shareColor[share.key] }"></i>{{ share.label }} {{ round(share.amount) }}</span>
      </p>
      <h4>三个例子</h4>
      <p>
        下面三个人是写好的例子，用来看权重一改，战力数字怎么变。他们的属性不是按同样的点数配的，所以柱子本来就不会一样长。
        柱子后面的数字是战力，不是每下伤害，也不是打斗用时。
      </p>
      <article v-for="puppet in preview?.puppets ?? []" :key="puppet.name" class="puppet">
        <h4>{{ puppet.name }}</h4>
        <p>{{ puppetNote[puppet.name] }}</p>
        <p>
          属性：攻击 {{ puppet.attack }}，防御 {{ puppet.defense }}，气血 {{ puppet.hp }}，速度 {{ puppet.speed }}。
          按现在的速度基数，{{ puppet.interval }} 秒出手一次。
        </p>
        <p>现在的战力是 <strong>{{ puppet.power }}</strong>。它是下面四行相加，再四舍五入：</p>
        <ul class="math">
          <li v-for="line in puppet.lines" :key="line.key">{{ line.label }} {{ line.stat }} × {{ line.weight }} = {{ line.amount }}</li>
        </ul>
        <p v-if="doubledOf(puppet.name)">
          右边那一列仍是这个人。速度权重调到 {{ preview?.speedWeightDoubled.weight }} 之后，战力变成
          <strong>{{ doubledOf(puppet.name)?.power }}</strong>。变的只有速度那一行：速度
          {{ speedPart(puppet.name)?.stat }} × {{ speedPart(puppet.name)?.weight }} = {{ speedPart(puppet.name)?.amount }}。
        </p>
      </article>
      <div v-if="preview" class="compare">
        <div>
          <p class="chart-title">现在的权重算出来的战力</p>
          <div v-for="puppet in preview.puppets" :key="puppet.name" class="bar-row">
            <span>{{ puppet.name }}</span>
            <div class="track"><div class="fill" :style="{ width: barWidth(puppet.power) }"></div></div>
            <strong>{{ puppet.power }}</strong>
          </div>
        </div>
        <div>
          <p class="chart-title">只把速度权重调到 {{ preview.speedWeightDoubled.weight }}</p>
          <div v-for="puppet in preview.speedWeightDoubled.puppets" :key="puppet.name" class="bar-row">
            <span>{{ puppet.name }}</span>
            <div class="track"><div class="fill raised-fill" :style="{ width: barWidth(puppet.power) }"></div></div>
            <strong>{{ puppet.power }}</strong>
          </div>
        </div>
      </div>
      <p v-if="preview">
        左边更高的是「{{ leader(preview.puppets) }}」。速度权重调到 {{ preview.speedWeightDoubled.weight }} 之后，更高的是「{{ leader(preview.speedWeightDoubled.puppets) }}」。
        偏速度的速度是 80，偏攻击的速度是 8，所以速度权重调大时，偏速度涨得更多。
      </p>
    
      </section>
        <section id="sec-battle" class="block">
          <h2>挑战与推荐战力</h2>
          <SchemaForm v-model="form" :schema="rulesSchema" :card="false" :only-groups="['battle']" show-all-errors @active="(f) => (active = f)" />
        </section>
        <section id="sec-world" class="block">
          <h2>行囊与离线</h2>
          <SchemaForm v-model="form" :schema="rulesSchema" :card="false" :only-groups="['world']" show-all-errors @active="(f) => (active = f)" />
        </section>
        <section class="block">
          <h2>其他全局参数</h2>
          <p class="note">初始境界、新手物品、功法栏位在「配置概览」里改；部位与品质表由服务端统一提供（配置概览 → 部位与品质，只读）。</p>
        </section>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { useRefetchOnActivate } from "../../../composables/dataVersion";
import { computed, onMounted, ref, watch } from "vue";
import { api } from "../../../api";
import SchemaForm from "../../../components/SchemaForm.vue";
import { useDirtyGuard } from "../../../composables/dirty";
import { refreshDraftStatus } from "../../../composables/draftStatus";
import { rulesSchema } from "../../../schema/resources";
import type { FieldDef, FormValues } from "../../../schema/types";
import { isBlank, validateSchema } from "../../../schema/validate";

const ruleKeys = rulesSchema.fields.map((field) => field.key);
// 公式预览接口只认这 7 个参数，其余参数不影响图。
const previewKeys = ["defenseConstant", "minInterval", "speedBase", "attackWeight", "defenseWeight", "hpWeight", "speedWeight"] as const;

type ShareKey = "attack" | "defense" | "hp" | "speed";

type PuppetLine = { key: ShareKey; label: string; stat: number; weight: number; amount: number };

type PuppetPreview = {
  name: string;
  attack: number;
  defense: number;
  hp: number;
  speed: number;
  interval: number;
  power: number;
  lines: PuppetLine[];
};

const puppetNote: Record<string, string> = {
  均衡: "标准配法。四个权重就是按这个人反推的，目标战力是 1000。他的柱子长度可以当成基准。",
  偏攻击: "攻击比均衡高 50，防御、气血、速度都更低。柱子更长，是因为这些属性按当前权重加起来更高，不是因为三个人花了同样的点数。",
  偏速度: "速度是 80，攻击只有 80。出手更快，但每一刀更轻。按当前权重，战力比均衡略低；速度权重加大之后，他的柱子会涨得最多。",
};

type Preview = {
  evenDamage: number;
  fightSeconds: number;
  raisedK: { k: number; damage: number; durationSeconds: number };
  damageCurve: { defense: number; damage: number; raisedDamage: number }[];
  kCurve: { k: number; damage: number; durationSeconds: number }[];
  defenseConstant: number;
  intervalAt20: number;
  minInterval: number;
  raisedSpeedBase: { speedBase: number; intervalAt20: number };
  intervalCurve: { speed: number; interval: number; raisedInterval: number }[];
  standardPower: number;
  shares: { key: ShareKey; label: string; amount: number; ratio: number }[];
  puppets: PuppetPreview[];
  speedWeightDoubled: { weight: number; puppets: PuppetPreview[] };
};

const shareColor: Record<ShareKey, string> = {
  attack: "var(--xx-chart-2)",
  defense: "var(--xx-chart-3)",
  hp: "var(--xx-chart-1)",
  speed: "var(--xx-gold-500)",
};


const form = ref<FormValues>({});
const original = ref("");
const active = ref<FieldDef | null>(null);
const globals = ref<Record<string, unknown>>({});
const preview = ref<Preview | null>(null);
const previewError = ref("");
const saving = ref(false);
let previewTimer = 0;

const dirty = computed(() => JSON.stringify(form.value) !== original.value);
const dirtyCount = computed(() => {
  const before = original.value ? (JSON.parse(original.value) as FormValues) : {};
  return ruleKeys.filter((key) => form.value[key] !== before[key]).length;
});
useDirtyGuard(dirty);

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

function percent(ratio: number): string {
  return `${Math.round(ratio * 100)}%`;
}

function leader(rows: { name: string; power: number }[]): string {
  return rows.reduce((best, row) => (row.power > best.power ? row : best)).name;
}

function doubledOf(name: string): PuppetPreview | undefined {
  return preview.value?.speedWeightDoubled.puppets.find((puppet) => puppet.name === name);
}

function speedPart(name: string): PuppetLine | undefined {
  return doubledOf(name)?.lines.find((line) => line.key === "speed");
}




function revert(): void {
  form.value = JSON.parse(original.value) as FormValues;
}

function previewPayload(): Record<string, number> | null {
  const body: Record<string, number> = {};
  for (const key of previewKeys) {
    const value = form.value[key];
    if (isBlank(value)) return null;
    body[key] = Number(value);
  }
  return body;
}

type Frame = { width: number; height: number; pad: number; sx: (value: number) => number; sy: (value: number) => number };

function frameOf(points: { x: number; y: number }[]): Frame {
  const width = 640;
  const height = 220;
  const pad = 36;
  const xs = points.map((point) => point.x);
  const ys = points.map((point) => point.y);
  const xMin = Math.min(...xs);
  const xMax = Math.max(...xs);
  const yMax = Math.max(...ys, 1) * 1.08;
  return {
    width,
    height,
    pad,
    sx: (value) => pad + ((value - xMin) / (xMax - xMin || 1)) * (width - pad * 2),
    sy: (value) => height - pad - (value / yMax) * (height - pad * 2),
  };
}

function lineOf(frame: Frame, points: { x: number; y: number }[]): string {
  return points.map((point) => `${frame.sx(point.x)},${frame.sy(point.y)}`).join(" ");
}

const damageChart = computed(() => {
  const data = preview.value;
  if (!data) {
    return null;
  }
  const current = data.damageCurve.map((point) => ({ x: point.defense, y: point.damage }));
  const raised = data.damageCurve.map((point) => ({ x: point.defense, y: point.raisedDamage }));
  const frame = frameOf([...current, ...raised]);
  return { ...frame, current: lineOf(frame, current), raised: lineOf(frame, raised) };
});

const durationChart = computed(() => {
  const data = preview.value;
  if (!data) {
    return null;
  }
  const points = data.kCurve.map((point) => ({ x: point.k, y: point.durationSeconds }));
  const frame = frameOf(points);
  const current = data.kCurve.reduce((best, point) => (Math.abs(point.k - data.defenseConstant) < Math.abs(best.k - data.defenseConstant) ? point : best));
  return {
    ...frame,
    line: lineOf(frame, points),
    markerX: frame.sx(current.k),
    markerY: frame.sy(current.durationSeconds),
  };
});

const intervalChart = computed(() => {
  const data = preview.value;
  if (!data) {
    return null;
  }
  const current = data.intervalCurve.map((point) => ({ x: point.speed, y: point.interval }));
  const raised = data.intervalCurve.map((point) => ({ x: point.speed, y: point.raisedInterval }));
  const frame = frameOf([...current, ...raised]);
  return { ...frame, current: lineOf(frame, current), raised: lineOf(frame, raised) };
});

const maxPower = computed(() => {
  const data = preview.value;
  if (!data) {
    return 1;
  }
  return Math.max(1, ...data.puppets.map((puppet) => puppet.power), ...data.speedWeightDoubled.puppets.map((puppet) => puppet.power));
});

function barWidth(power: number): string {
  return `${Math.max(2, (power / maxPower.value) * 100)}%`;
}


async function refreshPreview(): Promise<void> {
  const body = previewPayload();
  if (!body) {
    preview.value = null;
    previewError.value = "把上面的数填完整之后，这里会画出影响。";
    return;
  }
  try {
    preview.value = await api<Preview>("/admin/draft/formula-preview", { method: "POST", body: JSON.stringify(body) });
    previewError.value = "";
  } catch (cause) {
    preview.value = null;
    previewError.value = cause instanceof Error ? cause.message : "图加载失败";
  }
}

async function load(): Promise<void> {
  try {
    const rules = await api<Record<string, number | null>>("/admin/draft/rules");
    const values: FormValues = {};
    for (const key of ruleKeys) {
      values[key] = rules[key] ?? undefined;
    }
    form.value = values;
    original.value = JSON.stringify(values);
    await refreshPreview();
    try {
      const world = await api<{ globals: Record<string, unknown> }>("/content/current");
      globals.value = world.globals ?? {};
    } catch {
      globals.value = {};
    }
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "加载失败");
  }
}

async function save(): Promise<void> {
  const problems = validateSchema(rulesSchema, form.value);
  if (Object.keys(problems).length > 0) {
    ElMessage.warning(Object.values(problems)[0]);
    return;
  }
  const body: Record<string, number> = {};
  for (const key of ruleKeys) body[key] = Number(form.value[key]);
  saving.value = true;
  try {
    await api("/admin/draft/rules", { method: "PUT", body: JSON.stringify(body) });
    original.value = JSON.stringify(form.value);
    await refreshPreview();
    ElMessage.success("已保存到草稿");
    void refreshDraftStatus();
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "保存失败");
  } finally {
    saving.value = false;
  }
}

watch(
  form,
  () => {
    window.clearTimeout(previewTimer);
    previewTimer = window.setTimeout(() => void refreshPreview(), 200);
  },
  { deep: true },
);

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
  margin-bottom: var(--xx-space-3);
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
.layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: var(--xx-space-4);
}
.main {
  min-width: 0;
}
.block {
  margin-top: var(--xx-space-4);
  padding: var(--xx-space-4) var(--xx-space-5);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-lg);
  background: var(--xx-bg-surface);
}
.block h2 {
  margin: 0 0 var(--xx-space-2);
  font-size: var(--xx-fs-lg);
}
.explain {
  border-radius: var(--xx-radius-md);
}
.note {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.globals {
  display: grid;
  gap: var(--xx-space-1);
  margin: 0;
}
.g-row {
  display: grid;
  grid-template-columns: 260px 1fr;
  padding: 4px 0;
  border-bottom: 1px dashed var(--xx-border);
}
.g-row dt code {
  color: var(--xx-text-placeholder);
  font-size: var(--xx-fs-xs);
}
.g-row dd {
  margin: 0;
  font-family: var(--xx-font-mono);
  font-size: var(--xx-fs-sm);
}
.hint {
  color: var(--xx-warning) !important;
}
.formulas {
  margin: 0;
  padding-left: 1.2em;
}
.formulas li {
  margin: 14px 0;
}
.split {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
}
.split ul,
.math {
  margin: 8px 0 0;
  padding-left: 1.2em;
}
.puppet {
  margin: 16px 0;
  padding: 12px 14px;
  background: var(--el-fill-color-lighter);
  border-radius: 8px;
}
.puppet h4 {
  margin: 0 0 8px;
}
.formula {
  padding: 8px 12px;
  background: var(--el-fill-color-light);
  border-radius: 6px;
}
.chart {
  width: 100%;
  height: auto;
}
.chart-wrap {
  margin: 12px 0 20px;
}
.chart-title {
  margin-bottom: 4px;
  font-weight: 600;
}
.axis {
  stroke: var(--el-border-color);
  stroke-width: 1;
}
.line {
  fill: none;
  stroke: var(--xx-chart-1);
  stroke-width: 2.5;
}
.line.dashed {
  stroke: var(--xx-chart-2);
  stroke-dasharray: 6 4;
}
.marker {
  fill: var(--xx-chart-2);
}
.axis-label {
  fill: var(--el-text-color-secondary);
  font-size: 12px;
}
.legend {
  display: flex;
  gap: 16px;
  align-items: center;
  color: var(--el-text-color-secondary);
  font-size: 13px;
}
.swatch {
  display: inline-block;
  width: 18px;
  height: 4px;
  margin-right: 6px;
  vertical-align: middle;
}
.legend i.swatch {
  width: 10px;
  height: 10px;
  border-radius: 2px;
}
.swatch.current,
.legend .swatch.current {
  background: var(--xx-chart-1);
}
.swatch.raised {
  background: var(--xx-chart-2);
}
.stack {
  display: flex;
  height: 28px;
  overflow: hidden;
  border-radius: 6px;
}
.stack-part {
  height: 100%;
}
.weights {
  display: grid;
  grid-template-columns: 1fr 1fr;
  max-width: 720px;
}
.compare {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
  margin: 12px 0;
}
.bar-row {
  display: grid;
  grid-template-columns: 72px 1fr 64px;
  gap: 8px;
  align-items: center;
  margin: 8px 0;
}
.track {
  height: 14px;
  background: var(--el-fill-color);
  border-radius: 7px;
  overflow: hidden;
}
.fill {
  height: 100%;
  background: var(--xx-chart-1);
}
.raised-fill {
  background: var(--xx-chart-2);
}
@media (max-width: 800px) {
  .weights,
  .compare,
  .split {
    grid-template-columns: 1fr;
  }
}
</style>
