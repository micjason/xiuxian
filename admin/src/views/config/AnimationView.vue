<template>
  <div>
    <PageHeader title="战斗动画" desc="整段帧排在一条时间轴上。拖动滑杆逐帧看，多余的帧先隐藏，顺序可以拖着调。" />
    <el-alert type="info" :closable="false" show-icon class="banner" title="隐藏不会删掉这帧，还可以再显示。游戏端还没读取这份动画。" />

    <div class="row">
      <input ref="fileInput" class="file" type="file" accept="image/png,video/mp4,video/webm,video/quicktime,.png,.mp4,.webm,.mov" multiple @change="onFiles" />
      <el-button type="primary" @click="fileInput?.click()">上传视频或 PNG</el-button>
      <span class="hint">新上传的帧会接到时间轴末尾。视频不超过 8 秒，品红底会被抠掉。</span>
    </div>

    <div class="stage-wrap">
      <canvas ref="canvasEl" class="stage" width="640" height="320" />
      <div class="controls">
        <el-button @click="step(-1)">上一帧</el-button>
        <el-button type="primary" @click="playing = !playing">{{ playing ? "暂停" : "播放" }}</el-button>
        <el-button @click="step(1)">下一帧</el-button>
        <span class="hint">{{ statusText }}</span>
        <el-input-number v-model="frameDurationMs" :min="30" :max="400" :step="1" size="small" @change="persist" />
        <span class="hint">毫秒/帧</span>
      </div>
      <el-slider v-model="slider" :min="0" :max="sliderMax" :show-tooltip="false" :disabled="visible.length === 0" @input="onSlide" />
    </div>

    <div class="track">
      <button
        v-for="(frame, index) in timeline"
        :key="frame.id"
        type="button"
        class="clip"
        :class="{ hidden: frame.hidden, current: index === shownIndex }"
        draggable="true"
        @dragstart="dragFrom = index"
        @dragover.prevent
        @drop="dropOn(index)"
        @click="focusFrame(index)"
      >
        <img v-if="thumbUrl[frame.url]" :src="thumbUrl[frame.url]" alt="" />
        <span>{{ index + 1 }}</span>
        <em @click.stop="toggleHidden(index)">{{ frame.hidden ? "显示" : "隐藏" }}</em>
      </button>
    </div>
    <p class="hint">按住一帧拖到另一帧上即可换顺序。隐藏的帧还留在轴上，播放和滑杆会跳过它。</p>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref, watch } from "vue";
import { ElMessage } from "element-plus";
import PageHeader from "../../components/PageHeader.vue";
import { api, getToken } from "../../api";
import { frameIndexAt, timelineFromManifest, type AnimationManifest, type SlotName, type TimelineFrame } from "../../animation/playback";

type Clip = TimelineFrame & { url: string; stored: boolean };

const fileInput = ref<HTMLInputElement | null>(null);
const canvasEl = ref<HTMLCanvasElement | null>(null);
const timeline = ref<Clip[]>([]);
const slider = ref(0);
const playing = ref(false);
const frameDurationMs = ref(83);
const pinned = ref<number | null>(null);
const dragFrom = ref<number | null>(null);
const thumbUrl = reactive<Record<string, string>>({});
const images = new Map<string, HTMLImageElement>();
let raf = 0;
let playFrom = 0;
let extractId = "";

const visible = computed(() => timeline.value.map((frame, index) => ({ frame, index })).filter((item) => !item.frame.hidden));
const sliderMax = computed(() => Math.max(0, visible.value.length - 1));
const shownIndex = computed(() => {
  if (pinned.value !== null) return pinned.value;
  return visible.value[Math.min(slider.value, sliderMax.value)]?.index ?? 0;
});
const statusText = computed(() => {
  if (timeline.value.length === 0) return "还没有帧";
  const frame = timeline.value[shownIndex.value];
  const hidden = frame?.hidden ? "，已隐藏" : "";
  return `第 ${shownIndex.value + 1} / ${timeline.value.length} 帧${hidden}，播放 ${visible.value.length} 帧`;
});

function packUrl(slot: SlotName, name: string): string {
  return `/admin/animation-packs/player/files/${slot}/${name}`;
}

async function loadImage(url: string): Promise<void> {
  if (images.has(url)) return;
  const headers = new Headers();
  const token = getToken();
  if (token) headers.set("authorization", `Bearer ${token}`);
  const response = await fetch(url, { headers });
  if (!response.ok) throw new Error("有一帧加载失败");
  const blob = await response.blob();
  const objectUrl = URL.createObjectURL(blob);
  const image = new Image();
  image.src = objectUrl;
  await image.decode();
  images.set(url, image);
  thumbUrl[url] = objectUrl;
}

function draw(): void {
  const canvas = canvasEl.value;
  const ctx = canvas?.getContext("2d");
  if (!ctx) return;
  for (let y = 0; y < 320; y += 16) {
    for (let x = 0; x < 640; x += 16) {
      ctx.fillStyle = (x / 16 + y / 16) % 2 === 0 ? "#d7d7d7" : "#f3f3f3";
      ctx.fillRect(x, y, 16, 16);
    }
  }
  const current = timeline.value[shownIndex.value];
  const image = current ? images.get(current.url) : undefined;
  if (!image) {
    ctx.fillStyle = "#666";
    ctx.fillText("这一帧还没有画面", 24, 40);
    return;
  }
  const previous = visible.value[Math.max(0, slider.value - 1)];
  if (previous && previous.index !== shownIndex.value) {
    const onion = images.get(previous.frame.url);
    if (onion) {
      ctx.save();
      ctx.globalAlpha = 0.28;
      ctx.drawImage(onion, 0, 0);
      ctx.restore();
    }
  }
  ctx.drawImage(image, 0, 0);
}

