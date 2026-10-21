<template>
  <EditDrawer
    v-model="open"
    title="补发装备"
    subtitle="走「发放指定装备」接口 · 来源 admin_grant"
    :dirty="dirty"
    :saving="sending"
    :size="size"
    save-text="发放"
    always-savable
    @save="confirmSend"
  >
    <SectionCard title="发给谁" desc="最多 100 人；输入账号或玩家 ID 搜索，回车添加">
      <template #extra><span class="small">已选 <strong>{{ form.players.length }}</strong> 人</span></template>
      <FormRow label="玩家" required>
        <el-select
          v-model="form.players"
          multiple
          filterable
          remote
          value-key="id"
          :remote-method="search"
          :loading="searching"
          class="w656"
          placeholder="输入玩家账号或 ID，回车添加"
          :multiple-limit="100"
        >
          <el-option v-for="player in found" :key="player.id" :label="`${player.username}（${short(player.id)}）`" :value="player">
            <span>{{ player.username }}</span>
            <span class="muted small"> · {{ short(player.id) }} · {{ player.realmName }} · 行囊 {{ player.bagUsed }} / {{ player.bagCapacity }}</span>
          </el-option>
        </el-select>
        <template #note>从「玩家管理」点「补发装备」打开时，这里已经填好该玩家</template>
      </FormRow>
    </SectionCard>

    <SectionCard title="发什么" desc="公式装备和手动装备都能选；每人按下表各发一份">
      <el-table :data="form.items" size="small" class="items">
        <el-table-column label="装备" min-width="360">
          <template #default="{ row }">
            <el-select v-model="row.itemId" filterable class="w320" placeholder="搜索装备名称">
              <el-option v-for="item in gear" :key="item.id" :label="item.displayName" :value="item.id" :disabled="taken(item.id, row.itemId)">
                <span class="opt">
                  <span class="icon-box sm" :style="{ background: QUALITY_BG[item.quality] }"><img v-if="iconOf(item)" :src="iconOf(item)" alt="" /></span>
                  {{ item.displayName }}
                  <span class="q-tag" :style="{ color: qColor(item.quality), borderColor: qColor(item.quality) }">{{ qShort(item.quality) }}</span>
                  <span class="muted small">{{ item.majorName }} · {{ item.slotName }} · {{ item.origin === "manual" ? "手动" : "公式" }}</span>
                </span>
              </el-option>
            </el-select>
          </template>
        </el-table-column>
        <el-table-column label="每人数量" width="160">
          <template #default="{ row }"><NumInput v-model="row.count" :width="100" unit="件" :precision="0" :min="1" :max="20" /></template>
        </el-table-column>
        <el-table-column label="操作" width="80">
          <template #default="{ $index }"><el-button link type="danger" @click="form.items.splice($index, 1)">删除</el-button></template>
        </el-table-column>
      </el-table>
      <el-button class="add" :disabled="form.items.length >= 10" @click="form.items.push({ itemId: '', count: 1 })">＋ 添加装备</el-button>
    </SectionCard>

    <SectionCard title="原因">
      <div class="stack">
        <FormRow label="补发原因" required>
          <el-select v-model="form.reason" class="w320" placeholder="选择原因">
            <el-option v-for="reason in REASONS" :key="reason" :label="reason" :value="reason" />
          </el-select>
          <template #note>可选：{{ REASONS.join(" / ") }}</template>
        </FormRow>
        <FormRow label="备注" required>
          <el-input v-model="form.note" type="textarea" maxlength="200" :autosize="{ minRows: 2, maxRows: 4 }" class="w656" placeholder="例如：10-20 黑风岭·一首领首通，青云冠指定掉落未到账，工单 #2031" />
          <template #note>写进操作日志，玩家看不到</template>
        </FormRow>
      </div>
    </SectionCard>

    <SectionCard title="发放预览">
      <div class="preview">
        <div>{{ previewText }}</div>
        <div class="muted small">直接放进玩家行囊（行囊满也照放，可超出容量）· 来源记为 <code>admin_grant</code> · 写入操作日志（补发单号 {{ batchId }}）</div>
      </div>
    </SectionCard>

    <template #footer-left><span class="gold small">● 发放后不能撤回</span></template>
  </EditDrawer>
