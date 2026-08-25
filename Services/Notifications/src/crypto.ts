const encoder = new TextEncoder();

export const encodeBase64URL = (bytes: Uint8Array): string => {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/u, "");
};

export const decodeBase64URL = (value: string): Uint8Array => {
  if (!/^[A-Za-z0-9_-]+$/u.test(value)) throw new Error("invalid_base64url");
  const padded = value.replaceAll("-", "+").replaceAll("_", "/")
    + "=".repeat((4 - (value.length % 4)) % 4);
  const binary = atob(padded);
  return Uint8Array.from(binary, character => character.charCodeAt(0));
};

export const digest = async (value: string): Promise<string> =>
  encodeBase64URL(new Uint8Array(
    await crypto.subtle.digest("SHA-256", encoder.encode(value))
  ));

export const timingSafeEqual = (left: string, right: string): boolean => {
  const leftBytes = encoder.encode(left);
  const rightBytes = encoder.encode(right);
  let difference = leftBytes.byteLength ^ rightBytes.byteLength;
  const length = Math.max(leftBytes.byteLength, rightBytes.byteLength);
  for (let index = 0; index < length; index += 1) {
    difference |= (leftBytes[index] ?? 0) ^ (rightBytes[index] ?? 0);
  }
  return difference === 0;
};

export const hmac = async (keyValue: string, value: string): Promise<string> => {
  const keyBytes = decodeBase64URL(keyValue);
  if (keyBytes.byteLength !== 32) throw new Error("invalid_server_key");
  const key = await crypto.subtle.importKey(
    "raw", keyBytes, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  return encodeBase64URL(new Uint8Array(
    await crypto.subtle.sign("HMAC", key, encoder.encode(value))
  ));
};

export type EncryptedValue = { ciphertext: string; nonce: string };

export const encrypt = async (
  keyValue: string,
  plaintext: string
): Promise<EncryptedValue> => {
  const keyBytes = decodeBase64URL(keyValue);
  if (keyBytes.byteLength !== 32) throw new Error("invalid_server_key");
  const key = await crypto.subtle.importKey(
    "raw", keyBytes, "AES-GCM", false, ["encrypt"]
  );
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce }, key, encoder.encode(plaintext)
  );
  return {
    ciphertext: encodeBase64URL(new Uint8Array(ciphertext)),
    nonce: encodeBase64URL(nonce)
  };
};

export const decrypt = async (
  keyValue: string,
  encrypted: EncryptedValue
): Promise<string> => {
  const keyBytes = decodeBase64URL(keyValue);
  if (keyBytes.byteLength !== 32) throw new Error("invalid_server_key");
  const nonce = decodeBase64URL(encrypted.nonce);
  if (nonce.byteLength !== 12) throw new Error("invalid_nonce");
  const key = await crypto.subtle.importKey(
    "raw", keyBytes, "AES-GCM", false, ["decrypt"]
  );
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: nonce }, key, decodeBase64URL(encrypted.ciphertext)
  );
  return new TextDecoder().decode(plaintext);
};

export const requireCapability = (value: unknown): string => {
  if (typeof value !== "string") throw new Error("invalid_capability");
  const decoded = decodeBase64URL(value);
  if (decoded.byteLength !== 32) throw new Error("invalid_capability");
  return value;
};

export const hasValidServerKey = (value: unknown): value is string => {
  if (typeof value !== "string") return false;
  try {
    return decodeBase64URL(value).byteLength === 32;
  } catch {
    return false;
  }
};
