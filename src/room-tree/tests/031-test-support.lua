-- 031-test-support.lua — the shared bits every room-tree test uses.
--
-- Each test file is its own small program.  This file gives them: a way to
-- load the room tree on top of either the stand-in room-folders module
-- (030, kept here) or the real one (src/room-folders/, issue 101); a fresh
-- empty home folder in RAM for each test; and simple pass/fail counting
-- that ends the program with a non-zero exit when anything failed.
--
-- Which room-folders module is used is chosen by the test's second
-- argument, "stand-in" or "real"; there is no default, so a test run always
-- says which it tested against.

local M = {}

M.passed = 0
M.failed = 0

-- {{{ function M.setup
-- dir: string, the project folder.  which: "stand-in" or "real".
-- Gives rooms (the room-folders module), tree (021), text (024).  The
-- stand-in is put in place under the real module's name, so 021 cannot
-- tell which it was given.
function M.setup(dir, which)
    dofile(dir .. "/src/room-folders/001-load-path.lua")(dir)
    package.path = dir .. "/src/room-tree/tests/?.lua;" .. package.path
    -- stand-in: put it in place before 021 asks for room-folders by name
    -- real: let require find src/room-folders/002-room-folders.lua
    -- anything else: a mistyped run
    if which == "stand-in" then
        package.loaded["002-room-folders"] = dofile(dir .. "/src/room-tree/tests/030-stand-in-room-folders.lua")
    elseif which == "real" then
        require("002-room-folders")
    else
        error("tests: second argument must be stand-in or real, got " .. tostring(which))
    end
    M.dir = dir
    M.which = which
    M.scratch = dir .. "/tmp/shared-memory/room-tree/" .. which
    return require("002-room-folders"), require("021-room-tree"), require("024-forest-text")
end
-- }}}

-- {{{ function M.fresh_home
-- An empty home folder under tmp/shared-memory/room-tree/<which>/<name>.
-- Its config says mailboxes.unheld-parent = own-mailbox: the tree does not
-- care which mailbox a room listens in, and own-mailbox needs no mailbox
-- made beforehand.  028-test-mailboxes sets the other variant itself.
function M.fresh_home(rooms, name)
    local path = M.scratch .. "/" .. name
    os.execute('rm -rf "' .. path .. '"')
    os.execute('mkdir -p "' .. M.scratch .. '"')
    local home = rooms.open_home(path)
    rooms.set_config(home, "mailboxes.unheld-parent", "own-mailbox")
    return home
end
-- }}}

-- Ports handed to new mailboxes: each a different whole number, so no two
-- mailboxes share a port (a shared port is reported as a warning by 101,
-- and warnings are treated as errors here).
M.next_port = 20000

-- {{{ local function port_for
-- The mailbox_port make_room needs (contract, "Mailboxes"): a whole number
-- when the room starts a new mailbox, "" when it joins one.
--   direct room                       joins the one direct mailbox: ""
--   group room, no parent             a new tree mailbox: a port
--   group room, parent held here      the parent's mailbox: ""
--   group room, parent not held here  the home's mailboxes.unheld-parent:
--                                     own-mailbox a port, waiting-mailbox ""
local function port_for(rooms, home, spec)
    local fresh = function()
        M.next_port = M.next_port + 1
        return M.next_port
    end
    -- a direct message: never starts a mailbox
    if spec.kind == "direct" then
        return ""
    end
    -- a top group room: always a new mailbox
    if spec.parent == "" then
        return fresh()
    end
    -- the parent held here: the child joins its mailbox
    if rooms.find_by_fingerprint(home, spec.parent) ~= "" then
        return ""
    end
    local by_variant = { ["own-mailbox"] = fresh, ["waiting-mailbox"] = function() return "" end }
    local mode = rooms.config_value(home, "mailboxes.unheld-parent")
    local choose = by_variant[mode]
    -- a value this helper does not know: the test's own mistake
    if choose == nil then
        error("tests: mailboxes.unheld-parent = " .. tostring(mode))
    end
    return choose()
end
-- }}}

-- {{{ function M.make
-- make_room with the mailbox_port worked out as above.  spec: every
-- make_room field but mailbox_port.  A direct room in a home with no
-- direct mailbox yet gets one made first (real module only; the stand-in
-- keeps no mailboxes).
function M.make(rooms, home, spec)
    -- a direct room on the real module: the direct mailbox must exist
    if spec.kind == "direct" and M.which == "real" and rooms.direct_mailbox(home) == "" then
        M.next_port = M.next_port + 1
        rooms.make_mailbox(home, { label = "direct messages", kind = "direct", port = M.next_port })
    end
    local full = {}
    for key, value in pairs(spec) do
        full[key] = value
    end
    full.mailbox_port = port_for(rooms, home, spec)
    return rooms.make_room(home, full)
end
-- }}}

-- {{{ function M.room
-- Makes a group room through room-folders' make_room.  parent_room: the
-- tag of a room held in the same home whose token becomes the parent
-- fingerprint, or "" for none.  members: list of {address, port} (heard
-- is filled in as 0, never heard).  Gives the new tag.
function M.room(rooms, home, label, token, parent_room, members)
    local parent = ""
    -- a parent room given: name it by its token's fingerprint
    if parent_room ~= "" then
        parent = rooms.token_fingerprint(rooms.read_entry(home, parent_room).token)
    end
    return M.make(rooms, home, {
        label = label, token = token, kind = "group", parent = parent,
        filed_under = "", members = M.members(members),
    })
end
-- }}}

-- {{{ function M.members
-- { {"10.0.0.2", 7777}, ... } -> member records with heard = 0.
function M.members(pairs_list)
    local out = {}
    for i, pair in ipairs(pairs_list) do
        out[i] = { address = pair[1], port = pair[2], heard = 0 }
    end
    return out
end
-- }}}

-- {{{ function M.check
function M.check(condition, label)
    -- true: a pass; false: a failure, printed so it can be found
    if condition then
        M.passed = M.passed + 1
    else
        M.failed = M.failed + 1
        print("  FAIL " .. label)
    end
end
-- }}}

-- {{{ function M.equal
function M.equal(got, wanted, label)
    local same = got == wanted
    M.check(same, label)
    -- different: show both so the failure explains itself
    if not same then
        print("       got:    " .. tostring(got))
        print("       wanted: " .. tostring(wanted))
    end
end
-- }}}

-- {{{ function M.same_list
-- Two lists of strings compared by joining; a mismatch prints both.
function M.same_list(got, wanted, label)
    M.equal(table.concat(got, " | "), table.concat(wanted, " | "), label)
end
-- }}}

-- {{{ function M.refuses
-- fn must raise an error whose message holds `pattern` (a plain substring).
function M.refuses(fn, pattern, label)
    local ok, message = pcall(fn)
    -- it went through: that is the failure being tested for
    if ok then
        M.check(false, label .. " (no error was raised)")
        return
    end
    local found = tostring(message):find(pattern, 1, true) ~= nil
    M.check(found, label)
    -- wrong error: show it
    if not found then
        print("       error was: " .. tostring(message))
    end
end
-- }}}

-- {{{ function M.finish
function M.finish(name)
    print(string.format("%-28s %-9s pass %3d  fail %3d", name, M.which, M.passed, M.failed))
    -- any failure: non-zero exit so the runner notices
    if M.failed > 0 then
        os.exit(1)
    end
    os.exit(0)
end
-- }}}

return M
