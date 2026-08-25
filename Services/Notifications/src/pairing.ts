import { digest, encodeBase64URL, hmac } from "./crypto";
import { authorize, rateLimit, upsertDevice, useNonce } from "./enrollment";
import {
  readJSON, RequestError, requireBuild, requireDeviceToken,
  requireEnvironment, requireNonce, requireRecentTimestamp, requireUUID
} from "./validation";
import type { Environment } from "./index";

const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

export const generatePairingCode = (): string => {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return [...bytes].map(value => alphabet[value % alphabet.length]).join("");
};

export const normalizePairingCode = (value: unknown): string => {
  if (typeof value !== "string") {
    throw new RequestError(400, "invalid_request", "pairingCode is invalid.");
  }
  const normalized = value.toUpperCase().replaceAll("-", "").replaceAll(" ", "");
  if (normalized.length !== 12 || !/^[A-HJ-NP-Z2-9]+$/u.test(normalized)) {
    throw new RequestError(400, "invalid_request", "pairingCode is invalid.");
  }
  return normalized;
};

export const createPairingCode = async (
  request: Request,
  env: Environment,
  now = new Date()
): Promise<Response> => {
  const body = await readJSON(request);
  const householdID = requireUUID(body.householdID, "householdID");
  const nonce = requireNonce(body.nonce);
  requireRecentTimestamp(body.timestamp, now.getTime());
  await authorize(env, request, householdID, "admin");
  await rateLimit(env, `pair-create:${householdID}`, 5, now);
  await useNonce(env, householdID, nonce, now);
  const code = generatePairingCode();
  const codeHash = await hmac(env.DEVICE_TOKEN_ENCRYPTION_KEY, `pair:${code}`);
  const expiresAt = new Date(now.getTime() + 10 * 60_000).toISOString();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM notification_pairing_codes WHERE expires_at < ?")
      .bind(now.toISOString()),
    env.DB.prepare(
      "INSERT INTO notification_pairing_codes "
        + "(code_hash, household_id, created_at, expires_at) VALUES (?, ?, ?, ?)"
    ).bind(codeHash, householdID, now.toISOString(), expiresAt)
  ]);
  const displayCode = `${code.slice(0, 4)}-${code.slice(4, 8)}-${code.slice(8)}`;
  return Response.json({ pairingCode: displayCode, expiresAt });
};

export const pairDevice = async (
  request: Request,
  env: Environment,
  now = new Date()
): Promise<Response> => {
  const body = await readJSON(request);
  const code = normalizePairingCode(body.pairingCode);
  const deviceID = requireUUID(body.deviceID, "deviceID");
  const environment = requireEnvironment(body.environment);
  const deviceToken = requireDeviceToken(body.deviceToken);
  const appBuild = requireBuild(body.appBuild);
  const showBroadcastDetails = body.showBroadcastDetails === true;
  requireRecentTimestamp(body.timestamp, now.getTime());
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  await rateLimit(env, `pair-use:${ip}`, 10, now);
  const codeHash = await hmac(env.DEVICE_TOKEN_ENCRYPTION_KEY, `pair:${code}`);
  const pairing = await env.DB.prepare(
    "SELECT household_id FROM notification_pairing_codes "
      + "WHERE code_hash = ? AND used_at IS NULL AND expires_at >= ?"
  ).bind(codeHash, now.toISOString()).first<{ household_id: string }>();
  if (!pairing) {
    throw new RequestError(404, "pairing_unavailable", "That pairing code is unavailable.");
  }
  const consumed = await env.DB.prepare(
    "UPDATE notification_pairing_codes SET used_at = ? "
      + "WHERE code_hash = ? AND used_at IS NULL AND expires_at >= ?"
  ).bind(now.toISOString(), codeHash, now.toISOString()).run();
  if (!consumed.success || consumed.meta.changes !== 1) {
    throw new RequestError(409, "pairing_used", "That pairing code was already used.");
  }
  const deviceCapability = encodeBase64URL(
    crypto.getRandomValues(new Uint8Array(32))
  );
  await upsertDevice(
    env, pairing.household_id, deviceID, environment, deviceToken, appBuild,
    await digest(deviceCapability), showBroadcastDetails, now
  );
  return Response.json({
    householdID: pairing.household_id,
    deviceID,
    deviceCapability,
    registered: true
  });
};
