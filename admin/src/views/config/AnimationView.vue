<template>
  <div class="page" :class="{ 'is-preview': mode === 'preview' }">
    <header class="toolbar">
      <h1>战斗预览</h1>
      <el-radio-group v-model="mode" class="modes">
        <el-radio-button value="organize">素材整理</el-radio-button>
        <el-radio-button value="preview">战斗预演</el-radio-button>
      </el-radio-group>
      <span v-if="characterName" class="who">当前角色：{{ characterName }}</span>
      <span class="spacer"></span>
      <el-tag :type="dirty ? 'warning' : everSaved ? 'success' : 'info'" effect="plain">{{ statusText }}</el-tag>
      <el-button type="primary" :disabled="!dirty || saving || !loaded" :loading="saving" data-testid="save-draft" @click="saveDraft">保存草稿</el-button>
    </header>

    <el-alert class="banner" type="info" :closable="false" show-icon :title="banner" />
    <el-alert v-if="saveError" class="banner" type="error" :closable="false" show-icon :title="saveError">
      <el-button type="primary" size="small" @click="saveDraft">重试保存</el-button>
    </el-alert>
    <el-alert
      v-if="loaded && mode === 'preview' && missingActions.length > 0"
      class="banner"
      type="warning"
      :closable="false"
      show-icon
      :title="`还少：${missingActions.join(' / ')}`"
      description="可以继续看不完整的预演，也可以回素材整理补指定。"
    />

    <div v-if="loadError" class="empty">
      <p>{{ loadError }}</p>
      <el-button type="primary" @click="loadDraft">重试</el-button>
    </div>

    <template v-else-if="loaded">
      <div v-show="mode === 'organize'" class="workspace">
        <aside v-show="mode === 'organize'" class="col">
          <el-button type="primary" class="wide" :disabled="uploadPhase === 'running'" data-testid="upload-open" @click="openUpload">上传素材</el-button>
          <h2>素材列表</h2>
          <p v-if="doc.clips.length === 0" class="hint">还没有画面。</p>
          <div
            v-for="clip in doc.clips"
            :key="clip.id"
            class="clip-row"
            :class="{ on: clip.id === selectedClipId }"
            @click="selectClip(clip.id)"
          >
            <div class="clip-head">
              <strong>{{ clip.name }}</strong>
              <button type="button" class="danger-text" @click.stop="deleteClip(clip)">删除</button>
            </div>
            <span>已抽 {{ clip.frames.length }} 帧</span>
            <div class="role-tags">
              <button type="button" class="role" :class="{ on: clip.id === doc.characterClipId }" @click.stop="setCharacter(clip.id)">
                {{ clip.id === doc.characterClipId ? "当前角色" : "设为当前角色" }}
              </button>
              <button type="button" class="role" :class="{ on: clip.id === doc.opponentClipId }" @click.stop="setOpponent(clip.id)">
                {{ clip.id === doc.opponentClipId ? "演示对手" : "设为演示对手" }}
              </button>
            </div>
          </div>
          <h2>动作</h2>
          <button v-for="action in actionIds" :key="action" type="button" class="action-row" @click="previewAction(action)">
            <span>{{ actionLabel[action] }}</span>
            <em>{{ actionCount(action) }}</em>
          </button>
        </aside>

        <section class="col-main">
          <div class="panel-title">
            <strong>画面检查（不是游戏屏幕）</strong>
            <el-switch v-model="onion" :disabled="visibleCount < 2" active-text="洋葱皮" />
          </div>
          <div v-if="!selectedClip" class="empty">
            <p>还没有画面。上传一段视频或一组图片，抽出一格格画面，再指定哪些是待机、出招、受击。</p>
            <el-button type="primary" @click="openUpload">上传素材</el-button>
          </div>
          <template v-else>
            <canvas ref="checkCanvas" class="check" width="640" height="320" data-testid="check-canvas"></canvas>
            <p class="hint">2:1 棋盘格，用来看破图、抖动和透明边。当前是检查画布，不是游戏屏幕。{{ organizeStatus }}</p>
          </template>
        </section>

        <aside class="col">
          <h2>所选帧</h2>
          <p class="hint">{{ selectionText }}</p>
          <label class="field">所属动作</label>
          <el-select :model-value="selectionAction" :disabled="selectionCount === 0" @change="assignChoice">
            <el-option value="" label="未分配" />
            <el-option v-for="action in actionIds" :key="action" :value="action" :label="actionLabel[action]" />
          </el-select>
          <div class="quick">
            <el-button size="small" :disabled="selectionCount === 0" @click="assign('idle')">设为待机</el-button>
            <el-button size="small" :disabled="selectionCount === 0" @click="assign('attack')">设为出招</el-button>
            <el-button size="small" :disabled="selectionCount === 0" @click="assign('hit')">设为受击</el-button>
          </div>
          <el-button size="small" :disabled="selectionCount === 0" @click="assign(null)">取消分配</el-button>
          <label class="field">帧时长</label>
          <div class="duration">
            <el-input-number :model-value="selectionDuration" :min="30" :max="400" :step="1" :disabled="selectionCount === 0" @change="setDuration" />
            <span>毫秒</span>
          </div>
          <p class="hint">时长和动作都会作用到当前选中的全部帧。范围 30 到 400。新抽出的帧是 83。</p>
          <el-switch :model-value="selectionHidden" :disabled="selectionCount === 0" :active-text="selectionCount > 1 ? `隐藏所选 ${selectionCount} 帧` : '隐藏此帧'" @change="setHidden" />
          <p class="hint">隐藏后播放会跳过，帧还留在胶片上。</p>
        </aside>
      </div>

      <div v-show="mode === 'preview'" class="preview-layout">
        <div v-if="doc.clips.length === 0" class="empty">
          <p>还不能预演。请先在「素材整理」里指定出招和受击。</p>
          <el-button type="primary" @click="mode = 'organize'">去素材整理</el-button>
        </div>
        <div v-else class="stage-center">
          <div class="phone" :class="{ bare: !showPhone }">
            <canvas ref="stageCanvas" width="1080" height="2340" data-testid="stage-canvas"></canvas>
          </div>
        </div>
        <aside class="preview-side">
          <div class="transport">
            <el-button @click="restartStrike">重新开始</el-button>
            <el-button :disabled="beatAtStart" @click="stepBeat(-1)">上一拍</el-button>
            <el-button type="primary" :disabled="doc.clips.length === 0" @click="strikePlaying = !strikePlaying">{{ strikePlaying ? "暂停" : "播放" }}</el-button>
            <el-button :disabled="beatAtEnd" @click="stepBeat(1)">下一拍</el-button>
            <el-switch v-model="strikeLoop" active-text="循环" />
          </div>
          <p class="hint">对齐到「{{ currentEventLabel }}」</p>
          <div>
            <p class="hint">谁出招</p>
            <el-radio-group v-model="doc.attackerSide" class="stack">
              <el-radio value="left">左边打右边</el-radio>
              <el-radio value="right">右边打左边</el-radio>
            </el-radio-group>
          </div>
          <div>
            <p class="hint">{{ characterPlace }}</p>
            <el-radio-group v-model="doc.characterSide" class="stack">
              <el-radio value="left">当前角色站左</el-radio>
              <el-radio value="right">当前角色站右</el-radio>
            </el-radio-group>
          </div>
          <div>
            <p class="hint">演示数字</p>
            <el-input v-model="doc.demoNumber" maxlength="8" data-testid="demo-number" />
            <p class="hint">{{ opponentPlace }}</p>
          </div>
          <div class="ready-inline">
            <p v-for="item in readiness" :key="item.label" class="ready">
              <span>{{ item.label }}</span>
              <em :class="{ lack: item.lack }">{{ item.text }}</em>
            </p>
          </div>
          <el-switch v-model="showPhone" active-text="显示手机框" />
          <el-switch v-model="showMarks" active-text="显示对拍标记" />
          <button
            v-for="event in plan.events"
            :key="event.id"
            type="button"
            class="event-row"
            :class="{ on: event.id === selectedEvent }"
            @click="jumpTo(event.id)"
          >
            <span>{{ event.label }}</span>
            <em v-if="event.skipped">无素材，将跳过</em>
          </button>
          <div class="align">
            <p>{{ alignText }}</p>
            <template v-if="selectedEvent === 'projectile' || selectedEvent === 'hit'">
              <div class="duration">
                <span>对齐到出招第</span>
                <el-input-number :model-value="alignFrame" :min="1" :max="96" :step="1" @change="setAlignFrame" />
                <span>帧</span>
              </div>
              <el-button v-if="selectedEvent === 'hit'" size="small" @click="toggleHitMode">
                {{ doc.hitMode === "projectileArrive" ? "改成对齐到出招某一帧" : "改成对齐到飞出物到达对方" }}
              </el-button>
            </template>
            <div v-else-if="offsetEvent" class="duration">
              <span>相对命中</span>
              <el-input-number :model-value="offsetValue" :min="-60000" :max="60000" :step="10" @change="setOffset" />
              <span>毫秒</span>
            </div>
          </div>
          <div class="timeline" data-testid="strike-timeline">
            <div class="band">
              <span>攻击方</span>
              <div ref="timeTrack" class="track" @pointerdown="scrub">
                <button
                  v-for="(block, index) in attackerBands"
                  :key="`a-${index}`"
                  type="button"
                  class="block"
                  :class="block.tone"
                  :style="bandStyle(block)"
                  @pointerdown.stop="block.tone === 'attack' ? beginDrag('attackStart', $event) : undefined"
                >
                  {{ block.label }}
                </button>
                <i class="head" :style="{ left: headLeft }"></i>
              </div>
            </div>
            <div class="band">
              <span>受击方</span>
              <div class="track">
                <button v-for="(block, index) in defenderBands" :key="`d-${index}`" type="button" class="block" :class="block.tone" :style="bandStyle(block)">
                  {{ block.label }}
                </button>
                <i class="head" :style="{ left: headLeft }"></i>
              </div>
            </div>
            <div class="markers">
              <button
                v-for="event in markerEvents"
                :key="event.id"
                type="button"
                class="marker"
                :class="{ skip: event.skipped, on: event.id === selectedEvent }"
                :style="{ left: markerLeft(event.timeMs) }"
                @pointerdown.stop="beginDrag(event.id, $event)"
                @click.stop="jumpTo(event.id)"
              >
                {{ markerWord(event.id) }}
              </button>
            </div>
          </div>
        </aside>
      </div>

      <footer v-show="mode === 'organize'" class="dock">
        <div class="transport">
          <el-button :disabled="atStart" @click="step(-1)">上一帧</el-button>
          <el-button type="primary" :disabled="playable.length === 0" @click="playing = !playing">{{ playing ? "暂停" : "播放" }}</el-button>
          <el-button :disabled="atEnd" @click="step(1)">下一帧</el-button>
          <el-slider v-model="slider" class="slider" :min="0" :max="sliderMax" :show-tooltip="false" :disabled="playable.length === 0" @input="onSlide" />
          <el-switch v-model="loop" active-text="循环" />
          <span class="hint">{{ organizeStatus }}</span>
        </div>
        <div v-if="selectedClip" class="batch">
          <span class="hint">已选 {{ selectionCount }} 帧。单击选择，按住 Shift 再点另一帧则选中中间整段。</span>
          <el-button size="small" @click="selectAll">全选</el-button>
          <el-button size="small" @click="selectUnassigned">选中未分配</el-button>
          <el-button size="small" :disabled="selectionCount === 0" @click="clearSelection">取消选择</el-button>
          <el-button v-for="action in actionIds" :key="action" size="small" :disabled="selectionCount === 0" @click="assign(action)">
            把所选设为{{ actionLabel[action] }}
          </el-button>
          <el-button size="small" :disabled="selectionCount === 0" @click="assign(null)">取消分配</el-button>
          <el-button size="small" :disabled="selectionCount === 0" @click="setHidden(true)">隐藏所选</el-button>
          <el-button size="small" :disabled="selectionCount === 0" @click="setHidden(false)">显示所选</el-button>
        </div>
        <div v-if="selectedClip" class="film">
          <button
            v-for="(frame, index) in selectedClip.frames"
            :key="frame.id"
            type="button"
            class="cell"
            :class="{ on: frame.id === shownFrame?.id, picked: selectedFrameIds.includes(frame.id), hidden: frame.hidden }"
            @pointerdown="onFramePointerDown(index, $event)"
            @pointerenter="onFramePointerEnter(index)"
          >
            <img v-if="thumbs[frame.id]" :src="thumbs[frame.id]" alt="" />
            <span class="idx">{{ index + 1 }}</span>
            <em v-if="frame.hidden">隐藏</em>
            <em v-else-if="frame.action" :class="`tone-${frame.action}`">{{ actionLabel[frame.action] }}</em>
            <em v-else>未分配</em>
          </button>
        </div>
      </footer>

    </template>

    <el-dialog v-model="uploadOpen" title="上传素材" width="460px" :close-on-click-modal="false" :before-close="onUploadBeforeClose">
      <input ref="fileInput" class="file" type="file" accept="image/png,video/mp4,video/webm,video/quicktime,.png,.mp4,.webm,.mov" multiple @change="onPick" />
      <template v-if="uploadPhase === 'pick'">
        <el-button @click="fileInput?.click()">选择文件</el-button>
        <p class="hint">视频不超过 8 秒，或一组 PNG。一次不要又传视频又传图片。</p>
        <p v-if="uploadFiles.length">已选 {{ uploadFiles.length }} 个：{{ uploadNames }}</p>
      </template>
      <template v-else-if="uploadPhase === 'running'">
        <p>正在处理：{{ uploadStep }} {{ uploadPercent }}%</p>
        <el-progress :percentage="uploadPercent" />
        <p class="hint">步骤：上传 → 抽帧 → 完成</p>
      </template>
      <template v-else>
        <p>{{ uploadError }}</p>
        <el-button type="primary" @click="startUpload">重试</el-button>
        <el-button @click="repick">换一个文件</el-button>
      </template>
      <template #footer>
        <el-button @click="cancelUpload">取消</el-button>
        <el-button type="primary" :disabled="uploadFiles.length === 0 || uploadPhase === 'running'" @click="startUpload">开始处理</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="leaveOpen" title="还有没保存的更改" width="460px" :close-on-click-modal="false" @close="onLeaveDialogClose">
      <p>离开会丢掉还没保存的素材、顺序、隐藏、帧时长、动作分配和这一击的对齐。已经保存的草稿还在。</p>
      <template #footer>
        <el-button @click="chooseLeave('stay')">继续编辑</el-button>
        <el-button type="danger" plain @click="chooseLeave('discard')">离开并丢弃更改</el-button>
        <el-button type="primary" @click="chooseLeave('save')">先保存草稿</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref, watch } from "vue";
