import { eq } from "drizzle-orm";
import { describe, expect, it } from "vitest";
import { contentStages } from "../../db/schema.js";
import { withDb } from "../../test/db.js";
import { applyPrototypeV12 } from "./prototype-v12.js";
import { diffSnapshots } from "./snapshot-diff.js";
import { loadDraftSnapshot } from "./snapshot.js";
import { stageAutoPower } from "./stage-power.js";

describe("发布前改动列表：推荐战力清掉手动值后显示自动值而不是 0", () => {
  it("manual 2450 → cleared (stored null, snapshot 0) shows 「2450（手动）」→「自动 N」 with the computed value", async () => {
    await withDb(async (db) => {
      await applyPrototypeV12(db);
      const published = await loadDraftSnapshot(db);
      await db.update(contentStages).set({ recommendedPower: null }).where(eq(contentStages.slug, "zhuji_3"));
      const draft = await loadDraftSnapshot(db);
      const stage = draft.stages.find((row) => row.slug === "zhuji_3")!;
      // 快照里 0 = 没手动覆盖（库里是 null），原始值保持不变
      expect(stage.recommendedPower).toBe(0);
      const auto = stageAutoPower(draft, stage);
      expect(auto).toBeGreaterThan(0);
      const change = diffSnapshots(published, draft).changes.find((row) => row.slug === "zhuji_3")!;
      const field = change.fields.find((row) => row.field === "recommendedPower")!;
      expect(field).toMatchObject({ before: 2450, after: 0, beforeText: "2450（手动）", afterText: `自动 ${auto}` });
    });
  });
});
