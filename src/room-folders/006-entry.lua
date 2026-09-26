-- 006-entry.lua — a room's entry: the one file that says what a room is.
--
-- Every conversation, a group room or a direct message with one person,
-- is described by one small text file, `entry`, written in the same
-- "name.field = value" shape rmail uses for its contacts.  In rmail a
-- contact is a name, a shared secret, and the addresses of one person's
-- machines; a rao-chat room is the same thing with the addresses of
-- everyone in it.  So one reader serves rooms, direct messages, and
-- (later) rmail's own contacts.
--
-- The entry's "name" is the room's local tag (the random folder name that
-- never leaves this machine).  Tags never repeat, so every entry file in a
-- home can be joined together with `cat rooms/*/entry` and the result is
-- still one valid contacts file.
--
-- This file only turns an entry into text and back, and checks every
-- field; it never touches the disk (002-room-folders does), so everything
-- here can be tested with strings alone.  What each field means:
--
--   label        your own name for the room, any text but a line break
--   token        the room's shared secret, any text but a line break
--   kind         group | direct
--   parent       the parent room's token fingerprint (64 hex), or empty
--   mailbox      the local tag of the mailbox this room is in (014-mailboxes;
--                never empty — every room listens somewhere)
--   filed-under  the local tag of a room you filed this one under, or empty
--   ip[N], port[N], heard[N]
--                one member address: where to send, its own port (no
--                default), and when it was last heard from (whole seconds
--                since 1970; 0 = never).  Always all three together.

local formats = require("004-rmail-formats")
local tokens  = require("007-tokens")

-- The fields every entry has exactly once, in the order they are written.
-- The Lua name differs from the file's only for filed-under, because a
-- dash cannot be part of a plain Lua field name.
local SINGLE_FIELDS = {
    { file = "label",       lua = "label" },
    { file = "token",       lua = "token" },
    { file = "kind",        lua = "kind" },
    { file = "parent",      lua = "parent" },
    { file = "mailbox",     lua = "mailbox" },
    { file = "filed-under", lua = "filed_under" },
}

-- The fields written once per member address, with an index N from 1.
local ADDRESS_FIELDS = { ip = true, port = true, heard = true }

-- The kinds a room can be, and what each means.  A table so the list of
-- kinds is written once (listing by kind reads it too).
local KINDS = {
    ["group"]  = "a room with any number of members",
    ["direct"] = "a direct message: a room with one other person (who may have several machines)",
}

-- {{{ local function is_local_tag
-- A local tag is exactly 32 lower-case hexadecimal characters (16 random
-- bytes).  Upper-case is refused so one room never has two spellings.
local function is_local_tag(value)
    return type(value) == "string" and #value == 32 and value:match("^[0-9a-f]+$") ~= nil
end
-- }}}

-- {{{ local function check_one_line_text
-- Labels and tokens: a non-empty string with no line break.  Anything
-- else on the line is allowed (spaces, quotes, "/", "=") because the
-- value is written in quotes.
local function check_one_line_text(what, value)
    if type(value) ~= "string" or value == "" then
        error("the " .. what .. " must be a non-empty string, got " .. tostring(value), 4)
    end
    if value:find("[\r\n]") then
        error("the " .. what .. " may hold any characters but a line break", 4)
    end
end
-- }}}

-- {{{ local function check_member
-- One member: { address = string, port = integer, heard = integer }.
local function check_member(member, number)
    local where = "member " .. number
    if type(member) ~= "table" then
        error(where .. " must be a table {address, port, heard}, got " .. type(member), 4)
    end
    -- the address is written bare after "=", so it may hold no spaces,
    -- quotes or line breaks; an empty one could not be reached.
    if type(member.address) ~= "string" or member.address == "" or member.address:find('[%s"]') then
        error(where .. ": address must be a non-empty string with no spaces, quotes or line breaks, got "
            .. tostring(member.address), 4)
    end
    -- a port is a whole number 1–65535; there is no default to fall to.
    if type(member.port) ~= "number" or member.port % 1 ~= 0 or member.port < 1 or member.port > 65535 then
        error(where .. " (" .. member.address .. "): port must be a whole number 1-65535, got "
            .. tostring(member.port), 4)
    end
    -- heard: whole seconds since 1970, 0 meaning never heard.
    if type(member.heard) ~= "number" or member.heard % 1 ~= 0 or member.heard < 0 then
        error(where .. " (" .. member.address .. "): heard must be a whole number of seconds >= 0 "
            .. "(0 = never heard), got " .. tostring(member.heard), 4)
    end
    -- any other key is a misspelling that would be silently dropped.
    for key in pairs(member) do
        if key ~= "address" and key ~= "port" and key ~= "heard" then
            error(where .. ": unknown field '" .. tostring(key) .. "' (a member is {address, port, heard})", 4)
        end
    end
end
-- }}}

