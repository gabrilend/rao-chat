-- 236-service-files.lua — the service files of a home (issue 604): the
-- service's name from the home's path, the templates filled with every
-- value quoted the way each service manager's own syntax reads it, and
-- the check that an installed service file serves a given home.
--
--   luajit src/install/236-service-files.lua <project> name <home>
--       prints rao-chat-<the home's path, slashes as dashes>
--   luajit src/install/236-service-files.lua <project> fill <template> <out> key=value ...
--       keys: service, user, log_dir, home, project; writes <out>
--   luajit src/install/236-service-files.lua <project> check <template> key=value ...
--       as fill, writing nothing: exit 0 when it would fill
--   luajit src/install/236-service-files.lua <project> names-home <file> <home>
--       exit 0 when <file> says it serves <home>, 1 when it does not
--
-- A template holds @NAME@ placeholders (the table `forms` below).  Each
-- value is checked before anything is written, and the filled text is
-- searched for a placeholder left over: either way nothing is written (and
-- an <out> left from before is removed), exit 1, and the reason is said.
-- Exit 2 for a mistaken argument.

local M = {}

-- {{{ the checks
-- A path may hold any character but a control character (a newline would
-- end the comment line that names the home).  The names the service files
-- carry bare are held to plain characters.
local function plain_path(text) return type(text) == "string" and text:sub(1, 1) == "/" and not text:find("%c") end
local function service_name(text) return type(text) == "string" and #text <= 200 and text:match("^[A-Za-z0-9_-]+$") ~= nil end
local function user_name(text)
    return type(text) == "string" and #text <= 64 and text:match("^[A-Za-z_][A-Za-z0-9_.-]*%$?$") ~= nil
end
local function log_folder(text) return type(text) == "string" and text:match("^/[A-Za-z0-9._/-]*$") ~= nil end
-- what OpenRC can carry: it reads command and command_args through eval,
-- where a space splits one path into two words
local function openrc_word(text) return text:match("^/[A-Za-z0-9._/+-]*$") ~= nil end
-- }}}

