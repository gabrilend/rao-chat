-- 085-duplicate-check.lua — answers "is a record with this id already in
-- this log, and if so, what does it say?", which is what makes a repeated
-- delivery safe: the second copy is recognised and not filed again, and a
-- second copy that says something different can be caught and raised to
-- the person (081-message-log.lua compares the two).
--
-- Two ways of answering are built (config key log.duplicate-check, found
-- while building issue 105; the issue left "does the check need an index of
-- ids?" to measurement):
--
--   scan        read the whole log file every time and search it for the
--               id's marker (a piece of text that can only occur where that
--               record begins; see id_marker in 083-record-codecs.lua), then
--               decode just that one record.  Nothing is kept between calls,
--               so nothing can go stale, but the work grows with the log.
--   remembered  keep, in this program's memory, every record seen in each
--               log (by id) and how far into the file they were read.  Each
--               check reads only what was added to the file since the last
--               one.  The file is still the truth: before trusting its
--               memory the check makes sure the file still has the same
--               beginning and the same bytes just before where it stopped
--               reading; if not (the file was replaced, for example a test
--               making a fresh home in the same place), it forgets and reads
--               from the start.  Nothing is written to disk.  Keeping whole
--               records (not just ids) costs memory about the size of the
--               log's text, and is what lets a repeat be compared without
--               going back to the file.

local codecs = require("083-record-codecs")
local reader = require("084-log-reader")

local duplicates = {}

-- {{{ local function marker_start
-- Gives the 1-based byte position where the record marked by `marker`
-- (which starts with "\n") begins in `content`, or false when the marker is
-- nowhere.  The very start of the file counts as if a newline stood before.
local function marker_start(content, marker)
    local at_start = marker:sub(2)
    -- Path: the file starts with the record — position 1.  Else search the
    -- rest; the record begins just after the marker's leading newline.
    if content:sub(1, #at_start) == at_start then
        return 1
    end
    local found = content:find(marker, 1, true)
    -- Path: found — the byte after its newline.  Not found — false.
    if found then
        return found + 1
    end
    return false
end
-- }}}

-- {{{ local function scan
local function scan(path, id)
    local content = reader.read_file(path)
    local start = marker_start(content, codecs.get(codecs.SHAPE).id_marker(id))
    -- Path: the id's marker is in the file — decode that record.  Not
    -- there — absent.
    if start then
        return true, reader.parse_one(content, start)
    end
    return false
end
-- }}}

-- What `remembered` keeps per log path:
--   offset   integer  bytes of the file already read into `records`
--   head     string   the file's first bytes (up to 64) when last read
--   tail     string   the (up to 64) bytes just before `offset`
--   records  table    id string -> the first record filed with that id
--                     (a table as 083 describes; the log never holds two
--                     records with one id, because filing refuses it)
local memory = {}

local FINGERPRINT_BYTES = 64

-- {{{ local function still_same_file
-- True when the file still starts with the remembered head and still holds
-- the remembered tail just before the remembered offset.  Ids are random,
-- so a different file matching both is not a practical worry.
local function still_same_file(file, kept)
    local head = file:read(#kept.head) or ""
    -- Path: the beginning changed — a different file.
    if head ~= kept.head then
        return false
    end
    file:seek("set", kept.offset - #kept.tail)
    local tail = file:read(#kept.tail) or ""
    return tail == kept.tail
end
-- }}}

-- {{{ local function remembered
local function remembered(path, id)
    local file = io.open(path, "rb")
    -- Path: opened — check.  Missing — the room is not there.
    if not file then
        error("message-log: no log at " .. path .. " (is the room there?)", 0)
    end
    local size = file:seek("end")
    local kept = memory[path]
    file:seek("set", 0)
    -- Path: nothing remembered, the file is now shorter than what was read,
    -- or it no longer matches — start afresh from byte 0.  Otherwise carry on
    -- from the remembered offset.
    if not kept or size < kept.offset or not still_same_file(file, kept) then
        kept = { offset = 0, head = "", tail = "", records = {} }
        memory[path] = kept
    end
    file:seek("set", kept.offset)
    local added = file:read("*a")
    -- Path: something new — parse it.  Nothing new — memory is current.
    if #added > 0 then
        local records = reader.parse(added)
        for _, record in ipairs(records) do
            -- Path: first time this id is seen — keep it.  Seen before —
            -- the file holds two records with one id, which filing never
            -- does (hand-edited or written by a faulty program); the first
            -- one stays remembered, as scan would also find the first.
            if not kept.records[record.id] then
                kept.records[record.id] = record
            end
        end
        kept.offset = kept.offset + #added
        file:seek("set", 0)
        kept.head = file:read(math.min(FINGERPRINT_BYTES, kept.offset))
        file:seek("set", kept.offset - math.min(FINGERPRINT_BYTES, kept.offset))
        kept.tail = file:read(math.min(FINGERPRINT_BYTES, kept.offset))
    end
    file:close()
    local record = kept.records[id]
    -- Path: remembered — found, with its record.  Not — absent.
    if record then
        return true, record
    end
    return false
end
-- }}}

local STRATEGIES = { ["scan"] = scan, ["remembered"] = remembered }

-- {{{ function duplicates.find
-- path:     string, the log file.
-- id:       string, the message id looked for.
-- strategy: string, "scan" or "remembered" (log.duplicate-check).
-- Gives:    true and the record already filed with that id, or false.
function duplicates.find(path, id, strategy)
    local check = STRATEGIES[strategy]
    -- Path: known strategy — run it.  Unknown — refuse (config typo).
    if not check then
        error("message-log: log.duplicate-check '" .. tostring(strategy)
            .. "' is not one of scan, remembered", 0)
    end
    return check(path, id)
end
-- }}}

-- {{{ function duplicates.forget
-- Drops what `remembered` holds for one log (or every log when path is
-- the string "all").  For tests and for a program that knows a log was
-- replaced; the fingerprint check catches replacement anyway.
function duplicates.forget(path)
    -- Path: "all" — clear everything.  A path — clear that one.
    if path == "all" then
        memory = {}
    else
        memory[path] = nil
    end
end
-- }}}

return duplicates
