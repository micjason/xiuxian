const SLUG = /^[a-z][a-z0-9_]{1,47}$/;

export type ContentError = { kind: string; slug: string; field: string; message: string };

export type ContentSnapshot = {
  globals: {
    startingRealmSlug: string;
    starterItems: { itemSlug: string; quantity: number }[];
  };
  realms: {
    slug: string;
    nextRealmSlug: string | null;
    tickSeconds: number;
    gainPerTick: number;
    breakthroughCost: number;
    minRateBp: number;
    baseRateBp: number;
    maxRateBp: number;
    requiredStageSlug: string | null;
    recommendedPower: number;
    enabled: boolean;
  }[];
  stages: {
    slug: string;
    nextStageSlug: string | null;
    bossDropTableSlug: string;
    idleDropTableSlug: string;
    firstClearDropTableSlug: string;
    bossHp: number;
    bossInterval: number;
    recommendedPower: number;
    enabled: boolean;
  }[];
  dropTables: {
    slug: string;
    entries: { itemSlug: string; chanceBp: number; minQty: number; maxQty: number }[];
  }[];
  items: {
    slug: string;
    kind: string;
    slot: string | null;
    skillSlug: string | null;
    enabled: boolean;
  }[];
  skills: { slug: string; prerequisiteSkillSlugs: string[]; enabled: boolean }[];
};

const EQUIPMENT_SLOTS = new Set(["weapon", "helmet", "clothes", "shoes", "accessory"]);

