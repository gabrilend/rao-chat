-- 190-device.lua — the reference device: what a phone or a browser does,
-- written as a small Lua program the referees can drive (issue 303; the
-- Android app and the web page follow it, as they follow 183).
--
--   luajit src/devices/190-device.lua <device folder> test [--public]
--
-- The device's settings are `<device folder>/config`, "name = value"
-- lines, the lines 189's `add` prints plus the device's own:
--
--   port          the home's device port
--   home-network  the home's address on the home network, or "unknown"
--   public        the home's public address, or "unknown"
--   token         the device's own token, exactly as the home holds it
--   wait          whole or part seconds to wait for a connection, and
--                 again for an answer
--
-- `test` connects to the home-network address (`--public`: the public
-- one), sends a sealed `ping`, and says exactly what happened (rmail's
-- connection test, planning section 6):
--
--   answered in N ms by A P                     (exit 0)
--   nothing listens at A P (refused)            (exit 1, and below)
--   A cannot be reached: <why>                  no route, or no answer to
--                                               connect within the wait
--   A P closed the connection without a word:   the token is not one this
--     the token is not one this home knows      home knows
--   A P said nothing within W s: ...            not a device port, or a
--                                               home that is stuck
--   A P answered with something that is not a frame, or under another
--     key
--
-- The project folder is found from this file's own place (or
-- RAO_CHAT_DIR), as 183 does.

local DIR = os.getenv("RAO_CHAT_DIR")
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/devices/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local socket = require("socket")
local formats = require("004-rmail-formats")
local tokens = require("007-tokens")
local room_key = require("123-room-key")
local seal = require("124-seal")
local frames = require("125-frames")
local records = require("186-device-records")

local M = {}

-- For referees only (191): RAO_DEVICE_BROKEN=one-message (every failure
-- is told the same way).
M.broken = os.getenv("RAO_DEVICE_BROKEN") or ""

-- {{{ function M.read_config
-- device folder → the settings, or nil and why.
function M.read_config(folder)
    local handle = io.open(folder .. "/config", "rb")
    if not handle then return nil, folder .. "/config cannot be read" end
    local text = handle:read("*a")
    handle:close()
    local ok, values = pcall(formats.parse_config, text, folder .. "/config")
    if not ok then return nil, tostring(values) end
    local config = {}
    for _, name in ipairs({ "port", "home-network", "public", "token", "wait" }) do
        if values[name] == nil then return nil, folder .. "/config has no " .. name .. " line" end
        config[name] = values[name]
    end
    config.port = formats.parse_port(config.port)
    if not config.port then return nil, "port must be a whole number 1 to 65535" end
    config.wait = tonumber(config.wait)
    if not config.wait or config.wait <= 0 then return nil, "wait must be a number of seconds above 0" end
    local good, why = pcall(tokens.check_token, config.token)
    if not good then return nil, "token: " .. tostring(why) end
    return config
end
-- }}}

-- {{{ local function new_id
local function new_id()
    local source = assert(io.open("/dev/urandom", "rb"))
    local bytes = source:read(8)
    source:close()
    return (bytes:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end
-- }}}

-- {{{ function M.test
-- config, address → ok (boolean), the words that say what happened.
function M.test(config, address)
    local function told(ok, words)
        if not ok and M.broken == "one-message" then return false, "could not connect" end
        return ok, words
    end
    local where = address .. " " .. config.port
    if address == "unknown" then return told(false, "no address to try: the setting is \"unknown\"") end
    local started = socket.gettime()
    local sock = (address:find(":", 1, true) and socket.tcp6 or socket.tcp4)()
    sock:settimeout(config.wait)
    local connected, why = sock:connect(address, config.port)
    if not connected then
        sock:close()
        if why == "connection refused" then return told(false, "nothing listens at " .. where .. " (refused)") end
        if why == "timeout" then
            return told(false, address .. " cannot be reached: no answer to connect within " .. config.wait .. " s")
        end
        return told(false, address .. " cannot be reached: " .. tostring(why))
    end
    local pair = room_key.key_pair(config.token)
    local id = new_id()
    sock:settimeout(config.wait / frames.PATIENCE)
    local sent = frames.write_frame(sock, seal.seal(pair, records.encode({ kind = "ping", id = id })))
    local frame, lost
    if sent then frame, lost = frames.read_frame(sock) else lost = "closed" end
    sock:close()
    if not frame then
        if lost == "closed" then
            return told(false, where .. " closed the connection without a word: the token is not one this home knows")
        end
        if lost == "timeout" then
            return told(false, where .. " said nothing within " .. config.wait
                .. " s: this may not be a device port, or the home is stuck")
        end
        return told(false, where .. " answered with something that is not a frame (" .. tostring(lost) .. ")")
    end
    local line = seal.open(pair, frame)
    local reply = line and records.decode(line)
    if not reply or reply.kind ~= "pong" or reply.id ~= id then
        return told(false, where .. " answered under another key, or not this ping's pong")
    end
    return true, string.format("answered in %d ms by %s", math.floor((socket.gettime() - started) * 1000 + 0.5), where)
end
-- }}}

-- {{{ local function main
local function main(args)
    local folder, command = args[1], args[2]
    if not folder or command ~= "test" then
        io.stderr:write("usage: luajit 190-device.lua <device folder> test [--public]\n")
        return 2
    end
    local config, why = M.read_config(folder)
    if not config then io.stderr:write("device: " .. why .. "\n") return 1 end
    local ok, words = M.test(config, args[3] == "--public" and config.public or config["home-network"])
    io.write(words, "\n")
    return ok and 0 or 1
end
-- }}}

if arg and arg[0] and arg[0]:match("190%-device%.lua$") then os.exit(main(arg)) end
return M
