-- 081-message-log.lua — a room's messages: filing them, refusing repeats,
-- catching a repeat that says something different, reading them back in
-- file order or in the order they were written, and corrections.
--
-- Every room folder holds a file called `log` (made empty by room-folders,
-- issue 101, when the room is made).  Filing a message adds one record to
-- the end of that file; the file is never rewritten, so a person can read a
-- room with cat, back it up by copying the folder, and search it with grep.
--
-- Each record notes the address the message arrived from ("me" for your
-- own), never who wrote it: the writer is unknowable by design, and the
-- address proves nothing about authorship.  What a message says about its
-- writer is its signature, the last line of its text, stored as written;
-- showing it apart is a client's job and nothing here checks it.
--
-- Before a record is added, the log is asked whether a record with the same
-- message id is already there.  If so, and it says the same thing, the
-- message is answered "duplicate" and not filed again: a delivery repeated
-- because the first answer was lost does no harm.  (rmail, September 2026:
-- two daemons dialling each other at once filed one message eight times.)
-- If it says something different, that is an error raised to whoever filed
-- it, naming both versions — never settled quietly (owner: "If there's ever
-- a discrepancy it's raised as an error, not a silent warning in some log
-- somewhere that gets auto-corrected").
--
-- Order is decided when reading, never by moving records in the file: a
-- message that arrives late is written at the end of the file but shown
-- where its written time puts it.  Ties go by message id alone — the id is
-- the same on every reader's disk, while the room's folder tag is not.
--
-- After anything is filed the room-folders change bell is rung with "log",
-- so modules that keep derived views can catch up.
--
-- The one choice this module reads from rao-home/config (an absent key is
-- an error, there is no default):
--   log.duplicate-check      scan | remembered           every write and has_message
-- It waits on phase 2 (is the home server one long-running program?).
-- Four keys the owner has answered are no longer read (round 3): the
-- record shape is tsv (083-record-codecs.lua), so log.record-shape and
-- log.shape-mixing are gone; anyone may edit (log.who-may-edit); and a
-- repeat that differs only in the address it came from is a duplicate
-- (log.same-id-new-address).

local rooms = require("002-room-folders")
local ids = require("082-message-ids")
local codecs = require("083-record-codecs")
local reader = require("084-log-reader")
local duplicates = require("085-duplicate-check")
local edits = require("086-edits")

local log = {}

-- {{{ local function duplicate_check
-- Reads log.duplicate-check, the one switch left, once per call.
local function duplicate_check(home)
    return rooms.config_value(home, "log.duplicate-check")
end
-- }}}

-- {{{ local function check_record
-- Refuses a record that could not be written and read back faithfully.
local function check_record(record)
    ids.check_id(record.id, "message id")
    ids.check_from(record.from)
    ids.check_time(record.written, "written")
    ids.check_time(record.arrived, "arrived")
    -- Path: text is a string (any bytes) — fine.  Else — caller error.
    if type(record.text) ~= "string" then
        error("message-log: text must be a string, got " .. type(record.text), 0)
    end
    -- Path: a plain message has no target; an edit names one.
    if record.kind == "message" then
        -- Path: target is "" — fine.  Anything else — a message cannot
        -- point at another message.
        if record.target ~= "" then
            error("message-log: a message record must have target \"\"", 0)
        end
    else
        ids.check_id(record.target, "target")
        -- Path: an edit naming itself — refuse.
        if record.target == record.id then
            error("message-log: an edit cannot name its own id as its target", 0)
        end
    end
end
-- }}}

-- The fields that make up a message's contents.  `arrived` is left out on
-- purpose: every repeated delivery arrives at a new time.  So is `from`: a
-- copy may honestly come from another address — a member who moved, or a
-- missing message fetched from another member during the cross-check
-- (phase 2) — and the address proves nothing about who wrote it.  Owner,
-- 2026-09-25, on the same message arriving from a second address:
-- "duplicate".  The first copy's `from` stays in the file.
local CONTENT_FIELDS = { "written", "kind", "target", "text" }

-- {{{ local function describe
-- One record in words, for the error that names both versions of an id.
local function describe(record)
    local text = record.text
    -- Path: long text — cut to 120 bytes and say so.  Short — whole.
    if #text > 120 then
        text = text:sub(1, 120) .. "...(" .. #record.text .. " bytes)"
    end
    return string.format("{from %q, written %d, kind %s, target %q, text %q}",
        record.from, record.written, record.kind, record.target, text)
end
-- }}}

-- {{{ local function same_id
-- A record with this id is already filed (`kept`); decide what the
-- arriving one is.  Gives "duplicate" or raises an error naming both.
local function same_id(kept, arriving)
    for _, field in ipairs(CONTENT_FIELDS) do
        -- Path: a content field differs — the same id says two different
        -- things; raise it, naming both, file nothing.  All equal — a
        -- repeat, whatever address it came from.
        if kept[field] ~= arriving[field] then
            error("message-log: message id '" .. arriving.id .. "' arrived again with different "
                .. field .. ": filed " .. describe(kept) .. ", arriving " .. describe(arriving), 0)
        end
    end
    return "duplicate"
end
-- }}}

-- {{{ local function file_record
-- Adds one checked record to a room's log unless its id is already there,
-- then rings the bell.  before_filing: function(), or false — run after the
-- repeat check and before writing (edits check their target there, so a
-- repeat of an edit already filed is answered "duplicate", not refused).
-- Gives "filed" or "duplicate"; raises on a conflicting repeat.
local function file_record(home, room_id, record, before_filing)
    local path = rooms.log_path(home, room_id)
    local found, kept = duplicates.find(path, record.id, duplicate_check(home))
    -- Path: the id is already in the log — compare, and file nothing.
    if found then
        return same_id(kept, record)
    end
    -- Path: an extra check to run (edits) — run it; it raises to refuse.
    if before_filing then
        before_filing()
    end
    local encoded = codecs.get(codecs.SHAPE).encode(record)
    -- The whole record goes out in one write to a file opened for appending,
    -- so two programs appending at once put whole records one after the
    -- other (Linux appends each write at the end atomically for regular
    -- files of this size), rather than interleaving pieces.
    local file = io.open(path, "ab")
    -- Path: opened — write.  Not openable — refuse (permissions, disk).
    if not file then
        error("message-log: cannot open " .. path .. " to append", 0)
    end
    file:write(encoded)
    file:close()
    rooms.notify(home, room_id, "log")
    return "filed"
end
-- }}}

-- {{{ function log.new_message_id
-- Gives: string, 32 lower-case hex characters from /dev/urandom.
function log.new_message_id()
    return ids.new_message_id()
end
-- }}}

-- {{{ function log.append
-- message: { id=string, from=string ("me" or "<host> <port>"),
--            written=integer, arrived=integer, text=string (signature, if
--            any, as its last line) }.  A `kind` field, if given, must be
--            "message"; corrections and deletions go through log.correct /
--            log.delete.
-- Gives:   "filed" or "duplicate"; raises when the id is filed already
--          with different contents.
function log.append(home, room_id, message)
    -- Path: kind absent or "message" — a plain message.  Else — refuse, the
    -- edit checks must not be skipped by filing an edit through append.
    if message.kind ~= nil and message.kind ~= "message" then
        error("message-log: append files messages only; use correct or delete for '"
            .. tostring(message.kind) .. "'", 0)
    end
    local record = {
        id = message.id, from = message.from,
        written = message.written, arrived = message.arrived,
        kind = "message", target = "", text = message.text,
    }
    check_record(record)
    return file_record(home, room_id, record, false)
end
-- }}}

-- {{{ local function file_edit
local function file_edit(home, room_id, record)
    check_record(record)
    return file_record(home, room_id, record, function()
        local records = reader.parse(reader.read_file(rooms.log_path(home, room_id)))
        edits.check(records, record)
    end)
end
-- }}}

-- {{{ function log.correct
-- correction: { id=string (a new message id), from=string,
--               written=integer, arrived=integer, target=string (the id
--               of the message corrected), text=string (the new text) }.
-- Anyone may correct any message.  Gives "filed" or "duplicate"; raises an
-- error when the target is missing, is itself an edit, or is deleted.
function log.correct(home, room_id, correction)
    return file_edit(home, room_id, {
        id = correction.id, from = correction.from,
        written = correction.written, arrived = correction.arrived,
        kind = "correction", target = correction.target, text = correction.text,
    })
end
-- }}}

-- {{{ function log.delete
-- deletion: { id=string (a new message id), from=string, written=integer,
--             arrived=integer, target=string }.  Gives as log.correct.
-- Deleting hides: the original text stays in the file.
function log.delete(home, room_id, deletion)
    return file_edit(home, room_id, {
        id = deletion.id, from = deletion.from,
        written = deletion.written, arrived = deletion.arrived,
        kind = "deletion", target = deletion.target, text = "",
    })
end
-- }}}

-- {{{ function log.has_message
-- Gives bool: is a record with this id (message or edit) in the room's log.
function log.has_message(home, room_id, message_id)
    local found = duplicates.find(rooms.log_path(home, room_id), message_id,
        duplicate_check(home))
    return found
end
-- }}}

-- {{{ function log.read
-- Gives every record in the room's log in file order: messages, and any
-- corrections and deletions, each { id, from, written, arrived, kind,
-- target, text } (see 083-record-codecs.lua).  Plain messages have kind
-- "message" and target "".
function log.read(home, room_id)
    return (reader.parse(reader.read_file(rooms.log_path(home, room_id))))
end
-- }}}

-- {{{ function log.read_ordered
-- Gives the room as a person should see it: messages only, edits applied,
-- sorted by written time, then by message id.  Each view is { id, from,
-- written, arrived, text, edited=bool, deleted=bool, changed_from=string }
-- (see 086-edits.lua).  Nothing local (the room's folder tag, the arrival
-- time, the file order) takes part in the order, so two homes holding the
-- same messages show them in the same order.
function log.read_ordered(home, room_id)
    local views = edits.apply(log.read(home, room_id))
    table.sort(views, function(a, b)
        -- Path: written times differ — earlier first.  Same time — smaller
        -- message id first (ids never repeat within a log).
        if a.written ~= b.written then
            return a.written < b.written
        end
        return a.id < b.id
    end)
    return views
end
-- }}}

-- {{{ function log.forget_remembered_ids
-- Drops the in-memory records kept by log.duplicate-check = remembered
-- (argument: a log path, or "all").  Only needed by tests and tools that
-- replace log files; replacement is also detected on its own.
function log.forget_remembered_ids(path)
    duplicates.forget(path)
end
-- }}}

return log
