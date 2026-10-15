import { describe, expect, it } from "vitest";
import { diffSnapshots } from "./snapshot-diff.js";
import type { ContentSnapshot } from "./validate.js";

const realm = (slug: string, extra: Record<string, unknown> = {}) =>
  ({ slug, displayName: slug, sortOrder: 1, nextRealmSlug: null, tickSeconds: 1, gainPerTick: 1, ...extra }) as unknown as ContentSnapshot["realms"][number];

describe("diffSnapshots", () => {
  it("treats everything as added when nothing was published", () => {
    const diff = diffSnapshots(null, { realms: [realm("a")] });
    expect(diff).toMatchObject({ total: 1, added: 1, removed: 0, changed: 0 });
  });

  it("lists field changes, additions and removals, and ignores derived links", () => {
    const from = { realms: [realm("a"), realm("b")], globals: { bagCapacity: 100 } } as unknown as Partial<ContentSnapshot>;
    const to = {
      realms: [realm("a", { gainPerTick: 3, nextRealmSlug: "c" }), realm("c")],
      globals: { bagCapacity: 120 },
    } as unknown as Partial<ContentSnapshot>;
    const diff = diffSnapshots(from, to);
    expect(diff.added).toBe(1);
    expect(diff.removed).toBe(1);
    expect(diff.changed).toBe(2);
    const changedRealm = diff.changes.find((row) => row.kind === "realm" && row.type === "changed");
    expect(changedRealm?.fields).toEqual([{ field: "gainPerTick", before: 1, after: 3 }]);
    expect(diff.changes.find((row) => row.kind === "globals")?.fields).toEqual([{ field: "bagCapacity", before: 100, after: 120 }]);
  });

  it("reports nothing when snapshots are equal regardless of key order", () => {
    const left = { items: [{ slug: "x", attack: 1, hp: 2 }] } as unknown as Partial<ContentSnapshot>;
    const right = { items: [{ hp: 2, slug: "x", attack: 1 }] } as unknown as Partial<ContentSnapshot>;
    expect(diffSnapshots(left, right).total).toBe(0);
  });
});
