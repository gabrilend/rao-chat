-- 002-room-folders.lua (STAND-IN, tests only) — a small copy of the parts of
-- the room-folders module (issue 101) that the message log uses, so the log
-- can be tested alone.  It keeps the same file layout (rao-home/config,
-- rao-home/rooms/<local tag>/log) and the same function names as the
-- round-2 contract; it does not write an entry, check labels, tokens,
-- parents or members.  The message-log tests use it when asked to run
-- "stand-in", and the real module otherwise.

local rooms = {}

local listeners = {}

-- {{{ local function read_config_file
local function read_config_file(home)
    local config = {}
    local file = io.open(home.dir .. "/config", "rb")
    -- Path: a config file — parse "key = value" lines.  None — empty config.
    if file then
        for line in file:lines() do
            local key, value = line:match("^%s*([%w_%-%.]+)%s*=%s*(.-)%s*$")
            -- Path: a key line — keep it.  Anything else — skipped.
            if key then
                config[key] = value
            end
        end
        file:close()
    end
    return config
end
-- }}}

-- {{{ function rooms.open_home
function rooms.open_home(dir)
    os.execute('mkdir -p "' .. dir .. '/rooms"')
    return { dir = dir }
end
-- }}}

-- {{{ function rooms.read_config
function rooms.read_config(home)
    return read_config_file(home)
end
-- }}}

-- {{{ function rooms.set_config
function rooms.set_config(home, key, value)
    local config = read_config_file(home)
    config[key] = value
    local keys = {}
    for each in pairs(config) do
        keys[#keys + 1] = each
    end
    table.sort(keys)
    local file = assert(io.open(home.dir .. "/config", "wb"))
    for _, each in ipairs(keys) do
        file:write(each, " = ", config[each], "\n")
    end
    file:close()
end
-- }}}

-- {{{ function rooms.config_value
function rooms.config_value(home, key)
    local value = read_config_file(home)[key]
    -- Path: present — give it.  Absent — error, as the real module does.
    if value == nil then
        error("config key '" .. key .. "' is not set", 0)
    end
    return value
end
-- }}}

-- {{{ function rooms.new_local_tag
function rooms.new_local_tag()
    local source = assert(io.open("/dev/urandom", "rb"))
    local bytes = source:read(16)
    source:close()
    return (bytes:gsub(".", function(byte) return string.format("%02x", byte:byte()) end))
end
-- }}}

-- {{{ function rooms.room_dir
function rooms.room_dir(home, tag)
    return home.dir .. "/rooms/" .. tag
end
-- }}}

-- {{{ function rooms.log_path
function rooms.log_path(home, tag)
    return home.dir .. "/rooms/" .. tag .. "/log"
end
-- }}}

-- {{{ function rooms.make_room
-- spec is accepted and not checked; only the folder and an empty log are
-- made, which is all the log needs.
function rooms.make_room(home, spec)
    local tag = rooms.new_local_tag()
    os.execute('mkdir -p "' .. rooms.room_dir(home, tag) .. '"')
    assert(io.open(rooms.log_path(home, tag), "wb")):close()
    rooms.notify(home, tag, "created")
    return tag
end
-- }}}

-- {{{ function rooms.room_exists
function rooms.room_exists(home, tag)
    local file = io.open(rooms.log_path(home, tag), "rb")
    -- Path: log present — the room exists.  Absent — it does not.
    if file then
        file:close()
        return true
    end
    return false
end
-- }}}

-- {{{ function rooms.on_change
function rooms.on_change(listener)
    listeners[#listeners + 1] = listener
end
-- }}}

-- {{{ function rooms.notify
function rooms.notify(home, tag, what)
    for _, listener in ipairs(listeners) do
        listener(home, tag, what)
    end
end
-- }}}

return rooms
