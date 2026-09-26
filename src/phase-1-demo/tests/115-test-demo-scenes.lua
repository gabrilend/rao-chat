-- 115-test-demo-scenes.lua — builds every demo scene on the REAL phase 1 modules
-- and checks the figures the demo exists to show.
--
-- The demo sets exactly the setting names the modules declare (their
-- <index>-settings.lua lists, read through 101's declared_settings()),
-- each at the first variant its options file lists.  So that the scenes
-- can be checked even while a declared name has no options entry (a fixed
-- setting, or one whose choice is not written down yet), this test fills
-- in only those names, from a stand-in table below (the same idea as the
-- stand-in modules other builders keep).  Each name filled in that way is
-- reported, so a stand-in never hides silently; a stand-in is never used
-- for a name nobody declares (101 would refuse the config line).  Then, on
-- the real modules, it checks:
--   entries    two folders; both entries read by one reader; unpaired refused
--   tokens     suggestions have six words; typed token kept;
--              change keeps folder, label, members, message count
--   tree       three levels on two homes; fingerprints match, labels differ;
--              the coder added flagged in shopping, off the send list until
--              approved; a leaver from home flagged in kitchen and shopping;
--              declining withholds; a parent not held gives cannot-check
--   mailboxes  a top room and its children share one mailbox, direct
--              messages another; a shared port found and reported; a room
--              whose parent is not held in its own mailbox, then merged into
--              the parent's once it arrives, per
--              mailboxes.merge-when-parent-arrives variant; an undeclared
--              config line refused
--   members    six members; withholding one leaves five to send to, six members
--   leaving    unconfirmed leave changes nothing; confirmed removes; speaking re-adds
--   ignoring   mark shows a trace, hide shows nothing and files nothing; an
--              ignore covers every port; ignored addresses refused as members
--   people     one folder per direct message; the girlfriend's two machines
--              count once; each collision mode names two links differently
--   log        duplicate, conflict error, edit keeps the original, two homes agree
-- Each scene and each view also has to draw without error.

-- Keys the modules announced on the board (round 3 and 4) with their
-- variants, first = baseline.  Used only for a declared name no options
-- file lists.  Keys whose choice the owner answered are not here: no
-- module reads them (mailboxes.unheld-parent went in round 4).
local STAND_IN_VARIANTS = {
    ["mailboxes.merge-when-parent-arrives"] = { "automatic", "ask" },
    ["tree.filing-loop"]                = { "refuse", "unfile" },
    ["ignore.scope"]                    = { "home", "home-and-room" },
    ["recipients.shared-address-label"] = { "all-labels", "address" },
    ["people.link-collision"]           = { "suffix-id", "numbered", "id-folder" },
    ["people.slash-in-link-name"]       = { "percent", "division-slash" },
    ["people.direct-message-link"]      = { "leave-out", "include" },
    ["people.members-without-dm"]       = { "leave-out", "address-folder" },
    ["people.person-folder-collision"]  = { "suffix-id", "numbered", "merge" },
    ["log.duplicate-check"]             = { "remembered", "scan" },
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
    -- every module is loaded before any scene, as the demo does, so every
    -- bell listener hears every home the scenes make
    local baseline, variants_by_key = baseline_tool.from_options(gather.gather(DIR .. "/src"),
                                                                 m.rooms.declared_settings())
    local stood_in = {}
    for _, setting in ipairs(baseline) do
        local names = STAND_IN_VARIANTS[setting.key]
        if setting.value == nil and names then
            -- declared, but no options file lists it yet: use the stand-in, and say so
            variants_by_key[setting.key] = names
            setting.value = names[1]
            stood_in[#stood_in + 1] = setting.key
        end
        -- (listed by its module: the real options file wins; declared with
        -- no options entry and no stand-in: apply_input below refuses it)
    end
    baseline_tool.apply_input(baseline, variants_by_key, {})
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
        check("tokens: three suggestions", #tokens.suggested == 3)
        for _, token in ipairs(tokens.suggested) do
            -- no word in the EFF large list holds a dash, so six words = five dashes
            local _, dashes = token:gsub("-", "")
            check("tokens: a suggestion has six words", dashes == 5, token)
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

    -- {{{ local function flag_state
    -- The state word a room's flagged file gives one pair, or "" when the
    -- file has no line for it ("<address> <port> <state>", 103's format).
    local function flag_state(text, pair)
        local found = ""
        for line in text:gmatch("[^\n]+") do
            local address, port, state = line:match("^(%S+) (%S+) (%S+)$")
            if address and (address .. " " .. port) == pair then
                found = state
            end
        end
        return found
    end
    -- }}}

    local tree = scene("tree")
    if tree then
        local coder = PEOPLE.coder[1].address .. " " .. PEOPLE.coder[1].port
        local girlfriend = PEOPLE.girlfriend[1].address .. " " .. PEOPLE.girlfriend[1].port
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
        check("tree: the coder checks no in shopping", tree.check_coder.answer == "no", tree.check_coder.reason)
        check("tree: the housemate checks yes in shopping", tree.check_housemate.answer == "yes",
              tree.check_housemate.reason)
        check("tree: adding the coder answers added-flagged", tree.add_coder.ok
              and tree.add_coder.answer == "added-flagged", tree.add_coder.answer)
        check("tree: adding the housemate answers added", tree.add_housemate.ok
              and tree.add_housemate.answer == "added", tree.add_housemate.answer)
        check("tree: the flagged coder IS a member of shopping", has(tree.shopping_flagged.members, coder))
        check("tree: the flagged coder is not on the send list", not has(tree.shopping_flagged.send, coder))
        check("tree: the flagged file says no for the coder", flag_state(tree.shopping_flagged.flagged, coder) == "no",
              tree.shopping_flagged.flagged)
        check("tree: approving the coder ran", tree.approve_coder.ok, tree.approve_coder.answer)
        check("tree: approved, the coder is on the send list", has(tree.shopping_approved.send, coder))
        check("tree: the flagged file now says approved",
              flag_state(tree.shopping_approved.flagged, coder) == "approved", tree.shopping_approved.flagged)
        check("tree: the girlfriend's leave from home is removed", tree.leave.ok and tree.leave.answer == "removed",
              tree.leave.answer)
        check("tree: after leaving home she is still a member of kitchen",
              has(tree.kitchen_after_leave.members, girlfriend))
        check("tree: ... flagged no in kitchen", flag_state(tree.kitchen_after_leave.flagged, girlfriend) == "no",
              tree.kitchen_after_leave.flagged)
        check("tree: ... flagged no in shopping (a grandchild)",
              flag_state(tree.shopping_after_leave.flagged, girlfriend) == "no", tree.shopping_after_leave.flagged)
        check("tree: ... and off both send lists", not has(tree.kitchen_after_leave.send, girlfriend)
              and not has(tree.shopping_after_leave.send, girlfriend))
        check("tree: declining ran", tree.decline.ok, tree.decline.answer)
        check("tree: declined, her flag line is gone", flag_state(tree.kitchen_declined.flagged, girlfriend) == "",
              tree.kitchen_declined.flagged)
        check("tree: declined, she is withheld", tree.kitchen_withheld:find(girlfriend, 1, true) ~= nil,
              tree.kitchen_withheld)
        check("tree: declined, still off the send list", not has(tree.kitchen_declined.send, girlfriend))
        check("tree: a parent not held checks cannot-check", tree.check_unheld.answer == "cannot-check",
              tree.check_unheld.reason)
        check("tree: adding there answers added-flagged", tree.add_unheld.ok
              and tree.add_unheld.answer == "added-flagged", tree.add_unheld.answer)
        check("tree: the flagged file says cannot-check",
              flag_state(tree.orphan.flagged, coder) == "cannot-check", tree.orphan.flagged)
    end

    local mailboxes = scene("mailboxes")
    if mailboxes then
        local by_label = {}
        for _, room in ipairs(mailboxes.rooms) do by_label[room.label] = room end
        check("mailboxes: home, kitchen, shopping in one mailbox",
              by_label.home.mailbox == by_label.kitchen.mailbox and by_label.home.mailbox == by_label.shopping.mailbox)
        check("mailboxes: that mailbox is a tree mailbox", by_label.home.mailbox_kind == "tree")
        check("mailboxes: both direct messages in one direct mailbox",
              by_label.girlfriend.mailbox == by_label.coder.mailbox and by_label.coder.mailbox_kind == "direct")
        check("mailboxes: programming has a mailbox of its own", by_label.programming.mailbox ~= by_label.home.mailbox
              and by_label.programming.mailbox ~= by_label.coder.mailbox)
        check("mailboxes: three mailboxes before games", #mailboxes.table == 3, #mailboxes.table)
        check("mailboxes: no shared-port report before games", mailboxes.warnings_before == 0,
              mailboxes.warnings_before)
        check("mailboxes: the direct port tries two keys", #mailboxes.tried[1].rooms == 2,
              table.concat(mailboxes.tried[1].rooms, ","))
        check("mailboxes: home's port tries three keys", #mailboxes.tried[2].rooms == 3,
              table.concat(mailboxes.tried[2].rooms, ","))
        check("mailboxes: one shared port found", #mailboxes.shared.ports == 1
              and mailboxes.shared.ports[1].port == mailboxes.shared.port
              and #mailboxes.shared.ports[1].mailboxes == 2)
        check("mailboxes: one read reports the shared port once", #mailboxes.shared.warnings == 1
              and mailboxes.shared.warnings[1]:find(tostring(mailboxes.shared.port), 1, true) ~= nil,
              table.concat(mailboxes.shared.warnings, " / "))
        check("mailboxes: the shared port tries programming and games", #mailboxes.shared.tried == 2
              and has(mailboxes.shared.tried, "programming") and has(mailboxes.shared.tried, "games"))
        check("mailboxes: one row per mailboxes.merge-when-parent-arrives variant",
              #mailboxes.merge == #variants_by_key["mailboxes.merge-when-parent-arrives"])
        -- what each variant must show once loft (attic's declared parent) arrives
        local expect = {
            ["automatic"] = function(row)
                return #row.mergeable == 0 and not row.said_yes
                       and row.after.tag == row.loft.tag and row.trunk_after.tag == row.loft.tag
            end,
            ["ask"] = function(row)
                return #row.mergeable == 1 and row.mergeable[1].mailbox == row.before.tag
                       and row.mergeable[1].into == row.loft.tag and row.mergeable[1].rooms == 2
                       and row.after.tag == row.before.tag and row.trunk_after.tag == row.before.tag
                       and row.said_yes and row.after_yes.tag == row.loft.tag
                       and row.trunk_after_yes.tag == row.loft.tag
            end,
        }
        for _, row in ipairs(mailboxes.merge) do
            check("mailboxes " .. row.variant .. ": attic starts in a tree mailbox of its own",
                  row.before.kind == "tree" and row.before.tag ~= row.loft.tag, row.before.kind)
            check("mailboxes " .. row.variant .. ": trunk joins attic's mailbox, nothing mergeable yet",
                  row.trunk_before.tag == row.before.tag and row.mergeable_before == 0)
            check("mailboxes " .. row.variant .. ": after loft arrives, as the variant says",
                  expect[row.variant] ~= nil and expect[row.variant](row),
                  row.after.tag:sub(1, 8) .. " mergeable " .. #row.mergeable)
            check("mailboxes " .. row.variant .. ": nothing left to merge at the end", row.mergeable_after_yes == 0)
            local emptied = nil
            for _, box in ipairs(row.mailboxes) do
                if box.tag == row.before.tag then emptied = box end
            end
            check("mailboxes " .. row.variant .. ": attic's old mailbox stays, empty, with its port",
                  emptied ~= nil and #emptied.rooms == 0 and emptied.port == row.before.port)
        end
        local config = mailboxes.config
        check("mailboxes: the declared names include the merge setting",
              (function()
                  for _, item in ipairs(config.declared) do
                      if item.name == "mailboxes.merge-when-parent-arrives" and item.module == "room-folders" then
                          return true
                      end
                  end
                  return false
              end)())
        check("mailboxes: a home sets exactly the declared names", config.lines_before == #config.declared,
              config.lines_before .. " vs " .. #config.declared)
        check("mailboxes: set_config with an undeclared name is refused", not config.set_made_up.ok
              and config.set_made_up.answer:find("not a setting any module reads", 1, true) ~= nil,
              config.set_made_up.answer)
        check("mailboxes: the refused set_config wrote nothing",
              config.bytes_before_refused_set == config.bytes_after_refused_set)
        check("mailboxes: an undeclared line added by hand stops the next open, naming the line",
              not config.reopen.ok and config.reopen.answer:find("mailboxes.unheld-parent = own-mailbox", 1, true) ~= nil,
              config.reopen.answer)
        check("mailboxes: and every read of the config", not config.read.ok
              and config.read.answer:find("line", 1, true) ~= nil, config.read.answer)
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
        local marked, hidden = SIX[2].address .. " " .. SIX[2].port, SIX[3].address .. " " .. SIX[3].port
        local levels = {}
        for _, entry in ipairs(ignoring.levels) do levels[entry.who] = entry.level end
        check("ignoring: levels none/mark/hide", levels[SIX[1].address .. " " .. SIX[1].port] == "none"
              and levels[marked] == "mark" and levels[hidden] == "hide")
        local drawn = view.ignoring(ignoring)
        check("ignoring: the marked one shows as a trace", harness.contains_line(drawn, "(someone you ignore spoke)"))
        check("ignoring: the hidden one's words never appear",
              not harness.contains_line(drawn, "(something you chose never to see)"))
        check("ignoring: the marked one's words never appear",
              not harness.contains_line(drawn, "(something you chose not to read)"))
        check("ignoring: 4 of 5 filed (the hidden address's message is dropped)", ignoring.filed == 4,
              ignoring.filed)
        check("ignoring: the hidden machine on another port is hidden too",
              ignoring.other_port.level == "hide" and ignoring.other_port.files == false,
              ignoring.other_port.level .. " " .. tostring(ignoring.other_port.files))
        check("ignoring: the hidden address is refused as a member", ignoring.readd_hidden.ok
              and ignoring.readd_hidden.answer == "ignored", ignoring.readd_hidden.answer)
        check("ignoring: the marked address is refused as a member", ignoring.readd_marked.ok
              and ignoring.readd_marked.answer == "ignored", ignoring.readd_marked.answer)
        check("ignoring: after un-ignoring, the hidden one is added", ignoring.readd_after_unignore.ok
              and ignoring.readd_after_unignore.answer == "added", ignoring.readd_after_unignore.answer)
    end

    local log = scene("log")
    if log then
        check("log: four filed", table.concat(log.answers, ",") == "filed,filed,filed,filed",
              table.concat(log.answers, ","))
        check("log: the repeat is duplicate", log.repeat_answer.ok
              and log.repeat_answer.answer == "duplicate", log.repeat_answer.answer)
        check("log: the same id with new words is an error", not log.conflict.ok, log.conflict.answer)
        check("log: the edit is filed", log.edit.ok, log.edit.answer)
        check("log: five records in the file, original kept", #log.in_file == 5
              and log.in_file[3].text:find("parsre", 1, true) ~= nil)
        check("log: the late message is second on screen", log.shown[2].written == 30)
        check("log: the edit shows on screen, marked", log.shown[4].text:find("parser$") ~= nil
              and log.shown[4].edited == true, log.shown[4] and log.shown[4].text)
        check("log: the raw file is tab-separated", log.raw:find("\t", 1, true) ~= nil)
        check("log: the file's bytes were measured", log.bytes > 0 and log.bulk.bytes > 0)
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

    -- {{{ local function people_checks
    -- The people scene's figures, checked against the options actually set
    -- in its homes (`settings`: key -> value), so every variant is held to
    -- an exact expectation rather than loosened:
    --   people.direct-message-link  leave-out: a person's folder holds only
    --     the top group rooms they share with you; include: also a link to
    --     their own direct message (one more link each).
    --   people.link-collision  suffix-id / numbered: links sit directly in
    --     the person's folder, "<person>/<name> -> ../../rooms/<tag>";
    --     id-folder: one folder deeper, "<person>/<tag>/<name> ->
    --     ../../../rooms/<tag>", the middle folder named by the room's tag.
    -- The collision homes set people.link-collision per run (run.variant).
    local function people_checks(pass, people, settings)
        local own_dm = ({ ["leave-out"] = 0, include = 1 })[settings["people.direct-message-link"]]
        check(pass .. "people: people.direct-message-link is a value this test knows", own_dm ~= nil,
              settings["people.direct-message-link"])
        if own_dm == nil then
            -- no expectation can be worked out: stop checking this pass
            return
        end
        -- (known: each person's folder holds own_dm more links)

        -- {{{ local function link_shape_ok
        -- True when every "path -> target" line has the shape `mode` gives
        -- and names one room tag in both the path (id-folder) and target.
        local function link_shape_ok(lines, mode)
            local hex = string.rep("[0-9a-f]", 32)
            local shapes = {
                ["suffix-id"] = "^[^/]+/[^/]+ %-> %.%./%.%./rooms/(" .. hex .. ")$",
                numbered      = "^[^/]+/[^/]+ %-> %.%./%.%./rooms/(" .. hex .. ")$",
                ["id-folder"] = "^[^/]+/(" .. hex .. ")/[^/]+ %-> %.%./%.%./%.%./rooms/(" .. hex .. ")$",
            }
            local shape = shapes[mode]
            if shape == nil then
                -- a collision mode this test does not know: not ok
                return false
            end
            -- (known mode: every line must match it)
            for _, line in ipairs(lines) do
                local first, second = line:match(shape)
                if first == nil then
                    -- this line has another shape
                    return false
                end
                if second ~= nil and first ~= second then
                    -- id-folder: the middle folder must be the target's tag
                    return false
                end
                -- (matches)
            end
            return true
        end
        -- }}}

        check(pass .. "people: one folder per direct message", #people.folders == 3
              and has(people.folders, "girlfriend") and has(people.folders, "coder")
              and has(people.folders, "housemate"), table.concat(people.folders, ","))
        local girlfriend_links = {}
        for _, line in ipairs(people.links) do
            if line:match("^girlfriend/") then girlfriend_links[#girlfriend_links + 1] = line end
        end
        -- the girlfriend is in home (top) and programming (top); kitchen and
        -- shopping are under home, so not tops for her; her two machines
        -- count once; plus her own direct message under `include`
        check(pass .. "people: the girlfriend has " .. (2 + own_dm) .. " links (2 top rooms"
              .. (own_dm == 1 and " + her direct message" or "") .. ")",
              #girlfriend_links == 2 + own_dm, table.concat(girlfriend_links, " / "))
        local mode = settings["people.link-collision"]
        check(pass .. "people: every link has the " .. tostring(mode) .. " shape, relative",
              link_shape_ok(people.links, mode), table.concat(people.links, " / "))
        check(pass .. "people: one result per collision variant",
              #people.collisions == #variants_by_key["people.link-collision"])
        local distinct = {}
        for _, run in ipairs(people.collisions) do
            -- the coder: home and two rooms labelled programming, plus his
            -- own direct message under `include`
            check(pass .. "people " .. run.variant .. ": coder has " .. (3 + own_dm)
                  .. " links (home, programming x2" .. (own_dm == 1 and ", his direct message" or "") .. ")",
                  #run.links == 3 + own_dm, table.concat(run.links, " / "))
            -- the coder's links are listed from inside people/coder, so put
            -- the folder back in front before checking their shape
            local whole = {}
            for _, line in ipairs(run.links) do whole[#whole + 1] = "coder/" .. line end
            check(pass .. "people " .. run.variant .. ": links have that mode's shape",
                  link_shape_ok(whole, run.variant), table.concat(run.links, " / "))
            distinct[table.concat(run.links, "|")] = true
        end
        local count = 0
        for _ in pairs(distinct) do count = count + 1 end
        check(pass .. "people: the collision variants name the links differently", count == #people.collisions)
    end
    -- }}}

    -- {{{ local function settings_of
    -- A baseline list as key -> value.
    local function settings_of(list)
        local map = {}
        for _, setting in ipairs(list) do map[setting.key] = setting.value end
        return map
    end
    -- }}}

    -- The people scene, checked in full on both baselines: the first-listed
    -- (ctx.baseline was that until the loop above) and the last-listed.
    ctx.baseline, ctx.scratch = baseline, scratch .. "-people"
    probes.must_run("mkdir -p '" .. ctx.scratch .. "'")
    local people = scene("people")
    if people then
        -- built on the first-listed baseline
        people_checks("", people, settings_of(baseline))
    end
    -- (did not build: scene() already recorded the failure)
    ctx.baseline, ctx.scratch = last, scratch .. "-people-last"
    probes.must_run("mkdir -p '" .. ctx.scratch .. "'")
    local built, record = pcall(sections.people, ctx)
    check("people scene builds for the checks with every key at its last variant", built, record)
    if built then
        -- built on the last-listed baseline: the same checks, its expectations
        people_checks("[last] ", record, settings_of(last))
    end
    -- (did not build: already recorded)
end
