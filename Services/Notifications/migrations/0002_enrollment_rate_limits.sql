PRAGMA foreign_keys = ON;

-- Keys are HMAC-derived, short-lived buckets. Raw IP addresses, authorization
-- values, household content, and request bodies are never retained.
CREATE TABLE notification_rate_limits (
    bucket_key TEXT PRIMARY KEY NOT NULL,
    request_count INTEGER NOT NULL DEFAULT 1
        CHECK (request_count > 0),
    expires_at TEXT NOT NULL
) STRICT;

CREATE INDEX notification_rate_limits_expiry
    ON notification_rate_limits (expires_at);
