-- 135-settings.lua — every config setting name the delivery module reads,
-- handed to 101's config reader (contract, "Settings: every name is
-- declared").  Plain data: 101 reads this file by scanning src/.
--
-- delivery.retry-floor   — whole seconds: the first wait after a failed
--   attempt (131).  No default; rmail's 30 is a starting value.
-- delivery.retry-ceiling — whole seconds: the longest wait (131).  No
--   default; rmail's 7200 is a starting value.
-- failed-decryption.file-size  — bytes: a new failed-decryption file
--   starts before a line would carry the current one past this (139, 203).
--   No default; at least 1024.
-- failed-decryption.files-kept — how many failed-decryption files are kept
--   in all, the newest included (139, 203).  No default; at least 1.

return {
    "delivery.retry-floor",
    "delivery.retry-ceiling",
    "failed-decryption.file-size",
    "failed-decryption.files-kept",
}
