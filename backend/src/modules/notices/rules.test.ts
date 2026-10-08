import { describe, expect, it } from "vitest";
import { incomeNotice, orderNotices, type Notice } from "./rules.js";

const notice = (partial: Partial<Notice> & Pick<Notice, "id" | "priority">): Notice => ({
  type: "announcement",
  template: "acknowledge",
  triggeredAt: "2026-10-08T00:00:00.000Z",
  payload: {},
  ...partial,
});

describe("orderNotices", () => {
  it("orders by priority, then time, then id", () => {
    const ordered = orderNotices([
      notice({ id: "b", priority: 2, triggeredAt: "2026-10-08T00:00:00.000Z" }),
      notice({ id: "a", priority: 2, triggeredAt: "2026-10-08T00:00:00.000Z" }),
      notice({ id: "late", priority: 1, triggeredAt: "2026-10-09T00:00:00.000Z" }),
    ]);
    expect(ordered.map((row) => row.id)).toEqual(["late", "a", "b"]);
  });
});

describe("incomeNotice", () => {
  const previous = new Date("2026-10-08T00:00:00.000Z");

  it("appears only after 60 counted seconds with a gain", () => {
    expect(
      incomeNotice({
        countedSeconds: 59,
        gained: 10,
        hitCap: false,
        offlineCapSeconds: 28800,
        previousSettledAt: previous,
      }),
    ).toBeNull();
    expect(
      incomeNotice({
        countedSeconds: 60,
        gained: 10,
        hitCap: true,
        offlineCapSeconds: 28800,
        previousSettledAt: previous,
      }),
    ).toMatchObject({
      id: "income-2026-10-08T00:00:00.000Z",
      type: "income",
      template: "reward",
      payload: { cultivationGained: 10, countedSeconds: 60, hitCap: true, offlineCapSeconds: 28800 },
    });
  });
});
