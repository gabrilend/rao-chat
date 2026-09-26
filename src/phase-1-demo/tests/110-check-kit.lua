-- 110-check-kit.lua — the tiny checking kit the phase-1-demo tests share.
--
-- Each test file is given this harness and calls `check` once per claim it
-- makes ("the tally counts 3 owner choices").  The harness keeps a pass and a
-- fail count and prints one line per failure, so the runner can report the
-- totals and stop the build when anything fails.

local harness = { passed = 0, failed = 0, current_file = "" }

-- {{{ function harness.check
-- `claim` is a string describing what should be true; `holds` is the bool
-- saying whether it is; `detail` (string) is shown only when it fails.
function harness.check(claim, holds, detail)
    if holds then
        -- the claim held
        harness.passed = harness.passed + 1
    else
        -- the claim failed: say which file, which claim, and what was seen
        harness.failed = harness.failed + 1
        io.write("FAIL  ", harness.current_file, ": ", claim)
        io.write(detail and ("\n      saw: " .. tostring(detail)) or "", "\n")
    end
end
-- }}}

-- {{{ function harness.check_error
-- Runs `action` and checks that it fails with a message containing `expect`
-- (a plain substring, not a pattern).  Used for every refusal the tally must
-- make on a badly shaped options file.
function harness.check_error(claim, action, expect)
    local ran, message = pcall(action)
    if ran then
        -- it should have failed but did not
        harness.check(claim, false, "no error was raised")
    else
        -- it failed: the message must name the problem
        harness.check(claim, tostring(message):find(expect, 1, true) ~= nil, message)
    end
end
-- }}}

-- {{{ function harness.contains_line
-- True when some line in `lines` contains `text` (plain substring).
function harness.contains_line(lines, text)
    for _, line in ipairs(lines) do
        if line:find(text, 1, true) then
            return true
        end
    end
    return false
end
-- }}}

return harness
