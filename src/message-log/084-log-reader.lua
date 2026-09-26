-- 084-log-reader.lua — turns the text of a log file back into a list of
-- records, in the order they sit in the file.
--
-- The reader walks the file a line at a time; each line is one record in
-- the log's one shape (tsv, see 083-record-codecs.lua), handed to that
-- shape's translator.  Round 2 also read logs mixing several shapes, with
-- a switch deciding whether that was allowed (log.shape-mixing); with one
-- shape left there is nothing to mix, and both went in round 3.
--
-- A file that ends part-way through a record (no final newline) is an
-- error, not something to skip: on this machine it means a write was cut
-- short, and the person should see it.

local codecs = require("083-record-codecs")

local reader = {}

-- {{{ local function parse_at
-- Decodes the one record that begins at byte `position` of `content`.
-- Gives the record and the byte position just after it.
local function parse_at(content, position)
    local line_end = content:find("\n", position, true)
    -- Path: the line is finished — go on.  No newline left — the file
    -- stops mid-record.
    if not line_end then
        error("message-log: the log ends part-way through a record (a write cut short?): '"
            .. content:sub(position, position + 79) .. "'", 0)
    end
    local line = content:sub(position, line_end - 1)
    -- Path: an empty line where a record should begin — the file was
    -- edited by hand or damaged; refuse.  Otherwise a record starts here.
    if line == "" then
        error("message-log: an empty line where a record should begin, at byte " .. position, 0)
    end
    return codecs.get(codecs.SHAPE).decode(line), line_end + 1
end
-- }}}

-- {{{ function reader.parse
-- content: string, the file's bytes (or a tail of them that starts at a
--          record boundary).
-- Gives:   list of records (see 083 for their fields) and the list of the
--          byte position (integer, 1-based, within `content`) where each
--          record begins — both lists the same length.
function reader.parse(content)
    local records, starts = {}, {}
    local position = 1
    local length = #content
    while position <= length do
        local record, after = parse_at(content, position)
        records[#records + 1] = record
        starts[#starts + 1] = position
        position = after
    end
    return records, starts
end
-- }}}

-- {{{ function reader.parse_one
-- Decodes the single record beginning at byte `position` (integer, 1-based)
-- of `content`; used by the duplicate check once it has found where a
-- repeated id's record starts, so it can compare contents without decoding
-- the whole log.  Gives the record.
function reader.parse_one(content, position)
    local record = parse_at(content, position)
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
