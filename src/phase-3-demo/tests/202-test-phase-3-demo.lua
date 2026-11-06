-- 202-test-phase-3-demo.lua — the phase 3 demo's own referee (issue 310):
-- run the demo the way the owner would and check what it reports.
--
-- Issue 310's referee: each scene prints what it shows and passes or
-- fails.  Checked here:
--
--   - started through run-phase-demo 3, from another folder: input/ is read
--     first, a goodbye is written last, and the exit status agrees with the
--     goodbye's counts;
--   - every scene ran, and printed what it read: two homes, each with a
--     gatherer process and a listening device port on its own loopback
--     address; a phone and a browser paired with A, each answering its
--     test, the devices file private; both mirrors holding A's RAM
--     folder, every message the same; the browser reached A through the WebSocket upgrade; the
--     phone's message in A's log, the browser's mirror and B's log; the
--     phone checked in and caught B's message; the edit in both mirrors,
--     the two copies the same;
--   - nothing is left behind: the demo's folder is removed and none of its
--     processes is running;
--   - broken version 1: a scene made to fail (RAO_PHASE3_DEMO_BREAK) is
--     reported as could-not with its reason, the scenes before it still
--     ran, and the exit status is 1;
--   - broken version 2: a copy of the project missing one phase 3 module
--     reports every scene as could-not, naming the module, and exits 1.
--
-- Run it under the loopback-only wrapper, as every network test here: the
-- demo starts its own namespace inside it.
--
-- Run: luajit src/phase-3-demo/tests/202-test-phase-3-demo.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/phase%-3%-demo/tests/[^/]+$")
end

local passed, failed = 0, 0

-- {{{ local function check
local function check(claim, ok, detail)
    if ok then
        passed = passed + 1
        print("PASS " .. claim)
    else
        failed = failed + 1
        print("FAIL " .. claim .. (detail and (": " .. tostring(detail):sub(1, 600)) or ""))
    end
end
-- }}}

-- {{{ local function quote / run / read_all
local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
-- command → its output (stdout and stderr) and exit status.
local function run(command)
    local pipe = io.popen("cd / && " .. command .. " 2>&1; echo \"exit=$?\"")
    local output = pipe:read("*a")
    pipe:close()
    return output, tonumber(output:match("exit=(%d+)%s*$"))
end
local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
-- }}}

