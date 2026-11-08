import { describe, expect, it } from "vitest";
import type { Tx } from "../../db/tx.js";
import { hasUnsettledCombat, requireNoCombat } from "./journal-guard.js";
function tx(rows: { key: string }[]): Tx {
  const chain = { from: () => chain, where: () => chain, limit: async () => rows };
  return { select: () => chain } as unknown as Tx;
}
describe("active combat guards", () => {
  it("allows map actions only when no pending outcome exists", async () => {
    expect(await hasUnsettledCombat(tx([]), "p")).toBe(false);
    await expect(requireNoCombat(tx([]), "p")).resolves.toBeUndefined();
    expect(await hasUnsettledCombat(tx([{ key: "combat:a" }]), "p")).toBe(true);
    await expect(requireNoCombat(tx([{ key: "combat:a" }]), "p")).rejects.toMatchObject({ code: "INVALID_INPUT" });
  });
});
