-- 186-device-records.lua — the records inside a device frame (issue 302):
-- what a home and its paired phones and browsers say to each other.
--
-- The line shape is 126's (decision 3 of issue 302): the kind, then that
-- kind's fields in a fixed order, tab-separated, each escaped by the log's
-- rule ("\\" "\t" "\n" "\r" become \\ \t \n \r, nothing else touched), so
-- a record is always one line.  The table is this file's own: a device
-- frame and a room frame are different conversations, and a kind of one
-- can never be read as a kind of the other.  An unknown kind, a wrong
-- number of fields, an unknown escape, or a field that breaks its rule is
-- refused, never guessed at.
--
-- Kinds (each later issue adds its own here):
--   ping   id                  "are you there?"  (302)
--   pong   id, at              the ping's id, the home's clock  (302)

local KINDS = {
    ping = { "id" },
    pong = { "id", "at" },
}

-- Field rules: a field not named here may hold any text.
local RULES = {
    id = function(v) return #v >= 1 and #v <= 64 and v:match("^[%w%-]+$") ~= nil end,
    at = function(v) return v:match("^%d+$") ~= nil and #v <= 15 end,
}

local ESCAPE = { ["\\"] = "\\\\", ["\t"] = "\\t", ["\n"] = "\\n", ["\r"] = "\\r" }
local UNESCAPE = { ["\\"] = "\\", t = "\t", n = "\n", r = "\r" }

-- {{{ local function escape
local function escape(text) return (text:gsub("[\\\t\n\r]", ESCAPE)) end
-- }}}

-- {{{ local function unescape
-- text → the plain text, or nil for an unknown escape (or a lone "\").
local function unescape(text)
    local bad = false
    local plain = text:gsub("\\(.?)", function(letter)
        local character = UNESCAPE[letter]
        if not character then bad = true; return "" end
        return character
    end)
    if bad then return nil end
    return plain
end
-- }}}

-- {{{ local function split_tabs
local function split_tabs(line)
    local fields, start = {}, 1
    while true do
        local tab = line:find("\t", start, true)
        if not tab then fields[#fields + 1] = line:sub(start); return fields end
        fields[#fields + 1] = line:sub(start, tab - 1)
        start = tab + 1
    end
end
-- }}}

-- {{{ local function encode
-- {kind = ..., <fields>} → one line.  A missing field, an unknown kind or
-- a field breaking its rule is an error in the caller.
local function encode(record)
    local fields = KINDS[record.kind]
    if not fields then error("device record: unknown kind " .. tostring(record.kind), 2) end
    local parts = { record.kind }
    for _, name in ipairs(fields) do
        local value = record[name]
        if value == nil then error("device record: " .. record.kind .. " needs " .. name, 2) end
        value = type(value) == "number" and string.format("%d", value) or tostring(value)
        if RULES[name] and not RULES[name](value) then
            error("device record: " .. name .. " '" .. value:sub(1, 40) .. "' breaks its rule", 2)
        end
        parts[#parts + 1] = escape(value)
    end
    return table.concat(parts, "\t")
end
-- }}}

-- {{{ local function decode
-- one line → the record, or nil and why.
local function decode(line)
    if type(line) ~= "string" then return nil, "not a line" end
    local parts = split_tabs(line)
    local kind = parts[1]
    local fields = KINDS[kind]
    if not fields then return nil, "an unknown kind '" .. tostring(kind):sub(1, 20) .. "'" end
    if #parts ~= #fields + 1 then
        return nil, kind .. " has " .. (#parts - 1) .. " fields, not " .. #fields
    end
    local record = { kind = kind }
    for index, name in ipairs(fields) do
        local value = unescape(parts[index + 1])
        if value == nil then return nil, kind .. "'s " .. name .. " has an unknown escape" end
        if RULES[name] and not RULES[name](value) then return nil, kind .. "'s " .. name .. " breaks its rule" end
        record[name] = value
    end
    return record
end
-- }}}

return {
    encode = encode,
    decode = decode,
    escape = escape,
    unescape = unescape,
    KINDS = KINDS,
    RULES = RULES,
}
