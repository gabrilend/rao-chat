-- 075-test-people-by-address.lua — who counts as a person and which rooms
-- are theirs, in the room-is-a-contact model: a person is a direct-message
-- room, and a group room is theirs when one of its members is one of that
-- direct message's addresses.  Also the three new choices this model
-- raised: whether the direct message itself is linked, whether members with
-- no direct message get a folder, and two people whose folders would share
-- a name.
--
-- Run: luajit 075-test-people-by-address.lua [DIR] <stand-in|real-101|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local rooms, people, disk = H.rooms, H.people, H.disk

local LAPTOP, PHONE = "alice-laptop.example 7000", "alice-phone.example 7010"
local BOB, CAROL, V6 = "bob.example 7000", "carol.example 7000", "fe80::1 7000"

-- a person with two addresses counted once -------------------------------------
do
    local home = H.fresh_home("two-addresses", {})
    local alice = H.direct(home, "alice", { LAPTOP, PHONE })
    local both = H.group(home, "both", { LAPTOP, PHONE, BOB })
    local phone_only = H.group(home, "phone-only", { PHONE })
    local neither = H.group(home, "neither", { BOB })
    H.same(people.top_rooms_for(home, alice), H.sorted({ both, phone_only }),
           "two addresses: a room with both is one top, a room with either counts")
    H.same(H.view(home, "alice"), H.sorted({ H.link_line("", "both", both), H.link_line("", "phone-only", phone_only) }),
           "two addresses: one link per room, not per address")
    H.check(not disk.exists(home.dir .. "/people/bob"), "bob has no direct message: no folder (leave-out)")
    -- a move: the laptop's new address added beside the old
    H.set_members(home, neither, { BOB, "alice-laptop-new.example 7000" })
    H.check(not disk.is_link(home.dir .. "/people/alice/neither"),
            "an address the direct message does not hold does not make the room hers")
    H.set_members(home, alice, { LAPTOP, PHONE, "alice-laptop-new.example 7000" })
    H.check(disk.is_link(home.dir .. "/people/alice/neither"),
            "adding the new address to her direct message makes the room hers")
    -- the same host on another port is another member
    local other_port = H.group(home, "other-port", { "alice-phone.example 7011" })
    H.check(not disk.is_link(home.dir .. "/people/alice/other-port"),
            "same host, different port: not her (an address is always a pair)")
    H.same(people.top_rooms_for_addresses(home, { { address = "alice-phone.example", port = 7011 } }), { other_port },
           "top_rooms_for_addresses finds rooms by a pair no direct message holds")
end

-- whose rooms: never someone else's direct message ----------------------------
do
    local home = H.fresh_home("others-dm", {})
    H.direct(home, "alice", { LAPTOP })
    H.direct(home, "bob", { BOB, LAPTOP })   -- an odd direct message also holding alice's address
    H.check(not disk.exists(home.dir .. "/people/alice"),
            "someone else's direct message is not a shared room, even holding her address")
    local g = H.group(home, "g", { LAPTOP })
    H.check(disk.is_link(home.dir .. "/people/alice/g") and disk.is_link(home.dir .. "/people/bob/g"),
            "two direct messages holding one address: the room is in both folders")
    H.fails(function() people.top_rooms_for(home, g) end, "not a direct-message room",
            "top_rooms_for refuses a group room's tag")
end

