-- 232-make-home.lua — makes a home, or brings one up to date, through the
-- home's own code (issue 602).  The installer (scripts/install-home) asks
-- the questions; this writes the answers.
--
--   luajit src/install/232-make-home.lua <project> <home> --show
--   luajit src/install/232-make-home.lua <project> <home> [key=value ...]
--
-- --show prints what an existing home already holds, for the installer's
-- suggestions: one "config <key> = <value>" line per setting and one
-- "mailbox <kind> <port> <tag>" line per mailbox; nothing for a home not
-- made yet.  It writes nothing.
--
-- Otherwise each argument is a setting some module declares
-- (devices.port=51234) or direct-port=<port>, and it:
--
--   1. checks everything first and writes nothing when something is wrong
--      (exit 1, saying what): an undeclared name, a port that is not a
--      whole number 1-65535, the device port equal to a mailbox's port, the
--      direct-message mailbox's port equal to another mailbox's, a missing
--      folder above the home (002's rule: a typo grows no new tree);
--   2. opens the home (002's open_home makes what is missing of it);
--   3. sets each given setting: "set" when it was absent (written under a
--      comment holding its question), "changed <key> <old> -> <new>" when
--      it held another value (002's set_config, in place, so the person's
--      comments and order stay), "kept" when it already held this one;
--   4. states every other declared setting that is not in the file yet,
--      with the first variant of its options file and a comment holding
--      the question and how many variants there are: "stated";
--   5. makes the direct-message mailbox on direct-port when there is none
--      ("made"), moves it when it is on another port ("moved"), or "kept".
--
-- One line per step goes to standard output; exit 0.  The config it
-- leaves has been read back by 002 and accepted.

local DIR, HOME_DIR = arg[1], arg[2]
if not (DIR and HOME_DIR) then
    io.stderr:write("usage: luajit 232-make-home.lua <project> <home> --show | [key=value ...]\n")
    os.exit(2)
end
DIR = DIR:gsub("/+$", "")
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local rooms = require("002-room-folders")
local disk = require("003-disk")

-- {{{ local function fail
local function fail(words)
    io.stderr:write("232-make-home: " .. words .. "\n")
    os.exit(1)
end
-- }}}

-- {{{ local function options_by_key
-- config key → { question, count, file, first } from every module's
-- options file, as scripts/tally-options and the demos read them.
local function options_by_key()
    local found = {}
    local listing = io.popen("ls " .. disk.shell_quote(DIR) .. "/src/*/[0-9][0-9][0-9]-options.lua")
    for path in listing:lines() do
        for _, choice in ipairs(dofile(path)) do
            if choice.config_key ~= "" then
                found[choice.config_key] = { question = choice.question, count = #choice.variants,
                    file = path:sub(#DIR + 2), first = choice.variants[1].name }
            end
        end
    end
    listing:close()
    return found
end
-- }}}

-- {{{ local function show
if arg[3] == "--show" then
    if arg[4] then fail("--show takes nothing after it") end
    HOME_DIR = HOME_DIR:gsub("/+$", "")
    if not disk.is_file(HOME_DIR .. "/config") then os.exit(0) end
    local home = rooms.open_home(HOME_DIR)
    local config = rooms.read_config(home)
    local keys = {}
    for key in pairs(config) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do print("config " .. key .. " = " .. config[key]) end
    for _, mailbox in ipairs(rooms.read_mailboxes(home)) do
        print(string.format("mailbox %s %d %s", mailbox.kind, mailbox.port, mailbox.tag))
    end
    os.exit(0)
end
-- }}}

-- {{{ the arguments, checked before anything is written
local declared = rooms.declared_settings()
local given, given_order, direct_port = {}, {}, nil
-- {{{ local function port_value
local function port_value(name, text)
    local n = tonumber(text)
    if not (text:match("^%d+$") and n >= 1 and n <= 65535) then
        fail(name .. " must be a whole number from 1 to 65535, got '" .. text .. "'")
    end
    return n
end
-- }}}
for position = 3, #arg do
    local key, value = arg[position]:match("^([^=]+)=(.*)$")
    if not key then fail("not key=value: " .. arg[position]) end
    if key == "direct-port" then
        direct_port = port_value("direct-port", value)
    elseif not declared[key] then
        fail("no module declares a setting called '" .. key .. "'")
    elseif value == "" or value:find("\n") or value:match("^%s") or value:match("%s$") then
        fail(key .. " needs a value of one line with no spaces at its edges, got '" .. value .. "'")
    else
        if key == "devices.port" then port_value(key, value) end
        if key == "git.home-name" then
            local ok, problem = pcall(require("172-git").check_name, value)
            if not ok then fail(tostring(problem)) end
        end
        if given[key] == nil then given_order[#given_order + 1] = key end
        given[key] = value
    end
end

HOME_DIR = HOME_DIR:gsub("/+$", "")
if HOME_DIR:sub(1, 1) ~= "/" then fail("the home must be an absolute path, got " .. HOME_DIR) end
local parent = HOME_DIR:match("^(.*)/[^/]+$")
if parent ~= "" and not disk.is_dir(parent) then
    fail("the folder above the home does not exist: " .. parent .. " (make it first; a mistyped path should"
        .. " not grow a new tree of folders)")
end
if disk.is_file(HOME_DIR) then fail(HOME_DIR .. " is a file, not a folder") end

-- the ports against the home's mailboxes, as they are now
do
    local existing_mailboxes = {}
    if disk.is_file(HOME_DIR .. "/mailboxes") then
        existing_mailboxes = rooms.read_mailboxes({ dir = HOME_DIR })
    end
    local device_port = given["devices.port"] and tonumber(given["devices.port"])
    if not device_port and disk.is_file(HOME_DIR .. "/config") then
        device_port = tonumber(rooms.read_config({ dir = HOME_DIR })["devices.port"] or "")
    end
    if device_port and direct_port and device_port == direct_port then
        fail("the device port and the direct-message mailbox's port are both " .. device_port
            .. ": each needs its own")
    end
    for _, mailbox in ipairs(existing_mailboxes) do
        if device_port and mailbox.port == device_port then
            fail("the device port " .. device_port .. " is the port of the " .. mailbox.kind .. " mailbox "
                .. mailbox.label .. ": each needs its own")
        end
        if direct_port and mailbox.kind ~= "direct" and mailbox.port == direct_port then
            fail("the direct-message port " .. direct_port .. " is the port of the mailbox " .. mailbox.label
                .. ": each needs its own")
        end
    end
end
-- }}}

local options = options_by_key()
local home = rooms.open_home(HOME_DIR)
local config_path = HOME_DIR .. "/config"

-- {{{ local function append_setting
-- A setting not in the file yet: a blank line, its comment lines, and the
-- setting, added at the end; read back by 002 before it counts.
local function append_setting(key, value, comment_lines)
    local before = disk.read_all(config_path)
    local block = (before:match("\n$") or before == "") and "" or "\n"
    block = block .. "\n"
    for _, line in ipairs(comment_lines) do block = block .. "# " .. line .. "\n" end
    block = block .. key .. " = " .. value .. "\n"
    disk.write_atomic(config_path, before .. block)
    local ok, problem = pcall(rooms.read_config, home)
    if not ok then
        disk.write_atomic(config_path, before)
        fail("the config would not read back after adding " .. key .. ": " .. tostring(problem))
    end
end
-- }}}

-- {{{ local function question_lines
local function question_lines(key, asked)
    local option = options[key]
    local lines = {}
    if option then
        lines[1] = option.question
        if asked then
            lines[2] = "(asked when this home was installed; " .. option.file .. " has its notes)"
        else
            lines[2] = "(the first of " .. option.count .. " variant" .. (option.count == 1 and "" or "s")
                .. " in " .. option.file .. "; scripts/tally-options shows every choice)"
        end
    else
        lines[1] = asked and "(asked when this home was installed)" or "(set when this home was installed)"
    end
    return lines
end
-- }}}

-- 3. the given settings
for _, key in ipairs(given_order) do
    local value = given[key]
    local now = rooms.read_config(home)[key]
    if now == nil then
        append_setting(key, value, question_lines(key, true))
        print("set      " .. key .. " = " .. value)
    elseif now ~= value then
        rooms.set_config(home, key, value)
        print("changed  " .. key .. " " .. now .. " -> " .. value)
    else
        print("kept     " .. key .. " = " .. value)
    end
end

-- 4. every other declared setting not in the file yet
do
    local keys = {}
    for key in pairs(declared) do keys[#keys + 1] = key end
    table.sort(keys)
    local config = rooms.read_config(home)
    for _, key in ipairs(keys) do
        if config[key] == nil then
            local option = options[key]
            if not option then
                fail("the setting " .. key .. " has no options file to state it from: give " .. key .. "=<value>")
            end
            append_setting(key, option.first, question_lines(key, false))
            print("stated   " .. key .. " = " .. option.first)
        end
    end
end

-- 5. the direct-message mailbox
if direct_port then
    local tag = rooms.direct_mailbox(home)
    if tag == "" then
        rooms.make_mailbox(home, { label = "direct messages", kind = "direct", port = direct_port })
        print("made     the direct-message mailbox on port " .. direct_port)
    else
        local mailbox = rooms.read_mailbox(home, tag)
        if mailbox.port ~= direct_port then
            rooms.write_mailbox_port(home, tag, direct_port)
            print("moved    the direct-message mailbox from port " .. mailbox.port .. " to " .. direct_port)
        else
            print("kept     the direct-message mailbox on port " .. direct_port)
        end
    end
end

-- read back whole, as every program of the home will
rooms.read_config(home)
os.exit(0)
