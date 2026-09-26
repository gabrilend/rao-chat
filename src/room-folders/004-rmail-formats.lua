-- 004-rmail-formats.lua — reads and writes rmail's two settings formats.
--
-- rao-chat keeps its settings and its address book in the same plain-text
-- shapes rmail uses, so a person's rmail contacts file can be copied into
-- rao-chat unchanged.  This file turns that text into tables and back.
-- It only ever handles text: it does not open files (room-folders does),
-- so everything here can be tested with strings alone.
--
-- The config format, one setting per line:
--     # a comment
--     name = ritz-home
--     tree.parent-disclosure = always
-- The contacts format, one fact about one person per line:
--     // a comment (or #)
--     sorelu.ip       = 203.0.113.9
--     sorelu.port     = 7777
--     sorelu.ip[2]    = sorelu.example.org
--     sorelu.port[2]  = 7777
--     sorelu.token    = "a shared secret"
--     phone.own       = true
--
-- Where rmail quietly skipped a line it could not understand, this reader
-- stops and names the line: a misspelt setting that is silently skipped
-- becomes a setting that is silently absent.
--
-- One rule differs from rmail on purpose (address_pairs): every address
-- is written with its own port.  rmail lets an address with no port of
-- its own borrow the contact's plain "port"; rao-chat refuses it.

-- {{{ local function trim
local function trim(text)
    return text:match("^%s*(.-)%s*$")
end
-- }}}

