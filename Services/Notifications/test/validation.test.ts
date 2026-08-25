import { describe, expect, it } from "vitest";
import {
  RequestError, requireDeviceToken, requireEnvironment,
  requireRecentTimestamp, requireUUID
} from "../src/validation";

describe("notification request validation", () => {
  it("normalizes UUIDs", () => {
    expect(requireUUID("550E8400-E29B-41D4-A716-446655440000", "id"))
      .toBe("550e8400-e29b-41d4-a716-446655440000");
  });

  it("rejects stale timestamps", () => {
    expect(() => requireRecentTimestamp("2026-01-01T00:00:00Z", Date.parse("2026-01-01T00:10:00Z")))
      .toThrowError(RequestError);
  });

  it("accepts only APNs environments", () => {
    expect(requireEnvironment("sandbox")).toBe("sandbox");
    expect(() => requireEnvironment("development")).toThrowError(RequestError);
  });

  it("normalizes a valid APNs token and rejects malformed input", () => {
    expect(requireDeviceToken("AB".repeat(32))).toBe("ab".repeat(32));
    expect(() => requireDeviceToken("not-a-token")).toThrowError(RequestError);
  });
});
