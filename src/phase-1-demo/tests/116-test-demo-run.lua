-- 116-test-demo-run.lua — runs the finished demo the way the owner would.
--
-- Starts issues/completed/demos/phase-1-demo from another folder, and again
-- through the project's run-phase-demo picker, and checks the owner's two
-- rules (input/ read first, a goodbye written to output/ last), that the
-- exit status agrees with the goodbye's own count, and — the real finish
-- line — that every scene ran.  That last check fails for as long as some
-- module's options file does not yet record a choice a scene runs.

return function(DIR, harness)
    local check = harness.check

    -- {{{ local function run
    local function run(command)
        local pipe = io.popen("cd / && " .. command .. " 2>&1; echo \"exit=$?\"")
        local output = pipe:read("*a")
        pipe:close()
        return output, tonumber(output:match("exit=(%d+)%s*$"))
    end
    -- }}}

    local goodbye_path = DIR .. "/output/phase-1-demo.goodbye"
    os.remove(goodbye_path)
    local output, status = run("'" .. DIR .. "/issues/completed/demos/phase-1-demo' '" .. DIR .. "'")

    local input_at = output:find("0. What input/ holds (read first)", 1, true)
    local modules_at = output:find("phase 1 modules:", 1, true)
    check("input/ is read and shown before anything else",
          input_at ~= nil and modules_at ~= nil and input_at < modules_at, output:sub(1, 300))
    check("input/'s README is listed with its size", output:find("README%s+%d+ bytes") ~= nil)

    local goodbye = io.open(goodbye_path, "r")
    check("a goodbye is written to output/", goodbye ~= nil)
    if goodbye then
        -- the goodbye exists: check what it says
        local text = goodbye:read("*a")
        goodbye:close()
        check("the goodbye ends with goodbye.", text:match("goodbye%.\n$") ~= nil, text)
        local ran, total = text:match("(%d+) of (%d+) scenes ran")
        check("the goodbye counts the scenes", ran ~= nil, text)
        check("the exit status agrees with the goodbye",
              (ran == total and status == 0) or (ran ~= total and status == 1),
              tostring(ran) .. "/" .. tostring(total) .. " exit " .. tostring(status))
        check("the goodbye is written after the last scene",
              output:find("goodbye written to", 1, true) > (output:find("Which scenes ran", 1, true) or 0))
        check("EVERY scene ran (needs every module's options file)", ran ~= nil and ran == total,
              text)
    end
    -- (no goodbye: the checks above already failed)

    local picked, picked_status = run("'" .. DIR .. "/run-phase-demo' '" .. DIR .. "' 1")
    check("run-phase-demo 1 finds and runs this demo",
          picked:find("0. What input/ holds", 1, true) ~= nil, picked:sub(1, 300))
    check("run-phase-demo passes the demo's exit status through", picked_status == status)
end
