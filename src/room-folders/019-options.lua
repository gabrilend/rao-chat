-- 019-options.lua — the undecided choices found while building room-folders,
-- written down for the options tally (scripts/tally-options, issue 106).
--
-- Each entry is one question the owner (or some later state of the
-- project) has to settle.  Where a choice is switchable, every variant is
-- built and the home's config file picks the one in use, read with no
-- default.  The first variant listed is the one the phase 1 demo starts
-- its homes with, so the builder's leaning is listed first.  "findings"
-- are what building and testing each variant showed.
-- Plain data: nothing here runs.
--
-- Retired in round 2 (they belonged to the first model, where rooms were
-- named by ids that travelled and by names that went into paths):
-- rooms-unknown-parent (a parent held nowhere is now simply a top room,
-- decided by the new model) and rooms-slash-in-name (labels are the
-- reader's own and may hold any text but a line break).

return {
    {
        id = "rooms-suggested-token-words",
        question = "How many words should a suggested room token have? (Tokens may be any text; this is "
            .. "only what rao-chat offers, e.g. 'maple-orbit-velvet-tin'.)",
        waits_on = "owner",
        detail = "issue 101 open question 3 (planning section 15, answered question 4: suggest readable "
            .. "tokens, never restrict them); the list is the EFF large word list, 7,772 words",
        config_key = "rooms.suggested-token-words",
        variants = {
            {
                name = "6",
                summary = "Six random words: about 77.5 bits.",
                built_in = "src/room-folders/002-room-folders.lua (suggest_token) + 007-tokens.lua (suggest_token_of)",
                tests = "tests/010-test-tokens.lua ('every variant of rooms.suggested-token-words')",
                findings = {
                    "A room's safety against strangers is only its token (planning section 5: 'a room is as "
                        .. "private as its token is hard to guess'), and anyone who records sealed traffic, or "
                        .. "sees a child room's invitation (which carries the parent's fingerprint), can guess "
                        .. "offline without asking anyone: two SHA-256 per guess against a fingerprint.",
                    "Measured here: LuaJIT + libcrypto makes about 775,000 fingerprints a second on one CPU "
                        .. "core. Assumed, not measured: one modern GPU does about 5 billion a second. At that "
                        .. "rate the expected time to find a six-word token is about 700,000 years for one GPU.",
                    "Example length: 'overstock-yam-setback-praying-tin-orbit' — about 40 characters; still "
                        .. "readable aloud in one breath or two.",
                },
            },
            {
                name = "5",
                summary = "Five random words: about 64.6 bits.",
                built_in = "same code; config value 5",
                tests = "tests/010-test-tokens.lua",
                findings = "At the assumed 5 billion guesses a second: about 90 years for one GPU, about "
                    .. "33 days for a thousand GPUs working together — enough against a curious stranger, "
                    .. "not against someone who rents a large GPU farm for a month.",
            },
            {
                name = "4",
                summary = "Four random words: about 51.7 bits (the example the owner was shown).",
                built_in = "same code; config value 4",
                tests = "tests/010-test-tokens.lua",
                findings = "At the assumed rate: about 4 days for one GPU. The issue's first estimate (four "
                    .. "words from 2,048 = 44 bits, 'hard to guess by hand') holds against guessing by hand, "
                    .. "but a token here is guessed by machine against recorded traffic, where 4 words is weak.",
            },
        },
        leaning = "6: the token is the room's only lock and is attacked offline, so each extra word is cheap "
            .. "for the person and costly for the guesser. Any whole number >= 1 is accepted by the key, so "
            .. "the owner can pick another count without code changes.",
    },
    {
        id = "rooms-bell-failure",
        question = "When a module listening on the change bell fails after a room was written (say its "
            .. "people/ links cannot be built), should the room change stay, or be undone?",
        waits_on = "owner",
        detail = "issue 101 open question 1",
        config_key = "",
        variants = {
            {
                name = "keep-and-raise",
                summary = "The write stays on disk; the listener's error reaches whoever made the change.",
                built_in = "src/room-folders/005-change-bell.lua (notify) — the only variant built",
                tests = "tests/012-test-change-bell.lua ('a listener's failure reaches the writer; the change "
                    .. "is kept', 'a listener failing on created')",
                findings = "Simple and loud: the caller learns at once. The home is left with the room changed "
                    .. "and some summaries (where files, people/ links) not matching it until something rings "
                    .. "again. Listeners earlier in the list have already acted. With a token change, the "
                    .. "children are re-pointed and rung before 'token', so a failure on one child leaves the "
                    .. "new token written and later children not yet re-pointed (they then read as top rooms).",
            },
            {
                name = "undo-and-raise",
                summary = "Put the old file back (or remove a new room) before passing the error on.",
                built_in = "not built",
                tests = "none",
                findings = "Not built: undoing would need the listeners that already ran to undo too (a second "
                    .. "ring with the old value), and a second failure during the undo has no good answer.",
            },
        },
        leaning = "keep-and-raise for phase 1; revisit if a listener is found that fails for ordinary "
            .. "reasons rather than on damaged or refused data.",
    },
    {
        id = "rooms-write-durability",
        question = "Should room files survive a power cut, not just a crash (fsync before rename)?",
        waits_on = "state",
        detail = "issue 101 open question 2; waits on phase 6 (running as a service) measuring the cost "
            .. "of forcing each write to disk",
        config_key = "",
        variants = {
            {
                name = "rename-only",
                summary = "Write a temporary file, then rename it over the old one.",
                built_in = "src/room-folders/003-disk.lua (write_atomic) — the only variant built",
                tests = "tests/011-test-home-and-rooms.lua (no half-built folder left; refused rooms leave "
                    .. "nothing)",
                findings = "A crashed program leaves either the old file or the new, never half. After a power "
                    .. "cut the filesystem may hold the renamed file with no contents yet. Round 2 moved the "
                    .. "last-heard time into the entry (heard[N]), so the entry is now rewritten whenever a "
                    .. "member is heard from anew: the number of writes to measure grows with traffic.",
            },
            {
                name = "fsync-then-rename",
                summary = "Also force the file's bytes to disk before the rename (and the folder after).",
                built_in = "not built",
                tests = "none",
                findings = "Not built: needs file descriptors through LuaJIT's ffi (open/write/fsync) instead "
                    .. "of io.open, and costs a disk flush per write.",
            },
        },
        leaning = "rename-only until phase 6 measures the cost of fsync on a real home server.",
    },
    {
        id = "rooms-rmail-contacts",
        question = "A direct message is exactly an rmail contact. Keep rao-chat's entries in their own "
            .. "room folders, or read direct messages straight from rmail's contacts file?",
        waits_on = "owner",
        detail = "issue 101 open question 4; planning section 13 questions 6 and 7",
        config_key = "",
        variants = {
            {
                name = "own-folders",
                summary = "Every room, direct messages included, is rooms/<tag>/entry in rmail's format.",
                built_in = "src/room-folders/002-room-folders.lua, 006-entry.lua — the only variant built",
                tests = "tests/009-test-formats-and-entry.lua ('two entries joined are one valid contacts "
                    .. "file'), tests/011-test-home-and-rooms.lua",
                findings = "Because each entry is named by its tag, `cat rooms/*/entry` is a valid rmail "
                    .. "contacts file, so the two can meet later without converting. What differs from "
                    .. "rmail: entries carry heard[N] and kind/parent/filed-under, which rmail would read as "
                    .. "unknown fields, and they refuse rmail's plain ip/port (a default port).",
            },
            {
                name = "read-rmail-contacts",
                summary = "Direct messages are read from (and written to) rmail's own contacts file.",
                built_in = "not built",
                tests = "none",
                findings = "Not built: rmail lets an address fall back to a default port, which rao-chat "
                    .. "refuses, so an rmail contacts file with such a contact could not be read as-is; the "
                    .. "reader for it exists (004-rmail-formats.address_pairs reads plain ip/port as pair 0 "
                    .. "and refuses a missing port). Two programs writing one file would also need locking.",
            },
        },
        leaning = "own-folders for phase 1: one code path for every room; the rmail link is planned for "
            .. "after rao-chat is complete (planning section 10).",
    },
    {
        id = "rooms-token-change-children",
        question = "When a room's token is changed by hand, what happens to child rooms that name it (by "
            .. "the old token's fingerprint) as their parent?",
        waits_on = "owner",
        detail = "issue 101: new (round 2); a child names its parent by fingerprint, and the fingerprint "
            .. "changes with the token",
        config_key = "",
        variants = {
            {
                name = "repoint-held",
                summary = "Children held on this home are re-pointed to the new fingerprint at once.",
                built_in = "src/room-folders/002-room-folders.lua (change_token) — the only variant built",
                tests = "tests/011-test-home-and-rooms.lua ('the children held here follow'), "
                    .. "tests/012-test-change-bell.lua ('change_token rings parent for each held child, then token')",
                findings = {
                    "Your own tree stays whole. But every OTHER member's home still has the children naming "
                        .. "the old fingerprint: until they are given the new token by hand and enter it, "
                        .. "their copies of the children show as top rooms, and 102's parent-membership check "
                        .. "on their homes then has no parent to check against.",
                    "The person shut out still holds the child rooms' own tokens: changing the parent's "
                        .. "token does not shut them out of the children. Each child's token must be changed too.",
                },
            },
            {
                name = "leave-children",
                summary = "Children keep the old fingerprint; they read as top rooms until re-pointed by hand.",
                built_in = "not built",
                tests = "none",
                findings = "Not built: would break this home's own tree on every token change for no gain.",
            },
        },
        leaning = "repoint-held; and phase 2 might carry 'parent changed from X to Y' to members, sealed "
            .. "with the new token, so their children follow when they enter it.",
    },
    {
        id = "rooms-heard-in-entry",
        question = "Where does a member address's last-heard time live: in the entry beside its address, "
            .. "or in a separate per-room file?",
        waits_on = "owner",
        detail = "issue 101 open question 6 (new, round 2; 103 records the time so a client can offer "
            .. "pruning of silent members)",
        config_key = "",
        variants = {
            {
                name = "in-entry",
                summary = "heard[N] beside ip[N]/port[N] in the entry; its own bell kind 'heard'.",
                built_in = "src/room-folders/006-entry.lua, 002-room-folders.lua (write_heard) — the only variant built",
                tests = "tests/011-test-home-and-rooms.lua ('write_heard ...'), tests/013-test-with-neighbours.lua "
                    .. "('103: heard_from reaches 101's heard[N]')",
                findings = "One file says everything about a member, and an address can never lose its time "
                    .. "(they are written together). Cost: the entry is rewritten whenever a member is heard "
                    .. "from later than before (103 writes only when the time moves forward), so the entry is "
                    .. "no longer a file that changes only when a person edits the room; the 'heard' bell "
                    .. "kind keeps people/ from rebuilding on each one.",
            },
            {
                name = "separate-file",
                summary = "rooms/<tag>/heard, one 'address port seconds' line per member (103's first proposal).",
                built_in = "not built",
                tests = "none",
                findings = "Not built: 103 withdrew the request once heard[N] existed. Would keep the entry "
                    .. "quiet but let a member's address and its time drift apart (two files, two writes).",
            },
        },
        leaning = "in-entry, revisited with the power-cut measurement (rooms-write-durability).",
    },
    {
        id = "rooms-one-folder-per-token",
        question = "May one home hold two folders with the same token (the same room twice)?",
        waits_on = "owner",
        detail = "issue 101 open question 7 (new, round 2)",
        config_key = "",
        variants = {
            {
                name = "refuse-second",
                summary = "make_room and change_token refuse a token another room here already holds.",
                built_in = "src/room-folders/002-room-folders.lua (check_token_free, fingerprint_index) — the only variant built",
                tests = "tests/011-test-home-and-rooms.lua ('a token already held here is refused', 'two folders "
                    .. "holding one token (a copied folder) is an error, not a guess')",
                findings = "A token or fingerprint always leads to one folder, so an arriving message has one "
                    .. "place to be filed and find_by_fingerprint one answer. Someone invited twice is told "
                    .. "'already held here by room <tag>'. A folder copied by hand is caught on the next "
                    .. "lookup as an error, not silently merged.",
            },
            {
                name = "allow-several",
                summary = "Several folders may hold one token (for example two labels for one room).",
                built_in = "not built",
                tests = "none",
                findings = "Not built: every arriving message would need a rule for which folder it goes to, "
                    .. "and 102's tree would have two parents with one fingerprint.",
            },
        },
        leaning = "refuse-second: labels are free, so one room never needs two folders to be named twice.",
    },
}
