import { spawn } from "node:child_process";
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { AppError } from "../../shared/errors.js";
const MAX_SECONDS = 8;
const MAX_FRAMES = 96;

export function ffmpegBin(): string {
  return process.env.FFMPEG_PATH || "ffmpeg";
}

function run(bin: string, args: string[]): Promise<{ code: number; stderr: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { stdio: ["ignore", "ignore", "pipe"] });
    const chunks: Buffer[] = [];
    child.stderr.on("data", (chunk: Buffer) => chunks.push(chunk));
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? 1, stderr: Buffer.concat(chunks).toString("utf8") }));
  });
}

export function durationSeconds(stderr: string): number | null {
  const match = /Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/.exec(stderr);
  if (!match) return null;
  return Number(match[1]) * 3600 + Number(match[2]) * 60 + Number(match[3]);
}

export async function framesFromVideo(inputPath: string, outputDir: string): Promise<string[]> {
  const bin = ffmpegBin();
  let probed: { code: number; stderr: string };
  try {
    probed = await run(bin, ["-i", inputPath]);
  } catch {
    throw new AppError("INVALID_INPUT", "这台机器没有可用的 ffmpeg，视频抽不了帧");
  }
  const seconds = durationSeconds(probed.stderr);
  if (seconds == null) {
    throw new AppError("INVALID_INPUT", "读不出这段视频的时长");
  }
  if (seconds > MAX_SECONDS) {
    throw new AppError("INVALID_INPUT", `视频要在 ${MAX_SECONDS} 秒以内，这段是 ${seconds.toFixed(1)} 秒`);
  }
  await mkdir(outputDir, { recursive: true });
  const extracted = await run(bin, ["-y", "-i", inputPath, "-vf", "fps=12", "-start_number", "0", path.join(outputDir, "%02d.png")]);
  if (extracted.code !== 0) {
    throw new AppError("INVALID_INPUT", "抽帧失败，换一段较短的 mp4 或 webm");
  }
  const names = (await readdir(outputDir)).filter((name) => name.endsWith(".png")).sort();
  if (names.length === 0) {
    throw new AppError("INVALID_INPUT", "这段视频没有抽出帧");
  }
  if (names.length > MAX_FRAMES) {
    await rm(outputDir, { recursive: true, force: true });
    throw new AppError("INVALID_INPUT", `帧数超过 ${MAX_FRAMES}，请把视频剪到 8 秒以内`);
  }
  return names;
}

export async function framesFromPngs(files: { filename: string; bytes: Buffer }[], outputDir: string): Promise<string[]> {
  await mkdir(outputDir, { recursive: true });
  const ordered = [...files].sort((a, b) => a.filename.localeCompare(b.filename, "en"));
  if (ordered.length > MAX_FRAMES) {
    throw new AppError("INVALID_INPUT", `一次最多 ${MAX_FRAMES} 张`);
  }
  const names: string[] = [];
  for (let index = 0; index < ordered.length; index += 1) {
    const name = `${String(index).padStart(2, "0")}.png`;
    await writeFile(path.join(outputDir, name), ordered[index]?.bytes ?? Buffer.alloc(0));
    names.push(name);
  }
  return names;
}

export async function readNamedFrames(dir: string, names: string[]): Promise<Buffer[]> {
  const buffers: Buffer[] = [];
  for (const name of names) {
    if (!/^\d{2}\.png$/.test(name)) {
      throw new AppError("INVALID_INPUT", "帧文件名不正确");
    }
    buffers.push(await readFile(path.join(dir, name)));
  }
  return buffers;
}
