-- 113-test-tally-script.lua — runs scripts/tally-options the way the owner would.
--
-- The gathering and showing halves are tested on samples in 111 and 112.  This
-- file checks the joining script itself, on the real project: that it runs
-- from another folder, reads its flags, refuses a flag it does not know, and
-- that --walk stops honestly when its input ends.  Its figures depend on
-- whichever options files exist today, so only the shape is checked.

return function(DIR, harness)
    local check = harness.check
    local script = DIR .. "/scripts/tally-options"

    -- {{{ local function run
    -- Runs a shell command and returns (all output as one string, exit status).
    local function run(command)
        local pipe = io.popen("cd / && " .. command .. " 2>&1; echo \"exit=$?\"")
        local output = pipe:read("*a")
        pipe:close()
        local status = tonumber(output:match("exit=(%d+)%s*$"))
        return output, status
    end
    -- }}}

    local output, status = run('"' .. script .. '" "' .. DIR .. '"')
    check("summary runs from / and exits 0", status == 0, output)
    check("summary starts with the files read", output:find("^options files read: %d+") ~= nil,
          output:sub(1, 80))
    check("summary ends with the owner/state counts",
          output:find("waiting on the owner: %d+    waiting on some other state: %d+") ~= nil)

    -- Every live options file on disk is read: the count the summary gives
    -- equals the count `find` gives, and no retired <name>-done file is
    -- among them.  This is the check that a module rewriting its options
    -- file (round 2) is still picked up.
    local listing = io.popen('find "' .. DIR .. '/src" -mindepth 2 -maxdepth 2 -name "[0-9][0-9][0-9]-options.lua"')
    local on_disk = 0
    for _ in listing:lines() do
        on_disk = on_disk + 1
    end
    listing:close()
    check("the summary reads every live options file on disk (" .. on_disk .. ")",
          tonumber(output:match("^options files read: (%d+)")) == on_disk, output:sub(1, 80))
    check("no retired -done options file is named", output:find("options.lua-done", 1, true) == nil)

    output, status = run('"' .. script .. '" --walk --no-pause')
    local count = tonumber(output:match("choices: (%d+)")) -- absent in walk output
    check("walk --no-pause exits 0", status == 0, output:sub(1, 200))
    check("walk --no-pause shows a first page or says there is none",
          output:find("choice 1 of %d+") ~= nil or output:find("no undecided") ~= nil)
    check("walk --no-pause never asks for Enter", output:find("[Enter]", 1, true) == nil)
    check("walk output has no summary counts", count == nil)

    output, status = run('"' .. script .. '" --walk < /dev/null')
    check("walk with ended input exits 0", status == 0, output:sub(1, 200))
    -- with one choice or fewer there is no second page to stop before
    check("walk with ended input stops after one page, saying so",
          output:find("(input ended after choice 1 of", 1, true) ~= nil
          or output:find("choice 1 of 1:") ~= nil
          or output:find("no undecided") ~= nil, output:sub(-200))
    check("walk with ended input never shows page 2", output:find("choice 2 of") == nil)

    output, status = run('"' .. script .. '" --wlak')
    check("an unknown flag exits 2", status == 2, status)
    check("an unknown flag is named", output:find("unknown argument: --wlak", 1, true) ~= nil, output)
end
