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
-- callback.answer-time — whole seconds: how long a call-back check waits
--   for the stated pair's answer before the claim stays unconfirmed for
--   now (142, 204).  No default; at least 1.
-- address.recheck-earliest — whole seconds: the soonest the public address
--   is checked again after a check that got an answer (150, 212).  No
--   default; at least 1.
-- address.recheck-latest — whole seconds: the latest; each wait is drawn
--   between the two from the kernel's random source (150, 212).  No
--   default; at least address.recheck-earliest.
-- address.hostname — a hostname the person has for the home, stated in
--   hellos with each mailbox's outside port, or `none` (149, 212).
--   No default.
-- crosscheck.interval — whole seconds between one cross-check of every
--   room and the next: a summary, after 207's members digest, to every
--   pair on each send list (156, 209).  No default; at least 1.
-- crosscheck.window — whole seconds: how far back, by written time, a
--   summary lists the messages held (156, 209).  No default; at least 1.

return {
    "delivery.retry-floor",
    "delivery.retry-ceiling",
    "failed-decryption.file-size",
    "failed-decryption.files-kept",
    "callback.answer-time",
    "address.recheck-earliest",
    "address.recheck-latest",
    "address.hostname",
    "crosscheck.interval",
    "crosscheck.window",
}
