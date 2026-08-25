export class RequestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string
  ) {
    super(message);
  }
}

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/iu;

export const requireUUID = (value: unknown, field: string): string => {
  if (typeof value !== "string" || !uuidPattern.test(value)) {
    throw new RequestError(400, "invalid_request", `${field} must be a UUID.`);
  }
  return value.toLowerCase();
};

export const requireNonce = (value: unknown): string => {
  if (typeof value !== "string" || value.length < 16 || value.length > 128
      || !/^[A-Za-z0-9_-]+$/u.test(value)) {
    throw new RequestError(400, "invalid_request", "nonce is invalid.");
  }
  return value;
};

export const requireRecentTimestamp = (
  value: unknown,
  now = Date.now()
): string => {
  if (typeof value !== "string") {
    throw new RequestError(400, "invalid_request", "timestamp is invalid.");
  }
  const milliseconds = Date.parse(value);
  if (!Number.isFinite(milliseconds) || Math.abs(now - milliseconds) > 300_000) {
    throw new RequestError(400, "stale_request", "Request timestamp is outside the allowed window.");
  }
  return new Date(milliseconds).toISOString();
};

export const requireDeviceToken = (value: unknown): string => {
  if (typeof value !== "string" || value.length < 64 || value.length > 256
      || value.length % 2 !== 0 || !/^[0-9a-f]+$/iu.test(value)) {
    throw new RequestError(400, "invalid_request", "deviceToken is invalid.");
  }
  return value.toLowerCase();
};

export const requireEnvironment = (value: unknown): "sandbox" | "production" => {
  if (value !== "sandbox" && value !== "production") {
    throw new RequestError(400, "invalid_request", "environment is invalid.");
  }
  return value;
};

export const requireBuild = (value: unknown): number | null => {
  if (value === undefined || value === null) return null;
  if (!Number.isInteger(value) || (value as number) < 0 || (value as number) > 1_000_000_000) {
    throw new RequestError(400, "invalid_request", "appBuild is invalid.");
  }
  return value as number;
};

export const readJSON = async (request: Request): Promise<Record<string, unknown>> => {
  const contentType = request.headers.get("content-type")?.split(";", 1)[0];
  if (contentType !== "application/json") {
    throw new RequestError(415, "unsupported_media_type", "Expected application/json.");
  }
  const length = Number(request.headers.get("content-length") ?? 0);
  if (Number.isFinite(length) && length > 16_384) {
    throw new RequestError(413, "request_too_large", "Request is too large.");
  }
  let value: unknown;
  try {
    const text = await request.text();
    if (new TextEncoder().encode(text).byteLength > 16_384) {
      throw new RequestError(413, "request_too_large", "Request is too large.");
    }
    value = JSON.parse(text);
  } catch (error) {
    if (error instanceof RequestError) throw error;
    throw new RequestError(400, "invalid_json", "Request JSON is invalid.");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new RequestError(400, "invalid_json", "Expected a JSON object.");
  }
  return value as Record<string, unknown>;
};