import { ElMessage, ElMessageBox } from "element-plus";
import { api, ApiError, getToken } from "../../api";
import { useDirtyGuard } from "../../composables/dirty";
import type { LeaveChoice } from "../../composables/tabs";
import {
  ACTION_IDS,
  ACTION_LABEL,
  alignLabel,
  bands,
  clipById,
  emptyDocument,
  moveEvent,
  poseAt,
  projectileProgress,
  resolveStrike,
  visibleActionFrames,
  type ActionId,
  type BandBlock,
  type BattlePreviewDocument,
  type PreviewClip,
  type PreviewFrame,
  type Side,
  type StrikeEventId,
} from "../../battle-preview/strike";

const STAGE_W = 1080;
const STAGE_H = 2340;
const FEET_Y = 1280;
const DISPLAY_H = 280;
const FEET_X: Record<Side, number> = { left: Math.round(STAGE_W * 0.23), right: Math.round(STAGE_W * 0.77) };

const mode = ref<"organize" | "preview">("organize");
const doc = ref<BattlePreviewDocument>(emptyDocument());
const savedRaw = ref(JSON.stringify(emptyDocument()));
const everSaved = ref(false);
const loaded = ref(false);
const loadError = ref("");
const saving = ref(false);
const saveError = ref("");
const selectedClipId = ref("");
const selectedFrameIds = ref<string[]>([]);
const anchorIndex = ref<number | null>(null);
const loopAction = ref<ActionId | null>(null);
const loop = ref(false);
const playing = ref(false);
const onion = ref(false);
const slider = ref(0);
const pinnedHiddenId = ref<string | null>(null);
const showPhone = ref(true);
const showMarks = ref(false);
const strikePlaying = ref(false);
const strikeLoop = ref(true);
const playhead = ref(0);
const selectedEvent = ref<StrikeEventId>("hit");
const uploadOpen = ref(false);
const uploadPhase = ref<"pick" | "running" | "failed">("pick");
const uploadFiles = ref<File[]>([]);
const uploadStep = ref("上传");
const uploadPercent = ref(0);
const uploadError = ref("");
const leaveOpen = ref(false);
const thumbs = reactive<Record<string, string>>({});
const fileInput = ref<HTMLInputElement | null>(null);
const checkCanvas = ref<HTMLCanvasElement | null>(null);
const stageCanvas = ref<HTMLCanvasElement | null>(null);
const timeTrack = ref<HTMLElement | null>(null);
const images = new Map<string, HTMLImageElement>();
const battleBg = new Image();
let bgReady = false;
battleBg.onload = () => {
  bgReady = true;
};
battleBg.src = "/art/bg_battle_heifeng.webp";

