-- 160-test-phase-2-demo.lua — the phase 2 demo's own referee (issue 210):
-- run the demo the way the owner would and check what it reports.
--
-- Issue 210's referee: every scene reports a figure read from a running
-- home, and a scene that cannot run says why.  Checked here:
--
--   - started through run-phase-demo 2, from another folder: input/ is read
--     first, a goodbye is written last, and the exit status agrees with the
--     goodbye's counts (0 all ran, 1 one could not, 2 some wait or miss a
--     part);
--   - every scene whose issues are built ran, and printed figures;
--   - the scenes whose issues are not built (214, 215) say so, naming
--     the issue, and are not counted as run;
--   - the real-process scenes (211): each home's gatherer is a process of
--     its own, the starter restarts one killed, due/ holds the pile for a
--     member down and empties when it returns; acknowledge-after = disk
--     loses none of 10 acknowledged messages at a power cut, ram all 10;
--   - a missing part (fail2ban-regex, when it is not installed) is named;
--   - the homes stated their own loopback addresses and ports;
--   - broken version 1: a scene made to fail (RAO_PHASE2_DEMO_BREAK) is
--     reported as could-not with its reason, the other scenes still run,
--     and the exit status is 1;
--   - broken version 2: a copy of the project missing one phase 2 module
--     reports every runnable scene as could-not, naming the module, and
--     exits 1.
--
-- Run: luajit src/phase-2-demo/tests/160-test-phase-2-demo.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/phase%-2%-demo/tests/[^/]+$")
end

local passed, failed = 0, 0

-- {{{ local function check
local function check(claim, ok, detail)
    if ok then
        passed = passed + 1
        print("PASS " .. claim)
    else
        failed = failed + 1
        print("FAIL " .. claim .. (detail and (": " .. tostring(detail):sub(1, 400)) or ""))
    end
end
-- }}}

-- {{{ local function quote
local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
-- }}}

-- {{{ local function run
-- command → its output (stdout and stderr) and exit status.
local function run(command)
    local pipe = io.popen("cd / && " .. command .. " 2>&1; echo \"exit=$?\"")
    local output = pipe:read("*a")
    pipe:close()
    return output, tonumber(output:match("exit=(%d+)%s*$"))
end
-- }}}

