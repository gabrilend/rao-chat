-- 183-viewer.lua — the reference viewer: a text viewer on the home
-- machine that reads and writes only the RAM folders (issue 301, step 3).
--
--   luajit src/viewer/183-viewer.lua <home RAM folder> <command> [...]
--
-- <home RAM folder> is the home's folder under gatherer.ram-root (161's
-- home_ram), the one holding a folder per mailbox.  Commands:
--
--   tree                 every room of the home, as one tree, joined from
--                        each gatherer's inbox/.tree by tag; a room's
--                        flagged members and waiting pile are shown
--   room <room>          a room's facts (.room) and its messages, in the
--                        folder's name order, which is the room's order
--   write <room> [--signature <name>] <text...>
--                        drops a file into the room's gatherer's typed/:
--                        room:, written: (this clock), a blank line, the
--                        text with the signature on its own last line
--                        (with no text words, the text is read from stdin)
--   follow <room> [--for <seconds>]
--                        prints the room's messages, then each new or
--                        changed one as it appears (polled once a second;
--                        a listing is a hint to re-read, never a record of
--                        what changed); stops after <seconds>, or when
--                        stopped
--   problems             every gatherer's problem lines from its `state`
--
-- <room> is a room's local tag, a unique start of one, or its path of
-- labels as `.room` gives it ("home/ritz").
--
-- What it never does (the rules of 301): it never reads the disk home or
-- a room's log, so what it shows is what the gatherers wrote; it applies
-- no edits and works out no signature (the inbox files carry both
-- already); it places no room in the tree (each `.tree` line names the
-- room's parent, worked out by 102 in the gatherer); it deletes nothing
-- (there is no command that removes an inbox file, and removing one would
-- delete nothing anyway); and it writes only through 161's put, so a
-- gatherer never reads half a typed file.  The one check it makes on a
-- signature before writing is 169's rule, so that what it is given as the
-- signature is what will be read back as one.

local DIR = os.getenv("RAO_CHAT_DIR")
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/viewer/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)

local disk = require("003-disk")
local ram = require("161-ram-folders")
local signature = require("169-signature")

local M = {}

-- For referees only (184): RAO_VIEWER_BROKEN=own-order (children ordered
-- by tag, not label), in-place (typed files written straight to their
-- final name) are broken versions the referees must catch.
M.broken = os.getenv("RAO_VIEWER_BROKEN") or ""