let uploadXhr: XMLHttpRequest | null = null;
let raf = 0;
let lastTick = 0;
let organizeElapsed = 0;
let strikeOrigin = 0;
let ranging = false;
let leaveResolver: ((choice: LeaveChoice) => void) | null = null;

const actionIds = ACTION_IDS;
const actionLabel = ACTION_LABEL;
const dirty = computed(() => loaded.value && JSON.stringify(doc.value) !== savedRaw.value);
const statusText = computed(() => {
  if (saving.value) return "正在保存";
  if (!everSaved.value && !dirty.value) return "尚未保存过草稿";
  if (dirty.value) return everSaved.value ? "有未保存的更改" : "尚未保存过草稿";
  return "草稿已保存";
});
const banner = computed(() => {
  const base = "只在后台看表现，不会改到线上。游戏端还没读取这份动画。";
  return mode.value === "preview" ? `${base}演示数字只看位置和出现时机，不是真实伤害。` : `${base}隐藏不会删掉这一帧，还可以再显示。`;
});
const selectedClip = computed(() => doc.value.clips.find((clip) => clip.id === selectedClipId.value) ?? null);
const characterName = computed(() => clipById(doc.value, doc.value.characterClipId)?.name ?? "");
const playable = computed(() => {
  const clip = selectedClip.value;
  if (!clip) return [] as { frame: PreviewFrame; index: number }[];
  return clip.frames
    .map((frame, index) => ({ frame, index }))
    .filter((item) => !item.frame.hidden && (loopAction.value == null || item.frame.action === loopAction.value));
});
const sliderMax = computed(() => Math.max(0, playable.value.length - 1));
const shownFrame = computed(() => {
  const clip = selectedClip.value;
  if (!clip) return null;
  if (pinnedHiddenId.value) return clip.frames.find((frame) => frame.id === pinnedHiddenId.value) ?? null;
  return playable.value[Math.min(slider.value, sliderMax.value)]?.frame ?? null;
});
const shownPosition = computed(() => {
  const clip = selectedClip.value;
  const frame = shownFrame.value;
  if (!clip || !frame) return 0;
  return clip.frames.findIndex((item) => item.id === frame.id) + 1;
});
const visibleCount = computed(() => selectedClip.value?.frames.filter((frame) => !frame.hidden).length ?? 0);
const atStart = computed(() => playable.value.length === 0 || slider.value <= 0);
const atEnd = computed(() => playable.value.length === 0 || slider.value >= playable.value.length - 1);
const organizeStatus = computed(() => {
  if (!selectedClip.value) return "还没有画面";
  if (!shownFrame.value) return "还没有可播放的帧";
  const loopText = loopAction.value ? `正在循环预览「${ACTION_LABEL[loopAction.value]}」` : "整条胶片";
  return `${loopText} · 第 ${shownPosition.value} 帧`;
});
const plan = computed(() => resolveStrike(doc.value));
const attackerBands = computed(() => bands(plan.value).attacker);
const defenderBands = computed(() => bands(plan.value).defender);
const markerEvents = computed(() => plan.value.events.filter((event) => event.id !== "enterIdle" && event.id !== "returnIdle"));
const headLeft = computed(() => `${(playhead.value / Math.max(plan.value.durationMs, 1)) * 100}%`);
const missingActions = computed(() => {
  const names: string[] = [];
  const attacker = clipById(doc.value, plan.value.attackerClipId);
  const defender = clipById(doc.value, plan.value.defenderClipId);
  if (visibleActionFrames(attacker, "attack").length === 0) names.push("出招");
  if (visibleActionFrames(defender, "hit").length === 0) names.push("受击");
  return names;
});
const characterPlace = computed(() => (doc.value.characterSide === "left" ? "当前角色站左，对手站右。" : "当前角色站右，对手站左。"));
const opponentPlace = computed(() => {
  if (!doc.value.opponentClipId) return "还没有演示对手。";
  if (doc.value.opponentClipId === doc.value.characterClipId) return "演示对手沿用当前角色的待机和受击。";
  return `演示对手：${clipById(doc.value, doc.value.opponentClipId)?.name ?? "未找到"}。`;
});
const readiness = computed(() => {
  const attacker = clipById(doc.value, plan.value.attackerClipId);
  const defender = clipById(doc.value, plan.value.defenderClipId);
  const rows = [
    row("攻击方 · 待机", visibleActionFrames(attacker, "idle").length, false),
    row("攻击方 · 出招", visibleActionFrames(attacker, "attack").length, false),
    row("受击方 · 待机", visibleActionFrames(defender, "idle").length, false),
    row("受击方 · 受击", visibleActionFrames(defender, "hit").length, false),
    row("飞出物", effectCount("projectile"), true),
    row("打中爆开", effectCount("impact"), true),
  ];
  return rows;
});
const alignText = computed(() => alignLabel(doc.value, selectedEvent.value));
const alignFrame = computed(() => (selectedEvent.value === "projectile" ? doc.value.projectileFrame : doc.value.hitFrame));
const offsetEvent = computed(() => selectedEvent.value === "impact" || selectedEvent.value === "number" || selectedEvent.value === "defenderHit");
const offsetValue = computed(() => {
  if (selectedEvent.value === "impact") return doc.value.impactOffsetMs;
  if (selectedEvent.value === "number") return doc.value.numberOffsetMs;
  return doc.value.defenderHitOffsetMs;
});
const currentEventLabel = computed(() => plan.value.events.find((event) => event.id === selectedEvent.value)?.label ?? "命中");
const uploadNames = computed(() => uploadFiles.value.map((file) => file.name).join("、"));
const beatAtStart = computed(() => beatIndex() <= 0);
const beatAtEnd = computed(() => beatIndex() >= plan.value.events.length - 1);

