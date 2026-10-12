import { describe, expect, it } from "vitest";
import { AppError } from "../../shared/errors.js";
import { parseCredentials } from "./credentials.js";

describe("parseCredentials", () => {
  it("trims a username and stores a lowercase key", () => {
    expect(parseCredentials("  凡人甲  ", "correct-horse")).toEqual({
      username: "凡人甲",
      usernameLower: "凡人甲",
    });
  });

  it("rejects a short name or a hyphen, and allows a password equal to the username", () => {
    expect(() => parseCredentials("a", "correct-horse")).toThrow(AppError);
    expect(() => parseCredentials("bad-name", "correct-horse")).toThrow(AppError);
    expect(parseCredentials("admin", "admin")).toEqual({ username: "admin", usernameLower: "admin" });
  });
});
