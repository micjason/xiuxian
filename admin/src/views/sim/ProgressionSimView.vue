<template>
  <div>
    <PageHeader
      title="进度模拟"
      desc="用「最勤奋玩家」假设，把当前生效配置快进推一遍，几秒找出卡死点。读保存即生效后的配置；本页不导出。"
    />

    <el-alert type="info" :closable="false" show-icon class="banner" title="最勤奋玩家假设">
      <p>日节律固定：在线 16h + 挂机 8h；能打的 Boss 必打，装备强化到当前上限，洞府最优分配，技能自动装配。对下一 Boss 连续 10 游戏天打不过则标红停跑。</p>
    </el-alert>

    <section class="xx-card controls">
      <div class="controls-row">
        <label class="field-label">目标境界</label>
        <el-select
          v-model="targetRealmId"
          filterable
          placeholder="选择目标境界"
          class="realm-select"
          :loading="realmsLoading"
          :disabled="running"
        >
          <el-option
            v-for="realm in realms"
            :key="realm.id"
            :label="realm.label"
            :value="realm.id"
          />
        </el-select>
        <el-button type="primary" :loading="running" :disabled="!targetRealmId || realmsLoading" @click="run">
          跑一遍
        </el-button>
        <span v-if="result" class="meta">
          耗时 {{ result.meta.elapsedMs }} ms
          <template v-if="result.meta.truncated"> · 已截断</template>
          <template v-if="result.source === 'mock'"> · <el-tag size="small" type="warning" effect="plain">假数据（接口未就绪）</el-tag></template>
        </span>
      </div>
      <p v-if="realmsError" class="warn">{{ realmsError }}</p>
      <p v-if="runError" class="warn">{{ runError }}</p>
    </section>

    <template v-if="result">
      <SectionCard title="时间轴总览" desc="按天聚合；卡死行整行标红" flush>
        <el-table :data="result.overview" size="small" :row-class-name="overviewRowClass">
          <el-table-column prop="day" label="游戏天" width="88" align="right" />
          <el-table-column prop="realmName" label="境界" min-width="120" />
          <el-table-column prop="stageLabel" label="关卡 / Boss" min-width="180" show-overflow-tooltip />
          <el-table-column label="战力" width="110" align="right">
            <template #default="{ row }">{{ compactNumber(row.power) }}</template>
          </el-table-column>
          <el-table-column prop="gearTier" label="装备档" min-width="120" />
          <el-table-column prop="skillTier" label="技能档" min-width="120" />
          <el-table-column label="状态" width="96">
            <template #default="{ row }">
              <el-tag v-if="row.status === 'stuck'" type="danger" effect="light" size="small">卡死</el-tag>
              <el-tag v-else type="success" effect="light" size="small">正常</el-tag>
            </template>
          </el-table-column>
        </el-table>
      </SectionCard>

      <SectionCard v-if="result.stuck" title="卡死明细" desc="红灯维度与改数建议（不自动改配置）">
        <div class="stuck-grid">
          <div class="stuck-item">
            <span class="cap">卡在</span>
            <strong>{{ result.stuck.bossName }}</strong>
            <span class="sub">第 {{ result.stuck.day }} 游戏天 · {{ result.stuck.bossId }}</span>
          </div>
          <div class="stuck-item">
            <span class="cap">战力差距</span>
            <strong class="danger">差 {{ compactNumber(result.stuck.powerGap) }}</strong>
            <span class="sub">玩家 {{ compactNumber(result.stuck.playerPower) }} / 需要 {{ compactNumber(result.stuck.requiredPower) }}</span>
          </div>
          <div class="stuck-item">
            <span class="cap">红灯维度</span>
            <div class="lights">
              <el-tag
                v-for="light in result.stuck.redLights"
                :key="light"
                type="danger"
                effect="light"
                size="small"
              >
                {{ redLightLabel(light) }}
              </el-tag>
            </div>
          </div>
          <div class="stuck-item hint">
            <span class="cap">建议</span>
            <p>{{ result.stuck.hint }}</p>
          </div>
        </div>
      </SectionCard>

      <SectionCard title="流水账" desc="按游戏时间顺序；默认折叠，卡死日附近自动展开">
        <el-collapse v-if="timelineGroups.length > 0" v-model="openDays">
          <el-collapse-item v-for="group in timelineGroups" :key="group.day" :name="String(group.day)">
            <template #title>
              <span class="day-title" :class="{ stuck: isStuckDay(group.day) }">
                第 {{ group.day }} 天
                <el-tag v-if="isStuckDay(group.day)" type="danger" effect="light" size="small">卡死附近</el-tag>
                <span class="day-count">{{ group.events.length }} 条</span>
              </span>
            </template>
            <ul class="timeline">
              <li v-for="(event, index) in group.events" :key="`${group.day}-${index}`">
                <span class="when">{{ event.hour }}h</span>
                <el-tag size="small" effect="plain" class="kind">{{ timelineKindLabel(event.kind) }}</el-tag>
                <span class="text">{{ event.text }}</span>
              </li>
            </ul>
          </el-collapse-item>
        </el-collapse>
        <el-empty v-else description="没有流水账" />
      </SectionCard>
    </template>

    <el-empty v-else-if="!running && !runError" description="选择目标境界后点「跑一遍」" />
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref, watch } from "vue";
import PageHeader from "../../components/PageHeader.vue";
import SectionCard from "../../components/SectionCard.vue";
import { api } from "../../api";
import { compactNumber } from "../../composables/format";
import {
  redLightLabel,
  runProgressionSim,
  timelineKindLabel,
  type ProgressionSimRun,
  type ProgressionSimTimelineEvent,
} from "../../composables/progressionSim";

