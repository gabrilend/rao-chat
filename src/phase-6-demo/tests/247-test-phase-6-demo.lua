-- 247-test-phase-6-demo.lua — the phase 6 demo's own referee (issue 606):
-- run the demo the way the owner would and check what it reports.
--
--   1. the demo runs whole through run-phase-demo 6, from another folder:
--      input/ is read first, a goodbye is written last, every scene ran,
--      the exit status agrees, and nothing is left running or on disk;
--      what each scene printed: what a home needs, both homes installed
--      as systemd user services by the installer (the unit naming
--      run-home, the list holding both), installed again with no file
--      changed, each service running its home in a bare environment, the
--      restart giving each home a new launcher, each stop ending with
--      status 0 and every gatherer stopped = asked; and that no real
--      service manager was used, said;
--   2. the installed homes talk: B's inbox holds the line A's phone wrote,
--      after both were started from their unit files;
--   3. broken versions fail: a scene made to fail (RAO_PHASE6_DEMO_BREAK)
--      is reported as could-not, the scenes before it still ran, exit 1;
--      a project copy missing the launcher (scripts/run-home) reports
--      every scene as could-not, naming it, exit 1.
--
-- Run it under the loopback-only wrapper, as every network test here: the
-- demo starts its own namespace inside it.
--
-- Run: luajit src/phase-6-demo/tests/247-test-phase-6-demo.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/phase%-6%-demo/tests/[^/]+$")
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