-- {{{ local function read_all
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
    if not at then return nil end
    local after = output:find("\n%-%-%-%-%-%-%-%-%-%-+\n%d+%. ", at + #title)
    return output:sub(at, (after or #output) - 1)
end
-- }}}

local RUNNABLE = {
    { key = "delivery",   title = "A message to every pair at once" },
    { key = "down",       title = "A member down, its pile" },
    { key = "gatherers",  title = "Real gatherer processes" },
    { key = "join",       title = "Joining with a token and one pair" },
    { key = "keys",       title = "Two rooms with one label" },
    { key = "child",      title = "A child room flags an outsider" },
    { key = "syncing",    title = "Contact syncing" },
    { key = "token",      title = "A token changed by hand" },
    { key = "leaving",    title = "A genuine leave and a forged one" },
    { key = "crosscheck", title = "A two-faced sender caught" },
    { key = "housemates", title = "Housemates found" },
    { key = "failed",     title = "Failed decryption" },
    { key = "signatures", title = "A signature table" },
    { key = "git",        title = "Each mailbox's git repository" },
    { key = "acknowledge", title = "The gatherer.acknowledge-after switch" },
    { key = "phase1",     title = "Phase 1's tools on phase 2's homes" },
}
local WAITING = {}

local goodbye_path = DIR .. "/output/phase-2-demo.goodbye"
os.remove(goodbye_path)
local output, status = run(quote(DIR .. "/run-phase-demo") .. " " .. quote(DIR) .. " 2")

-- the owner's two rules
local input_at = output:find("0. What input/ holds (read first)", 1, true)
local modules_at = output:find("\nmodules:", 1, true)
check("input/ is read and shown before anything else", input_at and modules_at and input_at < modules_at,
      output:sub(1, 300))
check("run-phase-demo 2 finds the demo", output:find("17. Which scenes ran", 1, true) ~= nil, output:sub(-600))
local goodbye = read_all(goodbye_path)
check("a goodbye is written to output/, ending with goodbye.", goodbye and goodbye:match("goodbye%.\n$"), goodbye)
goodbye = goodbye or ""
check("the goodbye is written after the last scene",
      (output:find("goodbye written to", 1, true) or 0) > (output:find("Which scenes ran", 1, true) or math.huge))

-- the counts and the exit status agree
local ran, total, gaps, waits, could_not =
    goodbye:match("(%d+) of (%d+) scenes ran in full; (%d+) with a part missing; (%d+) wait on an issue; (%d+) could not run")
ran, total, gaps, waits, could_not = tonumber(ran), tonumber(total), tonumber(gaps), tonumber(waits), tonumber(could_not)
check("the goodbye counts the scenes", ran and total == 16, goodbye)
local expected = (could_not or 1) > 0 and 1 or (((gaps or 0) + (waits or 0)) > 0 and 2 or 0)
check("the exit status agrees with the goodbye (0 all, 1 could not, 2 waits or parts missing)",
      status == expected, "exit " .. tostring(status) .. ", goodbye:\n" .. goodbye)
check("no scene could not run", could_not == 0, goodbye)

-- every runnable scene ran and printed figures
for _, scene in ipairs(RUNNABLE) do
    local state = goodbye:match("\n  (%S+)%s+" .. scene.key:gsub("%-", "%%-") .. "%s")
    check("scene " .. scene.key .. " ran", state == "ran" or state == "gaps", goodbye)
    local text = scene_text(output, scene.title) or ""
    local figures = 0
    for _ in text:gmatch("%d") do figures = figures + 1 end
    check("scene " .. scene.key .. " printed figures read from its homes", figures >= 5
          and not text:find("COULD NOT", 1, true), text:sub(1, 400))
end
for key, issue in pairs(WAITING) do
    local line = goodbye:match("\n  waits%s+" .. key .. "%s+([^\n]*)")
    check("scene " .. key .. " waits, naming issue " .. issue, line and line:find(issue, 1, true), goodbye)
end
local fail2ban = io.popen("command -v fail2ban-regex"):read("*a")
if fail2ban == "" then
    check("without fail2ban-regex, the failed-decryption scene names that part as not run",
          goodbye:match("\n  gaps%s+failed%s+[^\n]*fail2ban%-regex") ~= nil, goodbye)
else
    check("with fail2ban-regex installed, the failed-decryption scene ran it",
          goodbye:match("\n  ran%s+failed") ~= nil, goodbye)
end

-- figures that only the real stages give
local delivery = scene_text(output, "A message to every pair at once") or ""
local acks = 0
for _ in delivery:gmatch("acknowledged %d+%.%d+ s after writing") do acks = acks + 1 end
check("delivery: an acknowledgement time for each of the three pairs", acks == 3, delivery)
check("delivery: each home connects from its own loopback address, on its own stated port",
      delivery:find("127.0.0.2 → 127.0.0.3:7603", 1, true) and delivery:find("C: tree mailbox, port 7604", 1, true),
      delivery)
local keys = scene_text(output, "Two rooms with one label") or ""
local tried = {}
for n in keys:gmatch('"[%w ]+" %x+%s+(%d) ') do tried[#tried + 1] = tonumber(n) end
table.sort(tried)
check("keys: the five frames each stopped at a different key (1 to 5 tried)",
      table.concat(tried, " ") == "1 2 3 4 5", keys)
local child = scene_text(output, "A child room flags an outsider") or ""
check("child: flagged, not sent to, then approved and sent to",
      child:find("C on B's send list: false; B's message reached C: 0", 1, true)
      and child:find("C on B's send list: true; B's next message reached C: 1", 1, true), child)
local leaving = scene_text(output, "A genuine leave and a forged one") or ""
check("leaving: the forged leave kept A; the genuine one removed it",
      leaving:find("B still holds A: true", 1, true) and leaving:find("A leaves: B removed A", 1, true), leaving)
local crosscheck = scene_text(output, "A two-faced sender caught") or ""
check("cross-check: both receivers raised the two-faced sender; the gap came back with its id",
      crosscheck:find("B raised 1", 1, true) and crosscheck:find("C raised 1", 1, true)
      and crosscheck:find("with the same id: true", 1, true), crosscheck)

local gatherers = scene_text(output, "Real gatherer processes") or ""
local processes = 0
for _ in gatherers:gmatch("pid %d+%s+163%-gatherer%.lua%s+127%.0%.0%.%d:76%d%d%s+running") do processes = processes + 1 end
check("gatherers: three homes' gatherers, each a running process of its own, on its own address",
      processes >= 3, gatherers)
check("gatherers: a gatherer killed is started again by its home's starter, which says so",
      gatherers:find("is gone after", 1, true) ~= nil or gatherers:find("started by hand", 1, true) ~= nil, gatherers)
check("gatherers: due/ holds B's pair with 3 missing, and none once B is back",
      gatherers:find("due/127.0.0.3-7603-", 1, true) and gatherers:find("missing = 3", 1, true)
      and gatherers:find("A's due/ now holds 0 file(s)", 1, true), gatherers)
local acknowledge = scene_text(output, "The gatherer.acknowledge-after switch") or ""
check("acknowledge: at a power cut, disk lost 0 of 10 acknowledged messages and ram lost 10",
      acknowledge:match("\n%s+disk%s+10%s+10%s+0%s") and acknowledge:match("\n%s+ram%s+10%s+0%s+10%s"), acknowledge)

local signatures = scene_text(output, "A signature table") or ""
local agree, of = signatures:match("(%d+) of (%d+) read as the table says")
check("signatures: every example of 214's table reads as the table says", agree and agree == of and tonumber(of) >= 15,
      signatures)
local gitscene = scene_text(output, "Each mailbox's git repository") or ""
check("git: the copies are byte-identical on both homes, under the token's fingerprint",
      gitscene:find("copies byte-identical on A and B: 2 of 2", 1, true)
      and gitscene:match("rooms/" .. string.rep("%x", 64) .. "/%d+%-%x+%.txt"), gitscene)
check("git: a hand edit is committed, and changes neither log",
      gitscene:find("1 file changed", 1, true)
      and gitscene:find("both logs unchanged by it (nothing sent): A same bytes, B same bytes", 1, true), gitscene)
check("git: one commit per sync cycle, by the home's name", gitscene:match("\n%s+%x+ A%-%d+: sync: %d+ cop"), gitscene)
check("git: the running log on its own branch, apart from the rooms' (215a)",
      gitscene:match("running%-log/A%-%d+/0001%.log  %d+ bytes")
      and gitscene:find("the rooms' branch holds 0 log file(s); the log branch 0 room copies", 1, true), gitscene)
check("git: both homes pulled and pushed a shared upstream; one file per message; the hand edit shared (215b)",
      gitscene:find("its rooms branch: 2 copies", 1, true) and gitscene:find("B's hand edit is there", 1, true)
      and gitscene:match("A: %d+ pull%(s%), [1-9]%d* push%(es%), last moment stop; conflicts 0"), gitscene)
check("git: another home's program is readable and never checked out (215b)",
      gitscene:match("A holds B's program as upstream/code/B%-%d+, readable and never checked out %(A's checked%-out branch: rooms%)")
      ~= nil, gitscene)

-- broken version 1: one scene made to fail
local broken, broken_status = run("RAO_PHASE2_DEMO_BREAK=keys " .. quote(DIR .. "/issues/completed/demos/phase-2-demo")
                                  .. " " .. quote(DIR))
local broken_goodbye = read_all(goodbye_path) or ""
check("broken 1: the failed scene is reported as could-not, with why",
      broken:find("COULD NOT RUN: failed: broken on purpose", 1, true)
      and broken_goodbye:match("\n  could not%s+keys%s+failed: broken on purpose"), broken_goodbye)
check("broken 1: the demo went on to the scenes after it", broken_goodbye:match("\n  ran%s+child%s") ~= nil,
      broken_goodbye)
check("broken 1: the exit status is 1", broken_status == 1, broken_status)

-- broken version 2: a project copy without the cross-check module
local copy = DIR .. "/tmp/shared-memory/phase-2-demo-referee"
os.execute("rm -rf " .. quote(copy) .. " && mkdir -p " .. quote(copy))
os.execute("cp -r " .. quote(DIR .. "/src") .. " " .. quote(DIR .. "/scripts") .. " " .. quote(DIR .. "/issues") .. " "
           .. quote(DIR .. "/input") .. " " .. quote(copy) .. " && mkdir -p " .. quote(copy .. "/output")
           .. " && rm " .. quote(copy .. "/src/delivery/156-cross-check.lua"))
local missing, missing_status = run("luajit " .. quote(copy .. "/src/phase-2-demo/158-phase-2-demo.lua") .. " " .. quote(copy))
local missing_goodbye = read_all(copy .. "/output/phase-2-demo.goodbye") or ""
check("broken 2: the missing module is named", missing:find("156%-cross%-check%s+%(issue 209%s*%)%s+NOT LOADED") ~= nil,
      missing:sub(1, 2000))
local none_ran = missing_goodbye:find("16 could not run", 1, true) ~= nil
check("broken 2: every runnable scene could not run, saying which module", none_ran
      and missing_goodbye:match("\n  could not%s+delivery%s+modules did not load: [^\n]*crosscheck"), missing_goodbye)
check("broken 2: the exit status is 1", missing_status == 1, missing_status)
os.execute("rm -rf " .. quote(copy))
os.execute("rm -rf " .. quote(DIR .. "/tmp/shared-memory/phase-2-demo"))
os.remove(goodbye_path)

print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