-- people.direct-message-link ----------------------------------------------------
for _, mode in ipairs({ "leave-out", "include" }) do
    local home = H.fresh_home("dm-link-" .. mode, { ["people.direct-message-link"] = mode })
    local alice = H.direct(home, "alice", { LAPTOP })
    local g = H.group(home, "games", { LAPTOP })
    local want = { H.link_line("", "games", g) }
    -- include: her own direct message is linked too, by its label
    if mode == "include" then
        want[#want + 1] = H.link_line("", "alice", alice)
    end
    H.same(H.view(home, "alice"), H.sorted(want), "direct-message-link " .. mode)
    -- a lone direct message: a folder only under include
    H.direct(home, "dave", { "dave.example 7000" })
    H.check(disk.is_dir(home.dir .. "/people/dave") == (mode == "include"),
            "direct-message-link " .. mode .. ": a direct message sharing nothing else "
            .. ((mode == "include") and "still gets a folder" or "gets no folder"))
    -- a group room filed under her direct message
    local filed = H.group(home, "filed-under-dm", { LAPTOP }, { filed = alice })
    H.check(disk.is_link(home.dir .. "/people/alice/filed-under-dm") == (mode == "leave-out"),
            "direct-message-link " .. mode .. ": a room filed under her direct message is a top only when the "
            .. "direct message is not linked")
end

-- people.members-without-dm -----------------------------------------------------
for _, mode in ipairs({ "leave-out", "address-folder" }) do
    local home = H.fresh_home("loose-" .. mode, { ["people.members-without-dm"] = mode })
    local g = H.group(home, "games", { CAROL, V6 })
    local p = home.dir .. "/people/"
    -- address-folder: carol's and the v6 member's folders, by address
    if mode == "address-folder" then
        H.same(H.view(home), H.sorted({
            "carol.example:7000/", "carol.example:7000/games -> ../../rooms/" .. g,
            "[fe80::1]:7000/", "[fe80::1]:7000/games -> ../../rooms/" .. g,
        }), "address-folder: a folder per member with no direct message; v6 bracketed")
    else
        H.same(H.view(home), {}, "leave-out: no folders for members with no direct message")
    end
    -- carol gets a direct message: her address folder gives way to her label
    H.direct(home, "carol", { CAROL })
    H.check(disk.is_link(p .. "carol/games") and not disk.exists(p .. "carol.example:7000"),
            mode .. ": once she has a direct message, her folder is its label")
end

-- people.person-folder-collision ------------------------------------------------
do
    local home = H.fresh_home("person-clash-missing", {})
    H.direct(home, "alex", { "alex1.example 7000" })
    H.fails(function() H.direct(home, "alex", { "alex2.example 7000" }) end, "people.person-folder-collision",
            "two direct messages labelled alex and no people.person-folder-collision: an error")
end
for _, mode in ipairs({ "suffix-id", "numbered", "merge" }) do
    local home = H.fresh_home("person-clash-" .. mode, { ["people.person-folder-collision"] = mode })
    local a1 = H.direct(home, "alex", { "alex1.example 7000" })
    local a2 = H.direct(home, "alex", { "alex2.example 7000" })
    local r1 = H.group(home, "one", { "alex1.example 7000" })
    local r2 = H.group(home, "two", { "alex2.example 7000" })
    local low, high = a1, a2
    -- tags are random: order them
    if a2 < a1 then
        low, high = a2, a1
    end
    local folders = {}
    for _, person in ipairs(people.people(home)) do
        folders[#folders + 1] = person.folder
    end
    -- what each mode makes of two people called alex
    if mode == "merge" then
        H.same(folders, { "alex" }, "merge: one folder")
        H.same(H.view(home, "alex"), H.sorted({ H.link_line("", "one", r1), H.link_line("", "two", r2) }),
               "merge: both people's rooms in it")
        H.same(people.top_rooms_for(home, a1), H.sorted({ r1, r2 }), "merge: either direct message gives the pooled tops")
    elseif mode == "numbered" then
        H.same(folders, { "alex", "alex-2" }, "numbered: alex and alex-2, in tag order")
        H.check(disk.is_dir(home.dir .. "/people/" .. ((low == a1) and "alex" or "alex-2")),
                "numbered: the lower tag keeps the bare name")
    else
        H.same(folders, H.sorted({ "alex~" .. low:sub(1, 4), "alex~" .. high:sub(1, 4) }),
               "suffix-id: alex~<first four of each tag>")
    end
    H.same(people.top_rooms_for(home, a2), (mode == "merge") and H.sorted({ r1, r2 }) or { r2 },
           mode .. ": the second alex's tops")
    -- relabel one: the clash ends and the key is no longer needed
    rooms.write_label(home, a2, "alexandra")
    H.check(disk.is_link(home.dir .. "/people/alex/one") and disk.is_link(home.dir .. "/people/alexandra/two"),
            mode .. ": relabelled apart: plain folders again")
end
do
    -- a direct-message label equal to a member's address folder name
    local home = H.fresh_home("person-clash-address", { ["people.members-without-dm"] = "address-folder",
                                                        ["people.person-folder-collision"] = "numbered" })
    local g = H.group(home, "games", { CAROL })
    local fake = H.direct(home, "carol.example:7000", { BOB })
    H.group(home, "bobs", { BOB })
    local folders = {}
    for _, person in ipairs(people.people(home)) do
        folders[#folders + 1] = person.folder
    end
    H.same(folders, { "carol.example:7000", "carol.example:7000-2" },
           "a direct message labelled like an address folder is told apart like any clash")
end

-- people() -----------------------------------------------------------------------
do
    local home = H.fresh_home("people-list", {})
    local alice = H.direct(home, "alice", { PHONE, LAPTOP })
    local list = people.people(home)
    H.check(#list == 1 and list[1].folder == "alice" and list[1].dm_tags[1] == alice
            and table.concat(list[1].addresses, ",") == LAPTOP .. "," .. PHONE,
            "people(): folder, direct message and sorted member keys")
end

H.finish()
