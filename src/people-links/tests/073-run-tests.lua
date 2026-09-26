#!/usr/bin/env luajit
-- 073-run-tests.lua — runs every people-links test, first against the
-- stand-in neighbours, then against the real room-folders module (issue
-- 101) with the stand-in room tree, then against both real modules (101
-- and 102) — each real mode only once that module has been rewritten for
-- the room-is-a-contact model — and prints how many checks passed and
-- failed.
--
-- Each test file runs as its own program so each starts fresh; the runner
-- reads the one RESULT line each prints.  A test that crashes before
-- printing its RESULT line counts as a failure.  Files ending in -done are
-- retired and never run.  Exits non-zero when anything failed, so a build
-- script can stop on it.
--
-- Usage: luajit 073-run-tests.lua [DIR]
--   DIR  the rao-chat project folder (default below)

local DIR = arg[1] or "/home/ritz/programs/rao-chat"

local TESTS = {
    "066-test-link-names",
    "067-test-disk-links",
    "068-test-owners-example",
    "069-test-collisions-on-disk",
    "070-test-safety",
    "071-test-choices",
    "075-test-people-by-address",
    "072-test-with-neighbours",
}

-- {{{ local function probe
-- Whether a real module has the function people-links calls (asked in a
-- separate program, so a half-written module cannot break the runner).
-- Gives true or false.
local function probe(module, name)
    local code = "dofile('" .. DIR .. "/src/room-folders/001-load-path.lua')('" .. DIR .. "') "
              .. "local ok, m = pcall(require, '" .. module .. "') "
              .. "os.exit((ok and type(m) == 'table' and type(m." .. name .. ") == 'function') and 0 or 1)"
    local result = os.execute("luajit -e \"" .. code .. "\" >/dev/null 2>&1")
    -- LuaJIT's os.execute gives the exit status number
    return result == 0 or result == true
end
-- }}}

-- {{{ local function run_one
-- Runs one test file in one mode; gives passed, failed (integers).
local function run_one(test, mode)
    local path = DIR .. "/src/people-links/tests/" .. test .. ".lua"
    local command = "luajit '" .. path .. "' '" .. DIR .. "' '" .. mode .. "' 2>&1"
    local output = io.popen(command)
    local passed, failed, seen = 0, 0, false
    for line in output:lines() do
        local p, f = line:match("^RESULT %S+ pass=(%d+) fail=(%d+)$")
        -- the result line: take its counts; any other line: show it
        if p then
            passed, failed, seen = tonumber(p), tonumber(f), true
        else
            print("  " .. line)
        end
    end
    output:close()
    -- no RESULT line: the test crashed; count one failure
    if not seen then
        failed = failed + 1
        print("  " .. test .. " [" .. mode .. "] crashed before reporting")
    end
    return passed, failed
end
-- }}}

-- {{{ local function run_all
local function run_all()
    local modes = { "stand-in" }
    local real_101 = probe("002-room-folders", "read_entry")
    local real_102 = real_101 and probe("021-room-tree", "snapshot")
    -- 101 rewritten: test against it (with the stand-in tree)
    if real_101 then
        modes[#modes + 1] = "real-101"
    else
        print("NOTE: the real 101 has no read_entry yet; real-101 and real modes not run")
    end
    -- 102 rewritten too: test against both
    if real_102 then
        modes[#modes + 1] = "real"
    elseif real_101 then
        print("NOTE: the real 102 has no snapshot yet; real mode not run")
    end
    local total_pass, total_fail = 0, 0
    for _, mode in ipairs(modes) do
        local mode_pass, mode_fail = 0, 0
        for _, test in ipairs(TESTS) do
            local p, f = run_one(test, mode)
            print(string.format("%-30s %-9s pass=%-4d fail=%d", test, mode, p, f))
            mode_pass, mode_fail = mode_pass + p, mode_fail + f
        end
        print(string.format("== %s: pass=%d fail=%d", mode, mode_pass, mode_fail))
        total_pass, total_fail = total_pass + mode_pass, total_fail + mode_fail
    end
    print(string.format("== total: pass=%d fail=%d", total_pass, total_fail))
    return total_fail
end
-- }}}

os.exit(run_all() == 0 and 0 or 1)