-- {{{ local function check_members
-- A plain list (no gaps), each pair once.  May be empty: a room you are
-- about to invite people to has nobody in it but you.
local function check_members(members)
    if type(members) ~= "table" then
        error("members must be a list of {address, port, heard}, got " .. type(members), 3)
    end
    local keys = 0
    for _ in pairs(members) do keys = keys + 1 end
    -- holes or named keys would be skipped by the numbered walk below.
    if keys ~= #members then
        error("members must be a plain list with no gaps or named keys", 3)
    end
    local seen = {}
    for number, member in ipairs(members) do
        check_member(member, number)
        local pair = member.address .. " " .. member.port
        -- the same address and port twice: one machine listed twice
        -- would be sent everything twice.
        if seen[pair] then
            error("member " .. number .. ": " .. member.address .. " port " .. member.port
                .. " is already member " .. seen[pair], 3)
        end
        seen[pair] = number
    end
end
-- }}}

-- {{{ local function check_kind
local function check_kind(kind)
    -- not one of the listed kinds.
    if KINDS[kind] == nil then
        error("kind must be 'group' or 'direct', got " .. tostring(kind), 3)
    end
end
-- }}}

-- {{{ local function check_parent_shape
-- "" (no declared parent) or a token fingerprint.  Whether that parent is
-- held here does not matter: a room whose parent you are not in is a top
-- room on your screen (102).
local function check_parent_shape(parent)
    -- neither empty nor a fingerprint.
    if parent ~= "" and not tokens.is_fingerprint(parent) then
        error("parent must be \"\" or a token fingerprint (64 lower-case hex), got " .. tostring(parent), 3)
    end
end
-- }}}

-- {{{ local function check_mailbox_shape
-- A local tag, never "": every room is in a mailbox.  Whether that
-- mailbox is in the mailboxes file is checked by 002, which can see the
-- disk, when it writes the field.
local function check_mailbox_shape(mailbox)
    -- not a local tag: an empty value or a port written by mistake.
    if not is_local_tag(mailbox) then
        error("mailbox must be the local tag of a mailbox (32 lower-case hex), got " .. tostring(mailbox), 3)
    end
end
-- }}}

-- {{{ local function check_filed_shape
-- "" (not filed) or a local tag.  Whether that tag is held here is
-- checked by 002, which can see the disk.
local function check_filed_shape(filed_under)
    -- neither empty nor a local tag.
    if filed_under ~= "" and not is_local_tag(filed_under) then
        error("filed_under must be \"\" or a local tag (32 lower-case hex), got " .. tostring(filed_under), 3)
    end
end
-- }}}

-- {{{ local function check_label
-- A label is your own name for a room: any one line of text.
local function check_label(label)
    check_one_line_text("label", label)
end
-- }}}

-- {{{ local function check_entry
-- Every field of an entry table, as read_entry gives and entry_text takes.
local function check_entry(entry)
    if type(entry) ~= "table" then
        error("an entry must be a table, got " .. type(entry), 3)
    end
    -- the tag names the entry inside its file.
    if not is_local_tag(entry.tag) then
        error("entry.tag must be a local tag (32 lower-case hex), got " .. tostring(entry.tag), 3)
    end
    check_one_line_text("label", entry.label)
    check_one_line_text("token", entry.token)
    check_kind(entry.kind)
    check_parent_shape(entry.parent)
    check_mailbox_shape(entry.mailbox)
    check_filed_shape(entry.filed_under)
    check_members(entry.members)
end
-- }}}

