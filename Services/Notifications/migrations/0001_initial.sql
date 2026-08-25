PRAGMA foreign_keys = ON;

-- Household identifiers are random service identifiers, not names or
-- CloudKit record IDs. Authentication secrets are stored only as one-way
-- hashes; their plaintext values never enter D1.
CREATE TABLE notification_households (
    id TEXT PRIMARY KEY NOT NULL,
    admin_secret_hash TEXT NOT NULL,
    enrollment_secret_hash TEXT NOT NULL,
    state TEXT NOT NULL DEFAULT 'active'
        CHECK (state IN ('active', 'paused', 'revoked')),
    secret_generation INTEGER NOT NULL DEFAULT 1
        CHECK (secret_generation > 0),
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
) STRICT;

-- APNs device tokens are sensitive routing data. token_hash supports
-- idempotency; token_ciphertext and token_nonce hold only application-layer
-- encrypted values. Plain device tokens must never be written to D1 or logs.
CREATE TABLE notification_devices (
    id TEXT PRIMARY KEY NOT NULL,
    household_id TEXT NOT NULL,
    environment TEXT NOT NULL
        CHECK (environment IN ('sandbox', 'production')),
    token_hash TEXT NOT NULL,
    token_ciphertext TEXT NOT NULL,
    token_nonce TEXT NOT NULL,
    broadcasts_enabled INTEGER NOT NULL DEFAULT 1
        CHECK (broadcasts_enabled IN (0, 1)),
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'disabled', 'invalid', 'revoked')),
    app_build INTEGER CHECK (app_build IS NULL OR app_build >= 0),
    last_seen_at TEXT NOT NULL,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    FOREIGN KEY (household_id) REFERENCES notification_households(id)
        ON DELETE CASCADE,
    UNIQUE (household_id, environment, token_hash)
) STRICT;

CREATE INDEX notification_devices_household_status
    ON notification_devices (household_id, status, broadcasts_enabled);

-- Delivery receipts contain no alert title, body, person name, quest title,
-- device token, or APNs authentication material.
CREATE TABLE notification_delivery_receipts (
    id TEXT PRIMARY KEY NOT NULL,
    household_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    notification_id TEXT NOT NULL,
    category TEXT NOT NULL
        CHECK (category IN ('family_broadcast')),
    result TEXT NOT NULL
        CHECK (result IN ('queued', 'accepted', 'retryable', 'permanent_failure')),
    error_category TEXT,
    attempted_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    FOREIGN KEY (household_id) REFERENCES notification_households(id)
        ON DELETE CASCADE,
    FOREIGN KEY (device_id) REFERENCES notification_devices(id)
        ON DELETE CASCADE,
    UNIQUE (device_id, notification_id)
) STRICT;

CREATE INDEX notification_receipts_household_expiry
    ON notification_delivery_receipts (household_id, expires_at);

-- Single-use request identifiers provide bounded replay protection without
-- retaining request bodies or family content.
CREATE TABLE notification_request_nonces (
    household_id TEXT NOT NULL,
    nonce_hash TEXT NOT NULL,
    used_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    PRIMARY KEY (household_id, nonce_hash),
    FOREIGN KEY (household_id) REFERENCES notification_households(id)
        ON DELETE CASCADE
) STRICT;

CREATE INDEX notification_nonces_expiry
    ON notification_request_nonces (expires_at);
