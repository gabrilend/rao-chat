-- 099-options.lua — the choices in the message-log module still open,
-- written down for the options tally (scripts/tally-options, issue 106).
--
-- Each entry is one question the owner (or some later state of the project)
-- has to settle.  Every variant listed is built and tested; the home's
-- config file picks the one in use.  The first variant listed is the one
-- the phase 1 demo starts its homes with, so the builder's leaning is
-- listed first.  The findings are what building, testing and measuring
-- each variant showed.  Plain data: nothing here runs.
--
-- Measurements come from tests/095-measure.lua (run it for fresh numbers:
-- luajit src/message-log/tests/095-measure.lua "" real 10000).  The
-- figures below are from the round-3 build on 2026-09-25, logs in RAM
-- (tmp/shared-memory), against the real round-3 room-folders module (the
-- stand-in gives the same figures within 10%), 10,000 messages averaging 44.6 bytes of text (short
-- chat lines, some multi-line, some with tabs, some non-ASCII), a third
-- from "me" and the rest from "198.51.100.23 40404", every seventh one
-- arriving late, record shape tsv (124.3 bytes per message).  "filing" =
-- all 10,000 one at a time, each with its duplicate check and config read;
-- "delivering again" = all 10,000 a second time, each compared field by
-- field with the filed copy and answered duplicate.
--
-- Removed in round 2 (answered by the owner, so no longer choices):
--   log-edits (never | corrections | window) — edits are always allowed,
--     with no time limit; log.edits and log.edit-window-seconds are gone.
--   log-repeated-id-different-content — the same id with different
--     contents is an error, naming both.
-- Removed in round 3 (answered 2026-09-25; the built variants that lost
-- are in git history):
--   log-record-shape — tsv.  The block and jsonl codecs, and the bundled
--     JSON library libs/dkjson.lua that only jsonl used, are deleted; the
--     key log.record-shape is no longer read.  The codec table stays a
--     table (083-record-codecs.lua), so a shape can be added back.
--   log-shape-mixing (per-record | fixed) — with one shape there is
--     nothing to mix; recognising a record's shape by its first characters
--     is deleted with it, and log.shape-mixing is no longer read.
--   log-who-may-edit — anyone.  The same-address rule is deleted and
--     log.who-may-edit is no longer read; the room view names the address
--     each change came from (changed_from).
--   log-same-id-new-address — duplicate.  The error variant is deleted and
--     log.same-id-new-address is no longer read.
--   log-deleted-view — the person chooses, in the client.  The log keeps a
--     deleted message in the view, empty and marked (built); nothing is
--     left open here.

