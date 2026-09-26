-- 115-test-demo-scenes.lua — builds every demo scene on the REAL phase 1 modules
-- and checks the figures the demo exists to show.
--
-- The demo takes its settings from the options files.  So that the scenes
-- can be checked even while a module's options file does not yet list a key
-- its code reads, this test starts from the real options files and fills
-- in only the keys none of them lists, from a stand-in table below (the
-- same idea as the stand-in modules other builders keep).  Each key filled
-- in that way is reported, so a stand-in never hides silently.  Then, on
-- the real modules, it checks:
--   entries   two folders; both entries read by one reader; unpaired refused
--   tokens    suggestions have the configured word count; typed token kept;
--             change keeps folder, label, members, message count
--   tree      three levels on two homes; fingerprints match, labels differ;
--             the coder refused in shopping, the housemate let in
--   members   six members; withholding one leaves five to send to, six members
--   leaving   unconfirmed leave changes nothing; confirmed removes; speaking re-adds
--   ignoring  mark shows a trace, hide shows nothing; hidden refused as member
--   people    one folder per direct message; the girlfriend's two machines
--             count once; each collision mode names two links differently
--   log       duplicate, conflict error, edit keeps the original, two homes agree
-- Each scene and each view also has to draw without error.

-- Keys the modules announced on the board (2026-09-25 round 2) with their
-- variants, first = baseline.  Used only for a key no options file lists.
local STAND_IN_VARIANTS = {
    ["rooms.suggested-token-words"]     = { "6", "5", "4" },
    ["tree.unheld-parent-join"]         = { "refuse", "accept" },
    ["tree.filing-loop"]                = { "refuse", "unfile" },
    ["ignore.hide-files"]               = { "filed", "not-filed" },
    ["ignore.scope"]                    = { "home", "home-and-room" },
    ["ignore.match"]                    = { "pair", "host" },
    ["recipients.shared-address-label"] = { "all-labels", "address" },
    ["people.link-collision"]           = { "suffix-id", "numbered", "id-folder" },
    ["people.slash-in-link-name"]       = { "percent", "division-slash" },
    ["people.direct-message-link"]      = { "leave-out", "include" },
    ["people.members-without-dm"]       = { "leave-out", "address-folder" },
    ["people.person-folder-collision"]  = { "suffix-id", "numbered", "merge" },
    ["log.record-shape"]                = { "tsv", "block", "jsonl" },
    ["log.who-may-edit"]                = { "anyone", "same-address" },
    ["log.shape-mixing"]                = { "per-record", "fixed" },
    ["log.duplicate-check"]             = { "remembered", "scan" },
    ["log.same-id-new-address"]         = { "duplicate", "error" },
}

