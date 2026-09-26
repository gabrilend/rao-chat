#!/usr/bin/env luajit
-- 050-run-tests.lua — runs every recipients test (issues 103 and 103a) and
-- reports the count.
--
-- Usage:  luajit 050-run-tests.lua [project folder] [stand-in | real-101 | real]
--
-- The recipients module leans on two neighbours: the room folders (issue
-- 101: the room's entry, the bell) and the room tree (issue 102: the check
-- that a child room only takes members of its parent).  "stand-in" runs the
-- tests against the small copies kept in this tests folder; "real" runs them
-- against the real modules in src/; "real-101" uses the real room folders
-- with the stand-in tree (while 102 is being rewritten).  Each test prints one pass/FAIL line;
-- the last line is the tally, and the program ends with a failure status if
-- any test failed, so a build script can stop on it.  Files ending in -done
-- are retired and never run: the list below names each test file.

local DIR = arg[1] or "/home/ritz/programs/rao-chat"
local neighbours = arg[2] or "stand-in"

local tests_dir = DIR .. "/src/recipients/tests/"
local h = dofile(tests_dir .. "045-test-harness.lua")(DIR, neighbours)

print("recipients tests against " .. neighbours .. " neighbours; scratch homes in " .. h.scratch)

for _, file in ipairs({
    "047-test-address-pairs.lua",
    "048-test-ignore.lua",
    "049-test-members.lua",
    "052-test-withheld-and-send.lua",
    "053-test-leave-and-heard.lua",
    "054-test-child-room.lua",
    "055-test-shown-as.lua",
    "051-test-options.lua",
}) do
    print("-- " .. file)
    dofile(tests_dir .. file)(h)
end

print(string.format("recipients (%s): %d passed, %d failed", neighbours, h.passed, h.failed))
-- any failure: exit non-zero so callers stop; all passed: exit zero
if h.failed > 0 then
    os.exit(1)
end
os.exit(0)
