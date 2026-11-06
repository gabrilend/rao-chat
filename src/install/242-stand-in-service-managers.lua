-- 242-stand-in-service-managers.lua — stand-ins for the commands of the
-- machine's service managers (issue 604), for the referees and the phase 6
-- demo (606): no real service is installed and nothing is raised.
--
--   luajit src/install/242-stand-in-service-managers.lua make <state>
--       makes <state>/bin (the commands below, as small sh scripts) and
--       <state>/root (the system root the stand-in systemctl reads system
--       units under); prints the bin folder, to go first on a PATH
--
-- Every call but whoami's is written to <state>/calls, one line: the
-- command's name and its arguments, separated by single spaces.
--
-- systemctl [--user] <verb> [unit]
--   daemon-reload, enable, disable   written down, nothing else
--   start <unit>      reads the unit (--user: $HOME/.config/systemd/user/,
--                     else <state>/root/etc/systemd/system/), and runs its
--                     ExecStart (systemd's quoting read back) as systemd
--                     would: a bare environment (PATH as systemd's, HOME,
--                     its Environment= lines), stdin from /dev/null, output
--                     appended to its StandardOutput=append: file.  The
--                     process's pid goes to <state>/<unit>.pid and its exit
--                     status, when it ends, to <state>/<unit>.status.
--   stop <unit>       KillMode=mixed: SIGTERM to that process alone, then
--                     SIGKILL after TimeoutStopSec; prints its exit status
--   restart <unit>    stop, then start
--   is-active <unit>  "active" (exit 0) or "inactive" (exit 3)
-- sv restart|start|stop|status <name>, rc-service <name> restart|start|stop|status
--                   a service's run state kept in <state>/<command>-<name>
--                   (nothing is run); status says it in the manager's
--                   words (sv: "run: ..." or "down: ..."; rc-service:
--                   exit 0 started, 3 stopped)
-- rc-update, loginctl, nixos-rebuild   written down
-- sudo              written down, then runs its command as this user (so
--                   a referee sees whether sudo was used, and for what)
-- whoami            prints <state>/user when that file exists (a referee
--                   that is root playing someone who is not), else the
--                   real name
--
-- Only the referees' scratch HOME and <state> are read or written.
-- Required as a module it gives unit_words (systemd's reading of an
-- ExecStart= value) and make.

local SCRIPT = debug.getinfo(1, "S").source:gsub("^@", "")

local function quote(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end

-- {{{ small tools
local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
local function write_file(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end
local function sleep(seconds) os.execute("sleep " .. seconds) end
local function alive(pid)
    local stat = pid and read_all("/proc/" .. pid .. "/stat")
    return stat ~= nil and stat:match("%) (%a)") ~= "Z"
end
-- }}}

-- {{{ local function unit_words(text) → the words of an ExecStart= value
-- systemd's own reading: words split on blanks; a double-quoted word keeps
-- its blanks and takes C escapes (\\, \"); %% is %, $$ is $.
local function unit_words(text)
    local words, i, n = {}, 1, #text
    while i <= n do
        local c = text:sub(i, i)
        if c:match("%s") then
            i = i + 1
        else
            local word = {}
            local quoted = c == '"'
            if quoted then i = i + 1 end
            while i <= n do
                c = text:sub(i, i)
                if quoted and c == '"' then i = i + 1 break end
                if not quoted and c:match("%s") then break end
                if c == "\\" then
                    i = i + 1
                    c = text:sub(i, i)
                elseif (c == "%" or c == "$") and text:sub(i + 1, i + 1) == c then
                    i = i + 1
                end
                word[#word + 1] = c
                i = i + 1
            end
            words[#words + 1] = table.concat(word)
        end
    end
    return words
end
-- }}}

-- {{{ local function read_unit(path) → the [Service] settings
local function read_unit(path)
    local text = read_all(path)
    if not text then return nil end
    local unit = { environment = {} }
    for line in text:gmatch("[^\n]+") do
        local key, value = line:match("^(%w+)=(.*)$")
        if key == "Environment" then
            unit.environment[#unit.environment + 1] = value
        elseif key then
            unit[key] = value
        end
    end
    return unit
end
-- }}}

-- {{{ local function systemctl(state, args) → exit status
local function systemctl(state, args)
    local user = false
    local rest = {}
    for _, a in ipairs(args) do
        if a == "--user" then user = true elseif a:sub(1, 2) ~= "--" then rest[#rest + 1] = a end
    end
    local verb, name = rest[1], rest[2]
    if verb == "daemon-reload" or verb == "enable" or verb == "disable" then return 0 end
    if not name then
        io.stderr:write("stand-in systemctl: " .. tostring(verb) .. " needs a unit\n")
        return 1
    end
    name = name:gsub("%.service$", "")
    local pid_file, status_file = state .. "/" .. name .. ".pid", state .. "/" .. name .. ".status"
    local function running_pid()
        local pid = tonumber(read_all(pid_file) or "")
        if pid and alive(pid) then return pid end
        return nil
    end
    local unit_path = user and (os.getenv("HOME") .. "/.config/systemd/user/" .. name .. ".service")
        or (state .. "/root/etc/systemd/system/" .. name .. ".service")

    local function stop()
        local pid = running_pid()
        if not pid then return 0 end
        local unit = read_unit(unit_path) or {}
        local wait = tonumber(unit.TimeoutStopSec or "") or 90
        os.execute("kill -TERM " .. pid)
        local tries = wait * 5
        while alive(pid) and tries > 0 do
            sleep(0.2)
            tries = tries - 1
        end
        if alive(pid) then
            io.stdout:write("stand-in systemctl: still running after " .. wait .. "s; SIGKILL\n")
            os.execute("kill -KILL " .. pid)
        end
        for _ = 1, 25 do
            if read_all(status_file) then break end
            sleep(0.2)
        end
        io.stdout:write("stand-in systemctl: " .. name .. " ended with status "
            .. ((read_all(status_file) or "?"):match("%S+") or "?") .. "\n")
        return 0
    end

    local function start()
        if running_pid() then return 0 end
        local unit = read_unit(unit_path)
        if not unit or not unit.ExecStart then
            io.stderr:write("stand-in systemctl: no unit at " .. unit_path .. "\n")
            return 5
        end
        local words = unit_words(unit.ExecStart)
        local command = { "env", "-i", "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
            "HOME=" .. (os.getenv("HOME") or "/") }
        for _, setting in ipairs(unit.environment) do
            for _, word in ipairs(unit_words(setting)) do command[#command + 1] = word end
        end
        for _, word in ipairs(words) do command[#command + 1] = word end
        for i, word in ipairs(command) do command[i] = quote(word) end
        local log = (unit.StandardOutput or ""):match("^append:(.+)$") or "/dev/null"
        os.remove(pid_file)
        os.remove(status_file)
        os.execute("( " .. table.concat(command, " ") .. " >>" .. quote(log) .. " 2>&1 </dev/null & echo $! >"
            .. quote(pid_file) .. "; wait $!; echo $? >" .. quote(status_file) .. " ) >/dev/null 2>&1 </dev/null &")
        for _ = 1, 25 do
            if (read_all(pid_file) or ""):match("%d+\n") then return 0 end
            sleep(0.2)
        end
        io.stderr:write("stand-in systemctl: " .. name .. " did not start\n")
        return 1
    end

    if verb == "start" then return start()
    elseif verb == "stop" then return stop()
    elseif verb == "restart" then
        stop()
        return start()
    elseif verb == "is-active" then
        if running_pid() then print("active") return 0 end
        print("inactive")
        return 3
    end
    io.stderr:write("stand-in systemctl: verb not stood in for: " .. tostring(verb) .. "\n")
    return 1
end
-- }}}

local COMMANDS = { "systemctl", "sv", "rc-service", "rc-update", "loginctl", "nixos-rebuild", "sudo", "whoami" }

-- {{{ local function make(state) → the bin folder
local function make(state)
    local luajit = io.popen("command -v luajit"):read("*l")
    assert(luajit and luajit ~= "", "no luajit on this PATH")
    assert(os.execute("mkdir -p " .. quote(state .. "/bin") .. " " .. quote(state .. "/root")) == 0)
    for _, name in ipairs(COMMANDS) do
        local path = state .. "/bin/" .. name
        write_file(path, "#!/bin/sh\n# a stand-in for " .. name .. " (issue 604): see "
            .. "src/install/242-stand-in-service-managers.lua\nexec " .. quote(luajit) .. " " .. quote(SCRIPT)
            .. " run " .. quote(state) .. " " .. name .. ' "$@"\n')
        os.execute("chmod +x " .. quote(path))
    end
    return state .. "/bin"
end
-- }}}

-- {{{ local function run(state, name, args) → exit status
local function run(state, name, args)
    if name ~= "whoami" then
        local f = assert(io.open(state .. "/calls", "ab"))
        f:write(name .. (#args > 0 and (" " .. table.concat(args, " ")) or "") .. "\n")
        f:close()
    end
    if name == "systemctl" then return systemctl(state, args) end
    if name == "sudo" then
        if #args == 0 then return 1 end
        local words = {}
        for i, a in ipairs(args) do words[i] = quote(a) end
        local ok = os.execute(table.concat(words, " "))
        return (ok == 0 or ok == true) and 0 or 1
    end
    if name == "whoami" then
        local user = read_all(state .. "/user")
        if user then io.stdout:write((user:match("%S+") or "") .. "\n") return 0 end
        return os.execute("PATH=/usr/bin:/bin whoami") == 0 and 0 or 1
    end
    -- sv <verb> <name>, rc-service <name> <verb>: a kept run state
    local verb, service
    if name == "sv" then verb, service = args[1], args[2] elseif name == "rc-service" then service, verb = args[1], args[2] end
    if verb and service then
        local file = state .. "/" .. name .. "-" .. service
        if verb == "restart" or verb == "start" then write_file(file, "run\n") return 0 end
        if verb == "stop" then os.remove(file) return 0 end
        if verb == "status" then
            local running = read_all(file) ~= nil
            if name == "sv" then
                print((running and "run: " or "down: ") .. service .. ": (stand-in)")
                return running and 0 or 3
            end
            print(" * status: " .. (running and "started" or "stopped"))
            return running and 0 or 3
        end
    end
    return 0
end
-- }}}

if arg and arg[0] and arg[0]:match("242%-stand%-in%-service%-managers%.lua$") then
    if arg[1] == "make" and arg[2] then
        print(make(arg[2]))
        os.exit(0)
    elseif arg[1] == "run" and arg[2] and arg[3] then
        local args = {}
        for i = 4, #arg do args[#args + 1] = arg[i] end
        os.exit(run(arg[2], arg[3], args))
    end
    io.stderr:write("usage: 242-stand-in-service-managers.lua make <state>\n")
    os.exit(2)
end
-- required (the referees): systemd's reading of an ExecStart= value
return { unit_words = unit_words, make = make }
