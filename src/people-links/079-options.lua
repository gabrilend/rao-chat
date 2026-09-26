-- 079-options.lua — the undecided choices in the people-links module,
-- written down for the options tally (scripts/tally-options, issue 106).
--
-- Each entry is one question the owner (or some later state of the project)
-- has to settle.  Every switchable variant is built and tested; the home's
-- config file picks the one in use.  The findings are what building and
-- testing each variant actually showed.  Plain data: nothing here runs.
--
-- The first variant listed is the one the phase 1 demo starts its homes
-- with, so order matters (contract, "The options tally").
--
-- Retired in round 2 (the room-is-a-contact model): people-split-records
-- (there are no splits any more).  people-own-devices lost its switch:
-- the home keeps no list of your own devices now (no contacts file), so
-- there is nothing for all-tops to act on until pairing exists.
-- Answered in round 4 and removed: people-flagged-members — a flagged
-- member counts toward the person's rooms (as built: people/ reads
-- membership from the entry, and a flagged member is in the entry).

return {
    {
        id = "people-link-collision",
        question = "Two top rooms you share with one person have the same label. What are their links in people/<person>/ called?",
        waits_on = "owner",
        detail = "issue 104 open question 1",
        config_key = "people.link-collision",
        variants = {
            {
                name = "suffix-id",
                summary = "Clashing rooms get a tag from their local tag: programming~3fa9, programming~b710. Rooms that do not clash keep their plain label.",
                built_in = "src/people-links/063-link-names.lua (name_suffix_id)",
                tests = { "tests/066-test-link-names.lua", "tests/069-test-collisions-on-disk.lua" },
                findings = "A clashing room's link name depends only on its own label and local tag, so a "
                    .. "third 'programming' arriving adds a link without renaming the other two (tested with "
                    .. "random tags on the real 101). Labels repeat far more often now than in round 1: labels "
                    .. "are the reader's own and two rooms with different tokens may carry the same one "
                    .. "(planning section 1, 'Labels belong to the reader'). The local tag never leaves this "
                    .. "home, so the suffix means nothing to anyone else — only to 'ls rooms/'. When a clash "
                    .. "first appears both rooms get a suffix, so the existing link moves once.",
            },
            {
                name = "numbered",
                summary = "Clashing rooms are numbered in local-tag order: programming, programming-2, programming-3.",
                built_in = "src/people-links/063-link-names.lua (name_numbered)",
                tests = { "tests/066-test-link-names.lua", "tests/069-test-collisions-on-disk.lua" },
                findings = "Reads most naturally in ls. The numbers belong to the set, not to a room: local "
                    .. "tags are random, so a newly made clashing room lands at a random place in the order "
                    .. "and renumbers every room after it (066 shows it with fixed tags). A remembered path "
                    .. "like people/alice/programming-2 can come to mean another room.",
            },
            {
                name = "id-folder",
                summary = "Every top room gets a folder named by its local tag, the labelled link inside: people/<person>/<tag>/programming.",
                built_in = "src/people-links/063-link-names.lua (name_id_folder)",
                tests = { "tests/066-test-link-names.lua", "tests/068-test-owners-example.lua", "tests/069-test-collisions-on-disk.lua" },
                findings = "Nothing can clash and no link moves when another room appears. 'ls people/alice' "
                    .. "shows 32-character tags, so answering the owner's question takes 'ls people/alice/*'. "
                    .. "Switching to or from it leaves nothing of the old shape behind (all six switches "
                    .. "tested on stand-in and real modules).",
            },
        },
        leaning = "suffix-id: labels stay readable and a link's name never changes because some other room "
            .. "appeared.",
    },
    {
        id = "people-slash-in-link-name",
        question = "A label that cannot be a file name as it is ('/' inside, or exactly '.' or '..'). How is it written as a link or folder name in people/?",
        waits_on = "owner",
        detail = "issue 104 open question 2; labels may hold any text but a line break (contract, 'The entry'), so this is now reachable on every home; read only when such a label exists",
        config_key = "people.slash-in-link-name",
        variants = {
            {
                name = "percent",
                summary = "'/' becomes %2F (home%2Fritz); '.' becomes %2E and '..' %2E%2E.",
                built_in = "src/people-links/061-people-links.lua (unsafe_rewrites, safe_name)",
                tests = "tests/071-test-choices.lua",
                findings = "Plain ASCII, obviously an escape, safe in every tool. Not reversed and needs not "
                    .. "be: a room really labelled 'a%2Fb' clashing with 'a/b' is told apart by the collision "
                    .. "mode like any clash (tested). The same rewrite serves people's folders (a direct "
                    .. "message labelled 'me/work' becomes people/me%2Fwork/, tested). Round 1 handled only "
                    .. "'/'; '.' and '..' were found while rewriting: 101 now allows them as labels, and "
                    .. "without a rewrite a room labelled '..' would stop every rebuild.",
            },
            {
                name = "division-slash",
                summary = "Look-alike characters: '/' becomes U+2215 (home∕ritz), '.' U+2024 (․), '..' U+2025 (‥).",
                built_in = "src/people-links/061-people-links.lua (unsafe_rewrites, safe_name)",
                tests = "tests/071-test-choices.lua",
                findings = "Reads like the real label in ls, which is also its danger: it looks like a path, "
                    .. "and typing people/friend/home/ritz finds nothing. Three bytes of UTF-8 per character "
                    .. "replaced.",
            },
        },
        leaning = "percent: an escape that looks like an escape.",
    },
    {
        id = "people-direct-message-link",
        question = "Is the person's own direct message linked in their people/ folder too, beside the group rooms you share?",
        waits_on = "owner",
        detail = "issue 104: new, found while rewriting (the issue links group rooms only; the owner's words were 'the top-level directories they're a part of', and a direct message is one)",
        config_key = "people.direct-message-link",
        variants = {
            {
                name = "leave-out",
                summary = "Only group rooms are linked; a person you share no group room with has no folder.",
                built_in = "src/people-links/061-people-links.lua (is_theirs)",
                tests = "tests/075-test-people-by-address.lua",
                findings = "people/ then lists exactly what the issue describes. A room filed under her "
                    .. "direct message counts as a top (its parent is not 'hers'), tested.",
            },
            {
                name = "include",
                summary = "Their direct message is linked too, named by its label; every person has a folder.",
                built_in = "src/people-links/061-people-links.lua (is_theirs)",
                tests = "tests/075-test-people-by-address.lua",
                findings = "people/ becomes a full address book: every direct message has a folder, and "
                    .. "people/alice/alice leads to the conversation with her. The link's name repeats the "
                    .. "folder's. A room filed under her direct message stops being a top (it sits inside "
                    .. "something of hers), tested.",
            },
        },
        leaning = "leave-out: the folder answers 'what do we share besides our own conversation'; the "
            .. "direct message is already one step away in rooms/.",
    },
    {
        id = "people-members-without-dm",
        question = "A member of a group room whose address no direct message holds: do they get a people/ folder, named by the address?",
        waits_on = "owner",
        detail = "issue 104 open question 3",
        config_key = "people.members-without-dm",
        variants = {
            {
                name = "leave-out",
                summary = "No folder: people/ lists only people you have a direct message with.",
                built_in = "src/people-links/061-people-links.lua (candidate_people)",
                tests = "tests/075-test-people-by-address.lua",
                findings = "Members you met only in a group are invisible in people/ (still in the room's "
                    .. "entry). Tested: no folder, then a direct message for her makes her folder appear.",
            },
            {
                name = "address-folder",
                summary = "One folder per such address, named host:port ([v6]:port for IPv6): people/carol.example:7000/.",
                built_in = "src/people-links/061-people-links.lua (candidate_people, address_folder_name)",
                tests = "tests/075-test-people-by-address.lua",
                findings = "Every member shows up. One person with two machines and no direct message gets "
                    .. "two folders, since nothing ties the addresses together. When she gets a direct "
                    .. "message, the address folder is swept and her label's folder appears (tested). ':' "
                    .. "and '[]' are legal in file names but need quoting in some shells. A direct message "
                    .. "labelled exactly like an address folder is a folder clash (tested under numbered).",
            },
        },
        leaning = "leave-out: an address is not a person until you give it a direct message and a label.",
    },
    {
        id = "people-person-folder-collision",
        question = "Two people whose folders would have the same name (two direct messages both labelled alex). What happens?",
        waits_on = "owner",
        detail = "issue 104: new, found while rewriting (labels are your own and may repeat, so direct messages may share one); read only when a clash exists",
        config_key = "people.person-folder-collision",
        variants = {
            {
                name = "suffix-id",
                summary = "alex~3fa9 and alex~b710, from each direct message's local tag.",
                built_in = "src/people-links/061-people-links.lua (person_namers), 063-link-names.lua",
                tests = "tests/075-test-people-by-address.lua",
                findings = "Same naming as the room links, so one rule to learn. Relabelling one apart "
                    .. "returns both to plain names (tested).",
            },
            {
                name = "numbered",
                summary = "alex and alex-2, in local-tag order.",
                built_in = "src/people-links/061-people-links.lua (person_namers), 063-link-names.lua",
                tests = "tests/075-test-people-by-address.lua",
                findings = "Which alex is 'alex' depends on random tags, not on who came first.",
            },
            {
                name = "merge",
                summary = "One folder, alex, holding the tops of both direct messages' addresses together.",
                built_in = "src/people-links/061-people-links.lua (merge_same_names)",
                tests = "tests/075-test-people-by-address.lua",
                findings = "Right when the two direct messages are one person (say, the same person on two "
                    .. "tokens); wrong when they are two different alexes. top_rooms_for either direct "
                    .. "message gives the pooled tops (tested).",
            },
        },
        leaning = "suffix-id, matching the room links; merge only if the owner reads a repeated label as "
            .. "'the same person'.",
    },
    {
        id = "people-own-devices",
        question = "Should your own devices get a folder in people/?",
        waits_on = "state",
        detail = "issue 104 open question 4; waits on pairing (a later phase): the home keeps no list of your own devices any more (no contacts file, contract 'The home folder')",
        config_key = "",
        variants = {
            {
                name = "none",
                summary = "Built: devices get no folder.",
                built_in = "src/people-links/061-people-links.lua (people come only from rooms)",
                tests = "tests/075-test-people-by-address.lua (people() lists direct messages only)",
                findings = "Devices are never members (contract), so they are never in a group room's "
                    .. "entry and cannot be 'someone's' address unless typed into a direct message by hand.",
            },
            {
                name = "all-tops",
                summary = "Not built: each device's folder would link the top of every tree you hold.",
                built_in = "",
                tests = "",
                findings = "Built in round 1 from contacts marked own = true. That list is gone from "
                    .. "rao-home; building it again needs pairing to say where devices are kept. It "
                    .. "would answer 'what do I hold', not 'what do I share with this person'.",
            },
        },
        leaning = "none.",
    },
    {
        id = "people-rebuild-scope",
        question = "Every ring of the bell that can move a link rebuilds all of people/. Is that cheap enough, or should a ring rebuild only the people it can affect?",
        waits_on = "state",
        detail = "issue 104 open question 5: needs a measurement of a real home's size",
        config_key = "",
        variants = {
            {
                name = "rebuild-all",
                summary = "Built: created/label/token/members/parent/filed/removed-room rebuild every person's folder from one read of all rooms.",
                built_in = "src/people-links/061-people-links.lua (on_bell, rebuild_all)",
                tests = { "tests/071-test-choices.lua (the bell)", "tests/068-test-owners-example.lua" },
                findings = "Measured on the real 101 and 102 (CPU time, 20 direct messages, rooms with one "
                    .. "or two members, a third filed under another): one rebuild_all took 12 ms at 100 rooms "
                    .. "and 39 ms at 400. Making 400 rooms one after another took 32.7 s in all, of which "
                    .. "104's rebuilds are about 8 s (estimated as the sum of a rebuild that grows linearly "
                    .. "to 39 ms); the rest is the other listeners and writes. First wiring called 102's "
                    .. "tree_parent_of once per room, and each call re-reads the whole home: 1.2 s per "
                    .. "rebuild at 100 rooms, 63 s to make them. Reading 102's snapshot once per rebuild "
                    .. "fixed that (060-neighbour-reads). A rebuild that changes nothing writes nothing.",
            },
            {
                name = "rebuild-affected",
                summary = "Not built: rebuild only the people holding an address in the changed room, or in rooms under it.",
                built_in = "",
                tests = "",
                findings = "The bell carries only the tag and the kind, not the old member list, so the "
                    .. "people who just left a room are unknown at ring time; 104 would have to keep its own "
                    .. "copy of every member list, a second truth.",
            },
        },
        leaning = "keep rebuild-all; a bulk import can ring once at the end.",
    },
}
