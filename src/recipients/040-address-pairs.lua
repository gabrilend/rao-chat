-- 040-address-pairs.lua — the one shape every address takes in this module:
-- a place a home server can be reached, always together with its own port.
--
-- In rao-chat a member of a room is not a person's name but a place: an IP
-- address or a hostname, and the port the home server there listens on.
-- The two always travel as a pair, because two people behind the same
-- household router share an address and differ only by port; there is no
-- "usual" port to fill in when one is missing.  This file checks that a
-- pair is well formed, turns it into one line of text for the small files
-- this module keeps, and reads such lines back.
--
-- The line shape is "<address> <port>" — a single space between, so an
-- address may not hold spaces (no real IP address or hostname does), and it
-- may hold colons (IPv6 addresses do), which is why a colon is not used as
-- the separator.
--
-- Data-making only: nothing here prints or draws.

local M = {}

-- {{{ local function check
-- Errors unless address is a non-empty string with no spaces or line breaks
-- and port is a whole number from 1 to 65535.  A port given as text is a
-- caller's mistake, not something to convert silently: the file readers
-- below do the one conversion from text, in one place.
local function check(address, port, where)
    -- the address must be text; anything else is a caller's slip
    if type(address) ~= "string" or address == "" then
        error((where or "address") .. ": address must be non-empty text, got " .. tostring(address), 3)
    end
    -- whitespace would break the one-line file shape
    if address:find("%s") then
        error((where or "address") .. ": address may not hold spaces or line breaks: '" .. address .. "'", 3)
    end
    -- the port must be a number and a whole one in range; there is no default
    if type(port) ~= "number" or port ~= math.floor(port) or port < 1 or port > 65535 then
        error((where or "address") .. ": port must be a whole number 1-65535, got " .. tostring(port), 3)
    end
end
-- }}}
M.check = check

-- {{{ local function key
-- The pair as one string, "<address> <port>"; used both as the file line
-- start and as a table key for "have I seen this pair".
local function key(address, port)
    check(address, port, "key")
    return address .. " " .. tostring(port)
end
-- }}}
M.key = key

-- {{{ local function same
local function same(a, b)
    return a.address == b.address and a.port == b.port
end
-- }}}
M.same = same

-- {{{ local function split_line
-- Splits one file line into its space-separated words.  `want` is how many
-- words the line must hold; any other count means the file was damaged or
-- hand-edited wrongly, and the reader stops rather than guess.
local function split_line(line, want, path)
    local words = {}
    for word in line:gmatch("%S+") do
        words[#words + 1] = word
    end
    -- the right number of words: hand them back; otherwise stop loudly
    if #words ~= want then
        error("recipients: " .. path .. ": expected " .. want .. " words, got " .. #words .. ": '" .. line .. "'")
    end
    return words
end
-- }}}
M.split_line = split_line

-- {{{ local function whole_number
-- Text to a whole number, erroring on anything else (a port or a time).
local function whole_number(text, path)
    local n = tonumber(text)
    -- a number with no fraction: fine; anything else: a damaged file
    if n == nil or n ~= math.floor(n) then
        error("recipients: " .. path .. ": expected a whole number, got '" .. text .. "'")
    end
    return n
end
-- }}}
M.whole_number = whole_number

-- {{{ local function read_lines
-- Every non-blank line of a file this module keeps.  The file must exist:
-- 101 makes each room's files empty before the room becomes visible, so an
-- absent file means a room made by hand or by something that skipped that
-- step — worth an error, not a quiet empty list.
local function read_lines(path)
    local file, why = io.open(path, "r")
    -- no file: say which and why
    if file == nil then
        error("recipients: cannot read " .. path .. ": " .. tostring(why))
    end
    local lines = {}
    for line in file:lines() do
        -- blank lines are skipped; everything else is data
        if line:find("%S") then
            lines[#lines + 1] = line
        end
    end
    file:close()
    return lines
end
-- }}}
M.read_lines = read_lines

-- {{{ local function read_pair_file
-- A file of lines "<address> <port> <extra words...>" into a list of
-- tables { address = string, port = integer, words = list of the extra
-- words as strings }, in file order.  `extra` is how many words follow the
-- pair on every line.
local function read_pair_file(path, extra)
    local rows = {}
    for _, line in ipairs(read_lines(path)) do
        local words = split_line(line, 2 + extra, path)
        local row = { address = words[1], port = whole_number(words[2], path), words = {} }
        check(row.address, row.port, path)
        for i = 3, #words do
            row.words[#row.words + 1] = words[i]
        end
        rows[#rows + 1] = row
    end
    return rows
end
-- }}}
M.read_pair_file = read_pair_file

-- {{{ local function pair_file_text
-- The reverse: rows as above to the file's text, one line each.
local function pair_file_text(rows)
    local lines = {}
    for _, row in ipairs(rows) do
        local parts = { key(row.address, row.port) }
        for _, word in ipairs(row.words) do
            parts[#parts + 1] = word
        end
        lines[#lines + 1] = table.concat(parts, " ") .. "\n"
    end
    return table.concat(lines)
end
-- }}}
M.pair_file_text = pair_file_text

-- {{{ local function index_of
-- The position of a pair in a list of pairs, or 0 when it is not there.
-- (0, not nil: "not there" is an ordinary answer here, and a number keeps
-- callers from mistaking it for a forgotten value.)
local function index_of(list, address, port)
    for i, row in ipairs(list) do
        -- same place and same port: found
        if row.address == address and row.port == port then
            return i
        end
    end
    return 0
end
-- }}}
M.index_of = index_of

return M
