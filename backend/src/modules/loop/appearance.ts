/** 换装 v1：五品质整图。战斗 preview_*、打坐 meditate_*、头像 avatar_* 与圆头像 avatar_*_round。不走分层叠合。 */

export const OUTFIT_QUALITIES = ["white", "green", "blue", "purple", "orange"] as const;
export type OutfitQuality = (typeof OUTFIT_QUALITIES)[number];

export type Appearance = {
  quality: OutfitQuality;
  previewKey: `preview_${OutfitQuality}`;
  meditateKey: `meditate_${OutfitQuality}`;
  avatarKey: `avatar_${OutfitQuality}`;
  avatarRoundKey: `avatar_${OutfitQuality}_round`;
};

const RANK: Record<OutfitQuality, number> = { white: 0, green: 1, blue: 2, purple: 3, orange: 4 };

export function outfitQuality(value: string | null | undefined): OutfitQuality {
  if (value && (OUTFIT_QUALITIES as readonly string[]).includes(value)) {
    return value as OutfitQuality;
  }
  return "white";
}

export function appearanceForQuality(quality: OutfitQuality): Appearance {
  return {
    quality,
    previewKey: `preview_${quality}`,
    meditateKey: `meditate_${quality}`,
    avatarKey: `avatar_${quality}`,
    avatarRoundKey: `avatar_${quality}_round`,
  };
}

type Piece = {
  slug: string;
  kind?: string | null;
  slot?: string | null;
  quality?: string | null;
};

type Worn = { itemSlug: string; equippedSlot: string | null };

/**
 * 没穿装备 → null（客户端继续用现有头像 / 立绘）。
 * 穿了衣服 → 用衣服品质。否则用身上品质最高的一件。
 * 套装不另选图，仍按这件的品质。
 */
export function appearanceOf(definitions: Piece[], equipped: Worn[]): Appearance | null {
  const worn = equipped.flatMap((row) => {
    if (!row.equippedSlot) {
      return [];
    }
    const definition = definitions.find((item) => item.slug === row.itemSlug);
    if (!definition || (definition.kind != null && definition.kind !== "equipment")) {
      return [];
    }
    return [{ slot: row.equippedSlot || definition.slot || "", quality: outfitQuality(definition.quality) }];
  });
  if (worn.length === 0) {
    return null;
  }
  const clothes = worn.find((row) => row.slot === "clothes");
  const picked = clothes ?? worn.reduce((best, row) => (RANK[row.quality] > RANK[best.quality] ? row : best));
  return appearanceForQuality(picked.quality);
}

/** 换装 v1 每个品质需要的四张资源 key（与客户端 OutfitAppearance 一致）。 */
export const OUTFIT_KEY_KINDS = ["preview", "meditate", "avatar", "avatar_round"] as const;
export type OutfitKeyKind = (typeof OUTFIT_KEY_KINDS)[number];

export type OutfitAssetRef = {
  quality: OutfitQuality;
  kind: OutfitKeyKind;
  /** 资源 key，如 preview_white / avatar_blue_round */
  key: string;
  /** 相对 game/assets/art/q/ 的路径（含 .png） */
  relativePath: string;
};

export function outfitAssetRefs(): OutfitAssetRef[] {
  const refs: OutfitAssetRef[] = [];
  for (const quality of OUTFIT_QUALITIES) {
    refs.push({ quality, kind: "preview", key: `preview_${quality}`, relativePath: `outfit/preview_${quality}.png` });
    refs.push({ quality, kind: "meditate", key: `meditate_${quality}`, relativePath: `outfit/meditate/meditate_${quality}.png` });
    refs.push({ quality, kind: "avatar", key: `avatar_${quality}`, relativePath: `outfit/avatar/avatar_${quality}.png` });
    refs.push({ quality, kind: "avatar_round", key: `avatar_${quality}_round`, relativePath: `outfit/avatar/avatar_${quality}_round.png` });
  }
  return refs;
}

export type OutfitAssetWarning = OutfitAssetRef & { message: string };

/**
 * 只读校验：对照「已有文件相对路径集合」找出缺图的 key。
 * present 里放相对 game/assets/art/q/ 的路径（可带或不带前导斜杠）。
 */
export function missingOutfitAssets(present: Iterable<string>): OutfitAssetWarning[] {
  const have = new Set([...present].map((path) => path.replace(/^\/+/, "")));
  return outfitAssetRefs()
    .filter((ref) => !have.has(ref.relativePath))
    .map((ref) => ({
      ...ref,
      message: `换装资源缺失：${ref.key}（${ref.relativePath}）`,
    }));
}