-- {{{ the quotings
-- sh: one single-quoted word
local function sh_word(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
-- systemd: one double-quoted word of ExecStart= (C escapes, % specifiers,
-- $ variables)
local function systemd_word(text)
    return '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%%", "%%%%"):gsub("%$", "$$") .. '"'
end
-- nix: the inside of a "..." string
local function nix_inside(text) return (text:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("%${", "\\${")) end
-- }}}

-- {{{ function M.name(home) → the service name for a home
-- rmail's slug (slashes to dashes, the leading one dropped) after
-- rao-chat-; any other character a service name cannot hold becomes _.
function M.name(home)
    local slug = home:gsub("/+$", ""):gsub("^/+", ""):gsub("/", "-"):gsub("[^A-Za-z0-9_-]", "_")
    if slug == "" then slug = "root" end
    return "rao-chat-" .. slug
end
-- }}}

-- {{{ local function forms(values) → placeholder → text, or nil, why
-- Forms whose value a syntax cannot carry are absent, with the reason in
-- `cannot`: a template asking for one is refused with that reason.
local function forms(values)
    for _, key in ipairs({ "service", "user", "log_dir", "home", "project" }) do
        if values[key] == nil then return nil, "no value for " .. key end
    end
    if not service_name(values.service) then
        return nil, "a service name is letters, digits, '-' and '_', not '" .. values.service .. "'"
    end
    if not user_name(values.user) then return nil, "not a user name: '" .. values.user .. "'" end
    if not log_folder(values.log_dir) then
        return nil, "the log folder must be an absolute path of letters, digits, '.', '_', '-' and '/', not '"
            .. values.log_dir .. "'"
    end
    for _, key in ipairs({ "home", "project" }) do
        if not plain_path(values[key]) then
            return nil, "the " .. key .. " must be an absolute path with no control characters"
        end
    end
    local run_home = values.project .. "/scripts/run-home"
    local log = values.log_dir:gsub("/+$", "") .. "/" .. values.service .. ".log"
    local exec = systemd_word(run_home) .. " " .. systemd_word(values.project) .. " " .. systemd_word(values.home)
    local filled = {
        SERVICE = values.service,
        USER = values.user,
        LOG = log,
        HOME_COMMENT = values.home,
        EXEC_SYSTEMD = exec,
        EXEC_NIX = nix_inside(exec),
        LOG_NIX = nix_inside(log),
        RUN_HOME_SH = sh_word(run_home),
        PROJECT_SH = sh_word(values.project),
        HOME_SH = sh_word(values.home),
        LOG_SH = sh_word(log),
    }
    local cannot = {}
    if openrc_word(run_home) and openrc_word(values.project) and openrc_word(values.home) then
        filled.OPENRC_COMMAND = run_home
        filled.OPENRC_ARGS = values.project .. " " .. values.home
    else
        local why = "OpenRC reads command and command_args through eval, so the program folder and the home"
            .. " must be paths of letters, digits, '.', '_', '+', '-' and '/' (" .. values.project .. ", "
            .. values.home .. ")"
        cannot.OPENRC_COMMAND, cannot.OPENRC_ARGS = why, why
    end
    return filled, cannot
end
-- }}}

-- {{{ function M.fill(template_text, values) → text, or nil, why
function M.fill(template_text, values)
    local filled, cannot = forms(values)
    if not filled then return nil, cannot end
    local unknown
    local text = template_text:gsub("@([A-Z_]+)@", function(name)
        if filled[name] then return filled[name] end
        unknown = unknown or name
        return nil
    end)
    if unknown then
        return nil, cannot[unknown] or ("the template asks for @" .. unknown .. "@, which is not a known value")
    end
    local left = text:match("@[A-Z_]+@")
    if left then return nil, "a placeholder is left after filling: " .. left end
    return text
end
-- }}}

-- {{{ function M.names_home(text, home) → whether a service file serves home
function M.names_home(text, home)
    for line in text:gmatch("[^\n]+") do
        if line == "# rao-chat home: " .. home then return true end
    end
    return false
end
-- }}}

-- {{{ the command line
local function main(argv)
    local command = argv[2]
    local function read_all(path)
        local f = io.open(path, "rb")
        if not f then return nil end
        local text = f:read("*a")
        f:close()
        return text
    end
    if command == "name" and argv[3] then
        if not plain_path(argv[3]) then
            io.stderr:write("the home must be an absolute path with no control characters\n")
            return 2
        end
        print(M.name(argv[3]))
        return 0
    elseif command == "names-home" and argv[3] and argv[4] then
        local text = read_all(argv[3])
        return (text and M.names_home(text, argv[4])) and 0 or 1
    elseif (command == "fill" and argv[3] and argv[4]) or (command == "check" and argv[3]) then
        local template, out = argv[3], command == "fill" and argv[4] or nil
        local values = {}
        for i = out and 5 or 4, #argv do
            local key, value = argv[i]:match("^([a-z_]+)=(.*)$")
            if not key then
                io.stderr:write("not key=value: " .. argv[i] .. "\n")
                return 2
            end
            values[key] = value
        end
        local template_text = read_all(template)
        local text, why
        if template_text then
            text, why = M.fill(template_text, values)
        else
            why = "no template at " .. template
        end
        if not text then
            if out then os.remove(out) end
            io.stderr:write(why .. "; nothing was written\n")
            return 1
        end
        if not out then return 0 end
        local f = io.open(out .. ".new", "wb")
        if not f or not f:write(text) or not f:close() then
            os.remove(out .. ".new")
            os.remove(out)
            io.stderr:write("could not write " .. out .. "\n")
            return 1
        end
        assert(os.rename(out .. ".new", out))
        return 0
    end
    io.stderr:write("usage: 236-service-files.lua <project> name <home>\n"
        .. "       236-service-files.lua <project> fill <template> <out> key=value ...\n"
        .. "       236-service-files.lua <project> check <template> key=value ...\n"
        .. "       236-service-files.lua <project> names-home <file> <home>\n")
    return 2
end
-- }}}

if arg and arg[0] and arg[0]:match("236%-service%-files%.lua$") then
    os.exit(main(arg))
end
return M