useDirtyGuard(dirty, saveDraft, confirmLeave);

function row(label: string, count: number, optional: boolean): { label: string; text: string; lack: boolean } {
  if (count > 0) return { label, text: optional ? "可选 · 已备" : "已备", lack: false };
  return { label, text: optional ? "无素材，将跳过" : "缺", lack: !optional };
}

function effectCount(action: "projectile" | "impact"): number {
  return doc.value.clips.reduce((total, clip) => total + visibleActionFrames(clip, action).length, 0);
}

function actionCount(action: ActionId): string {
  const count = visibleActionFrames(selectedClip.value, action).length;
  if (action === "projectile" || action === "impact") return count > 0 ? `可选 · ${count} 帧` : "可选 · 未指定";
  return count > 0 ? `已指定 · ${count} 帧` : "未指定";
}

function selectClip(id: string): void {
  selectedClipId.value = id;
  selectedFrameIds.value = [];
  pinnedHiddenId.value = null;
  loopAction.value = null;
  loop.value = false;
  slider.value = 0;
  playing.value = false;
}

function setCharacter(id: string): void {
  doc.value.characterClipId = id;
  ElMessage.success(id === doc.value.opponentClipId ? "这套素材同时是当前角色和演示对手" : "已标为当前角色");
}

function setOpponent(id: string): void {
  doc.value.opponentClipId = id;
  ElMessage.success(id === doc.value.characterClipId ? "这套素材同时是当前角色和演示对手" : "已标为演示对手");
}

function previewAction(action: ActionId): void {
  if (visibleActionFrames(selectedClip.value, action).length === 0) {
    ElMessage.info("请先在胶片上把可见帧指定成这个动作");
    return;
  }
  loopAction.value = action;
  loop.value = true;
  slider.value = 0;
  pinnedHiddenId.value = null;
  playing.value = true;
}

const selectionCount = computed(() => selectedFrameIds.value.length);
const selectedFrames = computed(() => selectedClip.value?.frames.filter((frame) => selectedFrameIds.value.includes(frame.id)) ?? []);
const selectionText = computed(() => {
  if (!selectedClip.value) return "先上传一套素材";
  if (selectionCount.value === 0) return "还没有选中帧。单击一帧，或按住 Shift 选中一整段。";
  return `已选 ${selectionCount.value} 帧，下面的动作、时长和隐藏都会作用到这些帧。`;
});
const selectionAction = computed(() => {
  const frames = selectedFrames.value;
  if (frames.length === 0) return "";
  const first = frames[0]?.action ?? "";
  return frames.every((frame) => (frame.action ?? "") === first) ? first : "";
});
const selectionDuration = computed(() => {
  const frames = selectedFrames.value;
  if (frames.length === 0) return 83;
  const first = frames[0]?.durationMs ?? 83;
  return frames.every((frame) => frame.durationMs === first) ? first : first;
});
const selectionHidden = computed(() => selectedFrames.value.length > 0 && selectedFrames.value.every((frame) => frame.hidden));

function selectAll(): void {
  selectedFrameIds.value = selectedClip.value?.frames.map((frame) => frame.id) ?? [];
}

function selectUnassigned(): void {
  selectedFrameIds.value = selectedClip.value?.frames.filter((frame) => !frame.action).map((frame) => frame.id) ?? [];
}

function clearSelection(): void {
  selectedFrameIds.value = [];
}

function assign(action: ActionId | null): void {
  const clip = selectedClip.value;
  if (!clip || selectedFrameIds.value.length === 0) return;
  const ids = new Set(selectedFrameIds.value);
  let replaced = 0;
  let count = 0;
  for (const frame of clip.frames) {
    if (!ids.has(frame.id)) continue;
    count += 1;
    if (frame.action && action && frame.action !== action) replaced += 1;
    frame.action = action;
  }
  const label = action ? actionLabel[action] : "未分配";
  ElMessage.success(replaced > 0 ? `已把 ${count} 帧改成${label}，其中 ${replaced} 帧原来是别的动作` : `已把 ${count} 帧设为${label}`);
}

function assignChoice(value: string): void {
  assign(value === "" ? null : (value as ActionId));
}

function setDuration(value: number | undefined): void {
  const clip = selectedClip.value;
  if (!clip || value == null) return;
  const ms = Math.round(value);
  if (ms < 30 || ms > 400) return;
  const ids = new Set(selectedFrameIds.value);
  if (ids.size === 0) return;
  for (const frame of clip.frames) {
    if (ids.has(frame.id)) frame.durationMs = ms;
  }
}

function setHidden(value: string | number | boolean): void {
  const hidden = value === true;
  const clip = selectedClip.value;
  if (!clip) return;
  const ids = new Set(selectedFrameIds.value);
  if (ids.size === 0) return;
  for (const frame of clip.frames) {
    if (ids.has(frame.id)) frame.hidden = hidden;
  }
  if (hidden && shownFrame.value) pinnedHiddenId.value = shownFrame.value.id;
  if (!hidden) pinnedHiddenId.value = null;
  if (slider.value > sliderMax.value) slider.value = sliderMax.value;
}

