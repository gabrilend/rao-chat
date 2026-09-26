-- 013-test-with-neighbours.lua — room-folders run together with the real
-- neighbouring modules (room-tree, recipients, the ignore list,
-- people-links, message-log), when they are present.
--
-- Everything else in this folder tests room-folders alone.  This file
-- loads the other modules for real, lets them sign up on the change bell,
-- and checks that room-folders' writes keep their derived files true:
-- the `where` files follow labels, parents and a token change; the
-- parent-membership rule sees 101's members; last-heard times reach the
-- entry; a member of a child room missing from the room above is added
-- flagged (into the empty-at-birth flagged file) and sent nothing until
-- approved; people/ links appear from direct-message rooms; a message
-- files into the empty log made at birth; every listening neighbour
-- accepts the round-3 bell kind "mailbox"; child rooms share their top
-- room's mailbox.  A module that cannot be loaded is
-- reported with a NOTE line and its checks are skipped (counted neither
-- as pass nor fail), so this file says plainly what could not be joined up.
-- Every config key the options files list is set to its first variant,
-- as the phase 1 demo does.
-- Run: luajit 013-test-with-neighbours.lua [project folder]

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local kit = dofile(DIR .. "/src/room-folders/tests/008-kit-for-tests.lua")
local rooms = kit.setup(DIR)
local check, same, fails = kit.check, kit.same, kit.fails

-- {{{ local function try_require
-- The module, or nil with a NOTE line saying why it could not be loaded.
local function try_require(name)
    local ok, module = pcall(require, name)
    -- loaded: use it.  Not: report and skip its checks.
    if ok then
        return module
    end
    print("NOTE could not load " .. name .. ": " .. tostring(module))
    return nil
end
-- }}}

-- The home is opened, and its direct-message mailbox made, before any
-- neighbour is loaded: making a mailbox rings "mailbox", and a neighbour
-- written before round 3 may refuse that kind.  Whether each one accepts
-- it is checked on its own below, so a refusal shows as one plain failure
-- instead of stopping every other check.
local home = kit.test_home(rooms, "neighbours", "")

local tree    = try_require("021-room-tree")
local members = try_require("041-recipients")
local ignore  = try_require("042-ignore-list")
local people  = try_require("061-people-links")
local log     = try_require("081-message-log")

