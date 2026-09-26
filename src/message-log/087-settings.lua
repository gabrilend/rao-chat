-- 087-settings.lua — every config setting name the message-log module
-- reads, handed to 101's config reader (contract, "Settings: every name is
-- declared").
--
-- The home's config file may hold only lines whose names some module
-- declares; a line nobody declares is an error when the home is opened.
-- That rule answered the log's round-3 question about retired settings
-- (log.record-shape, log.who-may-edit, log.shape-mixing,
-- log.same-id-new-address): they are simply not in this list, so a home
-- still naming one is refused with the line quoted, instead of the line
-- silently no longer applying.  Plain data: 101 reads this file by
-- scanning src/, nothing here runs.
--
-- log.duplicate-check — how a repeat is found (remembered | scan); read by
--   append, correct, delete and has_message.  Still an open choice
--   (099-options.lua, waits on phase 2).

return {
    "log.duplicate-check",
}