function focusFrame(index: number, extend: boolean): void {
  const clip = selectedClip.value;
  if (!clip) return;
  const frame = clip.frames[index];
  if (!frame) return;
  playing.value = false;
  if (loopAction.value && frame.action !== loopAction.value) {
    loopAction.value = null;
    loop.value = false;
  }
  if (extend && anchorIndex.value != null) {
    const start = Math.min(anchorIndex.value, index);
    const end = Math.max(anchorIndex.value, index);
    selectedFrameIds.value = clip.frames.slice(start, end + 1).map((item) => item.id);
  } else {
    anchorIndex.value = index;
    selectedFrameIds.value = [frame.id];
  }
  if (frame.hidden) pinnedHiddenId.value = frame.id;
  else {
    pinnedHiddenId.value = null;
    const playIndex = playable.value.findIndex((item) => item.frame.id === frame.id);
    if (playIndex >= 0) slider.value = playIndex;
  }
}

function onFramePointerDown(index: number, event: PointerEvent): void {
  ranging = !event.shiftKey;
  focusFrame(index, event.shiftKey);
}

function onFramePointerEnter(index: number): void {
  if (!ranging || anchorIndex.value == null || !selectedClip.value) return;
  const start = Math.min(anchorIndex.value, index);
  const end = Math.max(anchorIndex.value, index);
  selectedFrameIds.value = selectedClip.value.frames.slice(start, end + 1).map((frame) => frame.id);
}

function onSlide(): void {
  playing.value = false;
  pinnedHiddenId.value = null;
}

function step(delta: number): void {
  playing.value = false;
  pinnedHiddenId.value = null;
  const next = slider.value + delta;
  if (next < 0 || next >= playable.value.length) return;
  slider.value = next;
}

function bandStyle(block: BandBlock): Record<string, string> {
  const duration = Math.max(plan.value.durationMs, 1);
  return { left: `${(block.startMs / duration) * 100}%`, width: `${((block.endMs - block.startMs) / duration) * 100}%` };
}

function markerLeft(timeMs: number): string {
  return `${(timeMs / Math.max(plan.value.durationMs, 1)) * 100}%`;
}

function markerWord(id: StrikeEventId): string {
  if (id === "attackStart") return "出手";
  if (id === "projectile") return "飞出";
  if (id === "hit") return "命中";
  if (id === "impact") return "爆开";
  if (id === "number") return "数字";
  return "受击";
}

function beatIndex(): number {
  let index = 0;
  plan.value.events.forEach((event, eventIndex) => {
    if (event.timeMs <= playhead.value + 1) index = eventIndex;
  });
  return index;
}

function stepBeat(delta: number): void {
  strikePlaying.value = false;
  const next = beatIndex() + delta;
  const event = plan.value.events[next];
  if (!event) return;
  playhead.value = event.timeMs;
  selectedEvent.value = event.id;
}

function jumpTo(id: StrikeEventId): void {
  const event = plan.value.events.find((item) => item.id === id);
  if (!event) return;
  strikePlaying.value = false;
  playhead.value = event.timeMs;
  selectedEvent.value = id;
}

function restartStrike(): void {
  playhead.value = 0;
  strikeOrigin = performance.now();
  selectedEvent.value = "enterIdle";
}

function scrub(event: PointerEvent): void {
  const track = event.currentTarget as HTMLElement;
  const duration = Math.max(plan.value.durationMs, 1);
  const apply = (ev: PointerEvent) => {
    const rect = track.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (ev.clientX - rect.left) / Math.max(rect.width, 1)));
    playhead.value = ratio * duration;
    strikePlaying.value = false;
  };
  apply(event);
  const move = (ev: PointerEvent) => apply(ev);
  const up = () => {
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
  };
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", up);
}

function beginDrag(eventId: StrikeEventId, _event: PointerEvent): void {
  if (eventId === "enterIdle" || eventId === "returnIdle") return;
  const track = timeTrack.value;
  if (!track) return;
  strikePlaying.value = false;
  const duration = Math.max(resolveStrike(doc.value).durationMs, 1);
  const move = (ev: PointerEvent) => {
    const rect = track.getBoundingClientRect();
    const ratio = Math.min(1, Math.max(0, (ev.clientX - rect.left) / Math.max(rect.width, 1)));
    doc.value = moveEvent(doc.value, eventId, ratio * duration);
    selectedEvent.value = eventId;
  };
  const up = () => {
    window.removeEventListener("pointermove", move);
    window.removeEventListener("pointerup", up);
  };
  window.addEventListener("pointermove", move);
  window.addEventListener("pointerup", up);
}

function setAlignFrame(value: number | undefined): void {
  if (value == null) return;
  const frame = Math.max(1, Math.round(value));
  if (selectedEvent.value === "projectile") doc.value.projectileFrame = frame;
  else {
    doc.value.hitMode = "attackFrame";
    doc.value.hitFrame = frame;
  }
}

function toggleHitMode(): void {
  doc.value.hitMode = doc.value.hitMode === "projectileArrive" ? "attackFrame" : "projectileArrive";
}

function setOffset(value: number | undefined): void {
  if (value == null) return;
  const ms = Math.round(value);
  if (selectedEvent.value === "impact") doc.value.impactOffsetMs = ms;
  else if (selectedEvent.value === "number") doc.value.numberOffsetMs = ms;
  else doc.value.defenderHitOffsetMs = ms;
}

async function loadDraft(): Promise<void> {
  loadError.value = "";
  try {
    const body = await api<{ draft: BattlePreviewDocument | null }>("/admin/battle-preview/draft");
    doc.value = body.draft ?? emptyDocument();
    savedRaw.value = JSON.stringify(doc.value);
    everSaved.value = body.draft != null;
    loaded.value = true;
    selectedClipId.value = doc.value.characterClipId ?? doc.value.clips[0]?.id ?? "";
    await preload();
    try {
      await api("/admin/battle-preview/prune", { method: "POST", body: JSON.stringify({ keep: [] }) });
    } catch {
      ElMessage.warning("没能清掉上次没保存的临时帧，下次保存时还会再清");
    }
  } catch (error) {
    loaded.value = false;
    loadError.value = error instanceof Error ? error.message : "草稿没有读出来";
  }
}

async function saveDraft(): Promise<boolean> {
  if (saving.value) return false;
  if (!dirty.value) return true;
  saving.value = true;
  saveError.value = "";
  try {
    const saved = await api<{ draft: BattlePreviewDocument }>("/admin/battle-preview/draft", {
      method: "PUT",
      body: JSON.stringify(doc.value),
    });
    doc.value = saved.draft;
    savedRaw.value = JSON.stringify(saved.draft);
    everSaved.value = true;
    ElMessage.success("草稿已保存，不会改到线上。");
    return true;
  } catch (error) {
    saveError.value = error instanceof ApiError || error instanceof Error ? error.message : "保存失败";
    return false;
  } finally {
    saving.value = false;
  }
}

async function preload(): Promise<void> {
  clearImages();
  const failed: string[] = [];
  for (const clip of doc.value.clips) {
    for (const frame of clip.frames) {
      try {
        await loadFrame(clip.id, frame);
      } catch {
        failed.push(frame.name);
      }
    }
  }
  if (failed.length > 0) ElMessage.error(`有 ${failed.length} 帧没有载入`);
}

