import { describe, expect, it } from "vitest";
import * as schema from "./schema.js";

const tableNames = [
  "players",
  "admins",
  "sessions",
  "contentReleases",
  "realms",
  "skills",
  "items",
  "playerStates",
  "operationRecords",
  "repairPreviews",
  "repairApplications",
];

describe("schema", () => {
  it("exports every first-slice table", () => {
    for (const name of tableNames) {
      expect(schema).toHaveProperty(name);
    }
  });
});