type RealmOption = {
  id: string;
  label: string;
  majorName: string;
  displayName: string;
  layer: number;
};

type RealmApiRow = {
  code: number;
  slug: string;
  displayName: string;
  majorName: string;
  layer: 1 | 2 | 3;
};

const realms = ref<RealmOption[]>([]);
const realmsLoading = ref(false);
const realmsError = ref("");
const targetRealmId = ref("");
const running = ref(false);
const runError = ref("");
const result = ref<ProgressionSimRun | null>(null);
const openDays = ref<string[]>([]);

const timelineGroups = computed(() => {
  if (!result.value) return [];
  const map = new Map<number, ProgressionSimTimelineEvent[]>();
  for (const event of result.value.timeline) {
    const list = map.get(event.day) ?? [];
    list.push(event);
    map.set(event.day, list);
  }
  return [...map.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([day, events]) => ({ day, events: events.slice().sort((a, b) => a.hour - b.hour) }));
});

function isStuckDay(day: number): boolean {
  const stuck = result.value?.stuck;
  if (!stuck) return false;
  return Math.abs(day - stuck.day) <= 1;
}

function overviewRowClass({ row }: { row: { status: string } }): string {
  return row.status === "stuck" ? "row-stuck" : "";
}

function pickDefaultRealm(options: RealmOption[]): string {
  const dacheng = options.filter((row) => row.majorName.includes("大乘") || row.displayName.includes("大乘"));
  if (dacheng.length > 0) {
    return dacheng[dacheng.length - 1]!.id;
  }
  return options[options.length - 1]?.id ?? "";
}

async function loadRealms(): Promise<void> {
  realmsLoading.value = true;
  realmsError.value = "";
  try {
    // Same endpoint RealmsView uses (save-as-live still served under /admin/draft/*).
    const rows = await api<RealmApiRow[]>("/admin/draft/realms");
    realms.value = rows.map((row) => ({
      id: row.slug || String(row.code),
      label: row.displayName,
      majorName: row.majorName,
      displayName: row.displayName,
      layer: row.layer,
    }));
    if (!targetRealmId.value || !realms.value.some((row) => row.id === targetRealmId.value)) {
      targetRealmId.value = pickDefaultRealm(realms.value);
    }
  } catch (error) {
    realmsError.value = error instanceof Error ? error.message : "境界列表加载失败";
  } finally {
    realmsLoading.value = false;
  }
}

function expandNearStuck(run: ProgressionSimRun): void {
  if (!run.stuck) {
    openDays.value = [];
    return;
  }
  const near = new Set<string>();
  for (const event of run.timeline) {
    if (Math.abs(event.day - run.stuck.day) <= 1) {
      near.add(String(event.day));
    }
  }
  near.add(String(run.stuck.day));
  openDays.value = [...near];
}

async function run(): Promise<void> {
  if (!targetRealmId.value || running.value) return;
  running.value = true;
  runError.value = "";
  try {
    const runResult = await runProgressionSim(targetRealmId.value);
    result.value = runResult;
    expandNearStuck(runResult);
  } catch (error) {
    result.value = null;
    runError.value = error instanceof Error ? error.message : "模拟失败";
  } finally {
    running.value = false;
  }
}

watch(
  () => result.value?.stuck?.day,
  () => {
    if (result.value) expandNearStuck(result.value);
  },
);

onMounted(() => {
  void loadRealms();
});
</script>

<style scoped>
.banner {
  margin-bottom: var(--xx-space-4);
}
.controls {
  padding: var(--xx-space-4);
  margin-bottom: var(--xx-space-4);
}
.controls-row {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--xx-space-3);
}
.field-label {
  color: var(--xx-text-secondary);
  font-size: 13px;
}
.realm-select {
  width: 240px;
}
.meta {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: var(--xx-text-secondary);
  font-size: 13px;
}
.warn {
  margin: var(--xx-space-2) 0 0;
  color: var(--el-color-danger);
  font-size: 13px;
}
.stuck-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: var(--xx-space-4);
}
.stuck-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.stuck-item.hint {
  grid-column: 1 / -1;
}
.stuck-item .cap {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.stuck-item strong {
  font-size: 16px;
}
.stuck-item .danger {
  color: var(--el-color-danger);
}
.stuck-item .sub {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.stuck-item p {
  margin: 0;
  line-height: 1.5;
}
.lights {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.day-title {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.day-title.stuck {
  color: var(--el-color-danger);
}
.day-count {
  color: var(--xx-text-secondary);
  font-size: 12px;
}
.timeline {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.timeline li {
  display: grid;
  grid-template-columns: 48px auto 1fr;
  gap: 10px;
  align-items: start;
}
.timeline .when {
  color: var(--xx-text-secondary);
  font-variant-numeric: tabular-nums;
  font-size: 13px;
  text-align: right;
}
.timeline .kind {
  justify-self: start;
}
.timeline .text {
  line-height: 1.45;
}
:deep(.row-stuck) {
  --el-table-tr-bg-color: var(--el-color-danger-light-9);
}
@media (max-width: 900px) {
  .stuck-grid {
    grid-template-columns: 1fr;
  }
  .realm-select {
    width: 100%;
  }
}
</style>