async function loadFrame(clipId: string, frame: PreviewFrame): Promise<void> {
  const headers = new Headers();
  const token = getToken();
  if (token) headers.set("authorization", `Bearer ${token}`);
  const response = await fetch(`/admin/battle-preview/clips/${clipId}/frames/${frame.name}`, { headers });
  if (!response.ok) throw new Error("有一帧加载失败");
  const objectUrl = URL.createObjectURL(await response.blob());
  const image = new Image();
  image.src = objectUrl;
  await image.decode();
  images.set(frame.id, image);
  thumbs[frame.id] = objectUrl;
}

function clearImages(): void {
  for (const url of Object.values(thumbs)) URL.revokeObjectURL(url);
  for (const key of Object.keys(thumbs)) delete thumbs[key];
  images.clear();
}

function adoptClip(clip: PreviewClip): void {
  doc.value.clips.push(clip);
  if (!doc.value.characterClipId) {
    doc.value.characterClipId = clip.id;
    doc.value.opponentClipId = clip.id;
  }
  selectedClipId.value = clip.id;
  selectedFrameIds.value = [];
  void preload();
}

function openUpload(): void {
  uploadPhase.value = "pick";
  uploadFiles.value = [];
  uploadError.value = "";
  uploadPercent.value = 0;
  uploadStep.value = "上传";
  uploadOpen.value = true;
}

function onPick(event: Event): void {
  const input = event.target as HTMLInputElement;
  uploadFiles.value = Array.from(input.files ?? []);
  input.value = "";
  uploadPhase.value = "pick";
  uploadError.value = "";
}

function startUpload(): void {
  if (uploadFiles.value.length === 0 || uploadPhase.value === "running") return;
  uploadPhase.value = "running";
  uploadStep.value = "上传";
  uploadPercent.value = 5;
  uploadError.value = "";
  const form = new FormData();
  for (const file of uploadFiles.value) form.append("files", file);
  const xhr = new XMLHttpRequest();
  uploadXhr = xhr;
  xhr.open("POST", "/admin/battle-preview/clips");
  const token = getToken();
  if (token) xhr.setRequestHeader("authorization", `Bearer ${token}`);
  xhr.upload.onprogress = (progress) => {
    if (!progress.lengthComputable) return;
    uploadPercent.value = Math.max(5, Math.round((progress.loaded / progress.total) * 70));
  };
  xhr.upload.onload = () => {
    uploadStep.value = "抽帧";
    uploadPercent.value = Math.max(uploadPercent.value, 85);
  };
  xhr.onerror = () => finishUploadError("网络中断，没有传到服务器");
  xhr.onabort = () => {
    uploadPhase.value = "pick";
    uploadXhr = null;
  };
  xhr.onload = () => {
    uploadXhr = null;
    if (xhr.status < 200 || xhr.status >= 300) {
      let message = "上传失败";
      try {
        message = (JSON.parse(xhr.responseText) as { error?: { message?: string } }).error?.message ?? message;
      } catch {
        message = "上传失败";
      }
      finishUploadError(message);
      return;
    }
    const body = JSON.parse(xhr.responseText) as { clip: PreviewClip };
    uploadStep.value = "完成";
    uploadPercent.value = 100;
    uploadPhase.value = "pick";
    adoptClip(body.clip);
    uploadOpen.value = false;
    ElMessage.success(`抽出 ${body.clip.frames.length} 帧。还没保存，刷新会丢掉这次上传。`);
  };
  xhr.send(form);
}

function finishUploadError(message: string): void {
  uploadPhase.value = "failed";
  uploadError.value = message;
}

function repick(): void {
  uploadPhase.value = "pick";
  uploadFiles.value = [];
  uploadError.value = "";
}

async function confirmCancelUpload(): Promise<boolean> {
  if (uploadPhase.value !== "running") return true;
  try {
    await ElMessageBox.confirm("取消后，这次已经抽出但还没写进草稿的帧会丢掉。", "取消处理", {
      confirmButtonText: "确定取消",
      cancelButtonText: "继续处理",
      type: "warning",
    });
  } catch {
    return false;
  }
  uploadXhr?.abort();
  uploadPhase.value = "pick";
  return true;
}

async function cancelUpload(): Promise<void> {
  if (await confirmCancelUpload()) uploadOpen.value = false;
}

function onUploadBeforeClose(done: () => void): void {
  void confirmCancelUpload().then((ok) => {
    if (ok) done();
  });
}

async function deleteClip(clip: PreviewClip): Promise<void> {
  try {
    await ElMessageBox.confirm(`确定删掉「${clip.name}」这一套画面，以及它上面的动作分配？`, "删除素材", {
      confirmButtonText: "确定删除",
      cancelButtonText: "取消删除",
      type: "warning",
    });
  } catch {
    return;
  }
  const saved = JSON.parse(savedRaw.value) as BattlePreviewDocument;
  const stored = saved.clips.some((item) => item.id === clip.id);
  if (!stored) {
    try {
      await api(`/admin/battle-preview/clips/${clip.id}`, { method: "DELETE" });
    } catch (error) {
      ElMessage.error(error instanceof Error ? error.message : "没有删掉");
      return;
    }
  }
  doc.value.clips = doc.value.clips.filter((item) => item.id !== clip.id);
  if (doc.value.characterClipId === clip.id) doc.value.characterClipId = doc.value.clips[0]?.id ?? null;
  if (doc.value.opponentClipId === clip.id) doc.value.opponentClipId = doc.value.characterClipId;
  if (selectedClipId.value === clip.id) selectedClipId.value = doc.value.characterClipId ?? "";
  ElMessage.success(stored ? "已从列表去掉。保存草稿后才会从草稿里删掉。" : "已删掉这套还没保存的素材。");
}

function confirmLeave(): Promise<LeaveChoice> {
  leaveOpen.value = true;
  return new Promise((resolve) => {
    leaveResolver = resolve;
  });
}

function chooseLeave(choice: LeaveChoice): void {
  const resolve = leaveResolver;
  leaveResolver = null;
  leaveOpen.value = false;
  if (choice === "discard") {
    void api("/admin/battle-preview/prune", { method: "POST", body: JSON.stringify({ keep: [] }) }).catch(() => undefined);
  }
  resolve?.(choice);
}

function onLeaveDialogClose(): void {
  if (leaveResolver) chooseLeave("stay");
}

function drawCheck(): void {
  const canvas = checkCanvas.value;
  const ctx = canvas?.getContext("2d");
  if (!ctx) return;
  for (let y = 0; y < 320; y += 16) {
    for (let x = 0; x < 640; x += 16) {
      ctx.fillStyle = (x / 16 + y / 16) % 2 === 0 ? "#d7d7d7" : "#f3f3f3";
      ctx.fillRect(x, y, 16, 16);
    }
  }
  const clip = selectedClip.value;
  const current = shownFrame.value;
  if (!clip || !current) {
    ctx.fillStyle = "#666";
    ctx.font = "16px sans-serif";
    ctx.fillText(clip ? "这一帧还没有画面" : "还没有画面", 24, 40);
    return;
  }
  const index = clip.frames.findIndex((frame) => frame.id === current.id);
  if (onion.value) {
    drawFit(ctx, imageOf(clip.frames[index - 1]), 0.28);
    drawFit(ctx, imageOf(clip.frames[index + 1]), 0.22);
  }
  drawFit(ctx, imageOf(current), 1);
}

