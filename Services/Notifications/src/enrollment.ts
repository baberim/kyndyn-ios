import { digest, encrypt, hmac, requireCapability, timingSafeEqual } from "./crypto";
import {
  RequestError, readJSON, requireBuild, requireDeviceToken,
  requireEnvironment, requireNonce, requireRecentTimestamp, requireUUID
} from "./validation";
import type { Environment } from "./index";

type HouseholdRow = {
  id: string;
  admin_secret_hash: string;
  enrollment_secret_hash: string;
  state: string;
};

export const authorization = (request: Request): string => {
  const value = request.headers.get("authorization");
  if (!value?.startsWith("Bearer ")) {
    throw new RequestError(401, "unauthorized", "Authorization is required.");
  }
  try {
    return requireCapability(value.slice(7));
  } catch {
    throw new RequestError(401, "unauthorized", "Authorization is invalid.");
  }
};

const authorizeDeviceOrHousehold = async (
  env: Environment,
  request: Request,
  householdID: string,
  deviceID: string,
  householdKind: "admin" | "enrollment"
): Promise<void> => {
  const capability = authorization(request);
  const candidate = await digest(capability);
  const row = await household(env, householdID);
  const householdHash = householdKind === "admin"
    ? row.admin_secret_hash : row.enrollment_secret_hash;
  if (timingSafeEqual(candidate, householdHash)) return;
  const device = await env.DB.prepare(
    "SELECT device_secret_hash FROM notification_devices WHERE id = ? AND household_id = ?"
  ).bind(deviceID, householdID).first<{ device_secret_hash: string | null }>();
  if (!device?.device_secret_hash
      || !timingSafeEqual(candidate, device.device_secret_hash)) {
    throw new RequestError(401, "unauthorized", "Authorization is invalid.");
  }
};

const household = async (env: Environment, id: string): Promise<HouseholdRow> => {
  const row = await env.DB.prepare(
    "SELECT id, admin_secret_hash, enrollment_secret_hash, state "
      + "FROM notification_households WHERE id = ?"
  ).bind(id).first<HouseholdRow>();
  if (!row || row.state !== "active") {
    throw new RequestError(404, "household_unavailable", "Notification household is unavailable.");
  }
  return row;
};

export const authorize = async (
  env: Environment,
  request: Request,
  id: string,
  kind: "admin" | "enrollment"
): Promise<void> => {
  const capability = authorization(request);
  const row = await household(env, id);
  const candidate = await digest(capability);
  const expected = kind === "admin" ? row.admin_secret_hash : row.enrollment_secret_hash;
  if (!timingSafeEqual(candidate, expected)) {
    throw new RequestError(401, "unauthorized", "Authorization is invalid.");
  }
};

export const rateLimit = async (
  env: Environment,
  scope: string,
  limit: number,
  now: Date
): Promise<void> => {
  const window = Math.floor(now.getTime() / 60_000);
  const key = await hmac(env.DEVICE_TOKEN_ENCRYPTION_KEY, `rate:${scope}:${window}`);
  const expires = new Date((window + 2) * 60_000).toISOString();
  await env.DB.batch([
    env.DB.prepare("DELETE FROM notification_rate_limits WHERE expires_at < ?")
      .bind(now.toISOString()),
    env.DB.prepare(
      "INSERT INTO notification_rate_limits (bucket_key, request_count, expires_at) "
        + "VALUES (?, 1, ?) ON CONFLICT(bucket_key) DO UPDATE SET "
        + "request_count = request_count + 1"
    ).bind(key, expires)
  ]);
  const result = await env.DB.prepare(
    "SELECT request_count FROM notification_rate_limits WHERE bucket_key = ?"
  ).bind(key).first<{ request_count: number }>();
  if (!result || result.request_count > limit) {
    throw new RequestError(429, "rate_limited", "Please wait before trying again.");
  }
};

