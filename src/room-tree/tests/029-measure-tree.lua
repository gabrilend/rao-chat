-- 029-measure-tree.lua — measures how long the room tree takes to answer
-- as a home grows, against the real room-folders module.
--
-- The tree keeps no index: every question reads every room's entry and
-- works the tree out afresh (a "snapshot"), and every change that could
-- move a room rewrites every room's `where` note.  That is simple and
-- cannot fall out of step, but its cost grows with the number of rooms.
-- This script builds homes of increasing size (a chain of children plus
-- side rooms) and prints, for each size, the time for one snapshot, one
-- may_join, and one room made (which rings the bell, so it includes
-- rewriting every `where`).  It also times the same making with the
-- people/ module (104) loaded, which asks the tree about each room.
--
-- Not a pass/fail test; the runner does not run it.
-- Run: luajit 029-measure-tree.lua [DIR] [sizes, comma-separated] [with-people|tree-only]

local DIR = "/home/ritz/programs/rao-chat"
-- a project folder given first: use it; otherwise the one above
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
local SIZES = arg[2] or "10,50,200"
local WITH = arg[3] or "tree-only"

local t = dofile(DIR .. "/src/room-tree/tests/031-test-support.lua")
local rooms, tree = t.setup(DIR, "real")
-- with-people: load 104 so its listener runs on every ring too
-- tree-only: just the tree's listener
if WITH == "with-people" then
    require("061-people-links")
elseif WITH ~= "tree-only" then
    error("third argument must be with-people or tree-only, got " .. WITH)
end

-- {{{ local function seconds
local function seconds(fn)
    local start = os.clock()
    fn()
    return os.clock() - start
end
-- }}}

-- {{{ local function config_for
local function config_for(home)
    rooms.set_config(home, "people.link-collision", "suffix-id")
    rooms.set_config(home, "people.direct-message-link", "leave-out")
    rooms.set_config(home, "people.members-without-dm", "leave-out")
end
-- }}}

print(string.format("%-8s %-12s %12s %12s %14s", "rooms", "listeners", "snapshot s", "may_join s", "make_room s"))
for size in SIZES:gmatch("%d+") do
    local n = tonumber(size)
    local home = t.fresh_home(rooms, "measure-" .. n)
    config_for(home)
    local previous = ""
    for i = 1, n - 1 do
        local parent = ""
        -- every other room goes one level deeper; the rest are tops
        if i % 2 == 0 then
            parent = previous
        end
        local tag = t.room(rooms, home, "room-" .. i, "token-" .. n .. "-" .. i, parent,
            { { "10.0.0." .. (i % 250 + 1), 7777 } })
        -- a top: the next deeper room hangs from it
        if parent == "" then
            previous = tag
        end
    end
    local snap_time = seconds(function() tree.snapshot(home) end)
    local tag_any = rooms.list_rooms(home)[1]
    local join_time = seconds(function() tree.may_join(home, tag_any, "10.0.0.1", 7777) end)
    local make_time = seconds(function()
        t.room(rooms, home, "last", "token-last-" .. n, "", {})
    end)
    print(string.format("%-8d %-12s %12.4f %12.4f %14.4f", n, WITH, snap_time, join_time, make_time))
end
