-- 069-test-collisions-on-disk.lua — two top rooms both labelled
-- "programming" shared with one person, on disk, in each collision mode;
-- a third arriving; relabelling the clash away; and switching modes, which
-- must leave no links of the old mode behind.
--
-- Tags are random (101 makes them), so the expected names are worked out
-- from the tags the rooms were given: numbered goes in tag order, suffix-id
-- uses each tag's first four characters (more only when two share them).
--
-- Run: luajit 069-test-collisions-on-disk.lua [DIR] <stand-in|real-101|real>

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local H = dofile(DIR .. "/src/people-links/tests/065-test-harness.lua")
H.setup(DIR, arg[2])
local rooms, people = H.rooms, H.people

local FRIEND = "friend.example 7000"

-- {{{ local function expected
-- The view of people/friend/ for rooms (list of tags, all labelled
-- programming) in a mode.
local function expected(mode, tags)
    local sorted = H.sorted(tags)
    local out = {}
    for i, tag in ipairs(sorted) do
        -- each mode's naming, written out independently of 063
        if mode == "id-folder" then
            out[#out + 1] = tag .. "/"
            out[#out + 1] = tag .. "/programming -> ../../../rooms/" .. tag
        elseif mode == "numbered" then
            local name = (i == 1) and "programming" or ("programming-" .. i)
            out[#out + 1] = name .. " -> ../../rooms/" .. tag
        else
            -- suffix-id: the shortest prefix (from 4) that tells them apart
            local length = 4
            local distinct
            repeat
                local seen = {}
                distinct = true
                for _, other in ipairs(sorted) do
                    -- a prefix met twice: not yet long enough
                    if seen[other:sub(1, length)] then
                        distinct = false
                    end
                    seen[other:sub(1, length)] = true
                end
                -- not distinct: one character more
                if not distinct then
                    length = length + 1
                end
            until distinct
            out[#out + 1] = "programming~" .. tag:sub(1, length) .. " -> ../../rooms/" .. tag
        end
    end
    table.sort(out)
    return out
end
-- }}}

-- {{{ local function make_two
local function make_two(label, mode)
    local home = H.fresh_home("collisions-" .. label, { ["people.link-collision"] = mode })
    H.direct(home, "friend", { FRIEND })
    local a = H.group(home, "programming", { FRIEND })
    local b = H.group(home, "programming", { FRIEND })
    return home, a, b
end
-- }}}

for _, mode in ipairs(H.names.MODES) do
    local home, a, b = make_two(mode, mode)
    H.same(H.view(home, "friend"), expected(mode, { a, b }), mode .. ": two rooms labelled programming, both linked")

    local c = H.group(home, "programming", { FRIEND })
    H.same(H.view(home, "friend"), expected(mode, { a, b, c }), mode .. ": a third arrives, three links")

    -- relabel two away: no clash left, the bare label returns
    rooms.write_label(home, b, "work")
    rooms.write_label(home, c, "games")
    local bare = home.dir .. "/people/friend/" .. ((mode == "id-folder") and (a .. "/") or "") .. "programming"
    H.check(H.disk.is_link(bare), mode .. ": no clash left: the bare label returns")
end

-- switching mode: every link of the old shape goes, the new shape appears
for _, from in ipairs(H.names.MODES) do
    for _, to in ipairs(H.names.MODES) do
        -- only real switches
        if from ~= to then
            local home, a, b = make_two(from .. "-to-" .. to, from)
            rooms.set_config(home, "people.link-collision", to)
            people.rebuild_all(home)
            H.same(H.view(home, "friend"), expected(to, { a, b }),
                   "switch " .. from .. " -> " .. to .. ": only new-mode links remain")
        end
    end
end

H.finish()