-- {{{ local function scene_text
-- The text printed under scene `title`'s heading, up to the next heading.
local function scene_text(output, title)
    local at = output:find(title, 1, true)
    if not at then return "" end
    local after = output:find("\n%-%-%-%-%-%-%-%-%-%-+\n%d+%. ", at + #title)
    return output:sub(at, (after or #output) - 1)
end
-- }}}

local SCENES = {
    { key = "homes",    title = "Two homes, each with its gatherer" },
    { key = "pairing",  title = "A phone and a browser paired" },
    { key = "catch-up", title = "Each device catches up" },
    { key = "writing",  title = "The phone writes" },
    { key = "locked",   title = "The phone locks" },
    { key = "edit",     title = "A message edited" },
}
local SCRATCH = DIR .. "/tmp/shared-memory/phase-3-demo"
local goodbye_path = DIR .. "/output/phase-3-demo.goodbye"
os.remove(goodbye_path)
local output, status = run(quote(DIR .. "/run-phase-demo") .. " " .. quote(DIR) .. " 3")

-- the owner's two rules
local input_at = output:find("0. What input/ holds (read first)", 1, true)
local modules_at = output:find("\nmodules:", 1, true)
check("input/ is read and shown before anything else", input_at and modules_at and input_at < modules_at,
      output:sub(1, 300))
check("run-phase-demo 3 finds the demo", output:find("7. Which scenes ran", 1, true) ~= nil, output:sub(-1500))
local goodbye = read_all(goodbye_path)
check("a goodbye is written to output/, ending with goodbye.", goodbye and goodbye:match("goodbye%.\n$"), goodbye)
goodbye = goodbye or ""
check("the goodbye is written after the last scene",
      (output:find("goodbye written to", 1, true) or 0) > (output:find("Which scenes ran", 1, true) or math.huge))
check("every scene ran in full, and the exit status is 0",
      goodbye:find("6 of 6 scenes ran in full; 0 with a part missing; 0 could not run.", 1, true) and status == 0,
      "status " .. tostring(status) .. "; " .. goodbye)
for _, scene in ipairs(SCENES) do
    check("scene " .. scene.key .. " is reported as ran", goodbye:match("\n  ran%s+" .. scene.key:gsub("%-", "%%-") .. "%s"),
          goodbye)
end

-- what each scene printed
local homes = scene_text(output, SCENES[1].title)
local processes = 0
for _, pattern in ipairs({ "A: pid %d+%s+163%-gatherer%.lua%s+127%.0%.0%.2:7702%s+running",
                           "A: pid %d+%s+187%-device%-server%.lua%s+127%.0%.0%.2:7712%s+listening",
                           "B: pid %d+%s+163%-gatherer%.lua%s+127%.0%.0%.3:7703%s+running",
                           "B: pid %d+%s+187%-device%-server%.lua%s+127%.0%.0%.3:7713%s+listening" }) do
    if homes:match(pattern) then processes = processes + 1 end
end
check("homes: each home's gatherer runs and its device port listens, each on its own address", processes == 4, homes)
check("homes: each gatherer was started by its home's starter, which runs",
      homes:find("started by its own starter (164)", 1, true) and homes:match("A: pid %d+%s+164%-home%-starter%.lua%s+running")
      and homes:match("B: pid %d+%s+164%-home%-starter%.lua%s+running"), homes)

local pairing = scene_text(output, SCENES[2].title)
check("pairing: the phone and the browser are paired with A, and listed",
      pairing:find("paired phone", 1, true) and pairing:find("paired browser", 1, true)
      and pairing:match("<home A> list\n%s+browser\n%s+phone\n"), pairing)
check("pairing: no token is printed whole", not pairing:match("token = %a+%-%a+"), pairing)
check("pairing: A's devices file is private", pairing:find("(mode 600)", 1, true), pairing)
local _, answered = pairing:gsub("answered in %d+ ms by 127%.0%.0%.2 7712", "")
check("pairing: each device's test is answered by A", answered == 2, pairing)

local catch_up = scene_text(output, SCENES[3].title)
check("catch-up: both mirrors hold every file of A's RAM folder, every message the same",
      catch_up:match("the phone's mirror against A's RAM folder: [1-9]%d* files, every message the same")
      and catch_up:match("the browser's mirror against A's RAM folder: [1-9]%d* files, every message the same"), catch_up)
check("catch-up: the browser reached A through the WebSocket upgrade",
      catch_up:match("<browser> catch%-up\n[^\n]*through a WebSocket upgrade on /rao%-chat%-socket\n")
      and not catch_up:match("<phone> catch%-up\n[^\n]*WebSocket"), catch_up)
check("catch-up: a second catch-up with nothing new changes nothing", catch_up:match("0 message%(s%)%), 0 changed, 0 dropped"),
      catch_up)

local writing = scene_text(output, SCENES[4].title)
check("writing: the phone's message is in A's log, the browser's mirror and B's log, with times",
      writing:match("in A's log[^\n]-%d+%.%d s\n") and writing:match("in the browser's mirror[^\n]-%d+%.%d s\n")
      and writing:match("in B's log[^\n]-%d+%.%d s\n"), writing)
check("writing: the browser's live output shows the message pushed", writing:match("\n%s+received [^\n]*/%d+%-%x+"), writing)
check("writing: the phone sent its typed file", writing:find("sent 1 typed file(s) to 127.0.0.2 7712, 0 kept", 1, true),
      writing)

local locked = scene_text(output, SCENES[5].title)
check("locked: the phone checked in and caught B's message",
      locked:match("checked in: caught up with 127%.0%.0%.2 7712") and locked:match("in the phone's mirror %d+%.%d s after"),
      locked)

local edit = scene_text(output, SCENES[6].title)
check("edit: the edit reached A's inbox, the browser and the phone, with times",
      edit:match("A's inbox file rewritten[^\n]-%d+%.%d s\n") and edit:match("the browser's mirror[^\n]-%d+%.%d s\n")
      and edit:match("the phone's mirror[^\n]-%d+%.%d s\n"), edit)
check("edit: the phone's copy reads edited, with the new text, and the browser's is the same",
      edit:find("| edited: yes\n", 1, true) and edit:find("| written on the phone, and edited", 1, true)
      and edit:find("byte for byte the same: yes", 1, true), edit)
check("edit: the stand-in is said", edit:find("no viewer or device command makes an edit yet", 1, true), edit)

-- nothing left behind
check("the demo's folder is removed", os.execute("test -e " .. quote(SCRATCH)) ~= 0, SCRATCH)
-- (the pattern's last letter in brackets, so pgrep's own shell is not found)
local left = run("pgrep -f " .. quote(SCRATCH:sub(1, -2) .. "[" .. SCRATCH:sub(-1) .. "]") .. " | wc -l")
check("none of the demo's processes is running", tonumber(left:match("^%s*(%d+)")) == 0, left)

-- broken version 1: a scene made to fail
local broken, broken_status = run("RAO_PHASE3_DEMO_BREAK=edit " .. quote(DIR .. "/issues/completed/demos/phase-3-demo")
                                  .. " " .. quote(DIR))
local broken_goodbye = read_all(goodbye_path) or ""
check("broken 1: the broken scene says it could not run, and why",
      scene_text(broken, SCENES[6].title):find("COULD NOT RUN: failed: broken on purpose", 1, true), broken:sub(-2500))
check("broken 1: the scenes before it still ran",
      broken_goodbye:find("5 of 6 scenes ran in full; 0 with a part missing; 1 could not run.", 1, true)
      and broken_goodbye:match("\n  could not%s+edit%s+failed: broken on purpose"), broken_goodbye)
check("broken 1: the exit status is 1", broken_status == 1, broken_status)

-- broken version 2: a project copy without the reference device
local copy = DIR .. "/tmp/shared-memory/phase-3-demo-referee"
os.execute("rm -rf " .. quote(copy) .. " && mkdir -p " .. quote(copy))
os.execute("cp -r " .. quote(DIR .. "/src") .. " " .. quote(DIR .. "/input") .. " " .. quote(copy)
           .. " && mkdir -p " .. quote(copy .. "/output") .. " && rm " .. quote(copy .. "/src/devices/190-device.lua"))
local missing, missing_status = run("luajit " .. quote(copy .. "/src/phase-3-demo/200-phase-3-demo.lua") .. " " .. quote(copy))
local missing_goodbye = read_all(copy .. "/output/phase-3-demo.goodbye") or ""
check("broken 2: the missing module is named", missing:find("190%-device%s+%(issue 303%s*%)%s+NOT LOADED") ~= nil,
      missing:sub(1, 2000))
check("broken 2: every scene could not run, saying which module",
      missing_goodbye:find("0 of 6 scenes ran in full; 0 with a part missing; 6 could not run.", 1, true)
      and missing_goodbye:match("\n  could not%s+homes%s+modules did not load: device\n"), missing_goodbye)
check("broken 2: the exit status is 1", missing_status == 1, missing_status)
os.execute("rm -rf " .. quote(copy))
os.remove(goodbye_path)

print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
