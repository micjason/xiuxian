<template>
  <el-dialog v-model="open" title="试打" width="680px" append-to-body>
    <p class="hint">用游戏里同一套规则计算。首领数值取自表单里现在填的数，不需要先保存。可以同时选多个人偶。</p>
    <div class="pick">
      <el-select v-model="puppetIds" multiple collapse-tags collapse-tags-tooltip placeholder="选择人偶" style="flex: 1">
        <el-option v-for="puppet in puppets" :key="puppet.id" :label="puppetLabel(puppet)" :value="puppet.id" />
      </el-select>
      <el-button type="primary" :loading="running" :disabled="puppetIds.length === 0" @click="run">开打</el-button>
    </div>
    <p v-if="puppets.length === 0" class="hint">还没有人偶。<router-link to="/config/combat?tab=sim">去新建</router-link></p>
    <article v-for="result in results" :key="result.puppetId" class="result">
      <h3 :class="result.error || !result.win ? 'lose' : 'win'">{{ result.displayName }} · {{ result.kindName }}</h3>
      <p v-if="result.error">{{ result.error }}</p>
      <template v-else-if="result.player">
        <p class="verdict">{{ verdict(result) }}</p>
        <p>
          战力 {{ result.player.power }}，攻击 {{ result.player.attack }}，防御 {{ result.player.defense }}，气血 {{ result.player.hp }}，速度
          {{ result.player.speed }}，每 {{ round(result.player.interval) }} 秒出手一次
        </p>
        <p v-if="result.playerHits == null">人偶攻击是 0，打不动首领</p>
        <p v-else>每下打掉 {{ round(result.playerHit ?? 0) }}，要打 {{ result.playerHits }} 下，约 {{ round(result.playerKillSeconds ?? 0) }} 秒打死首领</p>
        <p v-if="result.bossHits == null">首领攻击是 0，打不动这个人偶</p>
        <p v-else>首领每下打掉 {{ round(result.bossHit ?? 0) }}，要打 {{ result.bossHits }} 下，约 {{ round(result.bossKillSeconds ?? 0) }} 秒打死这个人偶</p>
        <p class="hint">超过 {{ result.timeLimitSeconds }} 秒没分出胜负算输。</p>
      </template>
    </article>
  </el-dialog>
</template>

<script setup lang="ts">
import { ElMessage } from "element-plus";
import { ref, watch } from "vue";
import { api } from "../api";

type PuppetOption = { id: string; displayName: string; kindName: string; problem: string | null };
type TrialResult = {
  puppetId: string;
  displayName: string;
  kindName: string;
  error: string | null;
  win: boolean | null;
  reason: "win" | "defeated" | "timeout" | null;
  durationSeconds: number | null;
  timeLimitSeconds: number | null;
  player: { power: number; attack: number; defense: number; hp: number; speed: number; interval: number } | null;
  playerHit: number | null;
  playerHits: number | null;
  playerKillSeconds: number | null;
  bossHit: number | null;
  bossHits: number | null;
  bossKillSeconds: number | null;
};

const props = defineProps<{ boss: { attack: number; defense: number; hp: number; interval: number } | null }>();
const open = defineModel<boolean>({ required: true });

const puppets = ref<PuppetOption[]>([]);
const puppetIds = ref<string[]>([]);
const results = ref<TrialResult[]>([]);
const running = ref(false);

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

function puppetLabel(puppet: PuppetOption): string {
  return puppet.problem ? `${puppet.displayName}（${puppet.problem}）` : `${puppet.displayName}（${puppet.kindName}）`;
}

function verdict(result: TrialResult): string {
  if (result.win) {
    return `赢，用时 ${round(result.durationSeconds ?? 0)} 秒`;
  }
  if (result.reason === "timeout") {
    return `输，${result.timeLimitSeconds} 秒没打死首领`;
  }
  return `输，第 ${round(result.durationSeconds ?? 0)} 秒被打死`;
}

watch(open, async (value) => {
  if (!value) {
    return;
  }
  results.value = [];
  try {
    puppets.value = await api<PuppetOption[]>("/admin/draft/puppets");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "人偶加载失败");
  }
});

async function run(): Promise<void> {
  if (!props.boss) {
    return;
  }
  running.value = true;
  try {
    const body = await api<{ results: TrialResult[] }>("/admin/draft/trial", {
      method: "POST",
      body: JSON.stringify({
        puppetIds: puppetIds.value,
        boss: { attack: props.boss.attack, defense: props.boss.defense, hp: props.boss.hp, interval: props.boss.interval },
      }),
    });
    results.value = body.results;
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "试打失败");
  } finally {
    running.value = false;
  }
}
</script>

<style scoped>
.hint {
  color: var(--xx-text-secondary);
  font-size: var(--xx-fs-sm);
}
.pick {
  display: flex;
  gap: var(--xx-space-3);
  margin: var(--xx-space-3) 0;
}
.result {
  margin-top: var(--xx-space-3);
  padding: var(--xx-space-3) var(--xx-space-4);
  border: 1px solid var(--xx-border);
  border-radius: var(--xx-radius-md);
}
.result h3 {
  margin: 0 0 var(--xx-space-1);
  font-size: var(--xx-fs-md);
}
.result p {
  margin: 4px 0;
}
.verdict {
  font-weight: 600;
}
.win {
  color: var(--xx-success);
}
.lose {
  color: var(--xx-danger);
}
</style>