-- {{{ local function read_file
local function read_file(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end
-- }}}

-- {{{ local function list
-- folder → its plain names (no dot files), sorted.
local function list(folder)
    local names = {}
    local listing = io.popen("ls -1 " .. disk.shell_quote(folder) .. " 2>/dev/null")
    for name in listing:lines() do
        if name:sub(1, 1) ~= "." then names[#names + 1] = name end
    end
    listing:close()
    table.sort(names)
    return names
end
-- }}}

-- {{{ function M.gatherers
-- home RAM folder → the mailbox folders that have an inbox, sorted.
function M.gatherers(home_ram)
    local found = {}
    for _, name in ipairs(list(home_ram)) do
        if name:match("^%x+$") and disk.is_dir(home_ram .. "/" .. name .. "/inbox") then
            found[#found + 1] = home_ram .. "/" .. name
        end
    end
    return found
end
-- }}}

-- {{{ function M.read_fields
-- an inbox file's text → { field = value }, and the body (after the
-- first blank line).  `.room` has no body; its pile lines are a list.
function M.read_fields(text)
    local head, body = (text or ""):match("^(.-)\n\n(.*)$")
    if not head then head, body = text or "", nil end
    local fields = { pile = {} }
    for line in (head .. "\n"):gmatch("([^\n]*)\n") do
        local key, value = line:match("^(%a+): (.*)$")
        if key == "pile" then fields.pile[#fields.pile + 1] = value
        elseif key then fields[key] = value end
    end
    return fields, body
end
-- }}}

-- {{{ function M.rooms
-- home RAM folder → { [tag] = { tag, gatherer (its folder), label, kind,
-- parent, facts (.room's fields) } } and the tags in the order the
-- gatherers' trees list them.
function M.rooms(home_ram)
    local rooms, order = {}, {}
    for _, gatherer in ipairs(M.gatherers(home_ram)) do
        for line in (read_file(gatherer .. "/inbox/.tree") or ""):gmatch("[^\n]+") do
            local tag, parent, kind, label = line:match("^(%x+) (%S+) (%S+) (.*)$")
            if tag and not rooms[tag] then
                rooms[tag] = { tag = tag, gatherer = gatherer, parent = parent ~= "none" and parent or nil,
                    kind = kind, label = label,
                    facts = (M.read_fields(read_file(gatherer .. "/inbox/" .. tag .. "/.room")) ) }
                order[#order + 1] = tag
            end
        end
    end
    return rooms, order
end
-- }}}

-- {{{ function M.find_room
-- home RAM folder, a tag, the start of one, or a path of labels → the
-- room, or nil and why.
function M.find_room(home_ram, wanted)
    local rooms = M.rooms(home_ram)
    if rooms[wanted] then return rooms[wanted] end
    local found = {}
    for tag, room in pairs(rooms) do
        if (wanted:match("^%x+$") and tag:sub(1, #wanted) == wanted) or room.facts.path == wanted then
            found[#found + 1] = room
        end
    end
    if #found == 1 then return found[1] end
    if #found == 0 then return nil, "no room here is '" .. wanted .. "'" end
    local named = {}
    for _, room in ipairs(found) do named[#named + 1] = room.tag:sub(1, 8) .. " (" .. room.facts.path .. ")" end
    table.sort(named)
    return nil, "'" .. wanted .. "' could be any of " .. table.concat(named, ", ")
end
-- }}}

-- {{{ local function marks
-- a room's facts → " [2 flagged] [3 waiting]" or ""
local function marks(facts)
    local words = {}
    if tonumber(facts.flagged or "0") and tonumber(facts.flagged or "0") > 0 then
        words[#words + 1] = "[" .. facts.flagged .. " flagged]"
    end
    local waiting = 0
    for _, line in ipairs(facts.pile or {}) do
        local missing = line:match("^%S+ %d+ (%d+)")
        if missing then waiting = waiting + tonumber(missing) end
    end
    if waiting > 0 then words[#words + 1] = "[" .. waiting .. " waiting]" end
    return #words > 0 and (" " .. table.concat(words, " ")) or ""
end
-- }}}

-- {{{ function M.tree_text
-- home RAM folder → the joined tree as indented lines.  Children come in
-- 102's order (label, then tag), whichever gatherer listed them.
function M.tree_text(home_ram)
    local rooms, order = M.rooms(home_ram)
    local children, tops = {}, {}
    for _, tag in ipairs(order) do
        local room = rooms[tag]
        if room.parent and rooms[room.parent] then
            children[room.parent] = children[room.parent] or {}
            table.insert(children[room.parent], tag)
        else
            tops[#tops + 1] = tag
        end
    end
    local function by_label(a, b)
        if M.broken == "own-order" then return a < b end
        if rooms[a].label ~= rooms[b].label then return rooms[a].label < rooms[b].label end
        return a < b
    end
    local lines = {}
    local function walk(list, depth)
        table.sort(list, by_label)
        for _, tag in ipairs(list) do
            local room = rooms[tag]
            lines[#lines + 1] = string.rep("  ", depth) .. room.label .. (room.kind ~= "group" and (" (" .. room.kind .. ")") or "")
                .. "  " .. tag:sub(1, 8) .. marks(room.facts)
            walk(children[tag] or {}, depth + 1)
        end
    end
    walk(tops, 0)
    return table.concat(lines, "\n") .. (#lines > 0 and "\n" or "")
end
-- }}}

-- {{{ local function message_text
-- an inbox file's text → the lines a person reads for it.
local function message_text(text)
    local f, body = M.read_fields(text)
    local when = tonumber(f.written) and os.date("%Y-%m-%d %H:%M", tonumber(f.written)) or "?"
    local flags = {}
    if f.edited == "yes" then flags[#flags + 1] = "edited" end
    if f.ignored == "mark" then flags[#flags + 1] = "marked" end
    local head = when .. "  " .. (f.from or "?") .. (#flags > 0 and (" (" .. table.concat(flags, ", ") .. ")") or "")
    if f.deleted == "yes" then return head .. "\n    (deleted)" end
    local out = { head }
    for line in ((body or "") .. "\n"):gmatch("([^\n]*)\n") do out[#out + 1] = "    " .. line end
    if (f.signature or "") ~= "" then out[#out + 1] = "    -- " .. f.signature end
    return table.concat(out, "\n")
end
-- }}}

-- {{{ function M.room_text
-- home RAM folder, room → its heading and every message, in name order.
function M.room_text(home_ram, wanted)
    local room, why = M.find_room(home_ram, wanted)
    if not room then return nil, why end
    local f = room.facts
    local out = { string.format("== %s (%s, %s member(s))%s", f.path or room.label, room.kind, f.members or "?",
        marks(f)) }
    for _, line in ipairs(f.pile or {}) do
        local address, port, missing, oldest = line:match("^(%S+) (%d+) (%d+) (%d+)$")
        if address then
            out[#out + 1] = string.format("   %s %s waits for %s message(s), since %s", address, port, missing,
                os.date("%Y-%m-%d %H:%M", tonumber(oldest)))
        end
    end
    local folder = room.gatherer .. "/inbox/" .. room.tag
    for _, name in ipairs(list(folder)) do
        local text = read_file(folder .. "/" .. name)
        if text then out[#out + 1] = message_text(text) end
    end
    return table.concat(out, "\n") .. "\n", room
end
-- }}}

-- {{{ function M.typed_text
-- room tag, text, signature (or nil), written → the typed file's bytes,
-- or nil and why.  The signature must read back as itself by 169's rule.
function M.typed_text(tag, text, sig, written)
    if not tag:match("^%x+$") or #tag ~= 32 then return nil, "a room tag is 32 hex" end
    text = text:gsub("\r\n", "\n"):gsub("\n+$", "")
    if text == "" then return nil, "there is nothing to send" end
    local whole = text
    if sig and sig ~= "" then
        whole = text .. "\n\n" .. sig
        local body, read_back = signature.read(whole)
        if read_back ~= sig or body ~= text then
            return nil, "'" .. sig .. "' would not be read as a signature (one line, at most "
                .. signature.MOST_CHARACTERS .. " characters)"
        end
    end
    return "room: " .. tag .. "\nwritten: " .. string.format("%d", written) .. "\n\n" .. whole .. "\n"
end
-- }}}

-- {{{ function M.write
-- home RAM folder, room, text, signature, now → the typed file's path,
-- or nil and why.  Written into the gatherer that holds the room.
function M.write(home_ram, wanted, text, sig, now)
    local room, why = M.find_room(home_ram, wanted)
    if not room then return nil, why end
    local bytes, refused = M.typed_text(room.tag, text, sig, math.floor(now))
    if not bytes then return nil, refused end
    local queue = room.gatherer .. "/typed"
    local name = ram.new_name(now)
    if M.broken == "in-place" then
        local handle = assert(io.open(queue .. "/" .. name, "wb"))
        handle:write(bytes:sub(1, math.floor(#bytes / 2)))
        handle:flush()
        os.execute("sleep 0.3")
        handle:write(bytes:sub(math.floor(#bytes / 2) + 1))
        handle:close()
    else
        ram.put(queue, name, bytes)
    end
    return queue .. "/" .. name
end
-- }}}

-- {{{ function M.problems_text
-- home RAM folder → each gatherer's problem lines, "<mailbox> <name>: <words>".
function M.problems_text(home_ram)
    local out = {}
    for _, gatherer in ipairs(M.gatherers(home_ram)) do
        local state = ram.read_state(gatherer)
        local names = {}
        for name in pairs(state) do if name:match("^problem%.") then names[#names + 1] = name end end
        table.sort(names)
        for _, name in ipairs(names) do
            out[#out + 1] = gatherer:match("([^/]+)$"):sub(1, 8) .. " " .. name:sub(9) .. ": " .. state[name]
        end
    end
    return table.concat(out, "\n") .. (#out > 0 and "\n" or "")
end
-- }}}

-- {{{ function M.follow
-- home RAM folder, room, seconds (nil: until stopped), print function:
-- prints every message, then each one whose file is new or changed.
function M.follow(home_ram, wanted, seconds, out)
    local room, why = M.find_room(home_ram, wanted)
    if not room then return nil, why end
    local folder = room.gatherer .. "/inbox/" .. room.tag
    local seen = {}
    local stop = seconds and (os.time() + seconds) or nil
    while true do
        for _, name in ipairs(list(folder)) do
            local text = read_file(folder .. "/" .. name)
            if text and seen[name] ~= text then
                seen[name] = text
                out(message_text(text))
            end
        end
        if stop and os.time() >= stop then return true end
        os.execute("sleep 1")
    end
end
-- }}}

-- {{{ local function main
local function main(args)
    local home_ram, command = args[1], args[2]
    local usage = "usage: luajit src/viewer/183-viewer.lua <home RAM folder> tree | room <room> | "
        .. "write <room> [--signature <name>] <text...> | follow <room> [--for <seconds>] | problems"
    if not home_ram or not command then io.stderr:write(usage .. "\n") return 2 end
    if not disk.is_dir(home_ram) then io.stderr:write("no such folder: " .. home_ram .. "\n") return 2 end
    if command == "tree" then
        io.write(M.tree_text(home_ram))
    elseif command == "room" and args[3] then
        local text, why = M.room_text(home_ram, args[3])
        if not text then io.stderr:write(why .. "\n") return 1 end
        io.write(text)
    elseif command == "write" and args[3] then
        local sig, words, i = nil, {}, 4
        while args[i] do
            if args[i] == "--signature" then sig = args[i + 1]; i = i + 2
            else words[#words + 1] = args[i]; i = i + 1 end
        end
        local text = #words > 0 and table.concat(words, " ") or io.read("*a")
        local path, why = M.write(home_ram, args[3], text, sig, os.time())
        if not path then io.stderr:write(why .. "\n") return 1 end
        io.write("written: " .. path .. "\n")
    elseif command == "follow" and args[3] then
        local seconds = args[4] == "--for" and tonumber(args[5]) or nil
        local ok, why = M.follow(home_ram, args[3], seconds, function(text) io.write(text, "\n") io.flush() end)
        if not ok then io.stderr:write(why .. "\n") return 1 end
    elseif command == "problems" then
        io.write(M.problems_text(home_ram))
    else
        io.stderr:write(usage .. "\n")
        return 2
    end
    return 0
end
-- }}}

if arg and arg[0] and arg[0]:match("183%-viewer%.lua$") then os.exit(main(arg)) end
return M
