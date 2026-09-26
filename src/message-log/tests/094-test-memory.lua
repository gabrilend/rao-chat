-- 094-test-memory.lua — checks that the remembered duplicate check stays
-- right when the file grows behind its back or is replaced, and that an id
-- quoted inside a message's text is never taken for a record, under both
-- duplicate checks.  (Round 2's tests of mixing record shapes in one log
-- went with the retired shapes.)
--
-- Run: luajit 094-test-memory.lua [DIR] [real|stand-in]

local DIR = "/home/ritz/programs/rao-chat"
-- Path: a DIR argument — use it.  None — the hard-coded project folder.
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
local t = dofile(DIR .. "/src/message-log/tests/090-test-harness.lua").start(arg, "memory")
local log, rooms = t.log, t.rooms
local codecs = require("083-record-codecs")

-- The remembered check sees records appended by another program.
do
    local home = t.fresh_home(t.settings("remembered"))
    local room = t.new_room(home)
    log.append(home, room, t.message())
    local outside = t.message({ id = "written-by-someone-else" })
    local file = assert(io.open(rooms.log_path(home, room), "ab"))
    file:write(codecs.tsv.encode({ id = outside.id, from = "me", written = outside.written, arrived = 1,
        kind = "message", target = "", text = outside.text }))
    file:close()
    t.check(log.has_message(home, room, outside.id), "remembered: sees a record another program appended")
    t.check(log.append(home, room, outside) == "duplicate", "remembered: refuses it as a duplicate")
    local changed = t.message({ id = outside.id, text = "not what the other program wrote" })
    t.refuses(function() log.append(home, room, changed) end, "different text",
        "remembered: and compares against what the other program wrote")
end

-- The remembered check notices a replaced file.
do
    local home = t.fresh_home(t.settings("remembered"))
    local room = t.new_room(home)
    local first = t.message({ text = string.rep("a long message ", 20) })
    log.append(home, room, first)
    t.check(log.has_message(home, room, first.id), "remembered: knows the first id")
    -- Replace the log with a different, longer one.
    local replacement = t.message({ text = string.rep("another message ", 40) })
    local file = assert(io.open(rooms.log_path(home, room), "wb"))
    file:write(codecs.tsv.encode({ id = replacement.id, from = "me", written = 1, arrived = 1,
        kind = "message", target = "", text = replacement.text }))
    file:close()
    t.check(not log.has_message(home, room, first.id), "remembered: forgets ids of a replaced file")
    t.check(log.has_message(home, room, replacement.id), "remembered: learns the replacement's ids")
    -- Truncate to nothing.
    assert(io.open(rooms.log_path(home, room), "wb")):close()
    t.check(not log.has_message(home, room, replacement.id), "remembered: an emptied file holds nothing")
end

-- An id that sits only inside some text is not a duplicate, in either check.
for _, check in ipairs(t.CHECKS) do
    local home = t.fresh_home(t.settings(check))
    local room = t.new_room(home)
    local hidden = log.new_message_id()
    local text = codecs.tsv.id_marker(hidden) .. hidden .. "\t" .. "\n" .. hidden
    log.append(home, room, t.message({ text = text }))
    t.check(not log.has_message(home, room, hidden),
        check .. ": an id quoted in text is not taken for a record")
    t.check(log.append(home, room, t.message({ id = hidden })) == "filed",
        check .. ": and a message with that id can still be filed")
end

-- A log holding a record in a retired shape (written by round 2 with
-- log.record-shape = block) is refused loudly when read.  When filing, the
-- two checks differ: remembered decodes every new record and so refuses;
-- scan decodes only the record its id marker points at, so it does not see
-- the damaged lines and files the message (the next read still refuses).
local FILING_WITH_DAMAGE = {
    -- {{{ local function remembered
    ["remembered"] = function(home, room)
        t.refuses(function() log.append(home, room, t.message()) end, "fields, wanted 7",
            "remembered: a block-shaped record left in a log is an error when filing")
    end,
    -- }}}
    -- {{{ local function scan
    ["scan"] = function(home, room)
        t.check(log.append(home, room, t.message()) == "filed",
            "scan: a block-shaped record elsewhere in the log is not looked at when filing")
    end,
    -- }}}
}
for _, check in ipairs(t.CHECKS) do
    local home = t.fresh_home(t.settings(check))
    local room = t.new_room(home)
    local file = assert(io.open(rooms.log_path(home, room), "ab"))
    file:write("id: old\nfrom: me\nwritten: 1\narrived: 1\nkind: message\ntarget:\ntext:\n  hi\n\n")
    file:close()
    FILING_WITH_DAMAGE[check](home, room)
    t.refuses(function() log.read(home, room) end, "fields, wanted 7",
        check .. ": reading a log holding a block-shaped record is an error")
end

t.finish()