export function validateContent(
  draft: ContentSnapshot,
  knownSlugs: { realms: string[]; stages: string[]; items: string[]; skills: string[]; dropTables: string[] } = {
    realms: [],
    stages: [],
    items: [],
    skills: [],
    dropTables: [],
  },
): { errors: ContentError[]; warnings: ContentError[] } {
  const errors: ContentError[] = [];
  const warnings: ContentError[] = [];
  const push = (kind: string, slug: string, field: string, message: string) => errors.push({ kind, slug, field, message });
  const warn = (kind: string, slug: string, field: string, message: string) => warnings.push({ kind, slug, field, message });

  for (const [kind, rows] of [
    ["realm", draft.realms],
    ["stage", draft.stages],
    ["item", draft.items],
    ["skill", draft.skills],
    ["dropTable", draft.dropTables],
  ] as const) {
    const seen = new Set<string>();
    for (const row of rows) {
      if (!SLUG.test(row.slug)) {
        push(kind, row.slug, "slug", "编号格式不正确");
      }
      if (seen.has(row.slug)) {
        push(kind, row.slug, "slug", "编号重复");
      }
      seen.add(row.slug);
    }
  }

  const realmSlugs = new Set(draft.realms.map((row) => row.slug));
  const stageSlugs = new Set(draft.stages.map((row) => row.slug));
  const itemSlugs = new Set(draft.items.map((row) => row.slug));
  const skillSlugs = new Set(draft.skills.map((row) => row.slug));
  const dropSlugs = new Set(draft.dropTables.map((row) => row.slug));

  if (draft.realms.length === 0) {
    push("realm", "", "slug", "至少要有一个境界");
  } else {
    chainErrors("realm", draft.realms.map((row) => ({ slug: row.slug, next: row.nextRealmSlug })), push);
    if (!realmSlugs.has(draft.globals.startingRealmSlug)) {
      push("globals", "globals", "startingRealmSlug", "初始境界不存在");
    }
  }
  for (const realm of draft.realms) {
    if (realm.tickSeconds < 1) {
      push("realm", realm.slug, "tickSeconds", "节拍至少 1 秒");
    }
    if (realm.gainPerTick < 0 || realm.breakthroughCost < 0) {
      push("realm", realm.slug, "breakthroughCost", "修为数值不能为负");
    }
    if (!(0 <= realm.minRateBp && realm.minRateBp <= realm.baseRateBp && realm.baseRateBp <= realm.maxRateBp && realm.maxRateBp <= 10000)) {
      push("realm", realm.slug, "baseRateBp", "成功率上下限不正确");
    }
    if (realm.requiredStageSlug && !stageSlugs.has(realm.requiredStageSlug)) {
      push("realm", realm.slug, "requiredStageSlug", "要求的关卡不存在");
    }
    if (realm.recommendedPower > 0 && realm.baseRateBp < 3000) {
      warn("realm", realm.slug, "baseRateBp", "推荐战力下成功率低于 30%");
    }
  }

  chainErrors("stage", draft.stages.map((row) => ({ slug: row.slug, next: row.nextStageSlug })), push);
  for (const stage of draft.stages) {
    for (const field of ["bossDropTableSlug", "idleDropTableSlug", "firstClearDropTableSlug"] as const) {
      if (!dropSlugs.has(stage[field])) {
        push("stage", stage.slug, field, "掉落表不存在");
      }
    }
    if (stage.bossHp <= 0) {
      push("stage", stage.slug, "bossHp", "Boss 气血必须大于 0");
    }
    if (stage.bossInterval <= 0) {
      push("stage", stage.slug, "bossInterval", "Boss 出手间隔必须大于 0");
    }
  }

  for (const table of draft.dropTables) {
    for (const entry of table.entries) {
      if (!itemSlugs.has(entry.itemSlug) || draft.items.find((item) => item.slug === entry.itemSlug)?.enabled === false) {
        push("dropTable", table.slug, "itemSlug", "掉落物品不存在或已停用");
      }
      if (entry.chanceBp < 0 || entry.chanceBp > 10000) {
        push("dropTable", table.slug, "chanceBp", "概率必须在 0 到 10000");
      }
      if (entry.minQty < 1 || entry.maxQty < entry.minQty) {
        push("dropTable", table.slug, "minQty", "数量区间不正确");
      }
    }
  }

  const bookBySkill = new Map<string, string>();
  for (const item of draft.items) {
    if (item.kind === "equipment" && !EQUIPMENT_SLOTS.has(item.slot ?? "")) {
      push("item", item.slug, "slot", "装备部位不合法");
    }
    if (item.kind === "skill_book") {
      if (!item.skillSlug || !skillSlugs.has(item.skillSlug)) {
        push("item", item.slug, "skillSlug", "功法书必须指向存在的功法");
      } else if (bookBySkill.has(item.skillSlug)) {
        push("item", item.slug, "skillSlug", "一门功法最多一本书");
      } else {
        bookBySkill.set(item.skillSlug, item.slug);
      }
    }
  }
  for (const starter of draft.globals.starterItems) {
    const item = draft.items.find((row) => row.slug === starter.itemSlug);
    if (!item || !item.enabled) {
      push("globals", "globals", "starterItems", "新手物品不存在或已停用");
    }
  }

  const skillsBySlug = new Map(draft.skills.map((skill) => [skill.slug, skill]));
  for (const skill of draft.skills) {
    const stack = new Set<string>();
    const visit = (slug: string) => {
      if (stack.has(slug)) {
        push("skill", skill.slug, "prerequisiteSkillSlugs", "前置功法不能形成环");
        return;
      }
      const current = skillsBySlug.get(slug);
      if (!current) {
        push("skill", skill.slug, "prerequisiteSkillSlugs", "前置功法不存在");
        return;
      }
      stack.add(slug);
      for (const next of current.prerequisiteSkillSlugs) {
        visit(next);
      }
      stack.delete(slug);
    };
    visit(skill.slug);
    if (!bookBySkill.has(skill.slug)) {
      warn("skill", skill.slug, "skillSlug", "功法没有功法书");
    }
  }

  const droppedBooks = new Set(draft.dropTables.flatMap((table) => table.entries.map((entry) => entry.itemSlug)));
  for (const [skillSlug, bookSlug] of bookBySkill) {
    if (!droppedBooks.has(bookSlug)) {
      warn("item", bookSlug, "slug", `功法 ${skillSlug} 的书不在任何掉落表里`);
    }
  }

  const present = { realms: realmSlugs, stages: stageSlugs, items: itemSlugs, skills: skillSlugs, dropTables: dropSlugs };
  for (const key of Object.keys(knownSlugs) as (keyof typeof knownSlugs)[]) {
    for (const slug of knownSlugs[key]) {
      if (!present[key].has(slug)) {
        push(key, slug, "slug", "已发布的编号不能删除");
      }
    }
  }

  return { errors, warnings };
}

function chainErrors(
  kind: string,
  rows: { slug: string; next: string | null }[],
  push: (kind: string, slug: string, field: string, message: string) => void,
) {
  if (rows.length === 0) {
    return;
  }
  const bySlug = new Map(rows.map((row) => [row.slug, row]));
  const incoming = new Set(rows.flatMap((row) => (row.next ? [row.next] : [])));
  const starts = rows.filter((row) => !incoming.has(row.slug));
  const ends = rows.filter((row) => !row.next);
  if (starts.length !== 1 || ends.length !== 1) {
    push(kind, starts[0]?.slug ?? "", "next", "必须连成一条链");
    return;
  }
  const seen = new Set<string>();
  let cursor: { slug: string; next: string | null } | undefined = starts[0];
  while (cursor) {
    if (seen.has(cursor.slug)) {
      push(kind, cursor.slug, "next", "链条不能绕圈");
      return;
    }
    seen.add(cursor.slug);
    if (!cursor.next) {
      break;
    }
    const next = bySlug.get(cursor.next);
    if (!next) {
      push(kind, cursor.slug, "next", "下一环不存在");
      return;
    }
    cursor = next;
  }
  if (seen.size !== rows.length) {
    push(kind, "", "next", "链条不能分叉");
  }
}
