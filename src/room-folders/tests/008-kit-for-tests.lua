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