-- {{{ local function entry_text
-- entry table → the text of its entry file.  Fields are always written in
-- the same order, text values in quotes, addresses numbered from 1.
local function entry_text(entry)
    check_entry(entry)
    local tag = entry.tag
    local lines = { "// rao-chat room entry: rmail's contacts format, one entry named by its local tag" }
    -- label and token are free text: quoted.  The rest are plain words.
    local QUOTED = { label = true, token = true }
    for _, field in ipairs(SINGLE_FIELDS) do
        local value = entry[field.lua]
        -- free text is quoted so edge spaces and quotes survive; the
        -- others are written bare (an empty value is "field =").
        if QUOTED[field.file] then
            value = formats.quote_value(value)
        end
        lines[#lines + 1] = (tag .. "." .. field.file .. " = " .. value):gsub("%s+$", "")
    end
    for number, member in ipairs(entry.members) do
        lines[#lines + 1] = tag .. ".ip[" .. number .. "] = " .. member.address
        lines[#lines + 1] = tag .. ".port[" .. number .. "] = " .. member.port
        lines[#lines + 1] = tag .. ".heard[" .. number .. "] = " .. member.heard
    end
    return table.concat(lines, "\n") .. "\n"
end
-- }}}

-- {{{ local function check_field_name
-- Every field in an entry file must be one this reader knows: a single
-- field with no index, or an address field with an index.  A misspelt
-- field would otherwise be silently ignored.
local SINGLE_BY_FILE_NAME = {}
for _, field in ipairs(SINGLE_FIELDS) do
    SINGLE_BY_FILE_NAME[field.file] = field.lua
end
local function check_field_name(field, where)
    local base, index = field:match("^([%w_%-]+)%[(%d+)%]$")
    -- an indexed field: must be ip, port or heard.
    if base then
        if not ADDRESS_FIELDS[base] then
            error(where .. ": unknown indexed field '" .. field .. "'", 0)
        end
        return
    end
    -- a plain ip/port: rmail's first-address shape; entries number every
    -- address from 1, so a plain one means the file was not written here.
    if ADDRESS_FIELDS[field] then
        error(where .. ": '" .. field .. "' without an index; an entry writes every address as "
            .. field .. "[1], " .. field .. "[2], ...", 0)
    end
    -- any other plain field must be one of the single fields.
    if SINGLE_BY_FILE_NAME[field] == nil then
        error(where .. ": unknown field '" .. field .. "'", 0)
    end
end
-- }}}

-- {{{ local function parse_heard
local function parse_heard(text, index, where)
    -- 0, or a whole number with no leading zero.
    if text ~= "0" and not text:match("^[1-9]%d*$") then
        error(where .. ": heard[" .. index .. "] must be a whole number of seconds (0 = never), got '" .. text .. "'", 0)
    end
    return tonumber(text)
end
-- }}}

-- {{{ local function parse_entry
-- text of an entry file, the tag of the folder it is in, and a place name
-- for errors → entry table { tag, label, token, kind, parent, mailbox, filed_under,
-- members = list of { address, port, heard } }.
local function parse_entry(text, tag, where)
    local contacts = formats.parse_contacts(text, where)
    local names = {}
    for name in pairs(contacts) do names[#names + 1] = name end
    -- exactly one entry, named by this folder's tag: a copied or renamed
    -- folder whose entry names another tag is noticed here.
    if #names ~= 1 then
        error(where .. ": must hold exactly one entry, found " .. #names, 0)
    end
    if names[1] ~= tag then
        error(where .. ": the entry is named " .. names[1] .. " but its folder is " .. tag, 0)
    end
    local fields = contacts[tag]
    for field in pairs(fields) do
        check_field_name(field, where)
    end
    local entry = { tag = tag }
    for _, field in ipairs(SINGLE_FIELDS) do
        -- a single field missing: the file is incomplete.
        if fields[field.file] == nil then
            error(where .. ": field '" .. field.file .. "' is missing", 0)
        end
        entry[field.lua] = fields[field.file]
    end
    local found = formats.address_pairs(fields, where, { "heard" })
    local members = {}
    for position, pair in ipairs(found) do
        -- addresses numbered 1, 2, 3 ... with no gap: a gap means a
        -- hand edit lost one, and renumbering would hide it.
        if pair.index ~= position then
            error(where .. ": addresses must be numbered 1, 2, 3 ... with no gaps; found ip[" .. pair.index
                .. "] where ip[" .. position .. "] belongs", 0)
        end
        members[position] = { address = pair.address, port = pair.port,
                              heard = parse_heard(pair.heard, pair.index, where) }
    end
    entry.members = members
    -- the same rules the writer applies, so a hand-edited file cannot
    -- hold what the program would refuse to write.
    local ok, problem = pcall(check_entry, entry)
    -- not ok: say which file broke which rule.
    if not ok then
        error(where .. ": " .. tostring(problem), 0)
    end
    return entry
end
-- }}}

return {
    KINDS = KINDS,
    is_local_tag = is_local_tag,
    check_entry = check_entry,
    check_members = check_members,
    check_kind = check_kind,
    check_parent_shape = check_parent_shape,
    check_mailbox_shape = check_mailbox_shape,
    check_filed_shape = check_filed_shape,
    check_label = check_label,
    entry_text = entry_text,
    parse_entry = parse_entry,
}
