#!/usr/bin/env luajit
-- 118-run-tests.lua — runs every test of the phase-1-demo folder and totals them.
--
-- Finds each tests/1NN-test-*.lua file, runs it with the shared checking kit,
-- and prints how many claims passed and failed.  Exits with status 1 if any
-- failed (or a test file itself crashed), so a build can stop on it.
--
-- Usage (from any folder):
--   luajit src/phase-1-demo/tests/118-run-tests.lua [project folder]

local DIR = arg[1] or "/home/ritz/programs/rao-chat"

package.path = DIR .. "/src/phase-1-demo/?.lua;"
            .. DIR .. "/src/phase-1-demo/tests/?.lua;" .. package.path
local harness = require("110-check-kit")

-- {{{ local function list_test_files
local function list_test_files()
    local listing = io.popen('find "' .. DIR .. '/src/phase-1-demo/tests" -maxdepth 1 '
                             .. '-name "1[0-9][0-9]-test-*.lua"')
    local files = {}
    for file in listing:lines() do
        files[#files + 1] = file
    end
    listing:close()
    table.sort(files)
    return files
end
-- }}}

-- {{{ local function main
local function main()
    local crashed = 0
    for _, file in ipairs(list_test_files()) do
        harness.current_file = file:match("[^/]+$")
        local before = harness.passed + harness.failed
        local ran, problem = pcall(function() dofile(file)(DIR, harness) end)
        if ran then
            -- the file finished: report how many claims it made
            print(string.format("ran   %-34s %3d checks", harness.current_file,
                                harness.passed + harness.failed - before))
        else
            -- the file crashed part-way: that is a failure of its own
            crashed = crashed + 1
            print("CRASH " .. harness.current_file .. ": " .. tostring(problem))
        end
    end
    print(string.format("\npassed %d   failed %d   crashed files %d",
                        harness.passed, harness.failed, crashed))
    if harness.failed > 0 or crashed > 0 then
        -- something is wrong: say so to the shell as well
        os.exit(1)
    end
    -- (all passed: exit normally)
end
-- }}}

main()
