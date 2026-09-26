-- 090-test-harness.lua — shared helpers for the message-log tests: finds
-- the project, loads either the real room-folders module or the stand-in
-- kept in tests/stand-in/, makes fresh scratch homes in RAM, and counts
-- passes and failures.
--
-- Each test file is run as:  luajit <test file> [DIR] [real|stand-in]
-- DIR defaults to the project folder written below; the second argument
-- picks which room-folders module the log is tested against.

local harness = {}

-- {{{ function harness.start
-- args: the test file's `arg` table.  Gives the loaded modules and settings.
function harness.start(args, name)
    local DIR = "/home/ritz/programs/rao-chat"
    -- Path: a DIR given — use it.  None — the hard-coded project folder.
    if args[1] and args[1] ~= "" then
        DIR = args[1]
    end
    local neighbour = args[2] or "stand-in"
    dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
    -- Path: stand-in — put tests/stand-in/ ahead of every other folder so
    -- its 002-room-folders is found first.  real — leave the path alone.
    if neighbour == "stand-in" then
        package.path = DIR .. "/src/message-log/tests/stand-in/?.lua;" .. package.path
    elseif neighbour ~= "real" then
        error("second argument must be 'real' or 'stand-in', got " .. neighbour)
    end
    harness.DIR = DIR
    harness.neighbour = neighbour
    harness.name = name
    harness.scratch = DIR .. "/tmp/shared-memory/message-log/" .. name .. "-" .. neighbour
    harness.passed = 0
    harness.failed = 0
    harness.home_count = 0
    harness.room_count = 0
    os.execute('rm -rf "' .. harness.scratch .. '"')
    os.execute('mkdir -p "' .. harness.scratch .. '"')
    harness.rooms = require("002-room-folders")
    harness.log = require("081-message-log")
    return harness
end
-- }}}

-- {{{ function harness.fresh_home
-- A new empty home with the log settings given (a table key -> value).
function harness.fresh_home(settings)
    harness.home_count = harness.home_count + 1
    local home = harness.rooms.open_home(harness.scratch .. "/home-" .. harness.home_count)
    for key, value in pairs(settings) do
        harness.rooms.set_config(home, key, value)
    end
    return home
end
-- }}}

-- {{{ function harness.new_room
-- A new empty top-level group room with a token no other room in the home
-- holds (101 refuses a repeated token), no parent, not filed, no members.
-- A top room starts its own mailbox, so make_room needs a port for it
-- (round 3); each room gets a different one, since two mailboxes on one
-- port make 101 print a warning on every read.
-- Gives the room's local tag.
function harness.new_room(home)
    harness.room_count = harness.room_count + 1
    local tag_for_token = harness.rooms.new_local_tag()
    return harness.rooms.make_room(home, { label = "room" .. harness.room_count,
        token = "test-token-" .. tag_for_token, kind = "group", parent = "",
        filed_under = "", members = {}, mailbox_port = 20000 + harness.room_count })
end
-- }}}

-- {{{ function harness.check
function harness.check(condition, label)
    -- Path: true — a pass.  False — a failure, printed.
    if condition then
        harness.passed = harness.passed + 1
    else
        harness.failed = harness.failed + 1
        print("  FAIL " .. harness.name .. ": " .. label)
    end
end
-- }}}

-- {{{ function harness.refuses
-- Passes when calling `action` raises an error whose text holds `expected`.
function harness.refuses(action, expected, label)
    local ok, problem = pcall(action)
    -- Path: it raised — check the message.  It did not — a failure.
    if ok then
        harness.check(false, label .. " (no error raised)")
    else
        local matched = tostring(problem):find(expected, 1, true) ~= nil
        harness.check(matched, label .. " (error was: " .. tostring(problem) .. ")")
    end
end
-- }}}

-- {{{ function harness.message
-- A message with a fresh id; fields given in `fields` override the rest.
function harness.message(fields)
    local message = {
        id = harness.log.new_message_id(), from = "me",
        written = 1790000000, arrived = 1790000000, text = "hello",
    }
    for key, value in pairs(fields or {}) do
        message[key] = value
    end
    return message
end
-- }}}

-- The one switch left that shapes filing: how a repeat is recognised.
harness.CHECKS = { "scan", "remembered" }

-- {{{ function harness.settings
-- The config a home needs for the log: only log.duplicate-check.  The
-- answered keys (log.record-shape, log.shape-mixing, log.who-may-edit,
-- log.same-id-new-address) are left out on purpose, so a test proves they
-- are no longer read.
function harness.settings(check)
    return { ["log.duplicate-check"] = check }
end
-- }}}

-- {{{ function harness.finish
function harness.finish()
    print(string.format("%s [%s]: %d passed, %d failed",
        harness.name, harness.neighbour, harness.passed, harness.failed))
    os.exit(harness.failed == 0 and 0 or 1)
end
-- }}}

return harness
