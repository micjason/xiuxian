import { describe, expect, it } from "vitest";
import { scanOutfitAssets } from "./outfit-assets.js";

describe("scanOutfitAssets", () => {
  it("finds the repo outfit png set (or reports missing cleanly)", () => {
    const report = scanOutfitAssets();
    expect(report.expected).toBe(20);
    expect(report.present + report.missing.length).toBe(20);
    // 仓库里五品质整图已入库；若 CI 没检出 LFS，允许缺图但结构仍合法。
    for (const row of report.missing) {
      expect(row.key).toMatch(/^(preview|meditate|avatar)_/);
      expect(row.relativePath).toContain("outfit/");
    }
  });
});