export const useNonce = async (
  env: Environment,
  householdID: string,
  nonce: string,
  now: Date
): Promise<void> => {
  const nonceHash = await digest(nonce);
  const expires = new Date(now.getTime() + 10 * 60_000).toISOString();
  try {
    await env.DB.batch([
      env.DB.prepare("DELETE FROM notification_request_nonces WHERE expires_at < ?")
        .bind(now.toISOString()),
      env.DB.prepare(
        "INSERT INTO notification_request_nonces "
          + "(household_id, nonce_hash, used_at, expires_at) VALUES (?, ?, ?, ?)"
      ).bind(householdID, nonceHash, now.toISOString(), expires)
    ]);
  } catch {
    throw new RequestError(409, "replayed_request", "This request was already used.");
  }
};

export const provisionHousehold = async (
  request: Request,
  env: Environment,
  now = new Date()
): Promise<Response> => {
  const body = await readJSON(request);
  const id = requireUUID(body.householdID, "householdID");
  let admin: string;
  let enrollment: string;
  try {
    admin = requireCapability(body.adminCapability);
    enrollment = requireCapability(body.enrollmentCapability);
  } catch {
    throw new RequestError(400, "invalid_request", "Capabilities must contain 32 random bytes.");
  }
  if (admin === enrollment) {
    throw new RequestError(400, "invalid_request", "Capabilities must be distinct.");
  }
  requireRecentTimestamp(body.timestamp, now.getTime());
  requireNonce(body.nonce);
  const ip = request.headers.get("cf-connecting-ip") ?? "unknown";
  await rateLimit(env, `provision:${ip}`, 5, now);

  const adminHash = await digest(admin);
  const enrollmentHash = await digest(enrollment);
  const existing = await env.DB.prepare(
    "SELECT admin_secret_hash FROM notification_households WHERE id = ?"
  ).bind(id).first<{ admin_secret_hash: string }>();
  if (existing) {
    if (!timingSafeEqual(existing.admin_secret_hash, adminHash)) {
      throw new RequestError(409, "household_exists", "Notification household already exists.");
    }
    return Response.json({ householdID: id, state: "active", created: false });
  }
  await env.DB.prepare(
    "INSERT INTO notification_households "
      + "(id, admin_secret_hash, enrollment_secret_hash, state, secret_generation, created_at, updated_at) "
      + "VALUES (?, ?, ?, 'active', 1, ?, ?)"
  ).bind(id, adminHash, enrollmentHash, now.toISOString(), now.toISOString()).run();
  return Response.json({ householdID: id, state: "active", created: true }, { status: 201 });
};

export const registerDevice = async (
  request: Request,
  env: Environment,
  now = new Date()
): Promise<Response> => {
  const body = await readJSON(request);
  const householdID = requireUUID(body.householdID, "householdID");
  const deviceID = requireUUID(body.deviceID, "deviceID");
  const environment = requireEnvironment(body.environment);
  const deviceToken = requireDeviceToken(body.deviceToken);
  const appBuild = requireBuild(body.appBuild);
  const showBroadcastDetails = body.showBroadcastDetails === true;
  const nonce = requireNonce(body.nonce);
  requireRecentTimestamp(body.timestamp, now.getTime());
  await authorizeDeviceOrHousehold(
    env, request, householdID, deviceID, "enrollment"
  );
  await rateLimit(env, `register:${householdID}`, 30, now);
  await useNonce(env, householdID, nonce, now);

  await upsertDevice(
    env, householdID, deviceID, environment, deviceToken, appBuild, null,
    showBroadcastDetails, now
  );
  return Response.json({ deviceID, registered: true });
};

