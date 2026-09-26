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
--
-- Answered in round 3 and removed: rooms-suggested-token-words (the
-- owner: six words; built fixed, the rooms.suggested-token-words switch
-- and its 5- and 4-word variants are gone; suggest_token_of still takes
-- any count).  The measurement behind it (about 775,000 fingerprints a
-- second on one CPU core; six words about 700,000 years at an assumed
-- 5 billion guesses a second) is in the planning document's "Answers from
-- the tally, round 2".

return {
    {
        id = "rooms-unheld-parent-mailbox",
        question = "A child room is made (or joined) while this home does not hold its declared parent. "
            .. "Which mailbox (listening port) does it go in: a new one of its own, or a shared waiting "
            .. "mailbox until the parent arrives?",
        waits_on = "owner",
        detail = "issue 102 round 3 open question (found while writing); agreed on the board that 101's "
            .. "make_room takes the choice and this file holds it (102's options point here)",
        config_key = "mailboxes.unheld-parent",
        variants = {
            {
                name = "own-mailbox",
                summary = "The child starts its own tree mailbox, with a port the maker gives, as if it were "
                    .. "a top room; it stays there when the parent arrives.",
                built_in = "src/room-folders/002-room-folders.lua (UNHELD_PARENT_VARIANTS, make_room)",
                tests = "tests/015-test-mailboxes.lua ('own-mailbox: the child starts its own tree mailbox, "
                    .. "and stays in it when the parent arrives')",
                findings = {
                    "The port a room listens on never changes after it is made, so the addresses its members "
                        .. "hold for this home stay right; nothing has to be announced in phase 2.",
                    "Cost: one more forwarded router port for every such child, and once the parent arrives "
                        .. "one tree lives in two mailboxes on this home (a frame for the child arrives on the "
                        .. "child's port, a frame for the parent on the parent's). Rooms made under the child "
                        .. "later join the child's mailbox, not the parent's.",
                    "The maker must know, when making the room, that the parent is not held, to pass a port: "
                        .. "a missing port is an error naming the rule, never a default.",
                },
            },
            {
                name = "waiting-mailbox",
                summary = "The child goes in the home's one 'waiting' mailbox (made once with make_mailbox, "
                    .. "with its port); when the parent arrives it moves into the parent's mailbox.",
                built_in = "src/room-folders/002-room-folders.lua (UNHELD_PARENT_VARIANTS, settle_waiting, "
                    .. "called after make_room, change_token and write_parent)",
                tests = "tests/015-test-mailboxes.lua ('waiting-mailbox: the child waits ...', 'a chain whose "
                    .. "rooms arrive bottom-up settles top-down', 'a parent arriving by a token change', "
                    .. "'given a held parent by write_parent', 'without the waiting mailbox made')",
                findings = {
                    "Every orphaned child shares one port, so no extra router port per child, and a tree ends "
                        .. "up in one mailbox once its top arrives. A chain arriving bottom-up settles top-down "
                        .. "in repeated passes (one 'mailbox' ring per room moved).",
                    "Cost: when a waiting room moves, the port it listens on changes. Members who send to this "
                        .. "home for that room still use the waiting port, which no longer tries that room's "
                        .. "key, so their messages would be lost until phase 2 tells them the new port (or "
                        .. "keeps trying moved rooms on the waiting port for a while). Nothing in phase 1 does.",
                    "Needs one more one-per-home mailbox made before the first such child: without it the "
                        .. "child is refused with the make_mailbox call to run.",
                },
            },
        },
        leaning = "own-mailbox: a port that never moves is correctness, while the waiting mailbox trades it "
            .. "for one fewer router port and needs a phase 2 announcement to stay correct. Revisit if "
            .. "orphaned children turn out to be common (many ports) rather than rare.",
    },
    {
        id = "rooms-mailbox-after-parent-change",
        question = "A room already in a mailbox is given a different declared parent (write_parent). "
            .. "Should it move into the new parent's mailbox, or keep the one it has?",
        waits_on = "owner",
        detail = "issue 101: new (round 3, found while building mailboxes); the owner's rule says where a "
            .. "room goes when made ('a child room joins its declared parent's mailbox'), not after",
        config_key = "",
        variants = {
            {
                name = "keep",
                summary = "It keeps its mailbox (only a room in the waiting mailbox follows a held parent); "
                    .. "moving by hand is write_mailbox.",
                built_in = "src/room-folders/002-room-folders.lua (write_parent, settle_waiting) — the only "
                    .. "variant built",
                tests = "tests/015-test-mailboxes.lua ('a room already in a mailbox keeps it when its parent "
                    .. "is changed')",
                findings = "The port a room listens on changes only when someone asks (write_mailbox), so "
                    .. "members' addresses for this home stay right. A room whose parent changed can sit in "
                    .. "a different mailbox from its new parent: the tree and the mailboxes then disagree on "
                    .. "this home until moved by hand.",
            },
            {
                name = "follow",
                summary = "It moves (with everything under it) into the new parent's mailbox.",
                built_in = "not built",
                tests = "none",
                findings = "Not built: moves the listening port of a whole subtree on one parent change, with "
                    .. "the same lost-message problem as the waiting variant above; cheap to add (the "
                    .. "settling loop already moves rooms) once phase 2 can announce a new port.",
            },
        },
        leaning = "keep, until phase 2 can tell members that a room's port moved.",
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
