import { describe, expect, it } from "vitest";
import { generatePairingCode, normalizePairingCode } from "../src/pairing";

describe("device pairing codes", () => {
  it("creates high-entropy human-readable codes without ambiguous characters", () => {
    const values = new Set(Array.from({ length: 100 }, generatePairingCode));
    expect(values.size).toBe(100);
    for (const value of values) {
      expect(value).toMatch(/^[A-HJ-NP-Z2-9]{12}$/u);
      expect(value).not.toMatch(/[01IO]/u);
    }
  });

  it("normalizes grouped lowercase input", () => {
    expect(normalizePairingCode("abcd-efgh-jkmn")).toBe("ABCDEFGHJKMN");
  });

  it("rejects short and ambiguous codes", () => {
    expect(() => normalizePairingCode("ABC")).toThrow();
    expect(() => normalizePairingCode("ABCD-EFGH-IJKL")).toThrow();
  });
});
