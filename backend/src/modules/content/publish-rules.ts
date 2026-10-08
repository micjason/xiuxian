export type PublishDraft = {
  realms: { slug: string; nextSlug: string | null }[];
  skills: { slug: string; prerequisiteSlugs: string[] }[];
  items: { slug: string; kind: string; skillSlug: string | null }[];
  stages: { slug: string }[];
  drops: { stageSlug: string; itemSlug: string; chance: number; quantity: number }[];
  publishedSlugs: { realms: string[]; skills: string[]; items: string[]; stages: string[] };
};

export function validatePublish(draft: PublishDraft): string[] {
  return [
    ...realmErrors(draft.realms),
    ...skillErrors(draft.skills),
    ...bookErrors(draft.items, new Set(draft.skills.map((skill) => skill.slug))),
    ...dropErrors(draft),
    ...deletedSlugErrors(draft),
  ];
}

function realmErrors(realms: PublishDraft["realms"]): string[] {
  if (realms.length === 0) {
    return ["至少要有一个境界"];
  }
  const bySlug = new Map(realms.map((realm) => [realm.slug, realm]));
  const incoming = new Set(realms.flatMap((realm) => (realm.nextSlug ? [realm.nextSlug] : [])));
  const starts = realms.filter((realm) => !incoming.has(realm.slug));
  const ends = realms.filter((realm) => !realm.nextSlug);
  const reasons: string[] = [];
  if (starts.length !== 1 || ends.length !== 1) {
    reasons.push("境界必须连成一条链");
  }
  const seen = new Set<string>();
  let cursor = starts[0];
  while (cursor) {
    if (seen.has(cursor.slug)) {
      reasons.push("境界不能绕圈");
      break;
    }
    seen.add(cursor.slug);
    if (!cursor.nextSlug) {
      break;
    }
    const next = bySlug.get(cursor.nextSlug);
    if (!next) {
      reasons.push("下一境界不存在");
      break;
    }
    cursor = next;
  }
  if (seen.size !== realms.length && !reasons.includes("境界不能绕圈") && !reasons.includes("下一境界不存在")) {
    reasons.push("境界不能分叉");
  }
  return reasons;
}

function skillErrors(skills: PublishDraft["skills"]): string[] {
  const known = new Set(skills.map((skill) => skill.slug));
  const reasons = new Set<string>();
  for (const skill of skills) {
    const stack = new Set<string>();
    const visit = (slug: string): void => {
      if (stack.has(slug)) {
        reasons.add("前置技能不能形成环");
        return;
      }
      const current = skills.find((row) => row.slug === slug);
      if (!current) {
        if (!known.has(slug)) {
          reasons.add("前置技能不存在");
        }
        return;
      }
      stack.add(slug);
      for (const next of current.prerequisiteSlugs) {
        visit(next);
      }
      stack.delete(slug);
    };
    visit(skill.slug);
  }
  return [...reasons];
}

function bookErrors(items: PublishDraft["items"], skillSlugs: Set<string>): string[] {
  const reasons: string[] = [];
  const used = new Set<string>();
  for (const item of items) {
    if (item.kind !== "skill_book") {
      continue;
    }
    if (!item.skillSlug || !skillSlugs.has(item.skillSlug)) {
      reasons.push("技能书必须指向一个存在的技能");
      continue;
    }
    if (used.has(item.skillSlug)) {
      reasons.push("一个技能只能对应一本技能书");
    }
    used.add(item.skillSlug);
  }
  return reasons;
}

function dropErrors(draft: PublishDraft): string[] {
  const stages = new Set(draft.stages.map((stage) => stage.slug));
  const items = new Set(draft.items.map((item) => item.slug));
  const reasons = new Set<string>();
  for (const drop of draft.drops) {
    if (!stages.has(drop.stageSlug)) {
      reasons.add("掉落的关卡不在草稿里");
    }
    if (!items.has(drop.itemSlug)) {
      reasons.add("掉落的物品不在草稿里");
    }
    if (!Number.isInteger(drop.chance) || drop.chance < 0 || drop.chance > 100) {
      reasons.add("掉落概率必须是 0 到 100 的整数");
    }
    if (!Number.isInteger(drop.quantity) || drop.quantity < 1) {
      reasons.add("掉落数量必须是不小于 1 的整数");
    }
  }
  return [...reasons];
}

function deletedSlugErrors(draft: PublishDraft): string[] {
  const present = {
    realms: new Set(draft.realms.map((row) => row.slug)),
    skills: new Set(draft.skills.map((row) => row.slug)),
    items: new Set(draft.items.map((row) => row.slug)),
    stages: new Set(draft.stages.map((row) => row.slug)),
  };
  const labels = { realms: "境界", skills: "技能", items: "物品", stages: "关卡" } as const;
  const reasons: string[] = [];
  for (const key of Object.keys(labels) as (keyof typeof labels)[]) {
    for (const slug of draft.publishedSlugs[key]) {
      if (!present[key].has(slug)) {
        reasons.push(`不能删除已发布的${labels[key]} ${slug}`);
      }
    }
  }
  return reasons;
}
