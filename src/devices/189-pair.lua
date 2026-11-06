-- 189-pair.lua — pairing a device with the home, on the home machine
-- (issue 303).
--
--   luajit src/devices/189-pair.lua <project> <disk home> add <label> [--browser]
--   luajit src/devices/189-pair.lua <project> <disk home> list
--   luajit src/devices/189-pair.lua <project> <disk home> remove <label>
--
-- `add` makes a readable token of six words (007's list; 303 decision 1),
-- adds `<label>.token` and `<label>.own = true` to the home's `devices`
-- file (rmail's contacts format, 302), and prints what the device needs,
-- as lines its `config` takes (190):
--
--   port = <devices.port>
--   home-network = <devices.address, or "unknown" when it is "any">
--   public = <the public address 212 last confirmed, or "unknown">
--   token = <the token>
--
-- With `--browser` (issue 403), for the web client, it also prints the
-- lines a page needs beside those: stated values the person can change,
-- never defaults hidden in the page (403 decision 3: a phone's lines stay
-- as they were, so 190 does not start speaking WebSocket):
--
--   websocket-path = <devices.websocket-path>   the upgrade's path (309)
--   wait = 10                                   seconds to open, and to answer
--   quick-wait = 1                              seconds for the home-network address
--   keep-alive = <half of devices.idle-limit, whole seconds, at least 1>
--
-- `list` prints the labels, never a token.  `remove` takes the device's
-- lines out.  The file is written whole: under a temporary name made
-- private before a byte is written (umask 077), then renamed, so the
-- server (which reads it at each connection's first frame) never sees
-- half of it and nobody else can read it at any moment.  The owner's own
-- comments and other lines are kept.  A label is rmail's contact word
-- (letters, digits, "_" and "-"), at most 40 characters.

local DIR = arg and arg[1]
if not DIR or DIR == "" then
    io.stderr:write("usage: luajit 189-pair.lua <project> <disk home> add <label> [--browser] | list | remove <label>\n")
    os.exit(2)
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local disk = require("003-disk")
local tokens = require("007-tokens")
local ram = require("161-ram-folders")
local server = require("187-device-server")

local M = {}

-- For referees only (191): RAO_PAIR_BROKEN=trailing-space (the token is
-- written with a space after it, so the device's token is not the
-- home's), open-temporary (the temporary file is made with the default
-- umask, readable by others while it is written).
M.broken = os.getenv("RAO_PAIR_BROKEN") or ""

M.WORDS = 6

-- {{{ local function lua_pattern
local function lua_pattern(text) return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end
-- }}}

-- {{{ function M.write_private
-- path, text: written whole under a temporary name that only its owner
-- can read from the moment it exists, then renamed over path.
function M.write_private(path, text)
    local temporary = path .. ".pairing-" .. ram.new_name(os.time())
    local umask = M.broken == "open-temporary" and "" or "umask 077 && "
    if os.execute(umask .. ": > " .. disk.shell_quote(temporary)) ~= 0 then
        error("cannot make " .. temporary, 0)
    end
    local handle = assert(io.open(temporary, "wb"))
    handle:write(text)
    handle:close()
    os.execute("chmod 600 " .. disk.shell_quote(temporary))
    assert(os.rename(temporary, path))
end
-- }}}

-- {{{ function M.add
-- home folder, label → the token, or nil and why.
function M.add(home_dir, label)
    if type(label) ~= "string" or not label:match("^[%w_%-]+$") or #label > 40 then
        return nil, "a label is letters, digits, _ and -, at most 40 characters"
    end
    local list, text = server.read_devices(home_dir)
    if not list then return nil, text end
    for _, device in ipairs(list) do
        if device.label == label then return nil, label .. " is already paired" end
    end
    local token = tokens.suggest_token_of(M.WORDS)
    local written = token .. (M.broken == "trailing-space" and " " or "")
    if text ~= "" and not text:match("\n$") then text = text .. "\n" end
    M.write_private(server.devices_path(home_dir),
        text .. label .. '.token = "' .. written .. '"\n' .. label .. ".own = true\n")
    return token
end
-- }}}

-- {{{ function M.remove
-- home folder, label → true, or nil and why.
function M.remove(home_dir, label)
    local list, text = server.read_devices(home_dir)
    if not list then return nil, text end
    local found = false
    for _, device in ipairs(list) do if device.label == label then found = true end end
    if not found then return nil, tostring(label) .. " is not paired" end
    local kept = {}
    local mine = "^%s*" .. lua_pattern(label) .. "%.[%w_%-%[%]]+%s*="
    for line in (text .. (text:match("\n$") and "" or "\n")):gmatch("([^\n]*)\n") do
        if not line:match(mine) then kept[#kept + 1] = line end
    end
    M.write_private(server.devices_path(home_dir), #kept > 0 and (table.concat(kept, "\n") .. "\n") or "")
    return true
end
-- }}}

-- {{{ function M.settings_text
-- home folder, token, browser (true for --browser) → the lines a
-- device's config takes.
M.BROWSER_WAIT, M.BROWSER_QUICK_WAIT = 10, 1
function M.settings_text(home_dir, token, browser)
    local rooms = require("002-room-folders")
    local home = rooms.open_home(home_dir)
    local address = rooms.config_value(home, "devices.address")
    local root = ram.choose_root(rooms.config_value(home, "gatherer.ram-root"))
    local public = ram.read_state(ram.home_ram(root, home_dir))["public-address"]
    return "port = " .. rooms.config_value(home, "devices.port") .. "\n"
        .. "home-network = " .. (address == "any" and "unknown" or address) .. "\n"
        .. "public = " .. ((public and public ~= "") and public or "unknown") .. "\n"
        .. "token = " .. token .. "\n"
        .. (browser and M.browser_text(home) or "")
end
-- }}}

-- {{{ function M.browser_text
-- the home (002's) → the lines a page needs beside a device's (403).
function M.browser_text(home)
    local rooms = require("002-room-folders")
    local idle = tonumber(rooms.config_value(home, "devices.idle-limit")) or 2
    return "websocket-path = " .. rooms.config_value(home, "devices.websocket-path") .. "\n"
        .. "wait = " .. M.BROWSER_WAIT .. "\n"
        .. "quick-wait = " .. M.BROWSER_QUICK_WAIT .. "\n"
        .. "keep-alive = " .. math.max(1, math.floor(idle / 2)) .. "\n"
end
-- }}}

-- {{{ local function main
local function main(args)
    local home_dir, command, label, browser = args[2], args[3], args[4], args[5]
    if not home_dir or not command then
        io.stderr:write("usage: luajit 189-pair.lua <project> <disk home> add <label> [--browser] | list | remove <label>\n")
        return 2
    end
    if command == "add" and label and (browser == nil or browser == "--browser") then
        local ok, token, why = pcall(M.add, home_dir, label)
        if not ok then token, why = nil, token end
        if not token then
            io.stderr:write("pair: " .. tostring(why) .. "\n")
            return 1
        end
        io.write("paired " .. label .. "; give the " .. (browser and "page" or "device") .. " these lines:\n",
            M.settings_text(home_dir, token, browser ~= nil))
    elseif command == "remove" and label then
        local done, why = M.remove(home_dir, label)
        if not done then io.stderr:write("pair: " .. why .. "\n") return 1 end
        io.write("unpaired " .. label .. "\n")
    elseif command == "list" then
        local list, why = server.read_devices(home_dir)
        if not list then io.stderr:write("pair: " .. why .. "\n") return 1 end
        for _, device in ipairs(list) do io.write(device.label, "\n") end
    else
        io.stderr:write("usage: luajit 189-pair.lua <project> <disk home> add <label> [--browser] | list | remove <label>\n")
        return 2
    end
    return 0
end
-- }}}

if arg and arg[0] and arg[0]:match("189%-pair%.lua$") then os.exit(main(arg)) end
return M
