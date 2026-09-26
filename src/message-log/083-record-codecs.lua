-- 083-record-codecs.lua — how a message is written into a room's log file,
-- and read back: one line per message, its fields separated by tabs.
--
-- A "codec" is a pair of translators: one turns a message into the text
-- written in the file, the other turns that text back into a message.
-- There is one shape, tsv (the owner's answer to planning question 8,
-- 2026-09-25: "okay... wink ;)").  It is still looked up in a table by name
-- rather than called directly, so another shape could be added back beside
-- it without touching the rest of the log.  Two others were built and
-- measured in rounds 1 and 2 and retired in round 3 (they are in git
-- history): a labelled block per message, easiest to read in less but 40%
-- larger, and one JSON object per line, readable by JSON tools but 50%
-- larger, slowest, and needing a bundled JSON library.
--
--   tsv    one line per message, fields separated by tabs.  Tabs, line
--          breaks and backslashes inside the text are written as \t, \n,
--          \r and \\ so the message stays on one line.  grep shows a whole
--          message per hit; a person grepping for a multi-line text must
--          write the line break as \n.
--
-- The record the codec carries (all fields always present, never nil):
--   id       string  message id (see 082-message-ids.lua for its alphabet)
--   from     string  "me", or the address it arrived from as "<host> <port>"
--                    (see 082-message-ids.lua check_from); proves nothing
--                    about who wrote it — the signature, if any, is the
--                    last line of the text
--   written  integer seconds since 1970 when its writer wrote it (their clock)
--   arrived  integer seconds since 1970 when it reached this home
--   kind     string  "message", "correction" or "deletion" (edits: section 3)
--   target   string  the id a correction/deletion names; "" for a message
--   text     string  any bytes at all, including tabs, newlines, NUL, and
--                    bytes that are not valid UTF-8
--
-- The codec also gives an "id marker": a piece of text that can appear in
-- the file only at the start of the record with that id (never inside a
-- message's text, because the text's tabs and line breaks are escaped, so
-- the marker's pattern cannot form there).  The duplicate check uses it to
-- find an id with one plain text search instead of decoding every record.

local codecs = {}

local KINDS = { message = true, correction = true, deletion = true }

-- {{{ local function check_decoded
-- The decoder ends here, so a record that came back from the file with a
-- missing or malformed field is refused with a reason.
local function check_decoded(record, shape, raw)
    -- Path: a known kind — continue checking.  Unknown — the file is damaged
    -- or written by a newer program; refuse rather than guess.
    if not KINDS[record.kind] then
        error("message-log: " .. shape .. " record has unknown kind '"
            .. tostring(record.kind) .. "': " .. raw:sub(1, 80), 0)
    end
    for _, field in ipairs({ "id", "from", "target", "text" }) do
        -- Path: string field present — fine.  Absent — damaged record.
        if type(record[field]) ~= "string" then
            error("message-log: " .. shape .. " record lacks '" .. field .. "': " .. raw:sub(1, 80), 0)
        end
    end
    for _, field in ipairs({ "written", "arrived" }) do
        -- Path: whole number — fine.  Anything else — damaged record.
        if type(record[field]) ~= "number" or record[field] ~= math.floor(record[field]) then
            error("message-log: " .. shape .. " record has a bad '" .. field .. "': " .. raw:sub(1, 80), 0)
        end
    end
    return record
end
-- }}}

-- {{{ local function to_whole_number
local function to_whole_number(text, shape, field, raw)
    local number = tonumber(text)
    -- Path: digits only — the number.  Anything else — damaged record.
    if not text:match("^%d+$") or not number then
        error("message-log: " .. shape .. " record has a bad '" .. field .. "' ("
            .. text .. "): " .. raw:sub(1, 80), 0)
    end
    return number
end
-- }}}

------------------------------------------------------------------------------
-- tsv
------------------------------------------------------------------------------

-- Escapes, one table each way.  Only these four characters are escaped;
-- everything else (UTF-8, NUL, other control bytes) is written as it is.
local TSV_ESCAPE = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r" }
local TSV_UNESCAPE = { ["\\"] = "\\", t = "\t", n = "\n", r = "\r" }

-- {{{ local function tsv_unescape
local function tsv_unescape(text, raw)
    return (text:gsub("\\(.?)", function(letter)
        local plain = TSV_UNESCAPE[letter]
        -- Path: a known escape — its character.  Unknown (or a lone '\' at
        -- the end) — the line was not written by this codec.
        if not plain then
            error("message-log: tsv record has an unknown escape '\\" .. letter .. "': " .. raw:sub(1, 80), 0)
        end
        return plain
    end))
end
-- }}}

-- {{{ local function split_tabs
-- Splits a line on every tab, keeping empty fields (Lua 5.1's gmatch would
-- drop or double them, so this walks with find instead).
local function split_tabs(line)
    local fields = {}
    local start = 1
    while true do
        local tab = line:find("\t", start, true)
        -- Path: another tab — cut a field and go on.  No more — last field.
        if not tab then
            fields[#fields + 1] = line:sub(start)
            return fields
        end
        fields[#fields + 1] = line:sub(start, tab - 1)
        start = tab + 1
    end
end
-- }}}

codecs.tsv = {}

-- {{{ function codecs.tsv.encode
-- Field order on disk: id, from, written, arrived, kind, target, text.
function codecs.tsv.encode(record)
    return table.concat({
        record.id, record.from, tostring(record.written), tostring(record.arrived),
        record.kind, record.target, (record.text:gsub("[\\\t\n\r]", TSV_ESCAPE)),
    }, "\t") .. "\n"
end
-- }}}

-- {{{ function codecs.tsv.decode
-- `raw` is one line without its newline.
function codecs.tsv.decode(raw)
    local fields = split_tabs(raw)
    -- Path: seven fields — a record.  Other counts — not a tsv record.
    if #fields ~= 7 then
        error("message-log: tsv record has " .. #fields .. " fields, wanted 7: " .. raw:sub(1, 80), 0)
    end
    return check_decoded({
        id = fields[1],
        from = fields[2],
        written = to_whole_number(fields[3], "tsv", "written", raw),
        arrived = to_whole_number(fields[4], "tsv", "arrived", raw),
        kind = fields[5],
        target = fields[6],
        text = tsv_unescape(fields[7], raw),
    }, "tsv", raw)
end
-- }}}

-- {{{ function codecs.tsv.id_marker
-- A tsv record's id is the start of a line and is followed by a tab; text
-- has its tabs and newlines escaped, so "\n<id>\t" occurs nowhere else.
function codecs.tsv.id_marker(id)
    return "\n" .. id .. "\t"
end
-- }}}

------------------------------------------------------------------------------
-- choosing a codec
------------------------------------------------------------------------------

-- The shape every log is written and read in.  Not a config key: the owner
-- chose it.  To add a shape back, give it a codec above, list it in SHAPES,
-- and decide how a log holding more than one shape is read (round 2 built
-- recognising each record by its first characters; see git history).
codecs.SHAPE = "tsv"

codecs.SHAPES = { tsv = codecs.tsv }

-- {{{ function codecs.get
-- Gives the codec for a shape name; an unknown name is an error, never a
-- quiet substitute.
function codecs.get(shape)
    local codec = codecs.SHAPES[shape]
    -- Path: known shape — its codec.  Unknown — refuse.
    if not codec then
        error("message-log: record shape '" .. tostring(shape) .. "' is not one of tsv", 0)
    end
    return codec
end
-- }}}

return codecs
