-- 074-stand-in-room-tree.lua — a small stand-in for the room tree module
-- (issue 102), written only so the people-links tests can run before the
-- real one is rewritten.
--
-- It offers the calls people-links makes: snapshot(home) (entries and
-- tree parents of every room) and tree_parent_of(home, tag),
-- "which room does this one sit under in your tree?".  The answer follows
-- issue 102 and 102's board post: the room whose token fingerprint the
-- entry's parent names, if that room is held here; otherwise the room it
-- is filed under, if any; otherwise "" (a top room).  A declared parent
-- wins over filing.  The test runner uses the real module when it has been
-- rewritten.

local rooms = require("002-room-folders")

local M = {}

-- {{{ function M.tree_parent_of
function M.tree_parent_of(home, tag)
    local entry = rooms.read_entry(home, tag)
    -- a declared parent: held here wins
    if entry.parent ~= "" then
        local held = rooms.find_by_fingerprint(home, entry.parent)
        -- held: that is the parent in the tree
        if held ~= "" then
            return held
        end
    end
    -- filed under another room (or not): that, or no parent
    return entry.filed_under
end
-- }}}

-- {{{ function M.snapshot
-- The part of 102's snapshot people-links reads: entries (tag -> entry)
-- and parent (tag -> tree parent or "").
function M.snapshot(home)
    local snap = { entries = {}, parent = {} }
    for _, tag in ipairs(rooms.list_rooms(home)) do
        snap.entries[tag] = rooms.read_entry(home, tag)
        snap.parent[tag] = M.tree_parent_of(home, tag)
    end
    return snap
end
-- }}}

return M
