-- 065-test-harness.lua — shared helpers for the people-links tests.
--
-- Each test file is run as its own program (so every test starts with a
-- fresh copy of the modules and one bell listener).  It calls setup() with
-- the project folder and a mode:
--   stand-in  both neighbours are the stand-ins in this tests/ folder
--   real-101  the real room-folders module (issue 101), stand-in room tree
--   real      the real room-folders and room-tree modules (101 and 102)
-- then makes scratch homes under tmp/shared-memory/people-links/ (RAM),
-- builds rooms, and checks what appears in people/.  Every check is
-- counted; finish() prints one RESULT line the runner reads and exits
-- non-zero when anything failed.

local H = { passed = 0, failed = 0 }

-- {{{ local function use_stand_in_101
local function use_stand_in_101(dir)
    package.preload["002-room-folders"] = function()
        return dofile(dir .. "/src/people-links/tests/064-stand-in-room-folders.lua")
    end
end
-- }}}

-- {{{ local function use_stand_in_102
local function use_stand_in_102(dir)
    package.preload["021-room-tree"] = function()
        return dofile(dir .. "/src/people-links/tests/074-stand-in-room-tree.lua")
    end
end
-- }}}

-- {{{ local function use_nothing
local function use_nothing(dir)
end
-- }}}

-- which neighbours each mode swaps for a stand-in
local modes = {
    ["stand-in"] = { use_stand_in_101, use_stand_in_102 },
    ["real-101"] = { use_nothing,      use_stand_in_102 },
    ["real"]     = { use_nothing,      use_nothing },
}

-- {{{ function H.setup
-- dir: project folder; mode: one of the keys of `modes`.  Loads the modules
-- and keeps them on H (H.rooms, H.tree, H.people, H.disk, H.names).
function H.setup(dir, mode)
    local choose = modes[mode]
    -- no such mode: say which exist
    if choose == nil then
        error("harness: mode must be stand-in, real-101 or real, got " .. tostring(mode))
    end
    H.dir, H.mode = dir, mode
    dofile(dir .. "/src/room-folders/001-load-path.lua")(dir)
    choose[1](dir)
    choose[2](dir)
    H.rooms  = require("002-room-folders")
    H.tree   = require("021-room-tree")
    H.people = require("061-people-links")
    H.disk   = require("062-disk-links")
    H.names  = require("063-link-names")
    H.token_counter = 0
    H.port_counter = 7700
end
-- }}}

-- The settings every test home starts with unless a test says otherwise.
-- mailboxes.unheld-parent is 101's key (round 3), read by make_room only
-- for a room whose declared parent is not held here; own-mailbox gives
-- such a room its own tree mailbox, so H.group passes it a port.
local BASE_CONFIG = {
    ["mailboxes.unheld-parent"]    = "own-mailbox",
    ["people.link-collision"]      = "suffix-id",
    ["people.direct-message-link"] = "leave-out",
    ["people.members-without-dm"]  = "leave-out",
}

-- {{{ function H.fresh_home
-- A new empty rao-home in RAM, named after the test.  config: table of
-- key -> value laid over BASE_CONFIG (a value of false leaves that key
-- out, to test a missing key).
function H.fresh_home(name, config)
    local base = H.dir .. "/tmp/shared-memory/people-links"
    local path = base .. "/" .. H.mode .. "-" .. name
    os.execute('rm -rf "' .. path .. '"')
    os.execute('mkdir -p "' .. base .. '"')
    local home = H.rooms.open_home(path)
    local merged = {}
    for key, value in pairs(BASE_CONFIG) do merged[key] = value end
    for key, value in pairs(config or {}) do merged[key] = value end
    local keys = {}
    for key in pairs(merged) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        -- false: leave the key out on purpose
        if merged[key] ~= false then
            H.rooms.set_config(home, key, merged[key])
        end
    end
    -- round 3: a direct room needs the home's one direct mailbox first
    -- (101 refuses a direct room without it).  Making it rings 'mailbox',
    -- which people-links must hear and ignore.
    H.rooms.make_mailbox(home, { label = "direct messages", kind = "direct", port = 7700 })
    return home
end
-- }}}

-- {{{ function H.pair
-- One member: "gf.example 7000" -> { address, port (integer), heard = 0 }.
function H.pair(text)
    local address, port = text:match("^(%S+) (%d+)$")
    -- not "<address> <port>": the test is written wrong
    if address == nil then
        error("harness: a member is written '<address> <port>', got " .. tostring(text))
    end
    return { address = address, port = tonumber(port), heard = 0 }
end
-- }}}

-- {{{ local function pairs_of
local function pairs_of(list)
    local out = {}
    for i, text in ipairs(list) do
        out[i] = H.pair(text)
    end
    return out
end
-- }}}

-- {{{ local function next_token
-- A token no other room in this program holds (101 refuses repeats).
local function next_token()
    H.token_counter = H.token_counter + 1
    return "test-token-" .. H.token_counter .. "-" .. H.rooms.new_local_tag()
end
-- }}}

-- {{{ function H.fingerprint_of
-- The fingerprint of a held room's token (what a child names as parent).
function H.fingerprint_of(home, tag)
    return H.rooms.token_fingerprint(H.rooms.read_entry(home, tag).token)
end
-- }}}

-- {{{ local function next_port
-- A port for a room that starts a new mailbox (any integer 1-65535 does;
-- counting keeps them apart so 101 has no shared port to warn about).
local function next_port()
    H.port_counter = H.port_counter + 1
    return H.port_counter
end
-- }}}

