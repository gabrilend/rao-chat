-- 185-settings.lua — every config setting name the device server reads
-- (issue 302), handed to 017's declared-settings reader.  Plain data.
--
-- devices.port — the home's device port, where its paired phones and
--   browsers connect: a whole number 1 to 65535, never a mailbox's port.
--   No default ("no default port numbers").
-- devices.address — the address the device port listens on, or `any`.
--   No default.
-- devices.frame-deadline — whole seconds a connection has to deliver one
--   whole frame, counted from when the server starts waiting for it.  No
--   default; at least 1.
-- devices.idle-limit — whole seconds a device's connection may be quiet
--   (no frame begun) after its first frame before the home closes it
--   (issue 306).  No default; at least 1.

return {
    "devices.port",
    "devices.address",
    "devices.frame-deadline",
    "devices.idle-limit",
}
