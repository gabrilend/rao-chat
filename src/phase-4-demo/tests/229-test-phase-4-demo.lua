-- 229-test-phase-4-demo.lua — the phase 4 demo's own referee (issue 409):
-- run the demo the way the owner would and check what it reports.
--
-- Issue 409's referees:
--
--   1. the demo runs whole through run-phase-demo 4, from /: input/ is read
--      first, a goodbye is written last, every scene passes, the exit
--      status says so, and nothing is left running or on disk;
--   2. the clients talk: each page's room shows its own message on its side
--      and the other page's on the other, and each page's mirror holds its
--      own with `from: me` and the other's with another `from:`; and what
--      each scene printed (the folder whole, both pages answered, both
--      mirrors their homes', the times, the drop and the return);
--   3. broken versions fail: a scene made to fail (RAO_PHASE4_DEMO_BREAK)
--      is reported as could-not with its reason, the scenes before it still
--      ran, and the exit status is 1; a copy of the project missing the
--      stand-in browser reports every scene as could-not, saying so, and
--      exits 1.
--
-- Run it under the loopback-only wrapper, as every network test here: the
-- demo starts its own namespace inside it.
--
-- Run: luajit src/phase-4-demo/tests/229-test-phase-4-demo.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>"; exit status
-- 0 only when nothing failed.

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/phase%-4%-demo/tests/[^/]+$")
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
    { key = "folder",   title = "The page's folder" },
    { key = "homes",    title = "Two homes, each with its gatherer" },
    { key = "pairing",  title = "A page paired with each home" },
    { key = "catch-up", title = "Each page catches up" },
    { key = "talking",  title = "Page A writes" },
    { key = "rooms",    title = "Each page's room" },
    { key = "drop",     title = "Home A's device port stops" },
}
local SCRATCH = DIR .. "/tmp/shared-memory/phase-4-demo"
local goodbye_path = DIR .. "/output/phase-4-demo.goodbye"
os.remove(goodbye_path)
local output, status = run(quote(DIR .. "/run-phase-demo") .. " " .. quote(DIR) .. " 4")

-- {{{ referee 1: the demo runs whole
local input_at = output:find("0. What input/ holds (read first)", 1, true)
local modules_at = output:find("\nmodules:", 1, true)
check("1: input/ is read and shown before anything else", input_at and modules_at and input_at < modules_at,
      output:sub(1, 300))
check("1: run-phase-demo 4 finds the demo", output:find("8. Which scenes ran", 1, true) ~= nil, output:sub(-1500))
local goodbye = read_all(goodbye_path)
check("1: a goodbye is written to output/, ending with goodbye.", goodbye and goodbye:match("goodbye%.\n$"), goodbye)
goodbye = goodbye or ""
check("1: the goodbye is written after the last scene",
      (output:find("goodbye written to", 1, true) or 0) > (output:find("Which scenes ran", 1, true) or math.huge))
check("1: every scene ran in full, and the exit status is 0",
      goodbye:find("7 of 7 scenes ran in full; 0 with a part missing; 0 could not run.", 1, true) and status == 0,
      "status " .. tostring(status) .. "; " .. goodbye)
for _, scene in ipairs(SCENES) do
    check("1: scene " .. scene.key .. " is reported as ran", goodbye:match("\n  ran%s+" .. scene.key:gsub("%-", "%%-") .. "%s"),
          goodbye)
end
check("1: the demo's folder is removed", os.execute("test -e " .. quote(SCRATCH)) ~= 0, SCRATCH)
-- (the pattern's last letter in brackets, so pgrep's own shell is not found)
local left = run("pgrep -f " .. quote(SCRATCH:sub(1, -2) .. "[" .. SCRATCH:sub(-1) .. "]") .. " | wc -l")
check("1: none of the demo's processes is running", tonumber(left:match("^%s*(%d+)")) == 0, left)
check("1: Node standing in for the browser is said", output:find("stands in for the browser here (401 decision 4)", 1, true)
      and output:find("The page's drawing (207) is not\n  shown here", 1, true), output:sub(1, 4000))
-- }}}

