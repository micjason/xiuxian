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
