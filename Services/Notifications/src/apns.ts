import { decodeBase64URL, encodeBase64URL } from "./crypto";
import type { Environment } from "./index";

export type APNSEnvironment = "sandbox" | "production";

export type APNSMessage = {
  notificationID: string;
  title: string;
  body: string;
};

export type APNSResult = {
  result: "accepted" | "retryable" | "permanent_failure";
  errorCategory: string | null;
  invalidateToken: boolean;
};

const encoder = new TextEncoder();

const privateKey = async (pem: string): Promise<CryptoKey> => {
  const normalized = pem.replaceAll("\\n", "\n").trim();
  const body = normalized
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/gu, "");
  if (!body) throw new Error("missing_apns_private_key");
  const bytes = Uint8Array.from(atob(body), character => character.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    bytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
};

const jwt = async (
  teamID: string,
  keyID: string,
  pem: string,
  now: Date
): Promise<string> => {
  const header = encodeBase64URL(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyID })));
  const claims = encodeBase64URL(encoder.encode(JSON.stringify({
    iss: teamID,
    iat: Math.floor(now.getTime() / 1000)
  })));
  const unsigned = `${header}.${claims}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    await privateKey(pem),
    encoder.encode(unsigned)
  );
  return `${unsigned}.${encodeBase64URL(new Uint8Array(signature))}`;
};

const reasonCategory = (status: number, reason: unknown): APNSResult => {
  if (status === 410 || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"
      || reason === "Unregistered") {
    return { result: "permanent_failure", errorCategory: "invalid_device", invalidateToken: true };
  }
  if (status === 429 || status >= 500) {
    return { result: "retryable", errorCategory: status === 429 ? "rate_limited" : "apns_unavailable", invalidateToken: false };
  }
  if (reason === "ExpiredProviderToken" || reason === "InvalidProviderToken") {
    return { result: "retryable", errorCategory: "provider_authentication", invalidateToken: false };
  }
  return { result: "permanent_failure", errorCategory: "rejected", invalidateToken: false };
};

export const sendAPNS = async (
  env: Environment,
  environment: APNSEnvironment,
  deviceToken: string,
  message: APNSMessage,
  now = new Date(),
  performFetch: typeof fetch = fetch
): Promise<APNSResult> => {
  const production = environment === "production";
  const keyID = production ? env.APNS_PRODUCTION_KEY_ID : env.APNS_SANDBOX_KEY_ID;
  const pem = production ? env.APNS_PRODUCTION_PRIVATE_KEY : env.APNS_SANDBOX_PRIVATE_KEY;
  const host = production ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const token = await jwt(env.APPLE_TEAM_ID, keyID, pem, now);
  let response: Response;
  try {
    response = await performFetch(`https://${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${token}`,
        "apns-expiration": String(Math.floor(now.getTime() / 1000) + 86_400),
        "apns-id": message.notificationID,
        "apns-priority": "10",
        "apns-push-type": "alert",
        "apns-topic": env.APNS_TOPIC,
        "content-type": "application/json"
      },
      body: JSON.stringify({
        aps: {
          alert: { title: message.title, body: message.body },
          category: "KYNDYN_FAMILY_BROADCAST",
          sound: "default"
        },
        kind: "family_broadcast",
        notificationID: message.notificationID
      })
    });
  } catch {
    return { result: "retryable", errorCategory: "network", invalidateToken: false };
  }
  if (response.ok) {
    return { result: "accepted", errorCategory: null, invalidateToken: false };
  }
  let reason: unknown;
  try {
    reason = (await response.json() as { reason?: unknown }).reason;
  } catch {
    reason = undefined;
  }
  return reasonCategory(response.status, reason);
};

export const validateAPNSConfiguration = (env: Environment): boolean =>
  /^[A-Z0-9]{10}$/u.test(env.APPLE_TEAM_ID ?? "")
  && /^[A-Z0-9]{10}$/u.test(env.APNS_SANDBOX_KEY_ID ?? "")
  && /^[A-Z0-9]{10}$/u.test(env.APNS_PRODUCTION_KEY_ID ?? "")
  && typeof env.APNS_TOPIC === "string" && env.APNS_TOPIC.length > 0
  && typeof env.APNS_SANDBOX_PRIVATE_KEY === "string" && env.APNS_SANDBOX_PRIVATE_KEY.length > 0
  && typeof env.APNS_PRODUCTION_PRIVATE_KEY === "string" && env.APNS_PRODUCTION_PRIVATE_KEY.length > 0;
