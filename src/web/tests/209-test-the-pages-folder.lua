-- 209-test-the-pages-folder.lua — the referees of issue 401, the page's
-- folder: every file the page names is in src/web and every file there is
-- named; nothing comes from anywhere else; no text is read as markup or
-- as code; colours are written only in the palette; and the stand-in
-- browser (208) loads the page's scripts in the page's order, each adding
-- its part to `rao` and nothing else to the global names.
--
-- The checks of the folder are run on the real folder, and on copies of
-- it made wrong on purpose (a missing script, a script from a content
-- network, markup from text, a colour outside the palette), which they
-- must refuse: those copies are the referees' broken versions.  No
-- network is used; the copies are under RAO_TEST_ROOT when that is set,
-- otherwise a folder of its own under /dev/shm (or /tmp), removed at the
-- end.
--
-- Run: luajit src/web/tests/209-test-the-pages-folder.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/web/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local ffi = require("ffi")
local disk = require("003-disk")
ffi.cdef [[ int getpid(void); ]]

local base = os.getenv("RAO_TEST_ROOT")
if not base or base == "" then
    base = os.execute("test -d /dev/shm && test -w /dev/shm") == 0 and "/dev/shm" or "/tmp"
end
local ROOT = base .. "/rao-chat-pages-folder-test-" .. ffi.C.getpid()
local WEB = DIR .. "/src/web"
local STAND_IN = WEB .. "/tests/208-stand-in-browser.js"
local q = disk.shell_quote
local passed, failed = 0, 0

-- {{{ local function check / must
local ONLY = os.getenv("ONLY")
local function check(claim, test)
    if ONLY and not claim:find(ONLY, 1, true) then return end
    local ok, problem = pcall(test)
    if ok then
        passed = passed + 1
        print("PASS " .. claim)
    else
        failed = failed + 1
        print("FAIL " .. claim .. ": " .. tostring(problem))
    end
end
local function must(condition, words)
    if not condition then error(words, 2) end
end
-- }}}

-- {{{ local function read_file / write_file / run
local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
local function write_file(path, text)
    local handle = assert(io.open(path, "wb"))
    handle:write(text)
    handle:close()
end
-- command → exit status, what it printed (both streams)
local function run(command)
    local out = ROOT .. "/run-output"
    local status = os.execute(command .. " > " .. q(out) .. " 2>&1")
    return status, read_file(out) or ""
end
-- }}}

