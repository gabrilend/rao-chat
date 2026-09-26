-- 095-measure.lua — measures each record shape: how many bytes a message
-- takes in the log, how long filing 10,000 messages takes (each filing
-- includes the duplicate check), and how long reading them back takes,
-- in file order and in written order.  Run for both duplicate checks, so
-- the "does the check need an index of ids?" question gets a number.
--
-- The messages are a fixed, repeatable mix: short chat lines, a few long
-- ones, some with line breaks and tabs, some non-ASCII.  Times are wall
-- clock (the disk is RAM-backed tmp/shared-memory, so this measures the
-- code, not a spinning disk).
--
-- Run: luajit 095-measure.lua [DIR] [real|stand-in] [count]
-- Prints one line per shape and check; findings are copied into
-- 099-options.lua by hand after a run (the numbers there say when).

local DIR = "/home/ritz/programs/rao-chat"
-- Path: a DIR argument — use it.  None — the hard-coded project folder.
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
local count = tonumber(arg[3] or "10000")
local t = dofile(DIR .. "/src/message-log/tests/090-test-harness.lua").start(arg, "measure")
local log, rooms = t.log, t.rooms
local ffi = require("ffi")

ffi.cdef([[
    typedef struct { long seconds; long nanoseconds; } rao_timespec;
    int clock_gettime(int clock, rao_timespec *now);
]])

-- {{{ local function now
local function now()
    local spec = ffi.new("rao_timespec")
    ffi.C.clock_gettime(1, spec) -- 1 = CLOCK_MONOTONIC
    return tonumber(spec.seconds) + tonumber(spec.nanoseconds) / 1e9
end
-- }}}

local SAMPLES = {
    "ok", "on my way", "did you see the thing about the bridge?",
    "haha yes", "can you send me the notes from tuesday",
    "line one\nline two\nline three",
    "a tab\there and a backslash \\ there",
    "héllo, ça va? 日本語 🙂",
    string.rep("a longer message that goes on for a while. ", 6),
    "",
}

-- {{{ local function make_messages
local function make_messages()
    local messages = {}
    for position = 1, count do
        messages[position] = {
            id = log.new_message_id(),
            from = (position % 3 == 0) and "me" or "198.51.100.23 40404",
            -- Mostly in order, every seventh one late by a minute.
            written = 1790000000 + position * 5 - ((position % 7 == 0) and 60 or 0),
            arrived = 1790000000 + position * 5,
            text = SAMPLES[(position % #SAMPLES) + 1],
        }
    end
    return messages
end
-- }}}

-- {{{ local function file_size
local function file_size(path)
    local file = assert(io.open(path, "rb"))
    local size = file:seek("end")
    file:close()
    return size
end
-- }}}

local messages = make_messages()
local text_bytes = 0
for _, message in ipairs(messages) do
    text_bytes = text_bytes + #message.text
end
print(string.format("measure [%s]: %d messages, average text %.1f bytes",
    t.neighbour, count, text_bytes / count))
print(string.format("%-6s %-10s %-11s %9s %10s %10s %10s %12s",
    "shape", "check", "mixing", "bytes/msg", "append s", "read s", "ordered s", "repeat all s"))

for _, shape in ipairs(t.SHAPES) do
    for _, check in ipairs(t.CHECKS) do
        for _, mixing in ipairs(t.MIXINGS) do
            local home = t.fresh_home(t.settings(shape, mixing, check))
            local room = t.new_room(home)
            local started = now()
            for _, message in ipairs(messages) do
                log.append(home, room, message)
            end
            local appended = now() - started
            started = now()
            local records = log.read(home, room)
            local read_time = now() - started
            started = now()
            log.read_ordered(home, room)
            local ordered_time = now() - started
            -- Every message delivered a second time: all must be refused.
            started = now()
            local repeats = 0
            for _, message in ipairs(messages) do
                -- Path: refused — as it should be.  Filed — a failure.
                if log.append(home, room, message) == "duplicate" then
                    repeats = repeats + 1
                end
            end
            local repeat_time = now() - started
            -- Path: counts right — print.  Wrong — stop loudly.
            if #records ~= count or repeats ~= count then
                error("measure: " .. shape .. " read " .. #records .. " and refused " .. repeats
                    .. " of " .. count)
            end
            print(string.format("%-6s %-10s %-11s %9.1f %10.3f %10.3f %10.3f %12.3f",
                shape, check, mixing, file_size(rooms.log_path(home, room)) / count,
                appended, read_time, ordered_time, repeat_time))
            io.stdout:flush()
            os.execute('rm -rf "' .. home.dir .. '"')
        end
    end
end
