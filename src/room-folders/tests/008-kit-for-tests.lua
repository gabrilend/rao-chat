-- 008-kit-for-tests.lua — the small toolkit room-folders' tests are written with.
--
-- Each test file loads this kit, names its checks one by one, and at the
-- end asks the kit for the totals.  A check is a short function: if it
-- runs without raising an error it passed, otherwise it failed and the
-- error is printed beside its name.  The kit also hands out fresh, empty
-- homes in RAM (tmp/shared-memory/room-folders/), so no test sees
-- another's leftovers.  The last line a test file prints is
-- "counts <passed> <failed>", which the runner (018-run-tests) adds up.

local kit = { passed = 0, failed = 0 }

-- {{{ local function setup
-- Points Lua at the project's modules and returns the room-folders module.
local function setup(dir)
    kit.dir = dir
    kit.scratch = dir .. "/tmp/shared-memory/room-folders"
    -- the RAM scratch folder must exist before homes are made in it.
    os.execute("mkdir -p '" .. kit.scratch .. "'")
    dofile(dir .. "/src/room-folders/001-load-path.lua")(dir)
    return require("002-room-folders")
end
kit.setup = setup
-- }}}

-- {{{ local function check
local function check(name, test)
    local ok, problem = pcall(test)
    -- ok: counted as passed.  Otherwise: counted as failed with its reason.
    if ok then
        kit.passed = kit.passed + 1
        print("PASS " .. name)
    else
        kit.failed = kit.failed + 1
        print("FAIL " .. name .. ": " .. tostring(problem))
    end
end
kit.check = check
-- }}}

-- {{{ local function same
local function same(got, want, what)
    -- differs: say both values so the failure explains itself.
    if got ~= want then
        error((what or "value") .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
    end
end
kit.same = same
-- }}}

-- {{{ local function same_list
local function same_list(got, want, what)
    same(#got, #want, (what or "list") .. " length")
    for index = 1, #want do
        same(got[index], want[index], (what or "list") .. "[" .. index .. "]")
    end
end
kit.same_list = same_list
-- }}}

-- {{{ local function fails
-- The given function must raise an error whose text contains `pattern`
-- (a plain substring, not a Lua pattern).
local function fails(action, pattern)
    local ok, problem = pcall(action)
    -- it succeeded: the refusal being tested did not happen.
    if ok then
        error("expected an error containing '" .. pattern .. "', but it succeeded", 2)
    end
    -- wrong error: something else went wrong first.
    if not tostring(problem):find(pattern, 1, true) then
        error("expected an error containing '" .. pattern .. "', got: " .. tostring(problem), 2)
    end
end
kit.fails = fails
-- }}}

-- {{{ local function fresh_home_dir
-- An absolute path for a home that does not exist yet, removing any older
-- one of the same name.
local function fresh_home_dir(name)
    local path = kit.scratch .. "/" .. name
    os.execute("rm -rf '" .. path .. "'")
    return path
end
kit.fresh_home_dir = fresh_home_dir
-- }}}

-- The next listening port handed to a room that starts its own mailbox.
-- Each top room in a test gets a port of its own (the recommended shape),
-- so a shared port only ever appears where a test makes one on purpose.
kit.next_port = 7000

-- The ports of a test home's one-per-home mailboxes, kept apart from the
-- counted ports above.
kit.DIRECT_PORT = 7700
kit.WAITING_PORT = 7701

-- {{{ local function port_for
-- What a make_room spec's mailbox_port must be for a room of this kind
-- and declared parent, as the contract's placement table says: a fresh
-- port for a top group room (it starts a mailbox), "" for everything
-- else.  A child of an unheld parent under own-mailbox also needs a port;
-- such tests pass kit.fresh_port() themselves.
local function port_for(kind, parent)
    -- a top group room: starts a mailbox.  Anything else: joins one.
    if kind == "group" and parent == "" then
        return kit.fresh_port()
    end
    return ""
end
kit.port_for = port_for
-- }}}

-- {{{ local function fresh_port
local function fresh_port()
    kit.next_port = kit.next_port + 1
    return kit.next_port
end
kit.fresh_port = fresh_port
-- }}}

-- {{{ local function test_home
-- A fresh home ready for rooms of every kind: its direct-message mailbox
-- made, and, when `unheld` names a variant of mailboxes.unheld-parent,
-- that key set (and, for waiting-mailbox, the waiting mailbox made).
-- `unheld` "" leaves the key unset: making a child of an unheld parent is
-- then an error, as it should be on a home nobody configured.
local function test_home(rooms, name, unheld)
    local home = rooms.open_home(fresh_home_dir(name))
    rooms.make_mailbox(home, { label = "direct messages", kind = "direct", port = kit.DIRECT_PORT })
    -- a variant named: set it.  "": leave the key absent on purpose.
    if unheld ~= "" then
        rooms.set_config(home, rooms.UNHELD_PARENT_KEY, unheld)
    end
    -- the waiting variant needs its mailbox; the own variant needs none.
    if unheld == "waiting-mailbox" then
        rooms.make_mailbox(home, { label = "waiting", kind = "waiting", port = kit.WAITING_PORT })
    end
    return home
end
kit.test_home = test_home
-- }}}

-- {{{ local function read_file
local function read_file(path)
    local handle = assert(io.open(path, "rb"))
    local text = handle:read("*a")
    handle:close()
    return text
end
kit.read_file = read_file
-- }}}

-- {{{ local function write_file
local function write_file(path, text)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
end
kit.write_file = write_file
-- }}}

-- {{{ local function finish
local function finish()
    print("counts " .. kit.passed .. " " .. kit.failed)
    os.exit(kit.failed == 0 and 0 or 1)
end
kit.finish = finish
-- }}}

return kit