-- {{{ the folder's files
-- folder → the page's file name, and every file the page runs (not
-- tests/, not the .info.md notes beside the files), sorted
local function page_files(folder)
    local page, files = nil, {}
    for _, name in ipairs(disk.list_dir(folder)) do
        if disk.is_file(folder .. "/" .. name) and not name:match("%.info%.md$") then
            files[#files + 1] = name
            if name:match("^%d%d%d%-rao%-chat%.html$") then page = page and "two" or name end
        end
    end
    table.sort(files)
    return page, files
end

-- the page's HTML → the names its <link href> and <script src> give, in order
local function named_by(html)
    local names = {}
    for tag in html:gmatch("<link%f[%s][^>]*>") do
        local href = tag:match('href="([^"]+)"')
        if href then names[#names + 1] = href end
    end
    for tag in html:gmatch("<script%f[%s>][^>]*>") do
        names[#names + 1] = tag:match('src="([^"]+)"') or "(an inline script)"
    end
    return names
end
-- }}}

-- {{{ the checks, one function per referee: folder → list of problems
local CHECKS = {}

-- 1. whole: named ⇔ present
function CHECKS.whole(folder)
    local problems = {}
    local page, files = page_files(folder)
    if not page or page == "two" then return { "not exactly one <n>-rao-chat.html" } end
    local present = {}
    for _, name in ipairs(files) do present[name] = true end
    local named = { [page] = true }
    for _, name in ipairs(named_by(read_file(folder .. "/" .. page))) do
        if not present[name] then problems[#problems + 1] = "the page names " .. name .. ", which is not in the folder" end
        named[name] = true
    end
    for _, name in ipairs(files) do
        if not named[name] then problems[#problems + 1] = name .. " is in the folder but the page does not name it" end
    end
    return problems
end

-- 2. nothing from elsewhere
local OUTSIDE = {
    { "https?:", "an http(s) address" },
    { "wss?://[%w%[]", "a WebSocket address with its host written in" },
    { "[\"'(]//[%w%[]", "an address with no scheme (//host)" },
    { "url%(", "a url( in a stylesheet" },
    { "@import", "an @import" },
    { "type=\"module\"", "a module script" },
    { "%f[%w]import%s*%(", "a dynamic import(" },
    { "\n%s*import[%s{*]", "an import statement" },
    { "%f[%w]require%s*%(", "a require(" },
    { "fetch%s*%(", "a fetch(" },
    { "XMLHttpRequest", "an XMLHttpRequest" },
}
function CHECKS.nothing_from_elsewhere(folder)
    local problems = {}
    local _, files = page_files(folder)
    for _, name in ipairs(files) do
        local text = "\n" .. (read_file(folder .. "/" .. name) or "")
        for _, rule in ipairs(OUTSIDE) do
            if text:find(rule[1]) then problems[#problems + 1] = name .. " has " .. rule[2] end
        end
    end
    return problems
end

-- 3. no text read as markup or code
local AS_CODE = {
    { "innerHTML", "innerHTML" }, { "outerHTML", "outerHTML" },
    { "insertAdjacentHTML", "insertAdjacentHTML" }, { "document%.write", "document.write" },
    { "%f[%w]eval%s*%(", "eval(" }, { "new%s+Function", "new Function" },
    { "setTimeout%s*%(%s*[\"'`]", "a string given to setTimeout" },
    { "setInterval%s*%(%s*[\"'`]", "a string given to setInterval" },
    { "%son%a+%s*=%s*[\"']", "an inline on...= handler" },
    { "javascript:", "a javascript: address" },
}
function CHECKS.no_markup_from_text(folder)
    local problems = {}
    local _, files = page_files(folder)
    for _, name in ipairs(files) do
        local text = read_file(folder .. "/" .. name) or ""
        for _, rule in ipairs(AS_CODE) do
            if text:find(rule[1]) then problems[#problems + 1] = name .. " has " .. rule[2] end
        end
    end
    return problems
end

-- 4. one palette
local NAMED = { "black", "white", "red", "green", "blue", "yellow", "cyan", "magenta", "gray", "grey",
                "goldenrod", "orange", "purple", "pink", "lime", "aqua", "navy", "silver", "maroon", "olive", "teal" }
function CHECKS.one_palette(folder)
    local problems = {}
    local _, files = page_files(folder)
    for _, name in ipairs(files) do
        if not name:match("^%d%d%d%-palette%.css$") then
            local text = read_file(folder .. "/" .. name) or ""
            -- a #rgb, #rgba, #rrggbb or #rrggbbaa colour (an id selector
            -- such as #room is not one: its letters are not all hex)
            for found in text:gmatch("#(%x+)%f[^%w%-]") do
                if #found == 3 or #found == 4 or #found == 6 or #found == 8 then
                    problems[#problems + 1] = name .. " writes the colour #" .. found
                end
            end
            for _, word in ipairs({ "rgba?%(", "hsla?%(" }) do
                if text:find(word) then problems[#problems + 1] = name .. " writes a colour with " .. word:gsub("%%", "") end
            end
            if name:match("%.css$") then
                for property, value in text:gmatch("([%w%-]+)%s*:%s*([^;}]+)") do
                    for _, colour in ipairs(NAMED) do
                        if value:lower():find("%f[%w]" .. colour .. "%f[^%w%-]") and property ~= "font-family" then
                            problems[#problems + 1] = name .. " names the colour " .. colour .. " in " .. property
                        end
                    end
                end
            end
            if text:find("%.style%.") or text:find("%sstyle%s*=") then
                problems[#problems + 1] = name .. " sets a style outside the stylesheets"
            end
        end
    end
    return problems
end
-- }}}

-- {{{ local function copy_with
-- a copy of the folder with one file changed: name, function(text) → text
local copies = 0
local function copy_with(name, change)
    copies = copies + 1
    local folder = ROOT .. "/copy-" .. copies
    os.execute("mkdir -p " .. q(folder) .. " && cp -p " .. q(WEB) .. "/*.* " .. q(folder) .. "/")
    local path = folder .. "/" .. name
    write_file(path, change(read_file(path) or ""))
    return folder
end
local PAGE = select(1, page_files(WEB))
local function joined(problems) return table.concat(problems, "; ") end
-- }}}

os.execute("mkdir -p " .. q(ROOT))

-- {{{ referee 1: the folder is whole
check("1: every file the page names is in the folder, and every file there is named", function()
    local problems = CHECKS.whole(WEB)
    must(#problems == 0, joined(problems))
    must(#named_by(read_file(WEB .. "/" .. PAGE)) >= 4, "the page names fewer than four files")
end)
check("1 broken: a script tag naming a missing file is found", function()
    local copy = copy_with(PAGE, function(text)
        return text:gsub("</body>", '<script src="299-missing.js"></script>\n</body>')
    end)
    local problems = CHECKS.whole(copy)
    must(joined(problems):find("299%-missing%.js, which is not in the folder"), "not found: " .. joined(problems))
end)
check("1 broken: a file the page does not name is found", function()
    local copy = copy_with("206-rao.js", function(text) return text end)
    write_file(copy .. "/298-stray.js", "// stray\n")
    must(joined(CHECKS.whole(copy)):find("298%-stray%.js is in the folder"), "not found")
end)
-- }}}

-- {{{ referee 2: nothing comes from elsewhere
check("2: no file names an outside address or loads a module", function()
    local problems = CHECKS.nothing_from_elsewhere(WEB)
    must(#problems == 0, joined(problems))
end)
check("2 broken: a script from a content network is refused", function()
    local copy = copy_with(PAGE, function(text)
        return text:gsub("</head>", '<script src="https://cdn.example.org/library.js"></script>\n</head>')
    end)
    must(joined(CHECKS.nothing_from_elsewhere(copy)):find("an http%(s%) address"), "not refused")
end)
check("2 broken: a WebSocket address written in, and a module, are refused", function()
    local copy = copy_with("206-rao.js", function(text)
        return text .. '\nvar s = new WebSocket("ws://192.0.2.1:8080/x");\nimport("./other.js");\n'
    end)
    local found = joined(CHECKS.nothing_from_elsewhere(copy))
    must(found:find("host written in") and found:find("dynamic import"), "not refused: " .. found)
end)
-- }}}

-- {{{ referee 3: no text is read as markup or as code
check("3: no innerHTML, document.write, eval, new Function, string timers or inline handlers", function()
    local problems = CHECKS.no_markup_from_text(WEB)
    must(#problems == 0, joined(problems))
end)
check("3 broken: markup from text and an inline handler are refused", function()
    local copy = copy_with("207-page.js", function(text) return text .. "\nline.innerHTML = message;\n" end)
    must(joined(CHECKS.no_markup_from_text(copy)):find("innerHTML"), "innerHTML not refused")
    copy = copy_with(PAGE, function(text) return (text:gsub('<button type="button" id="retry%-now"', '<button type="button" onclick="go()" id="retry-now"')) end)
    must(joined(CHECKS.no_markup_from_text(copy)):find("inline on"), "onclick not refused")
end)
-- }}}

-- {{{ referee 4: one palette
check("4: colours are written only in the palette", function()
    local problems = CHECKS.one_palette(WEB)
    must(#problems == 0, joined(problems))
    local palette = read_file(WEB .. "/204-palette.css")
    for _, line in ipairs({ "--background: #000000;", "--text: #FFD040;", "--text-dim: #B89020;", "--accent: #00E5FF;" }) do
        must(palette:find(line, 1, true), "the palette is not rmail's (section 8): no '" .. line .. "'")
    end
end)
check("4 broken: a colour written in the layout, or set from a script, is refused", function()
    local copy = copy_with("205-layout.css", function(text) return text .. "\n.x { color: #FF0000; border-color: red; }\n" end)
    local found = joined(CHECKS.one_palette(copy))
    must(found:find("#FF0000") and found:find("names the colour red"), "not refused: " .. found)
    copy = copy_with("207-page.js", function(text) return text .. "\nline.style.color = other;\n" end)
    must(joined(CHECKS.one_palette(copy)):find("sets a style"), "a script's style not refused")
end)
-- }}}

-- {{{ referee 5: the stand-in loads the page's scripts
local has_node = os.execute("command -v node > /dev/null 2>&1") == 0
check("5: the stand-in loads the page's scripts in its order, adding only rao", function()
    must(has_node, "STOPPED: node is not installed, so the page's scripts cannot be run outside a browser here")
    local status, out = run("node " .. q(STAND_IN) .. " " .. q(DIR) .. " load")
    must(status == 0, "load failed: " .. out)
    local order = {}
    for name in out:gmatch("script (%S+)") do order[#order + 1] = name end
    local wanted = {}
    for _, name in ipairs(named_by(read_file(WEB .. "/" .. PAGE))) do
        if name:match("%.js$") then wanted[#wanted + 1] = name end
    end
    must(table.concat(order, " ") == table.concat(wanted, " "), "loaded " .. table.concat(order, " "))
    must(out:find("\nglobals rao\n"), "the scripts made other globals: " .. (out:match("globals[^\n]*") or "?"))
    local parts = " " .. (out:match("\nrao ([^\n]*)") or "") .. " "
    must(parts:find(" bytes ") and parts:find(" page "), "rao lacks a part: " .. parts)
    must(out:find("\ncrypto ok"), "WebCrypto not found")
end)
check("5b: without WebCrypto the page says why, rather than failing later", function()
    must(has_node, "STOPPED: node is not installed")
    local status, out = run("node " .. q(STAND_IN) .. " " .. q(DIR) .. " load --no-subtle")
    must(status == 0, "load failed: " .. out)
    must(out:find("crypto missing: [^\n]*open the page from a copy of its folder"), "no words: " .. out)
end)
check("5c: a script that touches the page as it loads is caught by the stand-in", function()
    must(has_node, "STOPPED: node is not installed")
    local copy = copy_with("206-rao.js", function(text) return text .. "\ndocument.title = 'x';\n" end)
    -- the stand-in reads <project>/src/web, so give the copy that shape
    os.execute("mkdir -p " .. q(ROOT .. "/project/src") .. " && rm -rf " .. q(ROOT .. "/project/src/web")
        .. " && cp -r " .. q(copy) .. " " .. q(ROOT .. "/project/src/web"))
    local status, out = run("node " .. q(STAND_IN) .. " " .. q(ROOT .. "/project") .. " load")
    must(status ~= 0 and out:find("document"), "not caught: " .. out)
end)
-- }}}

if ROOT:match("/rao%-chat%-pages%-folder%-test%-%d+$") then os.execute("rm -rf " .. q(ROOT)) end
print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