return function(DIR, harness)
    local check = harness.check
    local probes = require("102-demo-probes")
    local sections = require("103-demo-sections")
    local view = require("104-demo-view")
    local gather = require("100-gather-options")
    local baseline_tool = require("105-demo-baseline")
    dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
    local m = {
        rooms = require("002-room-folders"), tree = require("021-room-tree"),
        forest_text = require("024-forest-text"), members = require("041-recipients"),
        ignore = require("042-ignore-list"), people = require("061-people-links"),
        log = require("081-message-log"),
    }
    local baseline, variants_by_key = baseline_tool.from_options(gather.gather(DIR .. "/src"))
    local stood_in = {}
    for key, names in pairs(STAND_IN_VARIANTS) do
        if variants_by_key[key] == nil then
            -- no options file lists this key yet: use the stand-in, and say so
            variants_by_key[key] = names
            baseline[#baseline + 1] = { key = key, value = names[1] }
            stood_in[#stood_in + 1] = key
        end
        -- (listed by its module: the real options file wins)
    end
    table.sort(stood_in)
    if #stood_in > 0 then
        -- visible in the test output, never silent
        print("      (115: stand-in variants used for keys no options file lists: "
              .. table.concat(stood_in, ", ") .. ")")
    end
    -- (none: every key came from the real options files)
    local scratch = DIR .. "/tmp/shared-memory/phase-1-demo-tests/scenes"
    probes.must_run("mkdir -p '" .. scratch .. "'")
    local ctx = { dir = DIR, scratch = scratch, m = m, probes = probes, baseline = baseline,
                  variants_by_key = variants_by_key }
    local SIX, PEOPLE = sections.SIX, sections.PEOPLE

    -- {{{ local function scene
    -- Builds and draws one scene; gives its record, or nil after a failed check.
    local function scene(key)
        local built, record = pcall(sections[key], ctx)
        check(key .. " scene builds", built, record)
        if not built then
            -- nothing to check further
            return nil
        end
        -- (built: it must also draw)
        local drawn, lines = pcall(view[key], record)
        check(key .. " scene draws", drawn and type(lines) == "table" and #lines > 0, lines)
        return record
    end
    -- }}}

    -- {{{ local function has
    local function has(list, wanted)
        for _, item in ipairs(list) do
            if item == wanted then
                return true
            end
        end
        return false
    end
    -- }}}

    local entries = scene("entries")
    if entries then
        check("entries: two room folders", #entries.folder == 2, #entries.folder)
        check("entries: every folder name is a 32-hex local tag", (function()
            for _, name in ipairs(entries.folder) do
                if not name:match("^" .. string.rep("[0-9a-f]", 32) .. "$") then return false end
            end
            return true
        end)())
        local direct, group = entries.rooms[1].read, entries.rooms[2].read
        check("entries: the direct message reads as kind direct", direct.kind == "direct", direct.kind)
        check("entries: the group reads as kind group", group.kind == "group", group.kind)
        check("entries: girlfriend's two machines are two pairs", #direct.members == 2)
        check("entries: the group holds three pairs", #group.members == 3, #group.members)
        check("entries: ports read back as numbers", type(group.members[1].port) == "number")
        check("entries: the entry text names ip[1], port[1], heard[1]",
              entries.rooms[2].entry_text:find("%.ip%[1%]") and entries.rooms[2].entry_text:find("%.port%[1%]")
              and entries.rooms[2].entry_text:find("%.heard%[1%]"))
        check("entries: listed by kind", #entries.direct_list == 1 and #entries.group_list == 1
              and entries.direct_list[1] == entries.rooms[1].tag)
        check("entries: a member with no port is refused when making a room", not entries.unpaired_make.ok,
              entries.unpaired_make.answer)
        check("entries: an entry missing port[2] is refused when read", not entries.unpaired_read.ok,
              entries.unpaired_read.answer)
    end

    local tokens = scene("tokens")
    if tokens then
        check("tokens: one row per word-count variant",
              #tokens.suggested == #variants_by_key["rooms.suggested-token-words"])
        for _, row in ipairs(tokens.suggested) do
            local ok = true
            for _, token in ipairs(row.tokens) do
                local _, dashes = token:gsub("-", "")
                -- a word may itself hold a dash, so at least n-1 dashes
                ok = ok and dashes >= tonumber(row.words) - 1
            end
            check("tokens: " .. row.words .. "-word suggestions have at least " .. row.words .. " parts", ok,
                  table.concat(row.tokens, " "))
        end
        check("tokens: the typed token is read back unchanged", tokens.typed_back == tokens.typed)
        check("tokens: a second room with the same token is refused", not tokens.duplicate_token.ok,
              tokens.duplicate_token.answer)
        local before, after = tokens.before, tokens.after
        check("tokens: the token changed", before.token ~= after.token)
        check("tokens: the fingerprint changed", before.fingerprint ~= after.fingerprint)
        check("tokens: the folder is the same", before.folder == after.folder)
        check("tokens: label and members kept", before.label == after.label and before.members == after.members)
        check("tokens: message count unchanged (5)", before.messages == 5 and after.messages == 5,
              before.messages .. " / " .. after.messages)
        check("tokens: log bytes unchanged", before.log_bytes == after.log_bytes)
    end

    local tree = scene("tree")
    if tree then
        check("tree: home A drawn home/kitchen/shopping",
              table.concat(tree.lines_a, "|") == "home|└── kitchen|    └── shopping", table.concat(tree.lines_a, "|"))
        check("tree: home B drawn family/cooking/groceries",
              table.concat(tree.lines_b, "|") == "family|└── cooking|    └── groceries",
              table.concat(tree.lines_b, "|"))
        for position = 1, 3 do
            check("tree: room " .. position .. " fingerprints match across homes",
                  tree.a[position].fingerprint == tree.b[position].fingerprint)
            check("tree: room " .. position .. " local tags differ across homes",
                  tree.a[position].tag ~= tree.b[position].tag)
        end
        check("tree: shopping's where names its path of labels",
              tree.a[3].where:find("home/kitchen/shopping", 1, true) ~= nil, tree.a[3].where)
        check("tree: may_join says no to the coder", tree.may_join_coder.answer == false,
              tree.may_join_coder.reason)
        check("tree: may_join says yes to the housemate", tree.may_join_housemate.answer == true,
              tree.may_join_housemate.reason)
        check("tree: adding the coder answers not-in-parent", tree.add_coder.ok
              and tree.add_coder.answer == "not-in-parent", tree.add_coder.answer)
        check("tree: adding the housemate answers added", tree.add_housemate.ok
              and tree.add_housemate.answer == "added", tree.add_housemate.answer)
        check("tree: the coder is not a member of shopping",
              not has(tree.shopping_members, PEOPLE.coder[1].address .. " " .. PEOPLE.coder[1].port))
    end

    local members = scene("members")
    if members then
        check("members: six members, six to send to", #members.members_before == 6 and #members.send_before == 6)
        check("members: withheld starts empty", members.withheld_before == "")
        check("members: after withholding, six members", #members.members_after == 6)
        check("members: after withholding, five to send to", #members.send_after == 5)
        check("members: the withheld one is off the send list", not has(members.send_after, members.chosen))
        check("members: the withheld file names it", members.withheld_after:find(members.chosen, 1, true) ~= nil,
              members.withheld_after)
        check("members: un-withholding restores six", #members.send_restored == 6)
    end

    local leaving = scene("leaving")
    if leaving then
        check("leaving: six at the start", leaving.count_start == 6)
        check("leaving: unconfirmed leave leaves six", leaving.count_after_forged == 6)
        check("leaving: the forged-against address is still a member", leaving.forged_still_member == true)
        check("leaving: the entry is byte for byte unchanged", leaving.entry_unchanged == true)
        check("leaving: confirm_leave answers removed", leaving.confirmed.ok and leaving.confirmed.answer == "removed",
              leaving.confirmed.answer)
        check("leaving: five members after the confirmed leave", #leaving.members_after_leave == 5)
        check("leaving: the leaver is gone", not has(leaving.members_after_leave, leaving.real))
        check("leaving: speaking again answers added", leaving.spoke.ok and leaving.spoke.answer == "added",
              leaving.spoke.answer)
        check("leaving: six members again", #leaving.members_after_speaking == 6)
        check("leaving: the returner's heard time is recorded",
              leaving.entry_after:find("= 1790165700", 1, true) ~= nil)
    end

    local ignoring = scene("ignoring")
    if ignoring then
        check("ignoring: one result per ignore.hide-files variant",
              #ignoring.variants == #variants_by_key["ignore.hide-files"])
        for _, run in ipairs(ignoring.variants) do
            local name = "ignoring " .. run.variant .. ": "
            local marked, hidden = SIX[2].address .. " " .. SIX[2].port, SIX[3].address .. " " .. SIX[3].port
            local levels = {}
            for _, entry in ipairs(run.levels) do levels[entry.who] = entry.level end
            check(name .. "levels none/mark/hide", levels[SIX[1].address .. " " .. SIX[1].port] == "none"
                  and levels[marked] == "mark" and levels[hidden] == "hide")
            local drawn = view.ignoring({ variants = { run } })
            check(name .. "the marked one shows as a trace", harness.contains_line(drawn, "(someone you ignore spoke)"))
            check(name .. "the hidden one's words never appear",
                  not harness.contains_line(drawn, "(something you chose never to see)"))
            check(name .. "the marked one's words never appear",
                  not harness.contains_line(drawn, "(something you chose not to read)"))
            check(name .. "the hidden address is refused as a member", run.readd_hidden.ok
                  and run.readd_hidden.answer == "ignored", run.readd_hidden.answer)
            check(name .. "the marked address is refused as a member", run.readd_marked.ok
                  and run.readd_marked.answer == "ignored", run.readd_marked.answer)
            check(name .. "after un-ignoring, the hidden one is added", run.readd_after_unignore.ok
                  and run.readd_after_unignore.answer == "added", run.readd_after_unignore.answer)
            local expected_filed = ({ filed = 5, ["not-filed"] = 4 })[run.variant]
            check(name .. "messages filed = " .. tostring(expected_filed), run.filed == expected_filed, run.filed)
        end
    end

    local people = scene("people")
    if people then
        check("people: one folder per direct message", #people.folders == 3
              and has(people.folders, "girlfriend") and has(people.folders, "coder")
              and has(people.folders, "housemate"), table.concat(people.folders, ","))
        local girlfriend_links = {}
        for _, line in ipairs(people.links) do
            if line:match("^girlfriend/") then girlfriend_links[#girlfriend_links + 1] = line end
        end
        -- the girlfriend is in home (top) and programming (top); kitchen and
        -- shopping are under home, so not tops for her
        check("people: the girlfriend has two top rooms, counted once across two machines",
              #girlfriend_links == 2, table.concat(girlfriend_links, " / "))
        check("people: every link is relative", (function()
            for _, line in ipairs(people.links) do
                if not line:find(" %-> %.%./%.%./rooms/") then return false end
            end
            return true
        end)())
        check("people: one result per collision variant",
              #people.collisions == #variants_by_key["people.link-collision"])
        local distinct = {}
        for _, run in ipairs(people.collisions) do
            check("people " .. run.variant .. ": coder has three links (home, programming x2)",
                  #run.links == 3, table.concat(run.links, " / "))
            distinct[table.concat(run.links, "|")] = true
        end
        local count = 0
        for _ in pairs(distinct) do count = count + 1 end
        check("people: the collision variants name the links differently", count == #people.collisions)
    end

    local log = scene("log")
    if log then
        check("log: one result per shape", #log.shapes == #variants_by_key["log.record-shape"])
        for _, shape in ipairs(log.shapes) do
            local name = "log " .. shape.shape .. ": "
            check(name .. "four filed", table.concat(shape.answers, ",") == "filed,filed,filed,filed",
                  table.concat(shape.answers, ","))
            check(name .. "the repeat is duplicate", shape.repeat_answer.ok
                  and shape.repeat_answer.answer == "duplicate", shape.repeat_answer.answer)
            check(name .. "the same id with new words is an error", not shape.conflict.ok, shape.conflict.answer)
            check(name .. "the edit is filed", shape.edit.ok, shape.edit.answer)
            check(name .. "five records in the file, original kept", #shape.in_file == 5
                  and shape.in_file[3].text:find("parsre", 1, true) ~= nil)
            check(name .. "the late message is second on screen", shape.shown[2].written == 30)
            check(name .. "the edit shows on screen, marked", shape.shown[4].text:find("parser$") ~= nil
                  and shape.shown[4].edited == true, shape.shown[4] and shape.shown[4].text)
            check(name .. "the file's bytes were measured", shape.bytes > 0 and shape.bulk.bytes > 0)
        end
        check("log: two homes show the same order", log.two_homes.identical == true)
        check("log: two homes use different local tags", log.two_homes.homes[1].tag ~= log.two_homes.homes[2].tag)
        check("log: the two files hold different arrival orders",
              table.concat(log.two_homes.homes[1].in_file, ",") ~= table.concat(log.two_homes.homes[2].in_file, ","))
    end

    -- The scenes must not lean on the baseline being the first-listed
    -- variants (the owner may name others in input/phase-1-demo.config):
    -- every scene is built again with every key at its LAST-listed variant.
    local last = {}
    for _, setting in ipairs(baseline) do
        local names = variants_by_key[setting.key]
        last[#last + 1] = { key = setting.key, value = names[#names] }
    end
    ctx.baseline = last
    ctx.scratch = scratch .. "-last"
    probes.must_run("mkdir -p '" .. ctx.scratch .. "'")
    for _, entry in ipairs(sections.ORDER) do
        if entry.key ~= "tally" then
            -- a scene that builds homes: build and draw it under the other baseline
            local built, record = pcall(sections[entry.key], ctx)
            check(entry.key .. " scene builds with every key at its last variant", built, record)
            local drawn = built and pcall(view[entry.key], record)
            check(entry.key .. " scene draws with every key at its last variant", drawn == true)
        end
        -- (the tally makes no homes: nothing to vary)
    end
end
