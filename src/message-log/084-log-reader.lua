-- 084-log-reader.lua — turns the text of a log file back into a list of
-- records, in the order they sit in the file.
--
-- The reader walks the file a line at a time.  At the start of each record
-- it decides which shape the record is in, then takes either that one line
-- (tsv, jsonl) or every line up to the next blank line (block), and hands
-- the piece to that shape's translator (083-record-codecs.lua).
--
-- How the shape is decided is itself an undecided choice (config key
-- log.shape-mixing, found while building issue 105):
--   fixed       every record must be in the shape named by log.record-shape;
--               a record in any other shape is an error that says so.
--               Changing log.record-shape on a home with existing logs makes
--               those logs unreadable until the key is changed back.
--   per-record  each record is recognised by its first characters, so a log
--               may hold records of several shapes, for example after the
--               owner changes log.record-shape.  Nothing is ever rewritten.
--
-- A file that ends part-way through a record (no final newline, or a block
-- without its closing blank line) is an error, not something to skip: on
-- this machine it means a write was cut short, and the person should see it.

local codecs = require("083-record-codecs")

local reader = {}

-- How to pick the shape of the record starting at `first_line`.  One entry
-- per value of log.shape-mixing.
local SHAPE_PICKERS = {
    -- {{{ local function fixed
    ["fixed"] = function(first_line, configured_shape)
        local seen = codecs.detect(first_line)
        -- Path: the record looks like the configured shape — use it.  Looks
        -- like another shape — refuse, naming both, since the likely cause is
        -- a change of log.record-shape on a log that already had records.
        if seen ~= configured_shape then
            error("message-log: a record looks like " .. seen .. " but log.record-shape is "
                .. configured_shape .. " and log.shape-mixing is fixed: '"
                .. first_line:sub(1, 80) .. "'", 0)
        end
        return configured_shape
    end,
    -- }}}
    -- {{{ local function per_record
    ["per-record"] = function(first_line, configured_shape)
        return codecs.detect(first_line)
    end,
    -- }}}
}

-- {{{ function reader.picker
-- Gives the shape picker for a log.shape-mixing value; unknown is an error.
function reader.picker(mixing)
    local pick = SHAPE_PICKERS[mixing]
    -- Path: known value — its picker.  Unknown — refuse (config typo).
    if not pick then
        error("message-log: log.shape-mixing '" .. tostring(mixing)
            .. "' is not one of fixed, per-record", 0)
    end
    return pick
end
-- }}}

-- {{{ local function parse_at
-- Decodes the one record that begins at byte `position` of `content`.
-- pick: a shape picker from SHAPE_PICKERS.  Gives the record, the shape it
-- was found in, and the byte position just after it.
local function parse_at(content, position, pick, shape)
    local line_end = content:find("\n", position, true)
    -- Path: the line is finished — go on.  No newline left — the file
    -- stops mid-record.
    if not line_end then
        error("message-log: the log ends part-way through a record (a write cut short?): '"
            .. content:sub(position, position + 79) .. "'", 0)
    end
    local first_line = content:sub(position, line_end - 1)
    -- Path: an empty line where a record should begin — the file was
    -- edited by hand or damaged; refuse.  Otherwise a record starts here.
    if first_line == "" then
        error("message-log: an empty line where a record should begin, at byte " .. position, 0)
    end
    local record_shape = pick(first_line, shape)
    local codec = codecs.get(record_shape)
    local raw, after
    -- Path: a one-line shape — the record is this line.  A block — the
    -- record runs to the first blank line (no line inside a block is
    -- ever empty, since text lines are indented).
    if codec.record_ends == "line" then
        raw = first_line
        after = line_end + 1
    else
        local blank = content:find("\n\n", position, true)
        -- Path: the closing blank line is there — cut.  Missing — the
        -- file stops mid-record.
        if not blank then
            error("message-log: the log ends part-way through a block record: '"
                .. first_line:sub(1, 80) .. "'", 0)
        end
        raw = content:sub(position, blank - 1)
        after = blank + 2
    end
    return codec.decode(raw), record_shape, after
end
-- }}}

-- {{{ function reader.parse
-- content: string, the file's bytes (or a tail of them that starts at a
--          record boundary).
-- mixing:  string, "fixed" or "per-record".
-- shape:   string, the configured log.record-shape.
-- Gives:   list of records (see 083 for their fields), the list of the
--          shape each record was found in, and the list of the byte
--          position (integer, 1-based, within `content`) where each record
--          begins — all three lists the same length.
function reader.parse(content, mixing, shape)
    local pick = reader.picker(mixing)
    local records, shapes, starts = {}, {}, {}
    local position = 1
    local length = #content
    while position <= length do
        local record, record_shape, after = parse_at(content, position, pick, shape)
        records[#records + 1] = record
        shapes[#shapes + 1] = record_shape
        starts[#starts + 1] = position
        position = after
    end
    return records, shapes, starts
end
-- }}}

-- {{{ function reader.parse_one
-- Decodes the single record beginning at byte `position` (integer, 1-based)
-- of `content`; used by the duplicate check once it has found where a
-- repeated id's record starts, so it can compare contents without decoding
-- the whole log.  Gives the record.
function reader.parse_one(content, position, mixing, shape)
    local record = parse_at(content, position, reader.picker(mixing), shape)
    return record
end
-- }}}

-- {{{ function reader.read_file
-- Gives the whole file as a string; a missing file is an error (101 makes
-- an empty log in every room, so a missing one means no such room).
function reader.read_file(path)
    local file = io.open(path, "rb")
    -- Path: opened — read it.  Not there — refuse.
    if not file then
        error("message-log: no log at " .. path .. " (is the room there?)", 0)
    end
    local content = file:read("*a")
    file:close()
    return content
end
-- }}}

return reader
