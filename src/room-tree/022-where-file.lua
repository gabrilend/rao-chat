-- 022-where-file.lua — the small `where` file kept inside every room folder.
--
-- Rooms are stored flat on disk, one folder per local tag, so a folder's
-- location says nothing about which rooms it sits inside.  The owner asked
-- that a room's real folder on disk and its path of labels from the top
-- ("home/ritz/programming", in your own labels) both be kept right beside
-- the room, as easy to read as its label.  This file knows only how that
-- note is written and read back; deciding what goes in it is the room
-- tree's job (021).
--
-- The file is two "key = value" lines, the same shape as the config
-- file, so it can be read with cat:
--
--   folder = /home/you/rao-home/rooms/3f2a...e1
--   labels = home/ritz/programming
--
-- (A third line naming the declared parent's local tag was tried while
-- rebuilding, to find a parent's children after its token changed by
-- hand.  It was dropped: room-folders re-points held children itself when
-- a token changes, before it rings the bell.)
--
-- Only the first " = " on a line separates key from value, so a label
-- holding "=" survives.  A line break in a label is refused by the room
-- folders module (101) before anything reaches here.
--
-- Labels are the reader's own and may hold any text but a line break,
-- "/" included (issue 101).  So that the labels line can still be split
-- back into its steps, each label is written into the path with "\"
-- doubled and "/" written as "\/": a room labelled "a/b" inside "home" is
-- "home/a\/b".  With no "/" or "\" in any label the path is exactly the
-- labels joined with "/".

local M = {}

-- {{{ function M.path_step
-- One label as it appears in a path of labels (see the note above).
function M.path_step(label)
    return (label:gsub("\\", "\\\\"):gsub("/", "\\/"))
end
-- }}}

-- {{{ function M.split_path
-- The reverse of joining path steps: "home/a\/b" gives { "home", "a/b" }.
-- For readers of `where` and for tests; nothing in the tree needs it.
function M.split_path(path)
    local steps = {}
    local current = {}
    local position = 1
    while position <= #path do
        local c = path:sub(position, position)
        -- a backslash: the next character is part of the label as written
        -- a slash: the end of one step
        -- anything else: part of the label
        if c == "\\" then
            current[#current + 1] = path:sub(position + 1, position + 1)
            position = position + 2
        elseif c == "/" then
            steps[#steps + 1] = table.concat(current)
            current = {}
            position = position + 1
        else
            current[#current + 1] = c
            position = position + 1
        end
    end
    steps[#steps + 1] = table.concat(current)
    return steps
end
-- }}}

-- {{{ local function where_path
local function where_path(room_dir)
    return room_dir .. "/where"
end
-- }}}

-- {{{ function M.write
-- room_dir: string, the room's folder.  labels: string, the path of
-- labels.  The folder line
-- records room_dir itself, so the file always names the folder it is in,
-- even after the home folder has been moved and rewritten.  Written to a
-- temporary name and renamed, so a reader never sees half a file.
function M.write(room_dir, labels)
    local temporary = where_path(room_dir) .. ".tmp"
    local f = assert(io.open(temporary, "w"))
    f:write("folder = " .. room_dir .. "\n")
    f:write("labels = " .. labels .. "\n")
    f:close()
    assert(os.rename(temporary, where_path(room_dir)))
end
-- }}}

-- {{{ function M.read
-- Gives { folder = string, labels = string }.  A missing file, or one
-- lacking either line, is an error: it
-- means the room tree was not loaded when the room was made or last
-- changed, and that should be found, not papered over.
function M.read(room_dir)
    local f = io.open(where_path(room_dir), "r")
    -- no where file: say which room and why it matters
    if not f then
        error("room-tree: no where file in " .. room_dir
            .. " (was the room tree loaded when this room was made?)")
    end
    local fields = {}
    for line in f:lines() do
        local key, value = line:match("^(.-) = (.*)$")
        -- a key = value line is kept; any other line is a damaged file
        if key then
            fields[key] = value
        else
            f:close()
            error("room-tree: unreadable line in " .. where_path(room_dir) .. ": " .. line)
        end
    end
    f:close()
    -- both lines must be there; a half-written file is an error
    if fields.folder == nil or fields.labels == nil then
        error("room-tree: where file in " .. room_dir .. " is missing folder or labels")
    end
    return { folder = fields.folder, labels = fields.labels }
end
-- }}}

return M
