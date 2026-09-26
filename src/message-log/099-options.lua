-- 099-options.lua — the undecided choices in the message-log module,
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
-- luajit src/message-log/tests/095-measure.lua "" stand-in 10000).  The
-- figures below are from the round-2 build on 2026-09-25, logs in RAM
-- (tmp/shared-memory), against the stand-in room-folders module (the real
-- round-2 one had not landed), 10,000 messages averaging 44.6 bytes of text
-- (short chat lines, some multi-line, some with tabs, some non-ASCII), a
-- third from "me" and the rest from "198.51.100.23 40404", every seventh one
-- arriving late.  "append" = filing all 10,000 one at a time, each with its
-- duplicate check and config reads; "read" = reading the whole log back;
-- "repeat" = delivering all 10,000 a second time (all answered duplicate,
-- each one compared field by field with the filed copy).
--
-- Removed in round 2 (answered by the owner, so no longer choices):
--   log-edits (never | corrections | window) — edits are always allowed,
--     with no time limit; log.edits and log.edit-window-seconds are gone.
--   log-repeated-id-different-content — the same id with different
--     contents is an error, naming both.

return {
    {
        id = "log-record-shape",
        question = "How is one message written in a room's log file: one tab-separated line, "
            .. "a small labelled block, or one JSON object per line?",
        waits_on = "owner",
        detail = "issue 105 open question 1 (planning question 8)",
        config_key = "log.record-shape",
        variants = {
            {
                name = "tsv",
                summary = "One line per message: id, from, written, arrived, kind, target, text, "
                    .. "separated by tabs; tabs, line breaks, CR and backslashes in the text written "
                    .. "as \\t \\n \\r \\\\.",
                built_in = "src/message-log/083-record-codecs.lua (codecs.tsv)",
                tests = { "src/message-log/tests/091-test-codecs.lua", "src/message-log/tests/092-test-log.lua",
                    "src/message-log/tests/095-measure.lua" },
                findings = {
                    "Smallest: 124.3 bytes per message (round 1 with contact-name authors: 115.7; "
                        .. "an address 'host port' is longer than a name).",
                    "Fastest to read: 10,000 messages in 0.03 s (read) / 0.05-0.06 s (ordered).",
                    "Filing 10,000: 0.62 s with the remembered duplicate check, 6.0-6.3 s with scan.",
                    "grep shows one whole message per hit, but multi-line text shows as \\n and a "
                        .. "literal backslash as \\\\, so grep for 'line one\\nline two' needs the escape.",
                    "Round-trips every byte value, random bytes, invalid UTF-8, NUL, empty text "
                        .. "(229 texts in the codec test).",
                },
            },
            {
                name = "block",
                summary = "Labelled lines (id:, from:, written:, arrived:, kind:, target:, text:), "
                    .. "the text's lines each indented two spaces, a blank line after each message.",
                built_in = "src/message-log/083-record-codecs.lua (codecs.block)",
                tests = { "src/message-log/tests/091-test-codecs.lua", "src/message-log/tests/092-test-log.lua",
                    "src/message-log/tests/095-measure.lua" },
                findings = {
                    "174.0 bytes per message (the labels).",
                    "Reads 10,000 in 0.05-0.08 s (ordered 0.05-0.09 s).",
                    "Scan duplicate check is slowest here: 11.9 s to file 10,000 (the id marker "
                        .. "starts with a line break and a block record has about nine lines, so "
                        .. "the plain search stops at nine times as many candidate places); 0.62 s "
                        .. "with remembered.",
                    "Easiest to read in less: multi-line text looks like itself.  grep hits only "
                        .. "the matching line, not the whole message (grep -B needed for the address).",
                    "Text lines are always indented, so no text can pose as a label or end a "
                        .. "record early; tested with text 'id: fake\\n\\nid: other'.",
                },
            },
            {
                name = "jsonl",
                summary = "One JSON object per line, keys in the fixed order id, from, written, "
                    .. "arrived, kind, target, text (dkjson 2.5, bundled in libs/).",
                built_in = "src/message-log/083-record-codecs.lua (codecs.jsonl), libs/dkjson.lua",
                tests = { "src/message-log/tests/091-test-codecs.lua", "src/message-log/tests/092-test-log.lua",
                    "src/message-log/tests/095-measure.lua" },
                findings = {
                    "Largest: 191.3 bytes per message (quoted key names on every line).",
                    "Slowest to read: 0.11-0.16 s for 10,000 (ordered 0.12-0.18 s), even with "
                        .. "dkjson using lpeg.",
                    "Filing 10,000: 0.86 s remembered, 11.2 s scan.",
                    "Any JSON tool (jq) can read it; control characters show as \\u0000.",
                    "Bytes that are not valid UTF-8 pass through dkjson unchanged, so round trips "
                        .. "hold, but the file is then not strictly valid JSON for other tools.",
                    "Brings a 715-line library into the project (MIT licence).",
                },
            },
        },
        leaning = "tsv: smallest and fastest, one message per grep hit, and the escapes are the "
            .. "only thing a reader has to learn; block if reading logs in less matters more than "
            .. "grep.  jsonl buys tool compatibility the project does not need yet.",
    },
    {
        id = "log-who-may-edit",
        question = "Who may correct or delete a message, now that its writer cannot be known: any "
            .. "edit naming it, or only an edit that arrived from the same address as the message?",
        waits_on = "owner",
        detail = "issue 105 open question 2 (found while rewriting for 'a room is a contact')",
        config_key = "log.who-may-edit",
        variants = {
            {
                name = "anyone",
                summary = "Any correction or deletion naming a message in the room is filed; the "
                    .. "original always stays in the file, and the room view names the address "
                    .. "the change came from (changed_from).",
                built_in = "src/message-log/086-edits.lua (WHO_MAY_EDIT.anyone, edits.apply)",
                tests = "src/message-log/tests/093-test-edits.lua",
                findings = {
                    "Matches the owner's words: 'Everything is edit-able by design with no record, "
                        .. "so nothing can be trusted unless you make local copies yourself' — the "
                        .. "log is that local copy, and every version stays in it (cat shows them).",
                    "A member can rewrite what another member's message shows; changed_from lets "
                        .. "a client mark 'edited from another address', which is the only honest "
                        .. "signal there is.",
                },
            },
            {
                name = "same-address",
                summary = "An edit is filed only when its from equals the message's from ('me' edits "
                    .. "only 'me'); otherwise refused with an error naming both addresses.",
                built_in = "src/message-log/086-edits.lua (WHO_MAY_EDIT['same-address'])",
                tests = "src/message-log/tests/093-test-edits.lua",
                findings = {
                    "Proves nothing: an address can be shared, moved or put through Tor, so this "
                        .. "narrows rather than protects.  A member who moves can no longer edit "
                        .. "their earlier messages.",
                    "Governs filing only: edits already filed (for example under anyone, before "
                        .. "the switch) are still shown; tested.",
                    "In phase 2 the same address sends every member's copy, so every reader "
                        .. "reaches the same decision.",
                },
            },
        },
        leaning = "anyone: it is what the owner described, it keeps every version, and "
            .. "same-address adds a check that proves nothing.",
    },
    {
        id = "log-shape-mixing",
        question = "If the record shape is changed on a home that already has logs, may one log hold "
            .. "records of more than one shape?",
        waits_on = "owner",
        detail = "issue 105 open question 3",
        config_key = "log.shape-mixing",
        variants = {
            {
                name = "per-record",
                summary = "Each record is recognised by its first characters ('{' = jsonl, 'id:' = "
                    .. "block, anything else = tsv); a log may hold all three.",
                built_in = "src/message-log/084-log-reader.lua (SHAPE_PICKERS), "
                    .. "src/message-log/083-record-codecs.lua (codecs.detect)",
                tests = "src/message-log/tests/094-test-mixing-and-memory.lua",
                findings = {
                    "Works because ids may hold only letters, digits, '-' and '_' (no ':' or '{'), "
                        .. "so the three shapes cannot be confused.",
                    "Changing log.record-shape just changes how new records are written; nothing "
                        .. "is ever rewritten; all 6 shape pairs tested in both directions, including "
                        .. "comparing a repeat against a record in the old shape.",
                    "Duplicate scan must search for all three id markers: 18.9 s vs "
                        .. "11.9 s to file 10,000 block records; no measurable cost with remembered.",
                },
            },
            {
                name = "fixed",
                summary = "Every record must be in the configured shape; a record in another shape "
                    .. "makes the log unreadable with an error naming both shapes.",
                built_in = "src/message-log/084-log-reader.lua (SHAPE_PICKERS)",
                tests = "src/message-log/tests/094-test-mixing-and-memory.lua",
                findings = {
                    "Changing log.record-shape on a home with messages makes every existing room "
                        .. "unreadable until it is changed back; no converter is built (round 1's "
                        .. "copy_log, which could have been one, is retired).",
                },
            },
        },
        leaning = "per-record: the file stays append-only through a change of mind, and the "
            .. "detection is exact, not a guess.",
    },
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
                    "src/message-log/tests/094-test-mixing-and-memory.lua", "src/message-log/tests/095-measure.lua" },
                findings = {
                    "Filing 10,000: 0.62 s tsv, 0.62 s block, 0.86 s jsonl; does not grow "
                        .. "with log size.  Delivering all 10,000 again: 0.40 s (tsv), all "
                        .. "answered duplicate after comparing contents.",
                    "Round 2 keeps whole records, not just ids, so a repeat can be compared with "
                        .. "what was filed: memory grows with the log's text (about the file's size).",
                    "Sees, and compares against, records another program appended.",
                    "Notices a replaced or emptied file by checking the first 64 bytes and the 64 "
                        .. "bytes before where it stopped; then starts over.",
                    "Only helps a long-running program: a program started per delivery would "
                        .. "read the whole log on its first check, the same as scan.",
                },
            },
            {
                name = "scan",
                summary = "Read the whole log each time, search it for the id's marker text (which can "
                    .. "only occur where that record starts), and decode just that record to compare.",
                built_in = "src/message-log/085-duplicate-check.lua (scan), "
                    .. "src/message-log/084-log-reader.lua (parse_one)",
                tests = { "src/message-log/tests/092-test-log.lua", "src/message-log/tests/095-measure.lua" },
                findings = {
                    "Nothing kept, nothing can go stale.",
                    "Cost grows with the log: filing 10,000 one by one took 6.0-6.3 s (tsv), "
                        .. "11.9 s (block), 11.2 s (jsonl) — about 1 ms per message once "
                        .. "a log holds 10,000.",
                    "Comparing a repeat costs one extra record decode: delivering all 10,000 again "
                        .. "took 3.8-4.0 s (tsv).",
                    "At chat speed (a few messages a minute) 1 ms is nothing; it matters for "
                        .. "catch-up after being offline and for the cross-check (phase 2).",
                },
            },
        },
        leaning = "remembered for the home server if it is one long-running program; the numbers "
            .. "say no on-disk index is needed at 10,000 messages either way.",
    },
    {
        id = "log-same-id-new-address",
        question = "A repeated message id whose contents match the filed copy but which arrived from "
            .. "a different address: answer 'duplicate', or raise an error?",
        waits_on = "owner",
        detail = "issue 105 open question 8 (found while building the contents comparison); the "
            .. "key is read only when this case happens",
        config_key = "log.same-id-new-address",
        variants = {
            {
                name = "duplicate",
                summary = "Contents (written, kind, target, text) decide; the address it came from "
                    .. "does not.  The first copy's from stays in the file.",
                built_in = "src/message-log/081-message-log.lua (NEW_ADDRESS.duplicate, same_id)",
                tests = "src/message-log/tests/092-test-log.lua",
                findings = {
                    "Honest cases exist: a member whose address changed resends, or a missing "
                        .. "message is fetched from another member during the periodic cross-check "
                        .. "(phase 2), so its copy arrives from that member's address.",
                },
            },
            {
                name = "error",
                summary = "Raise an error naming both addresses and both versions; file nothing.",
                built_in = "src/message-log/081-message-log.lua (NEW_ADDRESS.error, same_id)",
                tests = "src/message-log/tests/092-test-log.lua",
                findings = {
                    "Would raise on every message obtained through the cross-check, since that "
                        .. "copy comes from whoever had it.",
                    "The address proves nothing about who wrote the message, so the error "
                        .. "signals a route change, not a forgery.",
                },
            },
        },
        leaning = "duplicate: the owner's error rule is about differing contents, and the "
            .. "address is not contents.",
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
                    "Every shape already carries arbitrary bytes, so a small picture could ride in "
                        .. "the text field, but tsv would escape it and jsonl would bloat it; a "
                        .. "picture would more likely be a file beside the log, named by message id.",
                },
            },
        },
        leaning = "text only in phase 1; decide with the owner before phase 2's wire format.",
    },
    {
        id = "log-deleted-view",
        question = "When a message is deleted, does the room still show a place for it "
            .. "(empty, marked deleted), or does it vanish from the room?",
        waits_on = "owner",
        detail = "issue 105 open question 5",
        config_key = "",
        variants = {
            {
                name = "marked-empty",
                summary = "The deleted message stays in the room view with no text, deleted = true, "
                    .. "and changed_from naming the deletion's address.",
                built_in = "src/message-log/086-edits.lua (edits.apply)",
                tests = "src/message-log/tests/093-test-edits.lua",
                findings = {
                    "A link to the message's anchor (a notice, a search result) still lands on it.",
                    "Either way the original text stays in the log file (append-only), so "
                        .. "deleting hides a message, it does not erase it; cat still shows it.",
                },
            },
            {
                name = "vanish",
                summary = "Not built: leave deleted messages out of read_ordered.",
                built_in = "",
                tests = "",
                findings = "One line in edits.apply; not built because anchors pointing at it would break.",
            },
        },
        leaning = "marked-empty, and tell the owner plainly that deletion is not erasure.",
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
                    .. "so filing it early would be safe for readers.  Under same-address the rule "
                    .. "could then only be checked when the message arrives.",
            },
        },
        leaning = "in phase 2, file edits that arrive early.",
    },
}
