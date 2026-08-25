import { decrypt } from "./crypto";
import { authorize, rateLimit, useNonce } from "./enrollment";
import { sendAPNS } from "./apns";
import { readJSON, RequestError, requireNonce, requireRecentTimestamp, requireUUID } from "./validation";
import type { Environment } from "./index";

type DeviceRow = {
  id: string;
  environment: "sandbox" | "production";
  token_ciphertext: string;
  token_nonce: string;
  show_broadcast_details: number;
};

export const broadcastPayload = (
  showDetails: boolean,
  notificationID: string,
  title: string,
  body: string
): { notificationID: string; title: string; body: string } => ({
  notificationID,
  title: showDetails ? title : "Family announcement",
  body: showDetails ? body : "Open kyndyn to read it."
});

const text = (value: unknown, field: string, maximum: number): string => {
  if (typeof value !== "string") {
    throw new RequestError(400, "invalid_request", `${field} is required.`);
  }
  const normalized = value.trim().replace(/\s+/gu, " ");
  if (!normalized || [...normalized].length > maximum) {
    throw new RequestError(400, "invalid_request", `${field} is too long or empty.`);
  }
  return normalized;
};

const receipt = async (
  env: Environment,
  householdID: string,
  deviceID: string,
  notificationID: string,
  result: "accepted" | "retryable" | "permanent_failure",
  errorCategory: string | null,
  now: Date
): Promise<void> => {
  const id = crypto.randomUUID();
  const expires = new Date(now.getTime() + 30 * 86_400_000).toISOString();
  await env.DB.prepare(
    "INSERT INTO notification_delivery_receipts "
      + "(id, household_id, device_id, notification_id, category, result, error_category, attempted_at, expires_at) "
      + "VALUES (?, ?, ?, ?, 'family_broadcast', ?, ?, ?, ?) "
      + "ON CONFLICT(device_id, notification_id) DO UPDATE SET result = excluded.result, "
      + "error_category = excluded.error_category, attempted_at = excluded.attempted_at, expires_at = excluded.expires_at"
  ).bind(
    id, householdID, deviceID, notificationID, result, errorCategory,
    now.toISOString(), expires
  ).run();
};

export const sendBroadcast = async (
  request: Request,
  env: Environment,
  now = new Date()
): Promise<Response> => {
  const body = await readJSON(request);
  const householdID = requireUUID(body.householdID, "householdID");
  const notificationID = requireUUID(body.notificationID, "notificationID");
  const senderDeviceID = body.senderDeviceID === undefined
    ? null : requireUUID(body.senderDeviceID, "senderDeviceID");
  const title = text(body.title, "title", 80);
  const messageBody = text(body.body, "body", 500);
  const nonce = requireNonce(body.nonce);
  requireRecentTimestamp(body.timestamp, now.getTime());
  await authorize(env, request, householdID, "admin");
  await rateLimit(env, `broadcast:${householdID}`, 10, now);
  await useNonce(env, householdID, nonce, now);

  await env.DB.prepare(
    "DELETE FROM notification_delivery_receipts WHERE expires_at < ?"
  ).bind(now.toISOString()).run();

  const devices = await env.DB.prepare(
    "SELECT id, environment, token_ciphertext, token_nonce, show_broadcast_details FROM notification_devices "
      + "WHERE household_id = ? AND status = 'active' AND broadcasts_enabled = 1 "
      + "ORDER BY created_at LIMIT 16"
  ).bind(householdID).all<DeviceRow>();
  const previousReceipts = await env.DB.prepare(
    "SELECT device_id, result FROM notification_delivery_receipts "
      + "WHERE household_id = ? AND notification_id = ?"
  ).bind(householdID, notificationID).all<{ device_id: string; result: string }>();
  const priorResult = new Map(
    previousReceipts.results.map(item => [item.device_id, item.result])
  );
  let accepted = 0;
  let retryable = 0;
  let failed = 0;
  let skipped = 0;

  for (const device of devices.results) {
    if (device.id === senderDeviceID) {
      skipped += 1;
      continue;
    }
    const previous = priorResult.get(device.id);
    if (previous === "accepted" || previous === "permanent_failure") {
      skipped += 1;
      continue;
    }
    const deviceToken = await decrypt(env.DEVICE_TOKEN_ENCRYPTION_KEY, {
      ciphertext: device.token_ciphertext,
      nonce: device.token_nonce
    });
    const outcome = await sendAPNS(
      env, device.environment, deviceToken,
      broadcastPayload(
        device.show_broadcast_details === 1,
        notificationID, title, messageBody
      ),
      now
    );
    await receipt(
      env, householdID, device.id, notificationID,
      outcome.result, outcome.errorCategory, now
    );
    if (outcome.invalidateToken) {
      await env.DB.prepare(
        "UPDATE notification_devices SET status = 'invalid', broadcasts_enabled = 0, updated_at = ? "
          + "WHERE id = ? AND household_id = ?"
      ).bind(now.toISOString(), device.id, householdID).run();
    }
    if (outcome.result === "accepted") accepted += 1;
    else if (outcome.result === "retryable") retryable += 1;
    else failed += 1;
  }

  return Response.json({ notificationID, accepted, retryable, failed, skipped });
};
