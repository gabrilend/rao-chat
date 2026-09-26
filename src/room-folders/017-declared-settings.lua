-- 017-declared-settings.lua — knows every setting name any module reads.
--
-- A home's `config` file is a list of "name = value" lines.  Round 4's
-- rule (the owner: "I think it should probably just give an error if it
-- doesn't recognize a value"): a line whose name no module reads is an
-- error naming the line — a retired setting left behind, a typo, or a
-- setting from a newer version of the program all stop the program,
-- instead of being quietly ignored while the person believes it works.
--
-- To know which names are real, every module declares the names it reads
-- in one small file of its own: `src/<module>/<3 digits>-settings.lua`,
-- returning a plain list of strings, for example
--
--     return { "tree.filing-loop" }
--
-- This file finds those lists by looking in every folder under src/ —
-- the same way 001-load-path finds module folders and the options tally
-- finds options files — so the answer does not depend on which modules a
-- program happened to load: a test that loads only room-folders, opening
-- a home the demo filled with every module's settings, sees the same
-- declarations the demo does.  (The other design, each module handing
-- its list over when it is loaded, was set aside for exactly that: a
-- name would be "unknown" whenever its module was not loaded.)
--
-- The lists are read once per running program and kept: they are part of
-- the program, not of the home, and do not change while it runs.
--
-- Nothing here touches a home; 002-room-folders calls check_config_lines
-- on every read of `config`, check_name before every write of a line and
-- every lookup of a value.

local disk = require("003-disk")

-- A declaration file's name: three digits (the module's own reading-order
-- index), then "-settings.lua".  Only one folder deep under src/ (never
-- inside tests/), so a sample list inside a test folder is never read.
local DECLARATION_FILE_PATTERN = "^%d%d%d%-settings%.lua$"

-- A setting name, as the config format allows one (004-rmail-formats):
-- letters, digits, "_", "-", ".".
local NAME_PATTERN = "^[%w_%.%-]+$"

-- {{{ local function this_src_dir
-- The src/ folder this file itself was loaded from: two levels above it
-- (src/room-folders/017-declared-settings.lua).  Lua records the path a
-- file was loaded by, starting with "@".  A path of any other shape (code
-- loaded from a string) cannot say where src/ is, and is refused rather
-- than guessed.
local function this_src_dir()
    local source = debug.getinfo(1, "S").source
    local path = source:match("^@(.*)/[^/]+/[^/]+$")
    -- no "@path": loaded some other way; the declarations cannot be found.
    if path == nil then
        error("017-declared-settings: cannot tell which src/ folder it was loaded from (source "
            .. tostring(source) .. ")", 2)
    end
    return path
end
-- }}}