return {
    {
        id = "log-duplicate-check",
        question = "To recognise a repeated delivery, does the log search the whole file each time, "
            .. "or keep what it has seen in memory?",
        waits_on = "state",
        detail = "issue 105 open question 4: waits on phase 2 — whether the home server is one "
            .. "long-running program (memory lasts) or started per delivery (memory is empty each time)",
        config_key = "log.duplicate-check",
        variants = {
            {
                name = "remembered",
                summary = "Keep each log's records (by id) in the program's memory with how far the "
                    .. "file has been read; each check reads only what was added since.  Nothing on disk.",
                built_in = "src/message-log/085-duplicate-check.lua (remembered)",
                tests = { "src/message-log/tests/092-test-log.lua",
                    "src/message-log/tests/094-test-memory.lua", "src/message-log/tests/095-measure.lua" },
                findings = {
                    "Filing 10,000: 0.42 s; does not grow with log size.  Delivering all "
                        .. "10,000 again: 0.26 s, all answered duplicate after comparing contents.",
                    "Keeps whole records, not just ids, so a repeat can be compared with "
                        .. "what was filed: memory grows with the log's text (about the file's size).",
                    "Sees, and compares against, records another program appended.",
                    "Notices a replaced or emptied file by checking the first 64 bytes and the 64 "
                        .. "bytes before where it stopped; then starts over.",
                    "Only helps a long-running program: a program started per delivery would "
                        .. "read the whole log on its first check, the same as scan.",
                    "Decodes every record it has not seen yet, so a damaged line anywhere in "
                        .. "the log (for example a record left in a retired shape) is an error "
                        .. "at the next filing; tested.",
                },
            },
            {
                name = "scan",
                summary = "Read the whole log each time, search it for the id's marker text (which can "
                    .. "only occur where that record starts), and decode just that record to compare.",
                built_in = "src/message-log/085-duplicate-check.lua (scan), "
                    .. "src/message-log/084-log-reader.lua (parse_one)",
                tests = { "src/message-log/tests/092-test-log.lua",
                    "src/message-log/tests/094-test-memory.lua", "src/message-log/tests/095-measure.lua" },
                findings = {
                    "Nothing kept, nothing can go stale.",
                    "Cost grows with the log: filing 10,000 one by one took 5.7 s — about "
                        .. "1 ms per message once a log holds 10,000.",
                    "Comparing a repeat costs one extra record decode: delivering all 10,000 again "
                        .. "took 3.6 s.",
                    "Decodes only the record its id marker points at, so a damaged line "
                        .. "elsewhere in the log is not noticed when filing (only when the log is "
                        .. "next read); tested.",
                    "At chat speed (a few messages a minute) 1 ms is nothing; it matters for "
                        .. "catch-up after being offline and for the cross-check (phase 2).",
                },
            },
        },
        leaning = "remembered for the home server if it is one long-running program; the numbers "
            .. "say no on-disk index is needed at 10,000 messages either way.",
    },
    {
        id = "log-pictures",
        question = "What a message can hold: text only, with pictures and files left to rmail, "
            .. "or small pictures in chat too?",
        waits_on = "owner",
        detail = "issue 105 open question 7 (planning question 9)",
        config_key = "",
        variants = {
            {
                name = "text-only",
                summary = "The only thing built: a message's text is any bytes, nothing else.",
                built_in = "src/message-log/083-record-codecs.lua",
                tests = "src/message-log/tests/091-test-codecs.lua",
                findings = {
                    "The tsv record already carries arbitrary bytes, so a small picture could ride "
                        .. "in the text field, but every tab, line break and backslash in it would be "
                        .. "escaped and the line would be unreadable in less; a picture would more "
                        .. "likely be a file beside the log, named by message id.",
                },
            },
        },
        leaning = "text only in phase 1; decide with the owner before phase 2's wire format.",
    },
    {
        id = "log-early-edits",
        question = "What happens to a correction or deletion that arrives before the message it changes?",
        waits_on = "state",
        detail = "issue 105 open question 6: needs phase 2 (delivery between home servers), where "
            .. "arrival order is not written order",
        config_key = "",
        variants = {
            {
                name = "refuse",
                summary = "Phase 1: an edit naming an id not in the log is refused when filed.",
                built_in = "src/message-log/086-edits.lua (find_target)",
                tests = "src/message-log/tests/093-test-edits.lua",
                findings = "Correct while all edits are made locally; in phase 2 it would drop an edit "
                    .. "whose message is still on its way.  Reading already leaves such an edit out "
                    .. "and applies it once its message is filed (tested with a hand-appended edit), "
                    .. "so filing it early would be safe for readers.",
            },
        },
        leaning = "in phase 2, file edits that arrive early.",
    },
    {
        id = "log-retired-keys-in-config",
        question = "A home whose config still names a retired log key (log.record-shape = block, "
            .. "log.who-may-edit = same-address, ...) from an earlier build: ignore the line, or "
            .. "refuse to start until it is removed?",
        waits_on = "owner",
        detail = "issue 105 open question 9 (found in round 3, when four log keys stopped being "
            .. "read); the config file is 101's, so a check for every module would live there",
        config_key = "",
        variants = {
            {
                name = "ignore",
                summary = "Built: the log reads only log.duplicate-check; any other log.* line in "
                    .. "config is never looked at.",
                built_in = "src/message-log/081-message-log.lua",
                tests = "src/message-log/tests/093-test-edits.lua",
                findings = {
                    "A home set to log.who-may-edit = same-address before round 3 now accepts "
                        .. "edits from any address with no word said; tested.",
                    "A home set to log.record-shape = block or jsonl before round 3 holds logs "
                        .. "the tsv reader refuses loudly (\"fields, wanted 7\"), so a shape "
                        .. "change cannot pass unnoticed; tested.",
                },
            },
            {
                name = "refuse",
                summary = "Not built: the log (or 101's config reader, for every module) raises an "
                    .. "error naming a retired key when it is present in config.",
                built_in = "",
                tests = "",
                findings = "Would turn the silent change above into an error the person sees once, "
                    .. "matching the house rule that fallbacks are errors; needs a list of retired "
                    .. "keys somewhere every module can add to.",
            },
        },
        leaning = "refuse, in 101's config reader, so every module's retired keys are caught in one "
            .. "place; ask the owner.",
    },
}