</template>

<script setup lang="ts">
import { ElMessage, ElMessageBox } from "element-plus";
import { computed, reactive, ref, watch } from "vue";
import { api } from "../api";
import { iconUrl, autoGearIcon, useItemIcons } from "../composables/itemIcons";
import EditDrawer from "./EditDrawer.vue";
import FormRow from "./FormRow.vue";
import NumInput from "./NumInput.vue";
import SectionCard from "./SectionCard.vue";

type Player = { id: string; username: string; realmName: string; bagUsed: number; bagCapacity: number };
type GearOption = { id: string; displayName: string; quality: string; slot: string; slotName: string; majorName: string; origin: "formula" | "manual"; iconKey: string };
type QualityRow = { key: string; short: string; color: string };

const props = withDefaults(defineProps<{ presetPlayers?: Player[]; size?: string | number }>(), { presetPlayers: () => [], size: 1080 });
const open = defineModel<boolean>({ required: true });
const emit = defineEmits<{ sent: [] }>();

const REASONS = ["补偿 · 奖励未到账", "补偿 · 服务器故障", "活动奖励", "测试", "其他"];
const QUALITY_BG: Record<string, string> = { white: "#eceeea", green: "#e3f1e5", blue: "#e2ecf7", purple: "#efe6f7", orange: "#fbeadb" };
const icons = useItemIcons();
const form = reactive({ players: [] as Player[], items: [] as { itemId: string; count: number | null }[], reason: "", note: "" });
const found = ref<Player[]>([]);
const searching = ref(false);
const sending = ref(false);
const gear = ref<GearOption[]>([]);
const qualities = ref<QualityRow[]>([]);
const batchId = ref("");
const original = ref("");
const dirty = computed(() => open.value && JSON.stringify(form) !== original.value);

const chosen = computed(() => form.items.filter((row) => row.itemId).map((row) => ({ ...row, item: gear.value.find((item) => item.id === row.itemId) })));
const perPlayer = computed(() => chosen.value.map((row) => `${row.item?.displayName ?? row.itemId} ×${row.count ?? 0}`).join("、"));
const totalPieces = computed(() => form.players.length * chosen.value.reduce((sum, row) => sum + (row.count ?? 0), 0));
const previewText = computed(() =>
  form.players.length && chosen.value.length ? `给 ${form.players.length} 名玩家各发 ${perPlayer.value}，共 ${totalPieces.value} 件` : "选好玩家和装备后，这里显示一共发多少",
);

function short(id: string): string {
  return `u_${id.slice(0, 6)}`;
}

function qShort(key: string): string {
  return qualities.value.find((row) => row.key === key)?.short ?? key;
}

function qColor(key: string): string {
  return qualities.value.find((row) => row.key === key)?.color ?? "#999";
}

function iconOf(item: GearOption): string {
  return iconUrl(icons.value, item.iconKey || autoGearIcon(item.slot));
}

function taken(id: string, current: string): boolean {
  return id !== current && form.items.some((row) => row.itemId === id);
}

async function search(query: string): Promise<void> {
  searching.value = true;
  try {
    const ids = query.split(/[\s,，]+/).filter(Boolean);
    const lists = await Promise.all((ids.length > 1 ? ids : [query]).map((q) => api<Player[]>(`/admin/grants/players?q=${encodeURIComponent(q)}`)));
    const merged = new Map<string, Player>();
    for (const player of [...form.players, ...lists.flat()]) merged.set(player.id, player);
    found.value = [...merged.values()];
  } finally {
    searching.value = false;
  }
}

