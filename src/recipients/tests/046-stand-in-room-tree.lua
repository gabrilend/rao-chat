-- 046-stand-in-room-tree.lua — a small copy of the three things the
-- recipients module asks the room tree (issue 102, round 3), written only so
-- the recipients tests can run on their own.
--
-- The rule it stands in for is detection, not refusal: "does this address
-- belong in this room, by every room declared above it?"  The answer is
-- yes (a member of every declared room above, as this home sees them; a top
-- room always says yes), no (some held room above lacks it), or
-- cannot-check (every held room above has it, but the chain climbs into a
-- room this home does not hold).  No beats cannot-check.  And the two
-- re-checking lists: the failing members of one room, and of every room
-- declared below it.  The runner loads the real module instead when told
-- "real".

local rooms = require("002-room-folders")

local M = {}

-- {{{ local function holds
local function holds(entry, address, port)
    for _, m in ipairs(entry.members) do
        -- this member: found
        if m.address == address and m.port == port then
            return true
        end
    end
    return false
end
-- }}}

-- {{{ function M.check_member
-- Gives "yes" | "no" | "cannot-check", and a reason ("" for yes).
function M.check_member(home, tag, address, port)
    local entry = rooms.read_entry(home, tag)
    local lacking = {}
    local unseen = false
    local seen = { [tag] = true }
    -- climb the declared parents until a top room or one not held here
    while entry.parent ~= "" do
        local above = rooms.find_by_fingerprint(home, entry.parent)
        -- not held here: the climb stops, unseen beyond
        if above == "" then
            unseen = true
            break
        end
        -- a loop of declared parents would climb forever
        if seen[above] then
            error("stand-in tree: declared parents loop at " .. above)
        end
        seen[above] = true
        entry = rooms.read_entry(home, above)
        -- this room above lacks the pair: noted
        if not holds(entry, address, port) then
            lacking[#lacking + 1] = entry.label
        end
    end
    -- a held room above lacks it: no, whatever lies beyond
    if #lacking > 0 then
        return "no", "not a member of " .. table.concat(lacking, ", ")
    end
    -- all held rooms have it, but one above is not held
    if unseen then
        return "cannot-check", "a room above is not held here"
    end
    return "yes", ""
end
-- }}}

-- {{{ function M.failing_members
function M.failing_members(home, tag)
    local out = {}
    for _, m in ipairs(rooms.read_entry(home, tag).members) do
        local answer, reason = M.check_member(home, tag, m.address, m.port)
        -- failing: listed; yes: not
        if answer ~= "yes" then
            out[#out + 1] = { room = tag, address = m.address, port = m.port, answer = answer, reason = reason }
        end
    end
    return out
end
-- }}}

-- {{{ local function collect_below
local function collect_below(home, tag, out)
    local fingerprint = rooms.token_fingerprint(rooms.read_entry(home, tag).token)
    for _, other in ipairs(rooms.list_rooms(home)) do
        -- declared directly under this room: its failing members, then its own children
        if rooms.read_entry(home, other).parent == fingerprint then
            for _, row in ipairs(M.failing_members(home, other)) do out[#out + 1] = row end
            collect_below(home, other, out)
        end
    end
end
-- }}}

-- {{{ function M.failing_below
function M.failing_below(home, tag)
    local out = {}
    collect_below(home, tag, out)
    return out
end
-- }}}

return M