-- {{{ referee 2: the clients talk, and each scene printed what it read
local folder = scene_text(output, SCENES[1].title)
check("2: folder: the page's files are all named by it, none names an address elsewhere, and its scripts load",
      folder:find("and the page names each one:", 1, true) and folder:find("no file of the page names an address", 1, true)
      and folder:find("\n      globals rao\n      crypto ok\n", 1, true), folder)
local homes = scene_text(output, SCENES[2].title)
local processes = 0
for _, pattern in ipairs({ "A: pid %d+%s+163%-gatherer%.lua%s+127%.0%.0%.2:7702%s+running",
                           "A: pid %d+%s+187%-device%-server%.lua%s+127%.0%.0%.2:7712%s+listening",
                           "B: pid %d+%s+163%-gatherer%.lua%s+127%.0%.0%.3:7703%s+running",
                           "B: pid %d+%s+187%-device%-server%.lua%s+127%.0%.0%.3:7713%s+listening" }) do
    if homes:match(pattern) then processes = processes + 1 end
end
check("2: homes: each home's gatherer runs and its device port listens, each on its own address", processes == 4, homes)
local pairing = scene_text(output, SCENES[3].title)
check("2: pairing: each home pairs a page (--browser lines), and each page's test is answered by its own home",
      select(2, pairing:gsub("give the page these lines", "")) == 2 and pairing:find("answered in %d+ ms by 127%.0%.0%.2 7712")
      and pairing:find("answered in %d+ ms by 127%.0%.0%.3 7713"), pairing)
check("2: pairing: no token is printed whole", not pairing:match("token = %a+%-%a+"), pairing)
local catch_up = scene_text(output, SCENES[4].title)
check("2: catch-up: each page's mirror holds its own home's RAM folder, every message the same",
      catch_up:match("page A's mirror against A's RAM folder: [1-9]%d* files, every message the same")
      and catch_up:match("page B's mirror against B's RAM folder: [1-9]%d* files, every message the same"), catch_up)
check("2: catch-up: a second catch-up from the mirror held sends no message again",
      catch_up:match("\n%s+%d+ file%(s%) received %(0 message%(s%)%)"), catch_up)
local talking = scene_text(output, SCENES[5].title)
local times = 0
for _, label in ipairs({ "in A's inbox", "in B's inbox", "in page B's mirror", "page B's answer in B's inbox",
                         "page B's answer in A's inbox", "page B's answer in page A's mirror" }) do
    if talking:match("\n%s+" .. label:gsub("'", "'") .. "[^\n]-%d+%.%d s\n") then times = times + 1 end
end
check("2: talking: page A's message reaches A, B and page B, and page B's answer reaches B, A and page A, with times",
      times == 6, talking)
check("2: talking: page B heard page A and answered; each page ended live with nothing pending",
      talking:find(" heard \"hello B, this is page A", 1, true)
      and select(2, talking:gsub("end live, tries 1, pending 0", "")) == 2, talking)
local rooms = scene_text(output, SCENES[6].title)
check("2: rooms: page A shows its own message on its side and page B's on the other, named where the speaker changes",
      rooms:match("\n%s+mine name page A %(me%)\n%s+mine message m%-%x+%.%.%. [^\n]*| hello B, this is page A")
      and rooms:match("\n%s+theirs name page B %(127%.0%.0%.3 7703%)\n%s+theirs message m%-%x+%.%.%. [^\n]*| hello A, page B heard you"),
      rooms)
check("2: rooms: page B shows the same talk from its side",
      rooms:match("\n%s+theirs name page A %(127%.0%.0%.2 7702%)\n%s+theirs message [^\n]*| hello B, this is page A")
      and rooms:match("\n%s+mine name page B %(me%)\n%s+mine message [^\n]*| hello A, page B heard you"), rooms)
check("2: rooms: each page's mirror holds its own message from: me and the other's from the other home",
      rooms:find("in page A's mirror: its own message from: me; the other's from: 127.0.0.3 7703", 1, true)
      and rooms:find("in page B's mirror: its own message from: me; the other's from: 127.0.0.2 7702", 1, true), rooms)
local drop = scene_text(output, SCENES[7].title)
check("2: drop: page A says the connection is lost with its retry, comes back by itself, and gets what was filed meanwhile",
      drop:find("errors retrying: connection lost: 127.0.0.2 7712 closed the connection (retrying in 5s)", 1, true)
      and drop:match("in page A's mirror %d+%.%d s after the server started again")
      and drop:match("end live, tries 2, pending 0"), drop)
-- }}}

-- {{{ referee 3: broken versions fail
local broken, broken_status = run("RAO_PHASE4_DEMO_BREAK=drop " .. quote(DIR .. "/issues/completed/demos/phase-4-demo")
                                  .. " " .. quote(DIR))
local broken_goodbye = read_all(goodbye_path) or ""
check("3: broken 1: the broken scene says it could not run, and why",
      scene_text(broken, SCENES[7].title):find("COULD NOT RUN: failed: broken on purpose", 1, true), broken:sub(-2500))
check("3: broken 1: the scenes before it still ran",
      broken_goodbye:find("6 of 7 scenes ran in full; 0 with a part missing; 1 could not run.", 1, true)
      and broken_goodbye:match("\n  could not%s+drop%s+failed: broken on purpose"), broken_goodbye)
check("3: broken 1: the exit status is 1", broken_status == 1, broken_status)

local copy = DIR .. "/tmp/shared-memory/phase-4-demo-referee"
os.execute("rm -rf " .. quote(copy) .. " && mkdir -p " .. quote(copy))
os.execute("cp -r " .. quote(DIR .. "/src") .. " " .. quote(DIR .. "/input") .. " " .. quote(copy)
           .. " && mkdir -p " .. quote(copy .. "/output") .. " && rm " .. quote(copy .. "/src/web/tests/208-stand-in-browser.js"))
local missing, missing_status = run("luajit " .. quote(copy .. "/src/phase-4-demo/227-phase-4-demo.lua") .. " " .. quote(copy))
local missing_goodbye = read_all(copy .. "/output/phase-4-demo.goodbye") or ""
check("3: broken 2: the missing stand-in is named", missing:find("208%-stand%-in%-browser%s+%(issue 401%s*%)%s+NOT THERE") ~= nil,
      missing:sub(1, 2000))
check("3: broken 2: every scene could not run, saying why",
      missing_goodbye:find("0 of 7 scenes ran in full; 0 with a part missing; 7 could not run.", 1, true)
      and missing_goodbye:match("\n  could not%s+folder%s+the stand%-in browser"), missing_goodbye)
check("3: broken 2: the exit status is 1", missing_status == 1, missing_status)
os.execute("rm -rf " .. quote(copy))
os.remove(goodbye_path)
-- }}}

print("counts " .. passed .. " " .. failed)
os.exit(failed == 0 and 0 or 1)