-- {{{ local function quote / run / read_all / scene_text
local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
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
-- The text printed under scene `title`'s heading, up to the next heading.
local function scene_text(output, title)
    local at = output:find(title, 1, true)
    if not at then return "" end
    local after = output:find("\n%-%-%-%-%-%-%-%-%-%-+\n%d+%. ", at + #title)
    return output:sub(at, (after or #output) - 1)
end
-- }}}

local SCENES = {
    { key = "needs",    title = "What a home needs, as this machine answers it" },
    { key = "install",  title = "Two homes installed, unattended" },
    { key = "again",    title = "Installed again: nothing changes" },
    { key = "room",     title = "A room between them" },
    { key = "services", title = "The services run the homes" },
    { key = "talk",     title = "The homes talk" },
    { key = "update",   title = "An update: every listed home restarted" },
    { key = "stop",     title = "The stop: each service stopped" },
}
local SCRATCH = DIR .. "/tmp/shared-memory/phase-6-demo"
local goodbye_path = DIR .. "/output/phase-6-demo.goodbye"
os.remove(goodbye_path)
local output, status = run(quote(DIR .. "/run-phase-demo") .. " " .. quote(DIR) .. " 6")

-- 1. the owner's two rules, and every scene
local input_at = output:find("0. What input/ holds (read first)", 1, true)
local modules_at = output:find("\nmodules:", 1, true)
check("1: input/ is read and shown before anything else", input_at and modules_at and input_at < modules_at,
      output:sub(1, 300))
local goodbye = read_all(goodbye_path)
check("1: a goodbye is written to output/, after the last scene, ending with goodbye.",
      goodbye and goodbye:match("goodbye%.\n$")
      and (output:find("goodbye written to", 1, true) or 0) > (output:find("Which scenes ran", 1, true) or math.huge),
      goodbye)
goodbye = goodbye or ""
check("1: every scene ran in full, and the exit status is 0",
      goodbye:find("8 of 8 scenes ran in full; 0 with a part missing; 0 could not run.", 1, true) and status == 0,
      "status " .. tostring(status) .. "; " .. goodbye .. output:sub(-3000))
for _, scene in ipairs(SCENES) do
    check("1: scene " .. scene.key .. " is reported as ran", goodbye:match("\n  ran%s+" .. scene.key .. "%s"), goodbye)
end
check("1: it says plainly that no real service manager is used, and why",
      output:find("No real service manager", 1, true) and output:find("installs nothing on the", 1, true), output:sub(1, 3000))

local needs = scene_text(output, SCENES[1].title)
check("1: needs: 601's lines, every required thing here", needs:find("every required thing is here", 1, true)
      and needs:match("found%s+LuaJIT"), needs)
local install = scene_text(output, SCENES[2].title)
local _, listed = install:gsub("\n  +listed   rao%-chat%-", "")
check("1: install: both homes made by the installer, each listed as a service",
      install:find("ok: the home is at <demo>/homes/A", 1, true) and install:find("ok: the home is at <demo>/homes/B", 1, true)
      and listed == 2, install)
check("1: install: the unit runs run-home with the project and the home, KillMode=mixed",
      install:find('ExecStart="<project>/scripts/run-home" "<project>" "<demo>/homes/A"', 1, true)
      and install:find("KillMode=mixed", 1, true), install)
check("1: install: the asked lines and stated lines are shown with their comments",
      install:find("(asked when this home was installed;", 1, true)
      and install:find("scripts/tally-options shows every choice)\n      gatherer.sync-interval = 30", 1, true), install)
local again = scene_text(output, SCENES[3].title)
check("1: again: every file byte for byte as it was", again:match("%d+ files [^\n]*every one byte for byte as it was"), again)
local services = scene_text(output, SCENES[5].title)
local _, active = services:gsub(": active\n", "")
local _, gatherers = services:gsub("gatherer pid %d+ running", "")
check("1: services: both active, each launcher in a bare environment, two gatherers each running",
      active == 2 and gatherers == 4
      and services:find("PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin HOME=", 1, true), services)
local update = scene_text(output, SCENES[7].title)
local _, renewed = update:gsub("launcher pid %d+ before, %d+ now %(running%)", "")
check("1: update: restart-homes restarted both, each with a new launcher, and the phone caught up after",
      update:find("every home asked for restarted and running (2)", 1, true) and renewed == 2
      and update:find("holds B's message after the update: yes; its own from before: yes", 1, true), update)
local stop = scene_text(output, SCENES[8].title)
local _, clean = stop:gsub("ended with status 0", "")
local _, asked = stop:gsub("stopped = asked", "")
check("1: stop: each launcher ended with status 0, saying everything stopped when asked; four gatherers asked",
      clean == 2 and asked == 4 and stop:find("processes of either home still running: none", 1, true), stop)
check("1: the demo's folder is removed", os.execute("test -e " .. quote(SCRATCH)) ~= 0, SCRATCH)
local left = run("pgrep -f " .. quote(SCRATCH:sub(1, -2) .. "[" .. SCRATCH:sub(-1) .. "]") .. " | wc -l")
check("1: none of the demo's processes is running", tonumber(left:match("^%s*(%d+)")) == 0, left)

-- 2. the installed homes talk
local talk = scene_text(output, SCENES[6].title)
local wrote = talk:match('write %x+ %-%-signature phone "(written on the phone, [%d:]+)"')
check("2: B's inbox holds the line A's phone wrote, after both started from their unit files",
      wrote and talk:find("in B's RAM inbox (301's layout)", 1, true)
      and talk:find("      | " .. wrote .. "\n", 1, true) ~= nil
      and (services:find("systemctl --user start", 1, true) or math.huge) < (output:find(SCENES[6].title, 1, true) or 0),
      talk)

-- 3. broken version 1: a scene made to fail
local broken, broken_status = run("RAO_PHASE6_DEMO_BREAK=talk " .. quote(DIR .. "/issues/completed/demos/phase-6-demo")
                                  .. " " .. quote(DIR))
local broken_goodbye = read_all(goodbye_path) or ""
check("3: broken 1: the broken scene says it could not run, and why",
      scene_text(broken, SCENES[6].title):find("COULD NOT RUN: failed: broken on purpose", 1, true), broken:sub(-2500))
check("3: broken 1: the scenes before it still ran, and the exit status is 1",
      broken_goodbye:match("\n  ran%s+services%s") and broken_goodbye:match("\n  could not%s+talk%s+failed: broken on purpose")
      and broken_status == 1, broken_goodbye)
check("3: broken 1: nothing is left running or on disk",
      os.execute("test -e " .. quote(SCRATCH)) ~= 0
      and tonumber(run("pgrep -f " .. quote(SCRATCH:sub(1, -2) .. "[" .. SCRATCH:sub(-1) .. "]") .. " | wc -l")
          :match("^%s*(%d+)")) == 0)

-- 3. broken version 2: a project copy without the launcher
local copy = DIR .. "/tmp/shared-memory/phase-6-demo-referee"
os.execute("rm -rf " .. quote(copy) .. " && mkdir -p " .. quote(copy))
os.execute("cp -r " .. quote(DIR .. "/src") .. " " .. quote(DIR .. "/scripts") .. " " .. quote(DIR .. "/input") .. " "
           .. quote(copy) .. " && mkdir -p " .. quote(copy .. "/output") .. " && rm " .. quote(copy .. "/scripts/run-home"))
local missing, missing_status = run("luajit " .. quote(copy .. "/src/phase-6-demo/245-phase-6-demo.lua") .. " " .. quote(copy))
local missing_goodbye = read_all(copy .. "/output/phase-6-demo.goodbye") or ""
check("3: broken 2: the missing launcher is named", missing:find("scripts/run%-home%s+%(issue 603%s*%)%s+NOT FOUND") ~= nil,
      missing:sub(1, 2500))
check("3: broken 2: every scene could not run, saying which program, exit 1",
      missing_goodbye:find("0 of 8 scenes ran in full; 0 with a part missing; 8 could not run.", 1, true)
      and missing_goodbye:match("\n  could not%s+needs%s+programs not found: scripts/run%-home\n") and missing_status == 1,
      missing_goodbye)
os.execute("rm -rf " .. quote(copy))
os.remove(goodbye_path)

print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