function drawFit(ctx: CanvasRenderingContext2D, image: HTMLImageElement | undefined, alpha: number): void {
  if (!image) return;
  const scale = Math.min(640 / image.width, 320 / image.height);
  const width = image.width * scale;
  const height = image.height * scale;
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.drawImage(image, (640 - width) / 2, (320 - height) / 2, width, height);
  ctx.restore();
}

function drawStage(): void {
  const canvas = stageCanvas.value;
  const ctx = canvas?.getContext("2d");
  if (!ctx) return;
  ctx.clearRect(0, 0, STAGE_W, STAGE_H);
  ctx.fillStyle = "#1a3328";
  ctx.fillRect(0, 0, STAGE_W, STAGE_H);
  if (bgReady) ctx.drawImage(battleBg, 0, 350, STAGE_W, 1640);
  else {
    ctx.fillStyle = "#24523a";
    ctx.fillRect(0, 350, STAGE_W, 1640);
    ctx.fillStyle = "#f4efe4";
    ctx.font = "28px sans-serif";
    ctx.textAlign = "left";
    ctx.fillText("战斗背景没有载入，这是纯色占位", 180, 430);
  }
  const pose = poseAt(doc.value, plan.value, playhead.value);
  const attackerSide = doc.value.attackerSide;
  const defenderSide: Side = attackerSide === "left" ? "right" : "left";
  drawActor(ctx, attackerSide, pose.attackerFrameId);
  drawActor(ctx, defenderSide, pose.defenderFrameId);
  const progress = projectileProgress(plan.value, playhead.value);
  if (progress != null && pose.projectileFrameId) {
    const x = FEET_X[attackerSide] + (FEET_X[defenderSide] - FEET_X[attackerSide]) * progress;
    drawCentered(ctx, images.get(pose.projectileFrameId), x, FEET_Y - DISPLAY_H * 0.55, 140);
  }
  if (pose.impactFrameId) drawCentered(ctx, images.get(pose.impactFrameId), FEET_X[defenderSide], FEET_Y - DISPLAY_H * 0.45, 180);
  if (pose.showNumber) {
    const x = FEET_X[defenderSide];
    const y = FEET_Y - DISPLAY_H - 70;
    ctx.textAlign = "center";
    ctx.lineWidth = 8;
    ctx.strokeStyle = "#8a3b12";
    ctx.fillStyle = "#fff4c2";
    ctx.font = "bold 72px sans-serif";
    ctx.strokeText(plan.value.numberText, x, y);
    ctx.fillText(plan.value.numberText, x, y);
    ctx.font = "28px sans-serif";
    ctx.fillStyle = "#ffe27a";
    ctx.fillText("演示", x, y + 36);
  }
  if (showMarks.value) {
    mark(ctx, FEET_X[attackerSide], FEET_Y - DISPLAY_H * 0.55, "出手");
    if (plan.value.projectileStartMs != null) mark(ctx, (FEET_X.left + FEET_X.right) / 2, FEET_Y - DISPLAY_H * 0.75, "飞出");
    mark(ctx, FEET_X[defenderSide], FEET_Y - DISPLAY_H * 0.4, "命中");
    mark(ctx, FEET_X[defenderSide], FEET_Y - DISPLAY_H - 130, "数字");
  }
}

function drawActor(ctx: CanvasRenderingContext2D, side: Side, frameId: string | null): void {
  const image = frameId ? images.get(frameId) : undefined;
  const x = FEET_X[side];
  if (!image) {
    ctx.fillStyle = "rgba(20, 16, 12, 0.45)";
    ctx.fillRect(x - 70, FEET_Y - DISPLAY_H, 140, DISPLAY_H);
    ctx.fillStyle = "#fff";
    ctx.font = "24px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("缺画面", x, FEET_Y - DISPLAY_H / 2);
    return;
  }
  const scale = DISPLAY_H / image.height;
  const width = image.width * scale;
  ctx.drawImage(image, x - width / 2, FEET_Y - DISPLAY_H, width, DISPLAY_H);
}

function drawCentered(ctx: CanvasRenderingContext2D, image: HTMLImageElement | undefined, x: number, y: number, height: number): void {
  if (!image) return;
  const scale = height / image.height;
  const width = image.width * scale;
  ctx.drawImage(image, x - width / 2, y - height / 2, width, height);
}

function mark(ctx: CanvasRenderingContext2D, x: number, y: number, text: string): void {
  ctx.fillStyle = "rgba(0, 0, 0, 0.55)";
  ctx.fillRect(x - 36, y - 18, 72, 28);
  ctx.fillStyle = "#fff";
  ctx.font = "20px sans-serif";
  ctx.textAlign = "center";
  ctx.fillText(text, x, y + 2);
}

function imageOf(frame: PreviewFrame | undefined): HTMLImageElement | undefined {
  return frame ? images.get(frame.id) : undefined;
}

function tick(now: number): void {
  if (mode.value === "organize" && playing.value) {
    const frames = playable.value;
    if (frames.length === 0) playing.value = false;
    else {
      organizeElapsed += now - lastTick;
      let guard = 0;
      while (guard < 8 && frames[slider.value] && organizeElapsed >= frames[slider.value].frame.durationMs) {
        organizeElapsed -= frames[slider.value].frame.durationMs;
        if (slider.value >= frames.length - 1) {
          if (loop.value) slider.value = 0;
          else {
            playing.value = false;
            organizeElapsed = 0;
            break;
          }
        } else slider.value += 1;
        guard += 1;
      }
    }
  }
  if (mode.value === "preview" && strikePlaying.value) {
    const duration = Math.max(plan.value.durationMs, 1);
    const elapsed = now - strikeOrigin;
    if (strikeLoop.value) playhead.value = elapsed % duration;
    else {
      playhead.value = Math.min(elapsed, duration);
      if (elapsed >= duration) strikePlaying.value = false;
    }
  }
  lastTick = now;
  if (mode.value === "organize") drawCheck();
  else drawStage();
  raf = requestAnimationFrame(tick);
}

watch(playing, (value) => {
  if (!value) return;
  organizeElapsed = 0;
  if (playable.value.length > 0 && slider.value >= playable.value.length - 1) slider.value = 0;
});

watch(strikePlaying, (value) => {
  if (value) strikeOrigin = performance.now() - playhead.value;
});

watch(playable, (frames) => {
  if (slider.value > frames.length - 1) slider.value = Math.max(0, frames.length - 1);
});

function stopRange(): void {
  ranging = false;
}

onMounted(() => {
  void loadDraft();
  lastTick = performance.now();
  raf = requestAnimationFrame(tick);
  window.addEventListener("pointerup", stopRange);
});

onUnmounted(() => {
  cancelAnimationFrame(raf);
  window.removeEventListener("pointerup", stopRange);
  uploadXhr?.abort();
  clearImages();
});
</script>

