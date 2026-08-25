import { describe, expect, it } from "vitest";
import {
  decodeBase64URL, decrypt, digest, encodeBase64URL, encrypt,
  hasValidServerKey, hmac, requireCapability
} from "../src/crypto";

const key = encodeBase64URL(new Uint8Array(32).fill(7));

describe("notification cryptography", () => {
  it("round-trips base64url without padding", () => {
    const source = new Uint8Array([0, 1, 2, 253, 254, 255]);
    expect(decodeBase64URL(encodeBase64URL(source))).toEqual(source);
  });

  it("accepts only 256-bit capabilities", () => {
    expect(requireCapability(key)).toBe(key);
    expect(() => requireCapability(encodeBase64URL(new Uint8Array(31)))).toThrow();
  });

  it("creates deterministic hashes and domain-separated token HMACs", async () => {
    expect(await digest("capability")).toBe(await digest("capability"));
    expect(await hmac(key, "sandbox:token")).not.toBe(await hmac(key, "production:token"));
  });

  it("uses fresh nonces for encrypted routing tokens", async () => {
    const first = await encrypt(key, "a".repeat(64));
    const second = await encrypt(key, "a".repeat(64));
    expect(first.ciphertext).not.toBe(second.ciphertext);
    expect(first.nonce).not.toBe(second.nonce);
    expect(decodeBase64URL(first.nonce)).toHaveLength(12);
    expect(await decrypt(key, first)).toBe("a".repeat(64));
  });

  it("recognizes only 32-byte server keys", () => {
    expect(hasValidServerKey(key)).toBe(true);
    expect(hasValidServerKey(encodeBase64URL(new Uint8Array(31)))).toBe(false);
    expect(hasValidServerKey(undefined)).toBe(false);
  });
});