export const upsertDevice = async (
  env: Environment,
  householdID: string,
  deviceID: string,
  environment: "sandbox" | "production",
  deviceToken: string,
  appBuild: number | null,
  deviceSecretHash: string | null,
  showBroadcastDetails: boolean,
  now: Date
): Promise<void> => {
  const tokenHash = await hmac(
    env.DEVICE_TOKEN_ENCRYPTION_KEY,
    `apns:${environment}:${deviceToken}`
  );
  const existingDevice = await env.DB.prepare(
    "SELECT household_id FROM notification_devices WHERE id = ?"
  ).bind(deviceID).first<{ household_id: string }>();
  if (existingDevice && existingDevice.household_id !== householdID) {
    throw new RequestError(409, "device_conflict", "This device registration conflicts with another household.");
  }
  if (!existingDevice) {
    const count = await env.DB.prepare(
      "SELECT COUNT(*) AS count FROM notification_devices "
        + "WHERE household_id = ? AND status = 'active'"
    ).bind(householdID).first<{ count: number }>();
    if ((count?.count ?? 0) >= 16) {
      throw new RequestError(409, "device_limit", "This household has reached its device limit.");
    }
  }
  const existingToken = await env.DB.prepare(
    "SELECT id FROM notification_devices WHERE household_id = ? AND environment = ? AND token_hash = ?"
  ).bind(householdID, environment, tokenHash).first<{ id: string }>();
  if (existingToken && existingToken.id !== deviceID) {
    const supersededHash = await hmac(
      env.DEVICE_TOKEN_ENCRYPTION_KEY,
      `superseded:${existingToken.id}:${now.toISOString()}`
    );
    await env.DB.prepare(
      "UPDATE notification_devices SET token_hash = ?, status = 'disabled', broadcasts_enabled = 0, "
        + "updated_at = ? WHERE id = ? AND household_id = ?"
    ).bind(supersededHash, now.toISOString(), existingToken.id, householdID).run();
  }
  const encrypted = await encrypt(env.DEVICE_TOKEN_ENCRYPTION_KEY, deviceToken);
  const result = await env.DB.prepare(
    "INSERT INTO notification_devices "
      + "(id, household_id, environment, token_hash, token_ciphertext, token_nonce, "
      + "broadcasts_enabled, status, app_build, last_seen_at, created_at, updated_at, "
      + "device_secret_hash, show_broadcast_details) "
      + "VALUES (?, ?, ?, ?, ?, ?, 1, 'active', ?, ?, ?, ?, ?, ?) "
      + "ON CONFLICT(id) DO UPDATE SET environment = excluded.environment, "
      + "token_hash = excluded.token_hash, token_ciphertext = excluded.token_ciphertext, "
      + "token_nonce = excluded.token_nonce, broadcasts_enabled = 1, status = 'active', "
      + "app_build = excluded.app_build, last_seen_at = excluded.last_seen_at, "
      + "device_secret_hash = COALESCE(excluded.device_secret_hash, device_secret_hash), "
      + "show_broadcast_details = excluded.show_broadcast_details, "
      + "updated_at = excluded.updated_at WHERE household_id = excluded.household_id"
  ).bind(
    deviceID, householdID, environment, tokenHash, encrypted.ciphertext,
    encrypted.nonce, appBuild, now.toISOString(), now.toISOString(), now.toISOString(),
    deviceSecretHash, showBroadcastDetails ? 1 : 0
  ).run();
  if (!result.success || result.meta.changes !== 1) {
    throw new RequestError(409, "device_conflict", "The device could not be registered safely.");
  }
};

export const revokeDevice = async (
  request: Request,
  env: Environment,
  now = new Date()
): Promise<Response> => {
  const body = await readJSON(request);
  const householdID = requireUUID(body.householdID, "householdID");
  const deviceID = requireUUID(body.deviceID, "deviceID");
  const nonce = requireNonce(body.nonce);
  requireRecentTimestamp(body.timestamp, now.getTime());
  await authorizeDeviceOrHousehold(env, request, householdID, deviceID, "admin");
  await rateLimit(env, `revoke:${householdID}`, 30, now);
  await useNonce(env, householdID, nonce, now);
  await env.DB.prepare(
    "UPDATE notification_devices SET status = 'revoked', broadcasts_enabled = 0, "
      + "updated_at = ? WHERE id = ? AND household_id = ?"
  ).bind(now.toISOString(), deviceID, householdID).run();
  return Response.json({ deviceID, revoked: true });
};
