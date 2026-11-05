-- 165-settings.lua — every config setting name the gatherer reads (issue
-- 211), handed to 101's config reader (contract, "Settings: every name is
-- declared").  Plain data: 101 reads this file by scanning src/.
--
-- gatherer.ram-root — an absolute folder under which each home gets its
--   RAM folder (`<home folder's name>-<12 hex>`), and in it one folder per
--   mailbox.  No default; /dev/shm/rao-chat is the first variant.  When it
--   cannot be made, /tmp/rao-chat-ram is used and the starter says so.
-- gatherer.sync-interval — whole seconds between one sync of RAM to disk
--   and the next.  No default; at least 1.
-- gatherer.acknowledge-after — `disk` or `ram`: which write comes before
--   a frame is answered (open question 1, built both ways).  No default.
-- gatherer.address — the address every mailbox of the home listens on
--   and sends from, or `any`.  No default.  (Three homes on one machine
--   use 127.0.0.2, .3, .4: 210's rubric.)
-- gatherer.connection-limit — how many connections one gatherer holds
--   open at once; at the limit, a new one closes the one held longest
--   (open question 6).  No default; at least 1.
-- gatherer.frame-deadline — whole seconds a connection has to deliver one
--   whole frame, from its first byte or from the last answer (open
--   question 8).  No default; at least 1.

return {
    "gatherer.ram-root",
    "gatherer.sync-interval",
    "gatherer.acknowledge-after",
    "gatherer.address",
    "gatherer.connection-limit",
    "gatherer.frame-deadline",
}
