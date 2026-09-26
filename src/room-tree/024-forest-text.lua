-- 024-forest-text.lua — draws a home's room trees (from 021's forest) as
-- plain text.
--
-- Kept apart from the working-out of the tree so that the tree can be
-- tested as data and drawn any number of ways; the clients draw it as
-- folders that open and close, this draws it for the tests and the phase
-- demo.  One room per line, children indented under their parent with
-- the same box-drawing branches the planning document uses.  Two marks
-- say how a room came to be where it is:
--
--   (filed)         you placed it here on your own screen; to everyone
--                   else it is not inside this room
--   (parent not held here)
--                   it was made inside a room you are not in (its
--                   invitation names a parent you do not hold), so it
--                   stands at the top for you
--
--   home
--   ├── kitchen
--   │   └── recipes
--   └── programming   (filed)

local M = {}

-- {{{ local function marks_for
local function marks_for(node)
    local marks = ""
    -- placed by filing: say so; declared or top: nothing
    if node.placed == "filed" then
        marks = marks .. "   (filed)"
    end
    -- names a parent that is not held here: say so; otherwise nothing
    if node.parent_unheld then
        marks = marks .. "   (parent not held here)"
    end
    return marks
end
-- }}}

-- {{{ local function draw_children
-- `lead` is what goes in front of each child's branch: spaces or a bar
-- for every level above, so lines under an unfinished parent keep a bar.
local function draw_children(children, lead, lines)
    for position, child in ipairs(children) do
        local last = position == #children
        -- the last child closes the branch; the others keep it open below
        local branch, below = "├── ", "│   "
        if last then
            branch, below = "└── ", "    "
        end
        lines[#lines + 1] = lead .. branch .. child.label .. marks_for(child)
        draw_children(child.children, lead .. below, lines)
    end
end
-- }}}

-- {{{ function M.lines
-- A list of strings, one per room, trees in the forest's order.
function M.lines(forest)
    local lines = {}
    for _, top in ipairs(forest) do
        lines[#lines + 1] = top.label .. marks_for(top)
        draw_children(top.children, "", lines)
    end
    return lines
end
-- }}}

-- {{{ function M.text
-- The same lines joined with line breaks, ending in one.
function M.text(forest)
    return table.concat(M.lines(forest), "\n") .. "\n"
end
-- }}}

return M
