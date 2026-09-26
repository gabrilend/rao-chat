-- 104-demo-view.lua — turns each measured demo scene into lines of text.
--
-- 103-demo-sections.lua builds the scenes and hands back records of what is
-- on disk; this file only draws them: files shown exactly as written,
-- listings indented under the command that would show them, figures in
-- columns, variants side by side.  Every function takes one record and
-- gives a list of lines, printing nothing, so a later HTML page could draw
-- the same records its own way.

local view = {}

-- {{{ local function add
local function add(lines, more, indent)
    for _, line in ipairs(more) do
        lines[#lines + 1] = indent .. line
    end
end
-- }}}

-- {{{ local function file_lines
-- A file's text as indented lines, exactly as stored; an empty file is
-- shown as "(empty)" so it is not mistaken for a missing listing.
local function file_lines(lines, text, indent)
    if text == "" then
        -- nothing in the file at all
        lines[#lines + 1] = indent .. "(empty)"
        return
    end
    -- (some text: one printed line per stored line)
    for line in (text:gsub("\n$", "") .. "\n"):gmatch("(.-)\n") do
        lines[#lines + 1] = indent .. line
    end
end
-- }}}

-- {{{ local function milliseconds
local function milliseconds(seconds)
    return string.format("%.2f ms", seconds * 1000)
end
-- }}}

-- {{{ local function joined
local function joined(list)
    if #list == 0 then
        -- an empty list: say so rather than print nothing
        return "(nobody)"
    end
    -- (entries: comma-separated)
    return table.concat(list, ", ")
end
-- }}}

-- {{{ local function outcome
-- One attempt ({ok, answer}) as text.  Some refusals are answers (103's
-- add_member says "not-in-parent" or "ignored" rather than raising), so
-- an answer is shown as "answered <word>" and a raised error as
-- "ERROR: <the module's own words>".
local function outcome(result)
    if result.ok then
        -- it ran: its own answer
        return "answered " .. result.answer
    end
    -- (raised: the module's own words, first line)
    return "ERROR: " .. result.answer:match("^([^\n]*)")
end
-- }}}

-- {{{ function view.entries
function view.entries(record)
    local lines = {}
    lines[#lines + 1] = "home folder: " .. record.home_dir
    lines[#lines + 1] = "2 rooms made in " .. milliseconds(record.seconds_to_make)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "$ ls rooms/                    (" .. #record.folder
                        .. " folders, named by local tags never sent to anyone)"
    add(lines, record.folder, "  ")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "$ find rooms -type f           (every file, with its size)"
    add(lines, record.files, "  ")
    for _, room in ipairs(record.rooms) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = "$ cat rooms/" .. room.tag .. "/entry   (" .. room.entry_bytes .. " bytes)"
        file_lines(lines, room.entry_text, "  ")
        local entry = room.read
        local pairs_read = {}
        for _, member in ipairs(entry.members) do
            pairs_read[#pairs_read + 1] = member.address .. " port " .. member.port
                                          .. " heard " .. member.heard
        end
        lines[#lines + 1] = "  read back by the same reader: label=" .. entry.label .. "  kind="
                            .. entry.kind .. "  " .. #entry.members .. " member pair(s): "
                            .. joined(pairs_read)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "listed by kind:  direct " .. joined(record.direct_list)
    lines[#lines + 1] = "                 group  " .. joined(record.group_list)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "an address without its port:"
    lines[#lines + 1] = "  making a room with { address = 192.0.2.99 } and no port: "
                        .. outcome(record.unpaired_make)
    lines[#lines + 1] = "  reading an entry with this line deleted by hand:  " .. record.removed_line
    lines[#lines + 1] = "    " .. outcome(record.unpaired_read)
    return lines
end
-- }}}

-- {{{ local function token_state
local function token_state(lines, label, state)
    lines[#lines + 1] = string.format("  %-7s token %-36s fingerprint %s…", label,
                                      "\"" .. state.token .. "\"", state.fingerprint:sub(1, 16))
    lines[#lines + 1] = string.format("          label %s, %d members, %d messages, log %d bytes, folder %s",
                                      state.label, state.members, state.messages, state.log_bytes,
                                      state.folder)
end
-- }}}

-- {{{ function view.tokens
function view.tokens(record)
    local lines = { "suggested readable tokens (rooms.suggested-token-words; EFF list, 7,772 words, "
                    .. "about 12.9 bits a word):" }
    for _, row in ipairs(record.suggested) do
        lines[#lines + 1] = string.format("  %s words (~%.0f bits):  %s", row.words,
                                          tonumber(row.words) * math.log(7772) / math.log(2),
                                          table.concat(row.tokens, "   "))
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "a typed token, any text:   \"" .. record.typed .. "\""
    lines[#lines + 1] = "  stored and read back as:  \"" .. record.typed_back .. "\""
    lines[#lines + 1] = "  a second room with the same token in this home: " .. outcome(record.duplicate_token)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "the token changed by hand (" .. milliseconds(record.seconds_to_change) .. "):"
    token_state(lines, "before", record.before)
    token_state(lines, "after", record.after)
    return lines
end
-- }}}

-- {{{ local function tree_table
local function tree_table(lines, rooms)
    for _, room in ipairs(rooms) do
        local parent = room.parent == "" and "(none)" or (room.parent:sub(1, 16) .. "…")
        lines[#lines + 1] = string.format("    %-10s fingerprint %s…  parent %s", room.label,
                                          room.fingerprint:sub(1, 16), parent)
    end
end
-- }}}

-- {{{ function view.tree
function view.tree(record)
    local lines = { "home A, drawn from its entries:" }
    add(lines, record.lines_a, "    ")
    tree_table(lines, record.a)
    lines[#lines + 1] = "  $ cat rooms/<shopping>/where"
    file_lines(lines, record.a[3].where, "    ")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "home B, the same three tokens under its own labels:"
    add(lines, record.lines_b, "    ")
    tree_table(lines, record.b)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "matched by fingerprint (labels never travel):"
    for position, room in ipairs(record.a) do
        local other = record.b[position]
        lines[#lines + 1] = string.format("    %s…  A: %-10s B: %-10s tags A %s  B %s  %s",
                                          room.fingerprint:sub(1, 16), room.label, other.label,
                                          room.tag:sub(1, 8), other.tag:sub(1, 8),
                                          room.fingerprint == other.fingerprint and "same" or "DIFFERENT")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "the parent-membership rule, in shopping (child of kitchen):"
    lines[#lines + 1] = "    kitchen members:  " .. joined(record.kitchen_members)
    -- 102's may_join gives a reason only when it says no ("" when yes)
    lines[#lines + 1] = "    may coder join?     " .. tostring(record.may_join_coder.answer) .. "  "
                        .. record.may_join_coder.reason
    lines[#lines + 1] = "    may housemate join? " .. tostring(record.may_join_housemate.answer)
                        .. "  (in kitchen, so allowed)"
    lines[#lines + 1] = "    adding coder:     " .. outcome(record.add_coder)
    lines[#lines + 1] = "    adding housemate: " .. outcome(record.add_housemate)
    lines[#lines + 1] = "    shopping members now: " .. joined(record.shopping_members)
    return lines
end
-- }}}

-- {{{ function view.members
function view.members(record)
    local lines = {}
    lines[#lines + 1] = string.format("before:   %d members, %d on the send list", #record.members_before,
                                      #record.send_before)
    add(lines, record.send_before, "    send to ")
    lines[#lines + 1] = "  $ cat withheld"
    file_lines(lines, record.withheld_before, "    ")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "withhold " .. record.chosen .. ":"
    lines[#lines + 1] = string.format("after:    %d members, %d on the send list", #record.members_after,
                                      #record.send_after)
    add(lines, record.send_after, "    send to ")
    lines[#lines + 1] = "  $ cat withheld"
    file_lines(lines, record.withheld_after, "    ")
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format("un-withheld: %d on the send list again", #record.send_restored)
    return lines
end
-- }}}

-- {{{ function view.leaving
function view.leaving(record)
    local lines = { "start: " .. record.count_start .. " members" }
    lines[#lines + 1] = ""
    lines[#lines + 1] = "a leave notice claiming to be from " .. record.forged
                        .. "; asked back, it says it is still here, so nothing is removed:"
    lines[#lines + 1] = "    members: " .. record.count_after_forged .. "; " .. record.forged
                        .. " still a member: " .. tostring(record.forged_still_member)
                        .. "; entry byte for byte unchanged: " .. tostring(record.entry_unchanged)
    lines[#lines + 1] = ""
    lines[#lines + 1] = record.real .. " leaves, and asking it back confirms:"
    lines[#lines + 1] = "    " .. outcome(record.confirmed)
    lines[#lines + 1] = "    members (" .. #record.members_after_leave .. "): "
                        .. joined(record.members_after_leave)
    lines[#lines + 1] = "    send list: " .. #record.send_after_leave
    lines[#lines + 1] = ""
    lines[#lines + 1] = record.real .. " speaks in the room again:"
    lines[#lines + 1] = "    " .. outcome(record.spoke)
    lines[#lines + 1] = "    members (" .. #record.members_after_speaking .. "): "
                        .. joined(record.members_after_speaking)
    lines[#lines + 1] = "  $ cat entry   (heard[N] is when each address was last heard from; 0 = never)"
    file_lines(lines, record.entry_after, "    ")
    return lines
end
-- }}}

-- What each ignore level leaves on screen for one message.  Keyed by the
-- level 103a answers; any other answer is an error in the view.
local SHOWN_AS = {
    none = function(shown) return shown.from .. ": " .. shown.text end,
    mark = function() return "(someone you ignore spoke)" end,
    hide = function() return nil end,
}

-- {{{ local function ignoring_variant
local function ignoring_variant(lines, record)
    lines[#lines + 1] = "ignore.hide-files = " .. record.variant
    lines[#lines + 1] = "  $ cat ignore"
    file_lines(lines, record.ignore_file, "      ")
    for _, entry in ipairs(record.levels) do
        lines[#lines + 1] = string.format("    %-18s ignored: %s", entry.who, entry.level)
    end
    lines[#lines + 1] = string.format("  %d messages delivered, %d filed in the log (%d bytes); the room as shown:",
                                      record.delivered, record.filed, record.log_bytes)
    for _, shown in ipairs(record.shown) do
        local draw = SHOWN_AS[shown.level]
        if draw == nil then
            -- an ignore level the view does not know: stop, do not guess
            error("view.ignoring: unknown ignore level " .. tostring(shown.level))
        end
        -- (a known level: draw it, or leave the line out for hide)
        local text = draw(shown)
        if text then
            -- none or mark: something appears
            lines[#lines + 1] = "      " .. text
        end
        -- (hide: nothing appears at all)
    end
    lines[#lines + 1] = "  another member's list brings the ignored addresses into another room:"
    lines[#lines + 1] = "      the hidden address:               " .. outcome(record.readd_hidden)
    lines[#lines + 1] = "      the marked address:               " .. outcome(record.readd_marked)
    lines[#lines + 1] = "      members there: " .. joined(record.other_members)
    lines[#lines + 1] = "      the hidden one, after un-ignoring: " .. outcome(record.readd_after_unignore)
    lines[#lines + 1] = "      members there: " .. joined(record.other_members_after)
end
-- }}}

-- {{{ function view.ignoring
function view.ignoring(record)
    local lines = {}
    for _, variant in ipairs(record.variants) do
        ignoring_variant(lines, variant)
        lines[#lines + 1] = ""
    end
    lines[#lines] = nil
    return lines
end
-- }}}

-- {{{ function view.people
function view.people(record)
    local lines = { "$ ls people/          (one folder per direct-message room)" }
    add(lines, record.folders, "    ")
    lines[#lines + 1] = "$ find people -type l"
    for _, line in ipairs(record.links) do
        local tag = line:match("rooms/(%x+)$")
        local label = tag and record.labels[tag]
        lines[#lines + 1] = "    " .. line .. (label and ("   (" .. label .. ")") or "")
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "a second top room also labelled programming, shared with coder:"
    for _, variant in ipairs(record.collisions) do
        lines[#lines + 1] = "  people.link-collision = " .. variant.variant
        add(lines, variant.links, "    ")
    end
    return lines
end
-- }}}

-- {{{ local function shown_rows
local function shown_rows(list, lines)
    for position, m in ipairs(list) do
        lines[#lines + 1] = string.format("    %d. written +%-4d %-20s %s%s", position, m.written, m.from,
                                          m.text, m.edited and "   [edited]" or "")
    end
end
-- }}}

-- {{{ function view.log
function view.log(record)
    local lines = { "times are seconds after " .. record.t0
                    .. " (2026-09-23 12:00 UTC); message 4 was written at +30 but arrives at +200." }
    local summary = { "", "bytes per message, " .. (record.shapes[1] and record.shapes[1].bulk.count or 0)
                      .. " one-line messages per shape:" }
    for _, shape in ipairs(record.shapes) do
        lines[#lines + 1] = ""
        lines[#lines + 1] = "log.record-shape = " .. shape.shape
        lines[#lines + 1] = "  filing the four:           " .. table.concat(shape.answers, ", ")
        lines[#lines + 1] = "  message 2 delivered again: " .. outcome(shape.repeat_answer)
        lines[#lines + 1] = "  message 2's id, new words: " .. outcome(shape.conflict)
        lines[#lines + 1] = "  an edit of message 3:      " .. outcome(shape.edit)
        lines[#lines + 1] = "  in the file (arrival order, originals kept):"
        for position, filed in ipairs(shape.in_file) do
            lines[#lines + 1] = string.format("    %d. %-10s written +%-4d %-20s %s", position, filed.kind,
                                              filed.written, filed.from, filed.text)
        end
        lines[#lines + 1] = "  on screen (written order, edits applied):"
        shown_rows(shape.shown, lines)
        lines[#lines + 1] = string.format("  $ cat log   (%d bytes)", shape.bytes)
        file_lines(lines, shape.raw, "    ")
        summary[#summary + 1] = string.format("  %-6s %6d bytes  %6.1f bytes per message  %.3f ms per filing",
                                              shape.shape, shape.bulk.bytes,
                                              shape.bulk.bytes / shape.bulk.count,
                                              shape.bulk.seconds * 1000 / shape.bulk.count)
    end
    add(lines, summary, "")
    lines[#lines + 1] = ""
    lines[#lines + 1] = "the same room on two homes (same token, different local tags), "
                        .. "the same four messages arriving in opposite orders:"
    for position, home in ipairs(record.two_homes.homes) do
        local ids = {}
        for _, shown in ipairs(home.shown) do
            ids[#ids + 1] = shown.id:sub(1, 8)
        end
        local filed = {}
        for _, id in ipairs(home.in_file) do
            filed[#filed + 1] = id:sub(1, 8)
        end
        lines[#lines + 1] = string.format("  home %s  tag %s  arrived %s", position == 1 and "A" or "B",
                                          home.tag:sub(1, 8), table.concat(home.arrival, ","))
        lines[#lines + 1] = "      in file:  " .. table.concat(filed, " ")
        lines[#lines + 1] = "      shown:    " .. table.concat(ids, " ")
    end
    lines[#lines + 1] = "  shown order identical on both homes: " .. tostring(record.two_homes.identical)
    return lines
end
-- }}}

-- {{{ function view.tally
-- Drawn by the tally's own showing half, so the demo and the script agree.
function view.tally(record, show)
    return show.summary_lines(record.record, record.counts)
end
-- }}}

return view
