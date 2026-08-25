PRAGMA foreign_keys = ON;

ALTER TABLE notification_devices ADD COLUMN device_secret_hash TEXT;

CREATE TABLE notification_pairing_codes (
    code_hash TEXT PRIMARY KEY NOT NULL,
    household_id TEXT NOT NULL,
    created_at TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    used_at TEXT,
    FOREIGN KEY (household_id) REFERENCES notification_households(id)
        ON DELETE CASCADE
) STRICT;

CREATE INDEX notification_pairing_codes_expiry
    ON notification_pairing_codes (expires_at, used_at);
