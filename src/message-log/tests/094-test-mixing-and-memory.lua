-- 094-test-mixing-and-memory.lua — checks what happens when log.record-shape
-- is changed on a log that already has records (log.shape-mixing = fixed
-- refuses, per-record reads both), and that the remembered duplicate check
-- stays right when the file grows behind its back or is replaced.
--
-- Run: luajit 094-test-mixing-and-memory.lua [DIR] [real|stand-in]

local DIR = "/home/ritz/programs/rao-chat"
-- Path: a DIR argument — use it.  None — the hard-coded project folder.
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
local t = dofile(DIR .. "/src/message-log/tests/090-test-harness.lua").start(arg, "mixing")
local log, rooms = t.log, t.rooms
local codecs = require("083-record-codecs")

-- Every pair of shapes: file one message in each, then read.
for _, before in ipairs(t.SHAPES) do
    for _, after in ipairs(t.SHAPES) do
        -- Path: two different shapes — a change worth testing.  The same
        -- shape twice — nothing changes; skipped.
        if before ~= after then
            for _, check in ipairs(t.CHECKS) do
                local label = before .. "->" .. after .. "/" .. check .. ": "

                -- per-record: both read, both found, repeats refused.
                local home = t.fresh_home(t.settings(before, "per-record", check))
                local room = t.new_room(home)
                local old = t.message({ text = "old\nshape", written = 10 })
                log.append(home, room, old)
                rooms.set_config(home, "log.record-shape", after)
                local new = t.message({ text = "new\tshape", written = 5 })
                log.append(home, room, new)
                local records = log.read(home, room)
                t.check(#records == 2 and records[1].text == old.text and records[2].text == new.text,
                    label .. "per-record reads a log holding both shapes")
                t.check(log.append(home, room, old) == "duplicate",
                    label .. "per-record finds an id written in the old shape")
                t.check(log.read_ordered(home, room)[1].id == new.id, label .. "per-record orders across shapes")

                -- fixed: the second shape makes the log unreadable, loudly.
                local fixed_home = t.fresh_home(t.settings(before, "fixed", check))
                local fixed_room = t.new_room(fixed_home)
                log.append(fixed_home, fixed_room, t.message())
                rooms.set_config(fixed_home, "log.record-shape", after)
                t.refuses(function() log.read(fixed_home, fixed_room) end, "shape-mixing is fixed",
                    label .. "fixed refuses to read a log in another shape")
            end
        end
    end
end

-- The remembered check sees records appended by another program.
do
    local home = t.fresh_home(t.settings("tsv", "fixed", "remembered"))
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
    local home = t.fresh_home(t.settings("block", "fixed", "remembered"))
    local room = t.new_room(home)
    local first = t.message({ text = string.rep("a long message ", 20) })
    log.append(home, room, first)
    t.check(log.has_message(home, room, first.id), "remembered: knows the first id")
    -- Replace the log with a different, longer one.
    local replacement = t.message({ text = string.rep("another message ", 40) })
    local file = assert(io.open(rooms.log_path(home, room), "wb"))
    file:write(codecs.block.encode({ id = replacement.id, from = "me", written = 1, arrived = 1,
        kind = "message", target = "", text = replacement.text }))
    file:close()
    t.check(not log.has_message(home, room, first.id), "remembered: forgets ids of a replaced file")
    t.check(log.has_message(home, room, replacement.id), "remembered: learns the replacement's ids")
    -- Truncate to nothing.
    assert(io.open(rooms.log_path(home, room), "wb")):close()
    t.check(not log.has_message(home, room, replacement.id), "remembered: an emptied file holds nothing")
end

-- An id that sits only inside some text is not a duplicate, in either check.
for _, shape in ipairs(t.SHAPES) do
    for _, check in ipairs(t.CHECKS) do
        local home = t.fresh_home(t.settings(shape, "per-record", check))
        local room = t.new_room(home)
        local hidden = log.new_message_id()
        local text = codecs.tsv.id_marker(hidden) .. codecs.block.id_marker(hidden)
            .. codecs.jsonl.id_marker(hidden) .. hidden
        log.append(home, room, t.message({ text = text }))
        t.check(not log.has_message(home, room, hidden),
            shape .. "/" .. check .. ": an id quoted in text is not taken for a record")
        t.check(log.append(home, room, t.message({ id = hidden })) == "filed",
            shape .. "/" .. check .. ": and a message with that id can still be filed")
    end
end

t.finish()
