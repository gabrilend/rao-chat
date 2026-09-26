-- 093-test-edits.lua — checks corrections and deletions under both
-- duplicate checks: anyone may edit any message (the owner's answer; no
-- config key), what is refused, what is filed, that the original stays in
-- the file, that there is no time limit, and what the room shows —
-- including a deleted message staying in the view, empty and marked.
--
-- Run: luajit 093-test-edits.lua [DIR] [real|stand-in]

local DIR = "/home/ritz/programs/rao-chat"
-- Path: a DIR argument — use it.  None — the hard-coded project folder.
if arg[1] and arg[1] ~= "" then
    DIR = arg[1]
end
local t = dofile(DIR .. "/src/message-log/tests/090-test-harness.lua").start(arg, "edits")
local log, rooms = t.log, t.rooms

local FRIEND = "203.0.113.7 51234"
local STRANGER = "198.51.100.23 40404"

-- {{{ local function edit_of
local function edit_of(message, fields)
    local edit = {
        id = log.new_message_id(), from = message.from,
        written = message.written + 10, arrived = message.written + 10,
        target = message.id, text = "corrected",
    }
    for key, value in pairs(fields or {}) do
        edit[key] = value
    end
    return edit
end
-- }}}

for _, check in ipairs(t.CHECKS) do
    local label = check .. ": "
    local home = t.fresh_home(t.settings(check))
    local room = t.new_room(home)
    local message = t.message({ from = FRIEND, written = 1000, text = "teh cat\n-- sorelu" })
    log.append(home, room, message)

    local fix = edit_of(message, { text = "the cat\twith a tab\nand a line\n-- sorelu" })
    t.check(log.correct(home, room, fix) == "filed", label .. "an edit from the message's own address is filed")
    t.check(log.correct(home, room, fix) == "duplicate", label .. "the same correction again is a duplicate")
    t.refuses(function() log.correct(home, room, edit_of(message, { id = fix.id, text = "other" })) end,
        "different text", label .. "the same correction id with other text is an error")
    local records = log.read(home, room)
    t.check(#records == 2 and records[1].text == message.text and records[2].kind == "correction"
        and records[2].target == message.id and records[2].from == FRIEND,
        label .. "the original stays in the file, the correction follows")
    local view = log.read_ordered(home, room)
    t.check(#view == 1 and view[1].text == fix.text and view[1].edited == true
        and view[1].changed_from == FRIEND and view[1].from == FRIEND,
        label .. "the room shows the corrected text, marked edited, with the edit's address")

    -- A later-written correction wins, even when filed first.
    local later = edit_of(message, { text = "the cat, final", written = 1030 })
    local earlier = edit_of(message, { text = "the cat, middle", written = 1020 })
    log.correct(home, room, later)
    log.correct(home, room, earlier)
    t.check(log.read_ordered(home, room)[1].text == "the cat, final",
        label .. "the latest-written correction wins, not the last filed")

    -- No time limit.
    local years = edit_of(message, { text = "the cat, years on", written = 1000 + 10 * 365 * 86400 })
    t.check(log.correct(home, room, years) == "filed", label .. "a correction ten years later is filed")

    -- An edit from another address: filed (anyone may edit), and the
    -- view names the address the change came from.
    local other = edit_of(message, { from = STRANGER, text = "not the cat", written = 400000000 })
    t.check(log.correct(home, room, other) == "filed", label .. "an edit from another address is filed")
    local shown = log.read_ordered(home, room)[1]
    t.check(shown.text == "not the cat" and shown.changed_from == STRANGER and shown.from == FRIEND,
        label .. "the view shows it, with the other address in changed_from")
    local mine = t.message({ written = 2000 })
    log.append(home, room, mine)
    t.check(log.correct(home, room, edit_of(mine, { from = FRIEND })) == "filed",
        label .. "another address may edit a message of mine")

    t.refuses(function() log.correct(home, room, edit_of(message, { target = log.new_message_id() })) end,
        "no message", label .. "a correction of an unknown id is refused")
    t.refuses(function() log.correct(home, room, edit_of(message, { target = fix.id })) end,
        "no message", label .. "a correction of a correction is refused")
    local self = edit_of(message)
    self.target = self.id
    t.refuses(function() log.correct(home, room, self) end, "its own id", label .. "an edit naming itself is refused")

    local gone = edit_of(message, { written = 500000000 })
    gone.text = nil
    t.check(log.delete(home, room, gone) == "filed", label .. "a deletion is filed")
    view = log.read_ordered(home, room)
    local deleted_view
    for _, each in ipairs(view) do
        -- Path: the deleted message — keep it for the checks below.
        if each.id == message.id then
            deleted_view = each
        end
    end
    t.check(deleted_view.deleted == true and deleted_view.text == "" and deleted_view.changed_from == FRIEND,
        label .. "a deleted message stays in the view, empty and marked, so its anchor still resolves")
    t.check(log.read(home, room)[1].text == message.text, label .. "the deleted original is still in the file")
    t.refuses(function() log.correct(home, room, edit_of(message, { written = 600000000 })) end,
        "already deleted", label .. "a deleted message cannot be corrected")
