-- 093-test-edits.lua — checks corrections and deletions in every record
-- shape under both answers to "who may edit a message?" (log.who-may-edit =
-- anyone, same-address): what is refused, what is filed, that the original
-- stays in the file, that there is no time limit, and what the room shows.
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

for _, shape in ipairs(t.SHAPES) do
    for _, who in ipairs({ "anyone", "same-address" }) do
        local label = shape .. "/" .. who .. ": "
        local home = t.fresh_home(t.settings(shape, "fixed", "scan", who))
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

        -- An edit from another address: the open question.
        local other = edit_of(message, { from = STRANGER, text = "not the cat", written = 400000000 })
        -- Path: anyone — filed, and the view names the stranger's address.
        -- same-address — refused, naming both addresses.
        if who == "anyone" then
            t.check(log.correct(home, room, other) == "filed", label .. "an edit from another address is filed")
            local shown = log.read_ordered(home, room)[1]
            t.check(shown.text == "not the cat" and shown.changed_from == STRANGER and shown.from == FRIEND,
                label .. "the view shows it, with the other address in changed_from")
        else
            local ok, problem = pcall(log.correct, home, room, other)
            t.check(not ok and problem:find(STRANGER, 1, true) and problem:find(FRIEND, 1, true),
                label .. "an edit from another address is refused, naming both (" .. tostring(problem) .. ")")
            local mine = t.message({ written = 2000 })
            log.append(home, room, mine)
            t.refuses(function() log.correct(home, room, edit_of(mine, { from = FRIEND })) end,
                "may not change", label .. "an address may not edit a message of mine")
            t.check(log.correct(home, room, edit_of(mine)) == "filed", label .. "me may edit my own")
        end

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
end

-- Edits filed under anyone stay shown after the rule becomes same-address.
do
    local home = t.fresh_home(t.settings("tsv", "fixed", "scan", "anyone"))
    local room = t.new_room(home)
    local message = t.message({ written = 1000 })
    log.append(home, room, message)
    log.correct(home, room, edit_of(message, { from = STRANGER, text = "kept" }))
    rooms.set_config(home, "log.who-may-edit", "same-address")
    local shown = log.read_ordered(home, room)[1]
    t.check(shown.text == "kept" and shown.changed_from == STRANGER,
        "a rule changed later does not hide edits already filed")
end

-- log.who-may-edit is read only when an edit is filed.
do
    local home = t.fresh_home({ ["log.record-shape"] = "tsv", ["log.shape-mixing"] = "fixed",
        ["log.duplicate-check"] = "scan" })
    local room = t.new_room(home)
    local message = t.message({ written = 1000 })
    t.check(log.append(home, room, message) == "filed", "messages file without log.who-may-edit")
    t.refuses(function() log.correct(home, room, edit_of(message)) end, "log.who-may-edit",
        "an edit without log.who-may-edit set is an error")
    rooms.set_config(home, "log.who-may-edit", "the-author")
    t.refuses(function() log.correct(home, room, edit_of(message)) end, "not one of anyone",
        "a misspelt log.who-may-edit is an error")
    t.check(#log.read(home, room) == 1, "and neither refused edit was filed")
end

-- An edit already in the file whose message has not arrived is left out.
do
    local home = t.fresh_home(t.settings("tsv", "fixed", "scan", "anyone"))
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