async function loadGear(): Promise<void> {
  type List = {
    majors: { majorName: string; pieces: { id: string; displayName: string; quality: string; slot: string; slotName: string; iconKey: string }[] }[];
    manual: { id: string; displayName: string; quality: string; slot: string; slotName: string; majorName: string; iconKey: string }[];
    qualities: QualityRow[];
  };
  const list = await api<List>("/admin/draft/gear");
  qualities.value = list.qualities ?? [];
  gear.value = [
    ...(list.manual ?? []).map((row) => ({ ...row, origin: "manual" as const })),
    ...list.majors.flatMap((major) => major.pieces.map((piece) => ({ ...piece, majorName: major.majorName, origin: "formula" as const }))),
  ];
}

function newBatchId(): string {
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  const random = Math.random().toString(36).slice(2, 8);
  return `G${stamp}_${random}`;
}

function reset(): void {
  form.players = [...props.presetPlayers];
  found.value = [...props.presetPlayers];
  form.items = [{ itemId: "", count: 1 }];
  form.reason = "";
  form.note = "";
  batchId.value = newBatchId();
  original.value = JSON.stringify(form);
}

async function confirmSend(): Promise<void> {
  if (!form.players.length) return void ElMessage.error("请选择玩家");
  if (!chosen.value.length) return void ElMessage.error("请选择要发的装备");
  if (!form.reason) return void ElMessage.error("请选择补发原因");
  if (!form.note.trim()) return void ElMessage.error("请填写备注");
  const names = form.players.map((player) => `${player.username}（${short(player.id)}）`).join("、");
  try {
    await ElMessageBox.confirm(
      `<div class="grant-confirm"><p>玩家：${names}</p><p>每人：${perPlayer.value}</p><p>合计 <b>${totalPieces.value}</b> 件 · 原因：${form.reason}</p><p class="gold">发放后不能撤回，会记录操作人和时间。</p></div>`,
      "确认补发装备？",
      { confirmButtonText: "确认发放", cancelButtonText: "取消", type: "warning", dangerouslyUseHTMLString: true, customStyle: { width: "480px" } },
    );
  } catch {
    return;
  }
  sending.value = true;
  try {
    const result = await api<{ granted: number; players: number }>("/admin/grants/batch", {
      method: "POST",
      body: JSON.stringify({ playerIds: form.players.map((player) => player.id), items: chosen.value.map((row) => ({ itemId: row.itemId, count: row.count })), reason: form.reason, note: form.note, batchId: batchId.value }),
    });
    ElMessage.success(`已发放：${result.players} 名玩家，共 ${result.granted} 件`);
    original.value = JSON.stringify(form);
    open.value = false;
    emit("sent");
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "发放失败");
  } finally {
    sending.value = false;
  }
}

watch(
  open,
  (value) => {
    if (value) {
      reset();
      void loadGear();
    }
  },
  { immediate: true },
);
</script>

<style scoped>
.stack {
  display: grid;
  gap: 18px;
}
.w320 {
  width: 320px;
}
.w656 {
  width: 656px;
}
.add {
  margin-top: 10px;
}
.opt {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.icon-box {
  display: inline-grid;
  place-items: center;
  border-radius: 6px;
  overflow: hidden;
}
.icon-box.sm {
  width: 24px;
  height: 24px;
}
.icon-box.sm img {
  width: 22px;
  height: 22px;
}
.q-tag {
  padding: 0 6px;
  border: 1px solid;
  border-radius: 4px;
  font-size: 12px;
  line-height: 18px;
}
.preview {
  display: grid;
  gap: 6px;
  padding: 10px 14px;
  border-radius: 6px;
  background: #f7f5ee;
  font-size: 13px;
}
.gold {
  color: #a5781e;
}
.muted {
  color: var(--xx-text-secondary);
}
.small {
  font-size: 12px;
}
</style>