end

-- log.who-may-edit is no longer read: absent is fine.  A value left in an
-- old config (same-address) used to stop applying with no word said; since
-- round 4 the real room-folders module refuses any config line no module
-- declares (the log declares only log.duplicate-check, 087-settings.lua),
-- so the leftover line is an error naming it.  The stand-in keeps no
-- declarations, so there the line is written and the log still ignores it.
do
    local home = t.fresh_home(t.settings("scan"))
    local room = t.new_room(home)
    local message = t.message({ written = 1000 })
    log.append(home, room, message)
    t.check(log.correct(home, room, edit_of(message, { from = STRANGER })) == "filed",
        "an edit files with no log.who-may-edit in config")
    local file = assert(io.open(home.dir .. "/config", "ab"))
    file:write("log.who-may-edit = same-address\n")
    file:close()
    local by_neighbour = {
        -- the real module: the leftover line is refused, naming it
        real = function()
            t.refuses(function() log.correct(home, room, edit_of(message, { from = FRIEND, written = 2000 })) end,
                "log.who-may-edit", "a leftover log.who-may-edit line is refused by the config reader")
            t.refuses(function() rooms.set_config(home, "log.record-shape", "block") end,
                "log.record-shape", "a retired log setting cannot be written either")
        end,
        -- the stand-in: no declarations; the log never reads the line
        ["stand-in"] = function()
            t.check(log.correct(home, room, edit_of(message, { from = FRIEND, written = 2000 })) == "filed",
                "stand-in: a leftover log.who-may-edit line is not read by the log")
        end,
    }
    by_neighbour[t.neighbour]()
end

-- The log's declared settings (round 4): exactly the one name it reads.
do
    local declared = dofile(t.DIR .. "/src/message-log/087-settings.lua")
    t.check(#declared == 1 and declared[1] == "log.duplicate-check",
        "087-settings declares log.duplicate-check and nothing else")
    -- the real module found it by scanning src/, owned by message-log
    if t.neighbour == "real" then
        local owner = rooms.declared_settings()["log.duplicate-check"]
        t.check(owner ~= nil and owner.module == "message-log",
            "the real config reader lists log.duplicate-check as message-log's")
    end
end

-- An edit already in the file whose message has not arrived is left out.
do
    local home = t.fresh_home(t.settings("scan"))
    local room = t.new_room(home)
    local file = assert(io.open(rooms.log_path(home, room), "ab"))
    file:write("bbbb\t" .. STRANGER .. "\t1001\t1001\tcorrection\taaaa\tearly\n")
    file:close()
    t.check(#log.read_ordered(home, room) == 0, "an edit whose message is absent shows nothing")
    log.append(home, room, t.message({ id = "aaaa", written = 1000 }))
    t.check(log.read_ordered(home, room)[1].text == "early",
        "and applies once its message is filed")
end

t.finish()
