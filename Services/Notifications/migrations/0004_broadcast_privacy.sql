ALTER TABLE notification_devices
    ADD COLUMN show_broadcast_details INTEGER NOT NULL DEFAULT 0
    CHECK (show_broadcast_details IN (0, 1));