-- {{{ local function mailbox_port_for
-- make_room's mailbox_port (contract, "Mailboxes"): an integer when the
-- room starts a new mailbox — a top room, or (under own-mailbox) a room
-- whose declared parent is not held here — and "" when it joins its held
-- parent's mailbox.
local function mailbox_port_for(home, parent_fingerprint)
    -- no declared parent: a top room, a new tree mailbox
    if parent_fingerprint == "" then
        return next_port()
    end
    -- the parent is held here: its mailbox
    if H.rooms.find_by_fingerprint(home, parent_fingerprint) ~= "" then
        return ""
    end
    -- the parent is not held here: own-mailbox, a new one
    return next_port()
end
-- }}}

-- {{{ function H.group
-- A group room.  opts: { parent = tag of a declared parent held here, or
-- nil; filed = tag to file it under, or nil }.  Members as "<addr> <port>".
function H.group(home, label, members, opts)
    opts = opts or {}
    local parent = ""
    -- a declared parent: name it by its token's fingerprint
    if opts.parent then
        parent = H.fingerprint_of(home, opts.parent)
    end
    local parent_fingerprint = opts.parent_fingerprint or parent
    return H.rooms.make_room(home, {
        label = label, token = next_token(), kind = "group",
        parent = parent_fingerprint, filed_under = opts.filed or "",
        members = pairs_of(members),
        mailbox_port = mailbox_port_for(home, parent_fingerprint),
    })
end
-- }}}

-- {{{ function H.direct
-- A direct-message room: a person, with their machines' addresses.
function H.direct(home, label, members)
    return H.rooms.make_room(home, {
        label = label, token = next_token(), kind = "direct",
        parent = "", filed_under = "", members = pairs_of(members),
        mailbox_port = "",
    })
end
-- }}}

-- {{{ function H.set_members
function H.set_members(home, tag, members)
    H.rooms.write_members(home, tag, pairs_of(members))
end
-- }}}

-- {{{ local function walk
local function walk(path, relative, out)
    for _, entry in ipairs(H.disk.list_dir(path)) do
        local full = path .. "/" .. entry
        local rel = (relative == "") and entry or (relative .. "/" .. entry)
        -- a link: record where it points
        if H.disk.is_link(full) then
            out[#out + 1] = rel .. " -> " .. H.disk.read_link(full)
        -- a folder: go in
        elseif H.disk.is_dir(full) then
            out[#out + 1] = rel .. "/"
            walk(full, rel, out)
        -- anything else: note it as a file
        else
            out[#out + 1] = rel .. " (file)"
        end
    end
end
-- }}}

-- {{{ function H.view
-- Everything under people/ (or people/<folder>/ when folder given), one
-- line per entry, sorted: "alice/home -> ../../rooms/<tag>".
function H.view(home, folder)
    local root = home.dir .. "/people"
    -- one person only
    if folder then
        root = root .. "/" .. folder
    end
    local out = {}
    -- nothing there: an empty view
    if not H.disk.is_dir(root) then
        return out
    end
    walk(root, "", out)
    table.sort(out)
    return out
end
-- }}}

-- {{{ function H.check
function H.check(ok, label)
    -- passed: count it quietly; failed: say which
    if ok then
        H.passed = H.passed + 1
    else
        H.failed = H.failed + 1
        print("FAIL [" .. H.mode .. "] " .. label)
    end
end
-- }}}

-- {{{ function H.same
-- Compares two lists of strings; on a mismatch prints both.
function H.same(got, want, label)
    local ok = table.concat(got, "\n") == table.concat(want, "\n")
    H.check(ok, label)
    -- mismatch: show both so the failure explains itself
    if not ok then
        print("   got:  " .. table.concat(got, " | "))
        print("   want: " .. table.concat(want, " | "))
    end
end
-- }}}

-- {{{ function H.fails
-- Checks that fn() raises an error whose text contains `fragment`.
function H.fails(fn, fragment, label)
    local ok, message = pcall(fn)
    local right = (not ok) and tostring(message):find(fragment, 1, true) ~= nil
    H.check(right, label)
    -- wrong outcome: show what happened instead
    if not right then
        print("   expected an error containing: " .. fragment)
        print("   got: " .. (ok and "no error" or tostring(message)))
    end
end
-- }}}

-- {{{ function H.sorted
function H.sorted(list)
    local copy = {}
    for i, v in ipairs(list) do
        copy[i] = v
    end
    table.sort(copy)
    return copy
end
-- }}}

-- {{{ function H.link_line
-- The expected view line for a flat link: "<folder>/<name> -> ../../rooms/<tag>"
-- (folder "" for a one-person view).
function H.link_line(folder, name, tag)
    local prefix = (folder == "") and "" or (folder .. "/")
    return prefix .. name .. " -> ../../rooms/" .. tag
end
-- }}}

-- {{{ function H.label_through
-- Follows a person's link: when the room's entry file is reachable through
-- it (the relative link really leads into rooms/), gives that room's label
-- as read from `home`; otherwise "(unreachable)".
function H.label_through(home, path)
    -- the link leads nowhere
    if not H.disk.exists(path .. "/entry") then
        return "(unreachable)"
    end
    local tag = H.disk.read_link(path):match("(%x+)$")
    return H.rooms.read_entry(home, tag).label
end
-- }}}

-- {{{ function H.finish
function H.finish()
    print(string.format("RESULT %s pass=%d fail=%d", H.mode, H.passed, H.failed))
    os.exit(H.failed == 0 and 0 or 1)
end
-- }}}

return H
