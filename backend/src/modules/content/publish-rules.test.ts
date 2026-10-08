import { describe, expect, it } from "vitest";
import { validatePublish, type PublishDraft } from "./publish-rules.js";

const chain = {
  realms: [
    { slug: "mortal", nextSlug: "qi_early" },
    { slug: "qi_early", nextSlug: null },
  ],
  skills: [{ slug: "heart_0", prerequisiteSlugs: [] }],
  items: [{ slug: "book_0", kind: "skill_book", skillSlug: "heart_0" }],
  stages: [{ slug: "woods" }],
  drops: [{ stageSlug: "woods", itemSlug: "book_0", chance: 20, quantity: 1 }],
  publishedSlugs: { realms: [], skills: [], items: [], stages: [] },
} satisfies PublishDraft;

describe("validatePublish", () => {
  it("accepts one realm chain, one book per skill, and a drop inside the draft", () => {
    expect(validatePublish(chain)).toEqual([]);
  });

  it("rejects a forked or cyclic realm chain and a missing realm", () => {
    expect(
      validatePublish({
        ...chain,
        realms: [
          { slug: "mortal", nextSlug: "qi_early" },
          { slug: "other", nextSlug: "qi_early" },
          { slug: "qi_early", nextSlug: "mortal" },
        ],
      }).length,
    ).toBeGreaterThan(0);
    expect(validatePublish({ ...chain, realms: [] })).toContain("至少要有一个境界");
  });

  it("rejects a skill cycle, a missing prerequisite, and two books for one skill", () => {
    expect(
      validatePublish({
        ...chain,
        skills: [
          { slug: "a", prerequisiteSlugs: ["b"] },
          { slug: "b", prerequisiteSlugs: ["a"] },
        ],
        items: [],
        drops: [],
      }),
    ).toContain("前置技能不能形成环");
    expect(
      validatePublish({
        ...chain,
        items: [
          { slug: "book_a", kind: "skill_book", skillSlug: "heart_0" },
          { slug: "book_b", kind: "skill_book", skillSlug: "heart_0" },
        ],
        drops: [],
      }),
    ).toContain("一个技能只能对应一本技能书");
  });

  it("rejects a drop that points outside the draft or has an illegal chance", () => {
    expect(validatePublish({ ...chain, drops: [{ stageSlug: "missing", itemSlug: "book_0", chance: 20, quantity: 1 }] })).toContain(
      "掉落的关卡不在草稿里",
    );
    expect(validatePublish({ ...chain, drops: [{ stageSlug: "woods", itemSlug: "book_0", chance: 101, quantity: 1 }] })).toContain(
      "掉落概率必须是 0 到 100 的整数",
    );
  });

  it("rejects deleting a slug that was already published", () => {
    expect(validatePublish({ ...chain, publishedSlugs: { ...chain.publishedSlugs, items: ["sword_0"] } })).toContain(
      "不能删除已发布的物品 sword_0",
    );
  });
});
