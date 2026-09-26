-- 076-test-mailboxes-and-flags.lua — what round 3 added around people/:
-- mailboxes (listening ports that group rooms; the bell rings `mailbox`)
-- and flags (a member the room tree could not vouch for is added but held
-- off the send list, and 103 rings `withheld` when flags change).
--
-- Neither changes who is in a room, so neither may move a link.  These
-- checks make sure people/ hears both rings, changes nothing, and that a
-- flagged member still counts toward a person's rooms (the owner's
-- answer in round 4, fixed in place).  The flag itself is written
-- by hand in stand-in and real-101 modes, and by the real 103 in real mode.
--
-- Run: luajit 076-test-mailboxes-and-flags.lua [DIR] <stand-in|real-101|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local rooms, people, disk = H.rooms, H.people, H.disk

local GF, CODER = "gf.example 7000", "coder.example 7003"

-- {{{ local function flagged_path
-- rooms/<tag>/flagged (the stand-in has no flagged_path; the file is there)
local function flagged_path(home, tag)
    return rooms.room_dir(home, tag) .. "/flagged"
end
-- }}}

-- {{{ local function write_file
local function write_file(path, text)
    local file = assert(io.open(path, "w"))
    file:write(text)
    file:close()
end
-- }}}

-- the direct mailbox's own ring --------------------------------------------------
-- fresh_home makes the direct mailbox after 061 is loaded, so every home in
-- every test has already rung `mailbox` with "" once; this one checks it
-- also rings on a home that already holds people.
do
    local home = H.fresh_home("mailbox-rings", {})
    local gf_dm = H.direct(home, "girlfriend", { GF })
    local home_tag = H.group(home, "home", { GF })
    local kitchen = H.group(home, "kitchen", { GF }, { parent = home_tag })
    local games = H.group(home, "games", { GF })
    local before = H.view(home)
    H.same(before, { "girlfriend/", H.link_line("girlfriend", "games", games),
                     H.link_line("girlfriend", "home", home_tag) },
           "people/ built with mailboxes in every entry")
    H.check(rooms.read_entry(home, kitchen).mailbox == rooms.read_entry(home, home_tag).mailbox,
            "a child room shares its held parent's mailbox (101's rule, seen here)")
    H.check(rooms.read_entry(home, gf_dm).mailbox == rooms.direct_mailbox(home),
            "a direct message sits in the direct mailbox")
    -- a port change rings mailbox with "": nothing drawn changes
    rooms.write_mailbox_port(home, rooms.read_entry(home, games).mailbox, 7799)
    H.same(H.view(home), before, "mailbox ring (a port changed): people/ unchanged")
    -- a room moved into another tree mailbox rings mailbox with its tag
    rooms.write_mailbox(home, kitchen, rooms.read_entry(home, games).mailbox)
    H.same(H.view(home), before, "mailbox ring (a room moved): people/ unchanged")
    -- a kind nobody listed is still an error (the listener did not go soft)
    H.fails(function() rooms.notify(home, home_tag, "no-such-kind") end, "no-such-kind",
            "an unlisted bell kind is still refused")
end

-- a flagged member still counts ---------------------------------------------------
-- Owner's example, round 3: coder added to shopping (a child of home) though
-- not in home.  The tree answers "no"; 103 adds and flags.  coder is a
-- member of shopping and not of home, so shopping is a top for coder.
do
    local home = H.fresh_home("flagged-counts", {
        ["ignore.scope"] = "home",
        ["recipients.shared-address-label"] = "all-labels",
        ["tree.filing-loop"] = "unfile",
    })
    H.direct(home, "coder", { CODER })
    local home_tag = H.group(home, "home", { GF })
    local shopping = H.group(home, "shopping", { GF }, { parent = home_tag })
    H.same(H.view(home, "coder"), {}, "coder in no room yet: an empty folder")
    local coder = H.pair(CODER)
    -- real mode: the real 103 adds and flags; otherwise do what 103 does by hand
    if H.mode == "real" then
        local members_module = require("041-recipients")
        local word, answer = members_module.add_member(home, shopping, coder.address, coder.port)
        H.check(word == "added-flagged" and answer == "no", "103 add_member: coder added-flagged, tree says no")
        local sent = {}
        for _, p in ipairs(members_module.send_list(home, shopping)) do
            sent[#sent + 1] = p.address .. " " .. p.port
        end
        H.same(sent, { GF }, "103: coder is held off the send list")
    else
        write_file(flagged_path(home, shopping), CODER .. " no\n")
        rooms.notify(home, shopping, "withheld")
        local entry = rooms.read_entry(home, shopping)
        entry.members[#entry.members + 1] = coder
        rooms.write_members(home, shopping, entry.members)
    end
    H.same(H.view(home, "coder"), { H.link_line("", "shopping", shopping) },
           "a flagged member counts: shopping is coder's top")
    -- a flag change alone (approve / decline ring withheld) moves nothing
    local before = H.view(home)
    -- real mode: decline through 103 (withheld, flag line gone); else by hand
    if H.mode == "real" then
        require("041-recipients").decline(home, shopping, coder.address, coder.port)
    else
        write_file(flagged_path(home, shopping), "")
        rooms.notify(home, shopping, "withheld")
    end
    H.same(H.view(home), before, "flag declined (withheld ring): people/ unchanged")
end

H.finish()