function focusFrame(index: number): void {
  playing.value = false;
  const frame = timeline.value[index];
  if (!frame) return;
  pinned.value = frame.hidden ? index : null;
  const visibleIndex = visible.value.findIndex((item) => item.index === index);
  if (visibleIndex >= 0) slider.value = visibleIndex;
  draw();
}

function onSlide(): void {
  pinned.value = null;
  playing.value = false;
  draw();
}

function step(delta: number): void {
  playing.value = false;
  pinned.value = null;
  if (visible.value.length === 0) return;
  slider.value = (slider.value + delta + visible.value.length) % visible.value.length;
  draw();
}

function toggleHidden(index: number): void {
  const frame = timeline.value[index];
  if (!frame) return;
  frame.hidden = !frame.hidden;
  if (slider.value > sliderMax.value) slider.value = sliderMax.value;
  draw();
  void persist();
}

function dropOn(index: number): void {
  const from = dragFrom.value;
  dragFrom.value = null;
  if (from === null || from === index) return;
  const next = [...timeline.value];
  const [item] = next.splice(from, 1);
  if (!item) return;
  next.splice(index, 0, item);
  timeline.value = next;
  pinned.value = null;
  draw();
  void persist();
}

async function persist(): Promise<void> {
  const frames = timeline.value.filter((frame) => frame.stored);
  if (frames.length === 0) return;
  try {
    await api("/admin/animation-packs/player/timeline", {
      method: "PUT",
      body: JSON.stringify({
        frames: frames.map((frame) => ({ id: frame.id, slot: frame.slot, name: frame.name, hidden: frame.hidden })),
        frameDurationMs: frameDurationMs.value,
      }),
    });
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "顺序没有保存上");
  }
}

async function onFiles(event: Event): Promise<void> {
  const input = event.target as HTMLInputElement;
  const files = Array.from(input.files ?? []);
  input.value = "";
  if (files.length === 0) return;
  const form = new FormData();
  for (const file of files) form.append("files", file);
  try {
    const headers = new Headers();
    const token = getToken();
    if (token) headers.set("authorization", `Bearer ${token}`);
    const response = await fetch("/admin/animation-packs/player/extract", { method: "POST", body: form, headers });
    const body = (await response.json()) as { extractId?: string; frames?: string[]; error?: { message?: string } };
    if (!response.ok || !body.extractId || !body.frames) throw new Error(body.error?.message ?? "上传失败");
    extractId = body.extractId;
    const added: Clip[] = body.frames.map((name, index) => ({
      id: `upload-${extractId}-${index}`,
      slot: "idle",
      name,
      hidden: false,
      url: `/admin/animation-packs/extract/${extractId}/${name}`,
      stored: false,
    }));
    await Promise.all(added.map((frame) => loadImage(frame.url)));
    timeline.value = [...timeline.value, ...added];
    slider.value = Math.max(0, visible.value.length - added.length);
    pinned.value = null;
    draw();
    ElMessage.success(`接到时间轴末尾 ${added.length} 帧。这批新帧还只在这一页，刷新后要重新上传。`);
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "上传失败");
  }
}

function tick(now: number): void {
  if (playing.value && visible.value.length > 0) {
    pinned.value = null;
    slider.value = frameIndexAt(
      { frameCount: visible.value.length, frameDurationMs: frameDurationMs.value, loop: true },
      now - playFrom,
    );
    draw();
  }
  raf = requestAnimationFrame(tick);
}

watch(slider, () => draw());

onMounted(async () => {
  try {
    const pack = await api<{ manifest: (AnimationManifest & { timeline?: TimelineFrame[] }) | null }>("/admin/animation-packs/player");
    if (pack.manifest) {
      frameDurationMs.value = pack.manifest.slots.idle.frameDurationMs;
      const frames = timelineFromManifest(pack.manifest);
      timeline.value = frames.map((frame) => ({ ...frame, url: packUrl(frame.slot, frame.name), stored: true }));
      await Promise.all(timeline.value.map((frame) => loadImage(frame.url)));
    }
  } catch (cause) {
    ElMessage.error(cause instanceof Error ? cause.message : "读取动画失败");
  }
  draw();
  raf = requestAnimationFrame(tick);
});

watch(playing, (value) => {
  if (value) playFrom = performance.now();
});

onUnmounted(() => cancelAnimationFrame(raf));
</script>

<style scoped>
.banner,
.stage-wrap,
.track {
  margin-top: 12px;
}
.row,
.controls,
.track {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
}
.file {
  display: none;
}
.hint {
  color: var(--el-text-color-secondary);
  font-size: 12px;
}
.stage {
  display: block;
  width: min(960px, 100%);
  background: #111;
}
.track {
  overflow-x: auto;
  flex-wrap: nowrap;
  padding-bottom: 8px;
}
.clip {
  flex: 0 0 auto;
  width: 84px;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 4px;
  border: 1px solid var(--el-border-color);
  background: transparent;
  color: inherit;
  cursor: grab;
}
.clip.current {
  border-color: var(--el-color-primary);
}
.clip.hidden {
  opacity: 0.38;
}
.clip img {
  width: 76px;
  height: 48px;
  object-fit: contain;
  background: repeating-conic-gradient(#d7d7d7 0% 25%, #f3f3f3 0% 50%) 50% / 16px 16px;
}
.clip em {
  font-style: normal;
  font-size: 12px;
  color: var(--el-color-primary);
}
</style>