-- {{{ local function split_lines
-- Splits on "\n"; a final line without its newline is still a line.
local function split_lines(text)
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    -- the text ended with "\n": the split made one empty line past the
    -- end that is not really in the file; drop it.
    if lines[#lines] == "" then
        lines[#lines] = nil
    end
    return lines
end
-- }}}

-- A config key: letters, digits, "_", "-" and "." (the dot groups keys by
-- module, "tree.parent-disclosure").  rmail allowed any non-space run;
-- this is narrower so a key can always be written back unambiguously.
local CONFIG_KEY_PATTERN = "^[%w_%.%-]+$"

-- {{{ local function parse_config_lines
-- text → list of { key (string), value (string), number (the line number,
-- counted from 1) } in file order.  Values stay strings ("true" is not
-- turned into a boolean as rmail does), so every caller compares against
-- the same kind of thing.  An empty value ("key =") is the empty string.
-- A key set twice is an error: which one wins would otherwise depend on
-- the reader.  The line numbers let a later check (017-declared-settings:
-- a name no module reads) point at the exact line to fix.
local function parse_config_lines(text, where)
    local lines, seen = {}, {}
    for number, raw in ipairs(split_lines(text)) do
        local line = trim(raw)
        -- blank or "#" comment: carries no setting.  Otherwise it must be
        -- "key = value" and is recorded.
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^([^%s=]+)%s*=%s*(.-)$")
            -- no match: not a setting line.
            if not key then
                error(where .. " line " .. number .. ": not a 'key = value' line: " .. raw, 0)
            end
            -- key already seen: two answers to one question.
            if seen[key] then
                error(where .. " line " .. number .. ": '" .. key .. "' is set twice", 0)
            end
            seen[key] = true
            lines[#lines + 1] = { key = key, value = value, number = number }
        end
    end
    return lines
end
-- }}}

-- {{{ local function config_table
-- The list from parse_config_lines → table of key → value.
local function config_table(lines)
    local config = {}
    for _, line in ipairs(lines) do
        config[line.key] = line.value
    end
    return config
end
-- }}}

-- {{{ local function parse_config
-- text → table of key (string) → value (string); the same rules as
-- parse_config_lines, without the line numbers.
local function parse_config(text, where)
    return config_table(parse_config_lines(text, where))
end
-- }}}

-- {{{ local function check_config_pair
-- A key or value that would not read back the same is refused before it
-- is written.
local function check_config_pair(key, value)
    -- the key must be a plain word-with-dots.
    if type(key) ~= "string" or not key:match(CONFIG_KEY_PATTERN) then
        error("config key must be letters, digits, '_', '-', '.': " .. tostring(key), 3)
    end
    -- the value must be a string on one line, with no edge spaces (the
    -- reader trims them, so they would silently disappear).
    if type(value) ~= "string" then
        error("config value for " .. key .. " must be a string, got " .. type(value), 3)
    end
    if value:find("[\r\n]") then
        error("config value for " .. key .. " must be one line", 3)
    end
    if value ~= trim(value) then
        error("config value for " .. key .. " has leading or trailing spaces", 3)
    end
end
-- }}}

-- {{{ local function config_with
-- text, key, value → new text with that key set.  The line holding the key
-- is replaced where it stands, so comments and the order a person chose
-- are kept; a new key goes at the end.
local function config_with(text, key, value)
    check_config_pair(key, value)
    local lines = split_lines(text)
    local replaced = false
    for number, raw in ipairs(lines) do
        local line_key = trim(raw):match("^([^%s=#][^%s=]*)%s*=")
        -- this line sets the key: replace it in place.
        if line_key == key then
            lines[number] = key .. " = " .. value
            replaced = true
        end
    end
    -- the key was not in the file: add it as a new last line.
    if not replaced then
        lines[#lines + 1] = key .. " = " .. value
    end
    return table.concat(lines, "\n") .. "\n"
end
-- }}}

-- rmail contact names and field names: letters, digits, "_" and "-".
local CONTACT_WORD = "[%w_%-]+"

-- {{{ local function parse_contacts
-- text → table of contact name (string) → { field (string) → value
-- (string) }.  Indexed fields keep their index in the field name, so
-- "sorelu.ip[2] = x" becomes contacts.sorelu["ip[2]"] = "x".  A value in
-- double quotes loses its quotes (tokens are written quoted).  A line
-- holding only a name makes a contact with no fields.
--
-- rmail's older files list extra addresses as repeated plain "ip" lines;
-- rmail numbers those itself, so this does the same (the second becomes
-- "ip[1]" if free, and so on).  Any other field set twice is an error.
local function parse_contacts(text, where)
    -- a file starting "{" is rmail's pre-2025 JSON contacts; rmail
    -- converts it on its own start, rao-chat does not.
    if text:match("^%s*{") then
        error(where .. ": this is rmail's old JSON contacts format; start rmail once to convert it, then copy it again", 0)
    end
    local contacts = {}
    for number, raw in ipairs(split_lines(text)) do
        local line = trim(raw)
        -- blank or comment ("//" or "#"): nothing to record.
        if line ~= "" and not line:match("^[/#]") then
            local name, field, value = line:match("^(" .. CONTACT_WORD .. ")%.(" .. CONTACT_WORD .. "%[?%d*%]?)%s*=%s*(.-)$")
            local bare = line:match("^(" .. CONTACT_WORD .. ")$")
            -- a "name.field = value" line: record the field.
            if name then
                local unquoted = value:match('^"(.*)"$')
                -- quoted: store what is inside the quotes.
                if unquoted then
                    value = unquoted
                end
                contacts[name] = contacts[name] or {}
                local person = contacts[name]
                -- field already set: repeated plain "ip" is rmail's old
                -- way of listing more addresses and gets the next free
                -- index; anything else repeated is an error.
                if person[field] ~= nil then
                    if field ~= "ip" then
                        error(where .. " line " .. number .. ": " .. name .. "." .. field .. " is set twice", 0)
                    end
                    local index = 1
                    while person["ip[" .. index .. "]"] ~= nil do
                        index = index + 1
                    end
                    field = "ip[" .. index .. "]"
                end
                person[field] = value
            -- a bare name: a contact with nothing known yet.
            elseif bare then
                contacts[bare] = contacts[bare] or {}
            -- anything else is not a contacts line.
            else
                error(where .. " line " .. number .. ": not a 'name.field = value' line: " .. raw, 0)
            end
        end
    end
    return contacts
end
-- }}}

-- {{{ local function parse_port
-- A port is written as a whole number 1–65535 with no sign, no leading
-- zero and nothing else.  Returns the number, or nil for anything else.
local function parse_port(text)
    -- not plain digits (or a leading zero): not a port as rmail writes one.
    if not text:match("^[1-9]%d*$") then
        return nil
    end
    local number = tonumber(text)
    -- past the largest port: not a port.
    if number > 65535 then
        return nil
    end
    return number
end
-- }}}

-- {{{ local function split_indexed_field
-- "ip[3]" → "ip", 3.  "ip" → "ip", 0 (rmail's plain first address).
-- A bracket that is not a plain index from 1 ("ip[0]", "ip[01]") gives
-- "ip", nil so the caller can refuse it: "ip[01]" and "ip[1]" would
-- otherwise be two spellings of one address, one of them silently lost.
local function split_indexed_field(field)
    local base = field:match("^[%w_%-]+")
    local rest = field:sub(#base + 1)
    -- nothing after the name: the plain field, index 0.
    if rest == "" then
        return base, 0
    end
    local index = rest:match("^%[([1-9]%d*)%]$")
    -- a proper index: its number.  Anything else: malformed (nil).
    if index then
        return base, tonumber(index)
    end
    return base, nil
end
-- }}}

-- {{{ local function address_pairs
-- One contact's fields (as parse_contacts gives them) → a list of its
-- addresses, each { index = integer, address = string, port = integer,
-- <each name in `also`> = string }, sorted by index.  Plain "ip"/"port"
-- are index 0 (rmail's first address); "ip[N]"/"port[N]" are index N.
--
-- The rule rao-chat adds to rmail: every address carries its own port.
-- rmail lets an "ip[N]" without "port[N]" fall back to the contact's
-- plain "port"; here that is an error, and so is a port with no address.
-- (The owner: "the current rmail design has one port for many IPs which
-- doesn't really make sense tbh"; "no default port numbers".)
-- `also` names more per-address fields that must be present with every
-- address (the room entry adds "heard"); nil or {} for none.
local function address_pairs(fields, where, also)
    local per_address = { ip = "address", port = "port" }
    for _, name in ipairs(also or {}) do
        per_address[name] = name
    end
    -- group every per-address field by its index.
    local by_index = {}
    for field, value in pairs(fields) do
        local base, index = split_indexed_field(field)
        -- a per-address field with a malformed index: refuse, naming it.
        if per_address[base] ~= nil and index == nil then
            error(where .. ": " .. field .. " has a malformed index (write "
                .. base .. "[1], " .. base .. "[2], ...)", 0)
        end
        -- a per-address field: filed under its index.  Others are the
        -- caller's business and skipped here.
        if per_address[base] ~= nil then
            by_index[index] = by_index[index] or {}
            by_index[index][base] = value
        end
    end
    local pairs_list = {}
    for index, found in pairs(by_index) do
        local suffix = index == 0 and "" or ("[" .. index .. "]")
        -- every per-address field must be there for this index.
        for base in pairs(per_address) do
            if found[base] == nil then
                error(where .. ": " .. base .. suffix .. " is missing (every address is written with "
                    .. "its own port" .. ((also and #also > 0) and (" and " .. table.concat(also, ", ")) or "")
                    .. "; there is no default)", 0)
            end
        end
        -- an empty address could not be reached.
        if found.ip == "" then
            error(where .. ": ip" .. suffix .. " is empty", 0)
        end
        local port = parse_port(found.port)
        -- not a whole number 1–65535.
        if port == nil then
            error(where .. ": port" .. suffix .. " must be a whole number 1-65535, got '" .. found.port .. "'", 0)
        end
        local entry = { index = index, address = found.ip, port = port }
        for _, name in ipairs(also or {}) do
            entry[name] = found[name]
        end
        pairs_list[#pairs_list + 1] = entry
    end
    table.sort(pairs_list, function(a, b) return a.index < b.index end)
    return pairs_list
end
-- }}}

-- {{{ local function quote_value
-- Text that may hold anything but a line break is written in double
-- quotes, so leading and trailing spaces survive the reader's trimming
-- and a value that itself starts and ends with '"' keeps them (the reader
-- takes off exactly one pair).
local function quote_value(text)
    return '"' .. text .. '"'
end
-- }}}

return {
    parse_config = parse_config,
    parse_config_lines = parse_config_lines,
    config_with = config_with,
    parse_contacts = parse_contacts,
    address_pairs = address_pairs,
    parse_port = parse_port,
    quote_value = quote_value,
    CONFIG_KEY_PATTERN = CONFIG_KEY_PATTERN,
    CONTACT_NAME_PATTERN = "^" .. CONTACT_WORD .. "$",
}
