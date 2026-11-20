import sharp from "sharp";
import { AppError } from "../../shared/errors.js";

export async function keyedPng(input: Buffer): Promise<Buffer> {
  const { data, info } = await sharp(input).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const pixels = info.width * info.height;
  let transparent = 0;
  for (let i = 0; i < pixels; i += 1) {
    if ((data[i * 4 + 3] ?? 255) < 250) transparent += 1;
  }
  if (transparent > pixels * 0.02) {
    return sharp(input).ensureAlpha().png().toBuffer();
  }
  const out = Buffer.from(data);
  for (let i = 0; i < pixels; i += 1) {
    const offset = i * 4;
    const red = out[offset] ?? 0;
    const green = out[offset + 1] ?? 0;
    const blue = out[offset + 2] ?? 0;
    const dist = Math.hypot(red - 255, green, blue - 255);
    if (dist < 80) {
      out[offset + 3] = 0;
    } else if (dist < 140) {
      const alpha = Math.round(((dist - 80) / 60) * 255);
      out[offset + 3] = alpha;
      const keep = alpha / 255;
      out[offset] = Math.round(red * keep + green * (1 - keep));
      out[offset + 2] = Math.round(blue * keep + green * (1 - keep));
    }
  }
  return sharp(out, { raw: { width: info.width, height: info.height, channels: 4 } }).png().toBuffer();
}

export type Bounds = { minX: number; minY: number; maxX: number; maxY: number };

export async function opaqueBounds(png: Buffer): Promise<Bounds | null> {
  const { data, info } = await sharp(png).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  let minX = info.width;
  let minY = info.height;
  let maxX = -1;
  let maxY = -1;
  for (let y = 0; y < info.height; y += 1) {
    for (let x = 0; x < info.width; x += 1) {
      const alpha = data[(y * info.width + x) * 4 + 3] ?? 0;
      if (alpha <= 16) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return null;
  return { minX, minY, maxX, maxY };
}

export async function composeCells(
  frames: Buffer[],
  options: { cellW: number; cellH: number; footX: number; footY: number; bodyHeight: number; reference: Buffer },
): Promise<Buffer[]> {
  if (frames.length === 0) return [];
  const reference = await keyedPng(options.reference);
  const referenceMeta = await sharp(reference).metadata();
  const idle = await opaqueBounds(reference);
  if (!idle || !referenceMeta.width || !referenceMeta.height) {
    throw new AppError("INVALID_INPUT", "待机帧里没有不透明的角色，对不齐脚底");
  }
  const fitted = await Promise.all(
    frames.map(async (frame) => {
      const keyed = await keyedPng(frame);
      const meta = await sharp(keyed).metadata();
      if (meta.width === referenceMeta.width && meta.height === referenceMeta.height) return keyed;
      return sharp(keyed).resize(referenceMeta.width, referenceMeta.height, { fit: "fill" }).png().toBuffer();
    }),
  );
  const bodyH = Math.max(1, idle.maxY - idle.minY + 1);
  const scale = options.bodyHeight / bodyH;
  const sourceFootX = (idle.minX + idle.maxX) / 2;
  const sourceFootY = idle.maxY;
  const cells: Buffer[] = [];
  for (const frame of fitted) {
    const width = Math.max(1, Math.round(referenceMeta.width * scale));
    const height = Math.max(1, Math.round(referenceMeta.height * scale));
    const scaled = await sharp(frame).resize(width, height, { fit: "fill" }).png().toBuffer();
    const left = Math.round(options.footX - sourceFootX * scale);
    const top = Math.round(options.footY - sourceFootY * scale);
    const cropLeft = Math.max(0, -left);
    const cropTop = Math.max(0, -top);
    const destLeft = Math.max(0, left);
    const destTop = Math.max(0, top);
    const cropWidth = Math.min(width - cropLeft, options.cellW - destLeft);
    const cropHeight = Math.min(height - cropTop, options.cellH - destTop);
    const base = sharp({
      create: {
        width: options.cellW,
        height: options.cellH,
        channels: 4,
        background: { r: 0, g: 0, b: 0, alpha: 0 },
      },
    });
    if (cropWidth <= 0 || cropHeight <= 0) {
      cells.push(await base.png().toBuffer());
      continue;
    }
    const piece = await sharp(scaled).extract({ left: cropLeft, top: cropTop, width: cropWidth, height: cropHeight }).png().toBuffer();
    cells.push(await base.composite([{ input: piece, left: destLeft, top: destTop }]).png().toBuffer());
  }
  return cells;
}
