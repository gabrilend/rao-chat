-- 005-change-bell.lua — the bell rung whenever a room (or the home) changes.
--
-- Some files in a home are summaries of other files: a room's `where`
-- (its path of labels) is worked out from the labels and parents above
-- it, and the `people/` links are worked out from every room's members.
-- When a room changes, those summaries must be redone.  Rather than have
-- the code that changes a room know every summary that depends on it, it
-- rings this bell, saying which room and what kind of change; whoever
-- keeps a summary has asked to be told, and redoes it.  The module that
-- keeps the `where` files (room-tree) and the one that keeps the
-- `people/` links (people-links) each sign up when they are loaded.
--
-- A listener that fails stops the ring and the failure reaches whoever
-- made the change: a summary left out of date silently would be a lie on
-- disk.  Listeners are told in the order they signed up.

-- The kinds of change a ring can announce, and what each one is about.
-- `scope` says what the second argument of a ring must be: "room" — the
-- local tag of the room that changed; "home-or-room" — the empty string
-- when the change belongs to the whole home, or a local tag when it
-- belongs to one room (the ignore list can be kept for the whole home or
-- per room; which is the ignore list's own open choice, ignore.scope; and
-- the mailboxes file is the whole home's, while a room moving between
-- mailboxes is that room's).
-- A table rather than a chain of comparisons, so the list is written once
-- and read everywhere (the demo and tests read it too).
local BELL_KINDS = {
    ["created"]      = { scope = "room", meaning = "a new room folder now exists (entry, empty withheld, empty flagged, empty log)" },
    ["label"]        = { scope = "room", meaning = "the entry's label changed" },
    ["token"]        = { scope = "room", meaning = "the entry's token (and so its fingerprint) changed" },
    ["members"]      = { scope = "room", meaning = "the entry's address pairs changed (rung for 103's writes)" },
    ["heard"]        = { scope = "room", meaning = "one address's last-heard time changed; membership did not" },
    ["parent"]       = { scope = "room", meaning = "the entry's parent fingerprint changed" },
    ["filed"]        = { scope = "room", meaning = "the entry's filed-under changed" },
    ["withheld"]     = { scope = "room", meaning = "the room's withheld or flagged file changed: who you send to (rung by recipients)" },
    ["log"]          = { scope = "room", meaning = "a record was filed in the room's log (rung by message-log)" },
    ["ignore"]       = { scope = "home-or-room", meaning = "the ignore file changed (rung by the ignore list: tag \"\" for the whole home, or the room it was scoped to)" },
    ["removed-room"] = { scope = "room", meaning = "a room folder is gone (rung by whoever retires one; none in phase 1)" },
    ["mailbox"]      = { scope = "home-or-room", meaning = "the mailboxes changed: tag \"\" when a mailbox was made by make_mailbox or its port changed, a room's tag when that room moved to another mailbox; membership did not change" },
}

-- How each scope checks the tag it is rung with.  A local tag is exactly
-- 32 lower-case hex characters (see 002-room-folders); the shape is
-- repeated here rather than required from 002, because 002 requires this
-- file and a loop of requires would fail on load.
local TAG_CHECKS = {
    ["room"] = function(tag)
        return type(tag) == "string" and #tag == 32 and tag:match("^[0-9a-f]+$") ~= nil,
            "a local tag (32 lower-case hex characters)"
    end,
    ["home-or-room"] = function(tag)
        local is_tag = type(tag) == "string" and #tag == 32 and tag:match("^[0-9a-f]+$") ~= nil
        return tag == "" or is_tag, "\"\" (the whole home) or a local tag (one room)"
    end,
}

-- The signed-up listeners, a list of functions.  Lives as long as the Lua
-- program: require() hands every module the same copy of this file.
local listeners = {}

-- {{{ local function on_change
local function on_change(listener)
    -- only a function can be called when the bell rings.
    if type(listener) ~= "function" then
        error("on_change needs a function, got " .. type(listener), 2)
    end
    listeners[#listeners + 1] = listener
end
-- }}}

-- {{{ local function notify
local function notify(home, tag, what)
    local kind = BELL_KINDS[what]
    -- an unknown kind is a typo in the ringer; nobody would be listening
    -- for it, so the change would pass unnoticed.
    if kind == nil then
        error("notify: unknown kind of change '" .. tostring(what) .. "'", 2)
    end
    -- the home must be a real value; listeners would otherwise fail
    -- somewhere far from the mistake.
    if type(home) ~= "table" or type(home.dir) ~= "string" then
        error("notify: first argument must be a home {dir = string}", 2)
    end
    local fits, wanted = TAG_CHECKS[kind.scope](tag)
    -- the tag does not match the kind's scope: a room change rung without
    -- a room, or a home change rung as if it were one room's.
    if not fits then
        error("notify: '" .. what .. "' must be rung with " .. wanted .. ", got " .. tostring(tag), 2)
    end
    for _, listener in ipairs(listeners) do
        listener(home, tag, what)
    end
end
-- }}}

-- {{{ local function listener_count
-- How many listeners have signed up; for tests and the phase demo.
local function listener_count()
    return #listeners
end
-- }}}

return {
    on_change = on_change,
    notify = notify,
    listener_count = listener_count,
    BELL_KINDS = BELL_KINDS,
}