-- {{{ local function first_variants
-- Every switchable key in every src/<module>/NNN-options.lua, with the
-- first variant listed (the demo's starting value).
local function first_variants()
    local listing = io.popen("ls " .. DIR .. "/src/*/[0-9][0-9][0-9]-options.lua")
    local settings = {}
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            -- switchable: take its first variant.  Not switchable: nothing to set.
            if choice.config_key ~= "" then
                settings[choice.config_key] = choice.variants[1].name
            end
        end
    end
    listing:close()
    return settings
end
-- }}}

-- {{{ local function checked_with
-- Runs the check only when every module it needs was loaded.
local function checked_with(needed, name, test)
    for _, module in ipairs(needed) do
        -- a needed module is missing: skip, saying so.
        if module == false then
            print("NOTE skipped (a module was not loaded): " .. name)
            return
        end
    end
    check(name, test)
end
-- }}}

for key, value in pairs(first_variants()) do
    rooms.set_config(home, key, value)
end
-- The two keys 102 reads only in their edge cases are set too, in case
-- their options file does not list them yet.
local config = rooms.read_config(home)
local EDGE_KEYS = { ["tree.filing-loop"] = "refuse" }
for key, value in pairs(EDGE_KEYS) do
    -- not set by the options files: set it here and say so.
    if config[key] == nil then
        print("NOTE " .. key .. " is not in any options file; set to " .. value .. " here")
        rooms.set_config(home, key, value)
    end
end

local have_tree, have_members = tree or false, members or false
local have_people, have_log, have_ignore = people or false, log or false, ignore or false

local PHONE = { address = "203.0.113.20", port = 7777 }
local LAPTOP = { address = "gf.example.org", port = 7801 }
local CODER = { address = "198.51.100.4", port = 9000 }

-- {{{ local function spec
local function spec(label, token, kind, parent, list)
    local with_heard = {}
    for index, pair in ipairs(list or {}) do
        with_heard[index] = { address = pair.address, port = pair.port, heard = 0 }
    end
    return { label = label, token = token, kind = kind, parent = parent, filed_under = "", members = with_heard,
             mailbox_port = kit.port_for(kind, parent) }
end
-- }}}

local top, middle, bottom, girlfriend

check("make the owner's tree and a direct message with every neighbour listening", function()
    top = rooms.make_room(home, spec("home", "n-home", "group", "", { PHONE }))
    middle = rooms.make_room(home, spec("ritz", "n-ritz", "group", rooms.token_fingerprint("n-home")))
    bottom = rooms.make_room(home, spec("programming", "n-prog", "group", rooms.token_fingerprint("n-ritz")))
    girlfriend = rooms.make_room(home, spec("girlfriend", "n-gf", "direct", "", { PHONE, LAPTOP }))
    print("NOTE listeners signed up: " .. rooms.listener_count())
end)

checked_with({ have_tree }, "102: where files hold the path of labels at birth", function()
    same(tree.read_where(home, bottom).labels, "home/ritz/programming")
end)

checked_with({ have_tree }, "102: a renamed middle room rewrites the where below it", function()
    rooms.write_label(home, middle, "ritz's things")
    same(tree.read_where(home, bottom).labels, "home/ritz's things/programming")
end)

checked_with({ have_tree }, "102: a token changed by hand keeps the tree whole (children re-pointed)", function()
    rooms.change_token(home, middle, "n-ritz-2")
    same(tree.read_where(home, bottom).labels, "home/ritz's things/programming")
    same(tree.tree_parent_of(home, bottom), middle)
end)

checked_with({ have_tree, have_members }, "102+103: the girlfriend's phone in programming (not in ritz) is added but flagged in 101's empty-at-birth flagged file", function()
    same(members.add_member(home, bottom, PHONE.address, PHONE.port), "added-flagged")
    same(rooms.read_entry(home, bottom).members[1].address, PHONE.address, "a member in the entry")
    same(kit.read_file(rooms.flagged_path(home, bottom)) ~= "", true, "the flag is on disk")
    same(#members.flagged(home, bottom), 1, "awaiting review")
    same(#members.send_list(home, bottom), 0, "sent nothing until approved")
end)

checked_with({ have_tree, have_members }, "103: approved in programming, it is sent to", function()
    same(members.approve(home, bottom, PHONE.address, PHONE.port), "approved")
    same(#members.send_list(home, bottom), 1)
end)

checked_with({ have_members }, "103: heard_from reaches 101's heard[N]", function()
    members.heard_from(home, top, PHONE.address, PHONE.port, 1790000000)
    same(rooms.read_entry(home, top).members[1].heard, 1790000000)
end)

checked_with({ have_members }, "103: withholding writes the empty-at-birth withheld file", function()
    members.withhold(home, top, PHONE.address, PHONE.port)
    same(kit.read_file(rooms.withheld_path(home, top)) ~= "", true)
    same(#members.send_list(home, top), 0)
end)

checked_with({ have_people }, "104: people/ has a folder for the direct message, linking to the top room", function()
    local tops = people.top_rooms_for(home, girlfriend)
    -- home is one of her tops; programming is too, since she is in it
    -- (flagged, approved) but not in ritz above it.
    local found = false
    for _, tag in ipairs(tops) do
        if tag == top then found = true end
    end
    same(found, true, "home among her top rooms")
    local link = io.popen("readlink '" .. home.dir .. "/people/girlfriend/home'"):read("*l")
    same(link, "../../rooms/" .. top, "the link on disk")
end)

checked_with({ have_log }, "105: a message files into the log made at birth", function()
    same(log.append(home, top, { id = log.new_message_id(), from = "me", written = 1790000100,
                                 arrived = 1790000100, text = "hello" }), "filed")
    same(#log.read(home, top), 1)
end)

checked_with({ have_ignore }, "103a: the ignore file opened empty is readable by the ignore list", function()
    same(ignore.how_ignored(home, top, CODER.address, CODER.port), "none")
end)

checked_with({ have_tree, have_people }, "all: a new room under an unheld parent is a top room, and the bell ring does not fail", function()
    -- the first variant of mailboxes.unheld-parent (own-mailbox) is set,
    -- so the stray child starts a mailbox of its own and needs a port.
    local stray_spec = spec("stray", "n-stray", "group", rooms.token_fingerprint("n-unheld"), { CODER })
    stray_spec.mailbox_port = kit.fresh_port()
    local orphan = rooms.make_room(home, stray_spec)
    same(tree.tree_parent_of(home, orphan), "")
end)

-- {{{ local function rings_mailbox_with
-- Rings "mailbox" once for the whole home and once for a room, with every
-- loaded neighbour listening: each must accept the round-3 kind.
local function rings_mailbox_with()
    rooms.notify(home, "", "mailbox")
    rooms.notify(home, top, "mailbox")
end
-- }}}

check("all: every listening neighbour accepts the round-3 bell kind 'mailbox'", rings_mailbox_with)

checked_with({ have_tree }, "102 and 101: the child rooms sit in their top room's mailbox", function()
    same(rooms.read_entry(home, bottom).mailbox, rooms.read_entry(home, top).mailbox)
    same(rooms.read_entry(home, girlfriend).mailbox, rooms.direct_mailbox(home))
end)

kit.finish()
