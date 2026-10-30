/** 换装资源只读校验：对照仓库内 game/assets/art/q/outfit 实际文件。 */
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { missingOutfitAssets, outfitAssetRefs, type OutfitAssetWarning } from "./appearance.js";

/** 仓库根下的 game/assets/art/q（相对本文件：backend/src/modules/loop → ../../../game/assets/art/q）。 */
export function outfitArtRoot(fromUrl: string | URL = import.meta.url): string {
  return join(fileURLToPath(new URL("../../../game/assets/art/q", fromUrl)));
}

function listPngRelative(root: string, prefix = ""): string[] {
  if (!existsSync(root)) {
    return [];
  }
  const out: string[] = [];
  for (const name of readdirSync(root, { withFileTypes: true })) {
    const rel = prefix ? `${prefix}/${name.name}` : name.name;
    if (name.isDirectory()) {
      out.push(...listPngRelative(join(root, name.name), rel));
    } else if (name.isFile() && name.name.endsWith(".png")) {
      out.push(rel);
    }
  }
  return out;
}

export type OutfitAssetReport = {
  expected: number;
  present: number;
  missing: OutfitAssetWarning[];
  ok: boolean;
};

/** 扫描本地 outfit 目录，返回缺图告警（不做映射编辑）。 */
export function scanOutfitAssets(artRoot = outfitArtRoot()): OutfitAssetReport {
  const present = listPngRelative(join(artRoot, "outfit")).map((path) => `outfit/${path}`);
  const missing = missingOutfitAssets(present);
  const expected = outfitAssetRefs().length;
  return {
    expected,
    present: expected - missing.length,
    missing,
    ok: missing.length === 0,
  };
}