<style scoped>
.page {
  display: flex;
  flex-direction: column;
  height: calc(100vh - 132px);
  min-height: 680px;
  min-width: 960px;
}
.page.is-preview {
  height: calc(100vh - 132px);
  overflow: hidden;
}
.toolbar,
.transport,
.panel-title,
.duration,
.quick,
.ready,
.action-row,
.clip-row,
.event-row {
  display: flex;
  align-items: center;
  gap: 8px;
}
.toolbar h1 {
  margin: 0;
  font-size: 18px;
}
.spacer {
  flex: 1;
}
.who,
.hint,
.clip-row span,
.action-row em,
.ready em,
.event-row em {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.banner {
  margin-top: 8px;
}
.workspace {
  flex: 1;
  min-height: 0;
  display: flex;
  gap: 12px;
  margin-top: 8px;
}
.col {
  width: 280px;
  flex: none;
  overflow: auto;
  padding: 8px;
  background: var(--el-bg-color);
  border: 1px solid var(--el-border-color);
  border-radius: 8px;
}
.col-main {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 8px;
  padding: 8px;
  background: var(--el-bg-color);
  border: 1px solid var(--el-border-color);
  border-radius: 8px;
}
.col h2,
.field {
  margin: 12px 0 6px;
  font-size: 13px;
}
.wide {
  width: 100%;
}
.stack {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
}
.clip-row,
.action-row,
.event-row,
.textish {
  width: 100%;
  margin-top: 6px;
  padding: 8px;
  border: 1px solid var(--el-border-color);
  border-radius: 8px;
  background: transparent;
  color: inherit;
  text-align: left;
  cursor: pointer;
}
.clip-row {
  flex-direction: column;
  align-items: flex-start;
}
.clip-head {
  display: flex;
  width: 100%;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}
.role-tags {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.role {
  border: 1px solid var(--el-border-color);
  background: transparent;
  border-radius: 999px;
  padding: 2px 8px;
  cursor: pointer;
}
.role.on {
  border-color: var(--el-color-primary);
  background: var(--el-color-primary-light-9);
  color: var(--el-color-primary);
  font-weight: 600;
}
.danger-text {
  border: 0;
  background: transparent;
  color: var(--el-color-danger);
  cursor: pointer;
}
.clip-row.on,
.event-row.on {
  border-color: var(--el-color-primary);
  background: var(--el-color-primary-light-9);
}
.row-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.row-actions button,
.textish {
  border: 0;
  background: transparent;
  color: var(--el-color-primary);
  cursor: pointer;
  padding: 0;
}
.ready,
.action-row,
.event-row {
  justify-content: space-between;
}
.ready em.lack {
  color: var(--el-color-warning);
}
.check {
  width: min(100%, 960px);
  height: auto;
  aspect-ratio: 2 / 1;
  align-self: center;
}
.preview-layout {
  flex: 1;
  min-height: 0;
  display: flex;
  flex-direction: row;
  gap: 12px;
  margin-top: 8px;
}
.preview-side {
  width: 420px;
  flex: none;
  min-height: 0;
  overflow: auto;
  display: flex;
  flex-direction: column;
  gap: 10px;
  padding: 8px;
  background: var(--el-bg-color);
  border: 1px solid var(--el-border-color);
  border-radius: 8px;
}
.preview-bar,
.preview-events,
.batch {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  align-items: flex-end;
}
.ready-inline {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 16px;
  align-items: center;
}
.stage-center {
  flex: 1;
  min-height: 0;
  display: flex;
  justify-content: center;
  align-items: flex-start;
  background: #efe8dc;
  border-radius: 8px;
  padding: 12px 0;
}
.preview-layout .stage-center {
  flex: 1;
  min-width: 0;
  min-height: 0;
  height: 100%;
  align-items: center;
}
.phone {
  height: 96%;
  aspect-ratio: 1080 / 2340;
  box-sizing: border-box;
  border: 12px solid #1b1b1b;
  border-radius: 28px;
  overflow: hidden;
  background: #163024;
}
.preview-layout .phone {
  height: calc(100vh - 220px);
  max-height: 100%;
  width: auto;
}
.phone.bare {
  border-color: transparent;
  border-radius: 0;
}
.phone canvas {
  width: 100%;
  height: 100%;
  display: block;
}
.empty {
  margin: auto;
  max-width: 420px;
  text-align: center;
}
.dock {
  flex: none;
  margin-top: 8px;
  padding: 8px;
  background: var(--el-bg-color);
  border: 1px solid var(--el-border-color);
  border-radius: 8px;
}
.slider {
  flex: 1;
  min-width: 120px;
}
.film {
  display: flex;
  gap: 6px;
  overflow-x: auto;
  padding-top: 8px;
}
.cell {
  flex: 0 0 auto;
  width: 84px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
  padding: 4px;
  border: 1px solid var(--el-border-color);
  border-radius: 6px;
  background: transparent;
  color: inherit;
  cursor: pointer;
}
.cell.on {
  border-color: var(--el-color-primary);
}
.cell.picked {
  outline: 3px solid var(--el-color-primary);
  background: var(--el-color-primary-light-9);
}
.cell.hidden {
  opacity: 0.4;
}
.cell img {
  width: 76px;
  height: 42px;
  object-fit: contain;
  background: repeating-conic-gradient(#d7d7d7 0% 25%, #f3f3f3 0% 50%) 50% / 12px 12px;
}
.cell em {
  font-style: normal;
  font-size: 11px;
  color: #fff;
  border-radius: 4px;
  padding: 0 4px;
}
.tone-idle {
  background: #2f7d4a;
}
.tone-attack {
  background: #c47b2b;
}
.tone-hit {
  background: #b42318;
}
.tone-projectile {
  background: #1d6fbf;
}
.tone-impact {
  background: #7a4db3;
}
.timeline {
  margin-top: 8px;
}
.band {
  display: grid;
  grid-template-columns: 52px 1fr;
  align-items: center;
  gap: 8px;
  margin-top: 6px;
}
.track {
  position: relative;
  height: 28px;
  background: var(--el-fill-color);
  border-radius: 6px;
}
.block {
  position: absolute;
  top: 2px;
  height: 24px;
  border: 0;
  border-radius: 4px;
  color: #fff;
  font-size: 12px;
  overflow: hidden;
}
.block.idle {
  background: #2f7d4a;
}
.block.attack {
  background: #c47b2b;
  cursor: ew-resize;
}
.block.hit {
  background: #b42318;
}
.head {
  position: absolute;
  top: -4px;
  width: 2px;
  height: 36px;
  background: #111;
  pointer-events: none;
}
.markers {
  position: relative;
  height: 28px;
  margin-left: 60px;
}
.marker {
  position: absolute;
  top: 4px;
  transform: translateX(-50%);
  border: 0;
  background: transparent;
  color: var(--el-text-color-primary);
  font-size: 12px;
  cursor: ew-resize;
}
.marker.skip {
  opacity: 0.45;
  text-decoration: line-through;
}
.file {
  display: none;
}
.align {
  margin-top: 8px;
}
</style>