-- {{{ local function read_declaration_file
-- One module's list: loads the file (plain data: it only returns a table)
-- and checks it is a plain list of setting names, each once.
local function read_declaration_file(path)
    local chunk, problem = loadfile(path)
    -- does not parse as Lua: name the file and the fault.
    if chunk == nil then
        error("setting declarations " .. path .. " do not load: " .. tostring(problem), 0)
    end
    local list = chunk()
    -- not a table: the module's list is missing.
    if type(list) ~= "table" then
        error("setting declarations " .. path .. " must return a list of setting names, got " .. type(list), 0)
    end
    local count = 0
    for key in pairs(list) do
        count = count + 1
        -- a key that is not 1..n: a table of settings with values, not a plain list.
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 then
            error("setting declarations " .. path .. " must be a plain list (found key " .. tostring(key) .. ")", 0)
        end
    end
    -- holes in the list (count > #list): ipairs would silently stop early.
    if count ~= #list then
        error("setting declarations " .. path .. " must be a plain list without gaps", 0)
    end
    local seen = {}
    for position, name in ipairs(list) do
        -- not a name the config format can hold: it could never match a line.
        if type(name) ~= "string" or not name:match(NAME_PATTERN) then
            error("setting declarations " .. path .. " item " .. position
                .. " is not a setting name (letters, digits, '_', '-', '.'): " .. tostring(name), 0)
        end
        -- listed twice in one file: a slip worth fixing where it is.
        if seen[name] then
            error("setting declarations " .. path .. " list '" .. name .. "' twice", 0)
        end
        seen[name] = true
    end
    return list
end
-- }}}

-- {{{ local function gather_declarations
-- Every declaration under src_dir → table name → { module = folder name,
-- file = path }.  A name declared by two modules is an error naming both:
-- each setting has one owner, who says what its values mean.  (Any module
-- may still read another's setting; declaring is owning.)  A folder with
-- two declaration files is an error: a module has one list.
local function gather_declarations(src_dir)
    local declared = {}
    for _, module in ipairs(disk.list_dir(src_dir)) do
        local folder = src_dir .. "/" .. module
        -- a folder (a module): look inside.  A plain file (src/README): skip.
        if disk.is_dir(folder) then
            local found = nil
            for _, name in ipairs(disk.list_dir(folder)) do
                -- a declaration file: read it (only one per module).
                if name:match(DECLARATION_FILE_PATTERN) then
                    if found ~= nil then
                        error("module " .. module .. " has two setting declaration files: " .. found
                            .. " and " .. name .. " (one list per module)", 0)
                    end
                    found = name
                    local path = folder .. "/" .. name
                    for _, setting in ipairs(read_declaration_file(path)) do
                        local earlier = declared[setting]
                        -- already owned by another module: two owners, one name.
                        if earlier ~= nil then
                            error("setting '" .. setting .. "' is declared by two modules: " .. earlier.file
                                .. " and " .. path .. " (each setting has one owner)", 0)
                        end
                        declared[setting] = { module = module, file = path }
                    end
                end
            end
        end
    end
    return declared
end
-- }}}

-- The declarations of this program, gathered on first use and kept.
local program_declarations = nil

-- {{{ local function declarations
-- This program's declarations (the src/ this file was loaded from).
local function declarations()
    -- first use: gather.  Afterwards: the same table.
    if program_declarations == nil then
        program_declarations = gather_declarations(this_src_dir())
    end
    return program_declarations
end
-- }}}

-- {{{ local function describe_unknown
-- The shared end of every "not declared" error: what it may be and how to
-- fix it, so the person reading it knows which of the three to do.
local function describe_unknown(name)
    return "'" .. name .. "' is not a setting any module reads (no src/<module>/<index>-settings.lua "
        .. "lists it): a retired setting, a typo, or a setting from a newer version"
end
-- }}}

-- {{{ local function check_config_lines
-- lines: list of { key, value, number } as 004's parse_config_lines gives
-- them; where: the file's path for the message.  The first line whose key
-- nobody declared stops everything, naming the file, the line number and
-- the line.  Checks against `declared` when given (tests), else this
-- program's declarations.
local function check_config_lines(lines, where, declared)
    declared = declared or declarations()
    for _, line in ipairs(lines) do
        -- not declared: the whole config is refused, pointing at the line.
        if declared[line.key] == nil then
            error(where .. " line " .. line.number .. ": " .. describe_unknown(line.key)
                .. " — remove or correct the line: " .. line.key .. " = " .. line.value, 0)
        end
    end
end
-- }}}

-- {{{ local function check_name
-- Before a value is written or looked up: a name nobody declares is refused.
-- For a write, it would put a line in config that the next read refuses;
-- for a lookup, a module is reading a name it forgot to declare.
local function check_name(name, doing)
    -- declared: fine.  Otherwise: the error says whose list it belongs in.
    if declarations()[name] == nil then
        error(doing .. ": " .. describe_unknown(name) .. " — the module that reads it must list it in its "
            .. "<index>-settings.lua", 3)
    end
end
-- }}}

-- {{{ local function declared_settings
-- A copy of this program's declarations: name → { module, file }.  For the
-- demo and tests (a copy, so nobody can add a name by writing into it).
local function declared_settings()
    local copy = {}
    for name, where in pairs(declarations()) do
        copy[name] = { module = where.module, file = where.file }
    end
    return copy
end
-- }}}

return {
    DECLARATION_FILE_PATTERN = DECLARATION_FILE_PATTERN,
    gather_declarations = gather_declarations,
    read_declaration_file = read_declaration_file,
    check_config_lines = check_config_lines,
    check_name = check_name,
    declared_settings = declared_settings,
    this_src_dir = this_src_dir,
}
