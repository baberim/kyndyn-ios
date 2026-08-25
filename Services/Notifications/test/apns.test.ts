import { beforeAll, describe, expect, it, vi } from "vitest";
import { sendAPNS, validateAPNSConfiguration } from "../src/apns";
import { decodeBase64URL } from "../src/crypto";
import type { Environment } from "../src/index";

let privateKeyPEM = "";

beforeAll(async () => {
  const pair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"]
  ) as CryptoKeyPair;
  const exported = await crypto.subtle.exportKey("pkcs8", pair.privateKey) as ArrayBuffer;
  const bytes = new Uint8Array(exported);
  const base64 = Buffer.from(bytes).toString("base64").match(/.{1,64}/gu)?.join("\n") ?? "";
  privateKeyPEM = `-----BEGIN PRIVATE KEY-----\n${base64}\n-----END PRIVATE KEY-----`;
});

const environment = (): Environment => ({
  APPLE_TEAM_ID: "96TZPZ6H89",
  APNS_TOPIC: "com.kyndynfamily.kyndyn",
  APNS_SANDBOX_KEY_ID: "2K8PCHCCV8",
  APNS_PRODUCTION_KEY_ID: "G6L8MSV9F4",
  APNS_SANDBOX_PRIVATE_KEY: privateKeyPEM,
  APNS_PRODUCTION_PRIVATE_KEY: privateKeyPEM,
  DEVICE_TOKEN_ENCRYPTION_KEY: "unused",
  SERVICE_STAGE: "test",
  DB: {} as D1Database
});

const message = {
  notificationID: "11111111-1111-4111-8111-111111111111",
  title: "Family update",
  body: "Dinner is ready."
};

describe("APNs delivery", () => {
  it("routes sandbox alerts without private household metadata", async () => {
    let capturedURL = "";
    let capturedInit: RequestInit | undefined;
    const mocked = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      capturedURL = String(input);
      capturedInit = init;
      return new Response(null, { status: 200 });
    }) as typeof fetch;
    const result = await sendAPNS(
      environment(), "sandbox", "a".repeat(64), message,
      new Date("2026-08-25T20:00:00Z"), mocked
    );
    expect(result.result).toBe("accepted");
    expect(capturedURL).toContain("api.sandbox.push.apple.com");
    const headers = capturedInit?.headers as Record<string, string>;
    expect(headers["apns-topic"]).toBe("com.kyndynfamily.kyndyn");
    const tokenParts = headers.authorization.replace("bearer ", "").split(".");
    expect(tokenParts).toHaveLength(3);
    expect(decodeBase64URL(tokenParts[2])).toHaveLength(64);
    const payload = JSON.parse(String(capturedInit?.body));
    expect(payload.aps.alert).toEqual({ title: message.title, body: message.body });
    expect(payload.householdID).toBeUndefined();
  });

  it("routes production devices to the production host", async () => {
    let capturedURL = "";
    const mocked = vi.fn(async (input: RequestInfo | URL) => {
      capturedURL = String(input);
      return new Response(null, { status: 200 });
    }) as typeof fetch;
    await sendAPNS(environment(), "production", "b".repeat(64), message, new Date(), mocked);
    expect(capturedURL).toContain("api.push.apple.com");
  });

  it("invalidates permanently rejected device tokens", async () => {
    const mocked = vi.fn(async () => Response.json(
      { reason: "Unregistered" }, { status: 410 }
    ));
    const result = await sendAPNS(environment(), "production", "c".repeat(64), message, new Date(), mocked);
    expect(result).toEqual({
      result: "permanent_failure",
      errorCategory: "invalid_device",
      invalidateToken: true
    });
  });

  it("classifies outages and network failures as retryable", async () => {
    const unavailable = vi.fn(async () => Response.json({}, { status: 503 }));
    expect((await sendAPNS(environment(), "sandbox", "d".repeat(64), message, new Date(), unavailable)).result)
      .toBe("retryable");
    const offline = vi.fn(async () => { throw new Error("offline"); });
    expect((await sendAPNS(environment(), "sandbox", "d".repeat(64), message, new Date(), offline)).errorCategory)
      .toBe("network");
  });

  it("fails configuration validation when either private key is absent", () => {
    const configured = environment();
    expect(validateAPNSConfiguration(configured)).toBe(true);
    configured.APNS_PRODUCTION_PRIVATE_KEY = "";
    expect(validateAPNSConfiguration(configured)).toBe(false);
  });
});
