import sharp from "sharp";
import { describe, expect, it } from "vitest";
import { composeCells, keyedPng, opaqueBounds } from "./frames.js";

async function canvas(
  width: number,
  height: number,
  rect: { x: number; y: number; w: number; h: number },
  background: "magenta" | "clear",
): Promise<Buffer> {
  const raw = Buffer.alloc(width * height * 4);
  for (let y = 0; y < height; y += 1) {
    for (let x = 0; x < width; x += 1) {
      const offset = (y * width + x) * 4;
      const inside = x >= rect.x && x < rect.x + rect.w && y >= rect.y && y < rect.y + rect.h;
      if (inside) {
        raw[offset] = 20;
        raw[offset + 1] = 20;
        raw[offset + 2] = 20;
        raw[offset + 3] = 255;
      } else if (background === "magenta") {
        raw[offset] = 255;
        raw[offset + 2] = 255;
        raw[offset + 3] = 255;
      }
    }
  }
  return sharp(raw, { raw: { width, height, channels: 4 } }).png().toBuffer();
}

describe("animation frames", () => {
  it("removes a magenta background and keeps an already transparent image", async () => {
    const keyed = await keyedPng(await canvas(8, 8, { x: 2, y: 2, w: 2, h: 2 }, "magenta"));
    const bounds = await opaqueBounds(keyed);
    expect(bounds).toEqual({ minX: 2, minY: 2, maxX: 3, maxY: 3 });

    const raw = Buffer.alloc(4 * 4 * 4);
    raw[0] = 255;
    raw[2] = 255;
    raw[3] = 255;
    const already = await sharp(raw, { raw: { width: 4, height: 4, channels: 4 } }).png().toBuffer();
    const kept = await opaqueBounds(await keyedPng(already));
    expect(kept?.minX).toBe(0);
  });

  it("locks every frame to the idle foot, so a jump stays in the air", async () => {
    const idle = await canvas(40, 80, { x: 10, y: 40, w: 20, h: 40 }, "magenta");
    const jump = await canvas(40, 80, { x: 10, y: 10, w: 20, h: 40 }, "magenta");
    const [idleCell, jumpCell] = await composeCells([idle, jump], {
      cellW: 200,
      cellH: 160,
      footX: 80,
      footY: 140,
      bodyHeight: 40,
      reference: idle,
    });
    const idleBounds = await opaqueBounds(idleCell ?? Buffer.alloc(0));
    const jumpBounds = await opaqueBounds(jumpCell ?? Buffer.alloc(0));
    expect(idleBounds?.maxY).toBe(140);
    expect(jumpBounds?.maxY).toBeLessThan(idleBounds?.maxY ?? 0);
  });

  it("clips a character taller than the cell instead of failing", async () => {
    const idle = await canvas(20, 40, { x: 4, y: 10, w: 12, h: 30 }, "magenta");
    const [cell] = await composeCells([idle], {
      cellW: 64,
      cellH: 32,
      footX: 32,
      footY: 30,
      bodyHeight: 80,
      reference: idle,
    });
    const bounds = await opaqueBounds(cell ?? Buffer.alloc(0));
    expect(bounds?.minY).toBe(0);
    expect(bounds?.maxY).toBeGreaterThanOrEqual(29);
    expect(bounds?.maxY).toBeLessThanOrEqual(31);
  });
});
