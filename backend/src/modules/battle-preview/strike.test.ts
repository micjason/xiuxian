import { emptyDocument, poseAt, resolveStrike, visibleActionFrames, type BattlePreviewDocument, type PreviewFrame } from "./strike.js";
import { describe, expect, it } from "vitest";

const clipId = "11111111-1111-4111-8111-111111111111";

function frame(id: string, action: PreviewFrame["action"], durationMs: number, hidden = false): PreviewFrame {
  return { id, name: `${id.slice(0, 2)}.png`, durationMs, hidden, action };
}

function sample(): BattlePreviewDocument {
  const doc = emptyDocument();
  doc.characterClipId = clipId;
  doc.opponentClipId = clipId;
  doc.hitFrame = 2;
  doc.clips = [
    {
      id: clipId,
      name: "主角",
      frames: [
        frame("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1", "idle", 100),
        frame("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2", "idle", 100, true),
        frame("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3", "attack", 100),
        frame("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4", "attack", 100),
        frame("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5", "hit", 80),
      ],
    },
  ];
  return doc;
}

describe("battle preview strike", () => {
  it("skips hidden frames and optional projectile or impact", () => {
    const doc = sample();
    const plan = resolveStrike(doc);
    expect(plan.warnings).toEqual(expect.arrayContaining(["飞出物没有素材，这一段会跳过", "打中爆开没有素材，这一段会跳过"]));
    expect(plan.events.find((event) => event.id === "projectile")?.skipped).toBe(true);
    expect(plan.events.find((event) => event.id === "impact")?.skipped).toBe(true);
    expect(plan.events.find((event) => event.id === "number")?.note).toContain("不是真实伤害");
    expect(plan.numberText).toBe("123");
    expect(plan.attackStartMs).toBe(100);
    expect(plan.attackEndMs).toBe(300);
    expect(plan.events.find((event) => event.id === "hit")?.timeMs).toBe(200);

    const during = poseAt(doc, plan, 200);
    expect(during.attackerFrameId).toBe("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4");
    expect(during.defenderFrameId).toBe("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa5");
    expect(during.showNumber).toBe(true);
    expect(during.projectileFrameId).toBeNull();
    expect(during.impactFrameId).toBeNull();
    expect(during.attackerFrameId).not.toBe("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2");

    const idle = poseAt(doc, plan, 0);
    expect(idle.attackerFrameId).toBe("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1");
    expect(visibleActionFrames(doc.clips[0] ?? null, "idle").map((item) => item.id)).toEqual([
      "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1",
    ]);
  });

  it("plays a projectile then impact when those frames exist", () => {
    const doc = sample();
    doc.hitMode = "projectileArrive";
    doc.clips[0]?.frames.push(
      frame("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6", "projectile", 100),
      frame("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7", "impact", 50),
    );
    const plan = resolveStrike(doc);
    expect(plan.projectileStartMs).toBe(100);
    expect(plan.projectileEndMs).toBe(200);
    expect(plan.events.find((event) => event.id === "hit")?.timeMs).toBe(200);
    expect(plan.impactStartMs).toBe(200);
    expect(plan.impactEndMs).toBe(250);
    expect(poseAt(doc, plan, 150).projectileFrameId).toBe("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa6");
    expect(poseAt(doc, plan, 210).impactFrameId).toBe("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa7");
    expect(poseAt(doc, plan, 150).impactFrameId).toBeNull();
  });

  it("keeps the typed demo text instead of a damage total", () => {
    const doc = sample();
    doc.demoNumber = "演示";
    expect(resolveStrike(doc).numberText).toBe("演示");
  });
});
