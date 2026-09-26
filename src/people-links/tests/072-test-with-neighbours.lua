-- 072-test-with-neighbours.lua — people-links next to the real neighbours:
-- the real room tree (102) agrees with our tops, and the real members
-- module (103) adding and withholding members reaches people/ through the
-- bell alone (adding moves links, withholding does not).
--
-- Runs only in "real" mode; a part whose module has not been rewritten yet
-- is reported as SKIP and counts as neither pass nor fail.
--
-- Run: luajit 072-test-with-neighbours.lua [DIR] real

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local rooms, people, disk, tree = H.rooms, H.people, H.disk, H.tree

-- not real mode: the neighbours would run on stand-ins; not useful
if H.mode ~= "real" then
    print("SKIP 072: neighbours are only tested in real mode")
    H.finish()
end

local GF, FRIEND, HOUSE = "gf.example 7000", "friend.example 7001", "house.example 7002"

-- {{{ local function neighbour_home
-- A home with every key the real 102 and 103 read on the paths used here
-- (their first-listed variants), so their code never stops on a missing
-- one.  Which keys they are was read from their options files (round 3:
-- ignore.hide-files, ignore.match and tree.unheld-parent-join were
-- answered and are no longer read, so they are no longer set here).
local function neighbour_home(name)
    local home = H.fresh_home(name, {})
    local keys = {
        { "ignore.scope", "home" },
        { "recipients.shared-address-label", "all-labels" },
        { "recipients.flag-after-passing", "kept" },
        { "tree.filing-loop", "unfile" },
    }
    for _, pair in ipairs(keys) do
        rooms.set_config(home, pair[1], pair[2])
    end
    return home
end
-- }}}

-- {{{ local function owners_tree
local function owners_tree(home)
    H.direct(home, "girlfriend", { GF })
    H.direct(home, "friend", { FRIEND })
    H.direct(home, "housemate", { HOUSE })
    local home_tag = H.group(home, "home", { GF, HOUSE })
    local ritz_tag = H.group(home, "ritz", {}, { parent = home_tag })
    local prog_tag = H.group(home, "programming", { GF, FRIEND }, { filed = ritz_tag })
    local bugs_tag = H.group(home, "bugs", { FRIEND }, { parent = prog_tag })
    return home_tag, ritz_tag, prog_tag, bugs_tag
end
-- }}}

-- {{{ local function tops_by_walking
-- Tops worked out a second way, from 102's ancestors: for each room holding
-- one of these member keys, climb its ancestors from the top and take the
-- highest from which every room down to it holds one of the keys.
local function tops_by_walking(home, keys)
    local set, tops = {}, {}
    local holds = {}
    for _, tag in ipairs(rooms.list_rooms(home)) do
        local entry = rooms.read_entry(home, tag)
        for _, m in ipairs(entry.members) do
            -- a group room with one of the keys: theirs
            if entry.kind == "group" and keys[m.address .. " " .. m.port] then
                holds[tag] = true
            end
        end
    end
    for tag in pairs(holds) do
        local chain = tree.ancestors(home, tag)
        local top = tag
        for i = #chain, 1, -1 do
            -- theirs: the top can climb here; not: stop climbing
            if holds[chain[i]] then
                top = chain[i]
            else
                break
            end
        end
        set[top] = true
    end
    for tag in pairs(set) do
        tops[#tops + 1] = tag
    end
    table.sort(tops)
    return tops
end
-- }}}

-- 102's tree and people-links agree ------------------------------------------
do
    local home = neighbour_home("neighbours-tree")
    local home_tag, ritz_tag, prog_tag, bugs_tag = owners_tree(home)
    local dms = rooms.list_rooms_by_kind(home, "direct")
    for _, dm in ipairs(dms) do
        local keys = {}
        for _, m in ipairs(rooms.read_entry(home, dm).members) do
            keys[m.address .. " " .. m.port] = true
        end
        H.same(people.top_rooms_for(home, dm), tops_by_walking(home, keys),
               "102's ancestors and people-links agree for " .. rooms.read_entry(home, dm).label)
    end
    H.check(tree.tree_parent_of(home, prog_tag) == ritz_tag, "102: programming sits under ritz (filed)")
    H.check(tree.tree_parent_of(home, bugs_tag) == prog_tag, "102: bugs sits under programming (declared)")
end

-- 103 adding and withholding reach people/ through the bell --------------------
local ok_103, members_module = pcall(require, "041-recipients")
if not ok_103 or type(members_module.add_member) ~= "function" then
    print("SKIP 072: 103's add_member is not there yet")
else
    local home = neighbour_home("neighbours-members")
    local home_tag, ritz_tag = owners_tree(home)
    local gf = H.pair(GF)
    members_module.add_member(home, ritz_tag, gf.address, gf.port)
    H.check(not disk.is_link(home.dir .. "/people/girlfriend/programming"),
            "103 add_member: the girlfriend added to ritz, programming no longer a top for her")
    -- withholding changes who you send to, not who is in the room
    if type(members_module.withhold) == "function" then
        members_module.withhold(home, home_tag, gf.address, gf.port)
        H.check(disk.is_link(home.dir .. "/people/girlfriend/home"),
                "103 withhold: the link stays (membership unchanged)")
    else
        print("SKIP 072: 103's withhold is not there yet")
    end
end

H.finish()
