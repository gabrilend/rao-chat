-- 086-edits.lua — correcting and deleting messages, and how a room looks
-- once those are taken into account.
--
-- Anything may be edited, at any time (planning document section 3,
-- "Edits"; owner: "Everything is edit-able by design with no record, so
-- nothing can be trusted unless you make local copies yourself").  The log
-- is that local copy, so it is never rewritten: an edit is itself a new
-- record added to the end of the file — a "correction" carrying the new
-- text, or a "deletion" — each with its own id, naming the id of the
-- message it changes (its target).  The original stays in the file,
-- readable with cat; the room view shows the latest text.
--
-- Who may edit a message is still open (issue 105, open question 2): the
-- writer of a message cannot be known, only the address its copy came
-- from.  Both answers are built, chosen by the config key log.who-may-edit:
--
--   anyone        any edit naming a message in the room is filed; the view
--                 says which address the change came from.
--   same-address  an edit is filed only when it came from the same address
--                 as the message it changes ("me" edits only "me").  This
--                 is not a proof of anything — an address can be shared,
--                 moved or borrowed — only a narrowing.
--
-- The rule governs filing new edits only.  When reading, every correction
-- or deletion already in the file is applied whatever the rule says now:
-- the file is the record of what happened, and a rule changed later does
-- not un-happen it.  Each view carries `changed_from` so a client can show
-- an edit that came from an address other than the message's.

local edits = {}

-- {{{ local function find_target
-- Gives the "message" record with id `edit.target` from `records`, or
-- raises an error naming why the edit cannot be filed.
local function find_target(records, edit)
    local found
    local deleted = false
    for _, record in ipairs(records) do
        -- Path: the original message — remember it.  A deletion of it —
        -- note that it is gone.  Anything else — not relevant.
        if record.id == edit.target and record.kind == "message" then
            found = record
        elseif record.kind == "deletion" and record.target == edit.target then
            deleted = true
        end
    end
    -- Path: no such message here — refuse (phase 1 files edits only for
    -- messages already in the log, and an edit of an edit is not a thing;
    -- see issue 105 open question 6 for edits that arrive before their
    -- message).
    if not found then
        error("message-log: no message '" .. edit.target .. "' in this room to "
            .. (edit.kind == "deletion" and "delete" or "correct"), 0)
    end
    -- Path: already deleted — refuse; there is nothing left to change.
    if deleted then
        error("message-log: message '" .. edit.target .. "' was already deleted", 0)
    end
    return found
end
-- }}}

-- One entry per log.who-may-edit value.  Each takes the message being
-- changed and the edit; it returns nothing when the edit may be filed and
-- raises an error when it may not.
local WHO_MAY_EDIT = {
    -- {{{ local function anyone
    ["anyone"] = function(target, edit)
    end,
    -- }}}
    -- {{{ local function same_address
    ["same-address"] = function(target, edit)
        -- Path: same address (or both "me") — allowed.  Different — refused,
        -- naming both addresses.
        if target.from ~= edit.from then
            error("message-log: an edit from '" .. edit.from .. "' may not change message '"
                .. target.id .. "' from '" .. target.from .. "' (log.who-may-edit = same-address)", 0)
        end
    end,
    -- }}}
}

-- {{{ function edits.check
-- who:     string, log.who-may-edit value ("anyone" or "same-address").
-- records: list, the room's records in file order.
-- edit:    record of kind "correction" or "deletion".
-- Gives nothing; raises an error when the edit is refused.
function edits.check(who, records, edit)
    local rule = WHO_MAY_EDIT[who]
    -- Path: known rule — apply it.  Unknown — refuse (config typo).
    if not rule then
        error("message-log: log.who-may-edit '" .. tostring(who)
            .. "' is not one of anyone, same-address", 0)
    end
    rule(find_target(records, edit), edit)
end
-- }}}

-- {{{ local function later
-- The order in which edits of one message take effect: by written time,
-- then by id, so every reader agrees on which edit is the latest.
local function later(a, b)
    -- Path: different times — the later time wins.  Same time — larger id.
    if a.written ~= b.written then
        return a.written > b.written
    end
    return a.id > b.id
end
-- }}}

-- {{{ local function keep_latest
-- Puts `record` into `held[record.target]` when it is later than what is
-- there.
local function keep_latest(held, record)
    local current = held[record.target]
    -- Path: nothing held yet, or this one is later — it becomes the latest.
    -- Otherwise the held one stays.
    if not current or later(record, current) then
        held[record.target] = record
    end
end
-- }}}

-- {{{ function edits.apply
-- records: list, the room's records in file order.
-- Gives:   list of message views (only kind "message"), in file order, each
--          { id, from, written, arrived  (as in the record),
--            text         = string, the latest correction's text ("" when
--                           deleted),
--            edited       = bool, at least one correction applies,
--            deleted      = bool, a deletion applies,
--            changed_from = string, the `from` of the deletion if deleted,
--                           else of the latest correction, else "" }.
-- A correction or deletion whose message is not in the file is left out
-- quietly: it may belong to a message that has not arrived yet (phase 2).
function edits.apply(records)
    local latest_fix = {}
    local latest_deletion = {}
    for _, record in ipairs(records) do
        -- Path: a correction — keep it if latest for its target.  A
        -- deletion — likewise.  A message — nothing to collect.
        if record.kind == "correction" then
            keep_latest(latest_fix, record)
        elseif record.kind == "deletion" then
            keep_latest(latest_deletion, record)
        end
    end
    local views = {}
    for _, record in ipairs(records) do
        -- Path: a message — build its view.  Edits — already folded in.
        if record.kind == "message" then
            local fix = latest_fix[record.id]
            local deletion = latest_deletion[record.id]
            local text, changed_from = record.text, ""
            -- Path: deleted — no text, the deleter's address.  Corrected —
            -- the latest text and its address.  Neither — as written.
            if deletion then
                text, changed_from = "", deletion.from
            elseif fix then
                text, changed_from = fix.text, fix.from
            end
            views[#views + 1] = {
                id = record.id, from = record.from,
                written = record.written, arrived = record.arrived,
                text = text, edited = fix ~= nil, deleted = deletion ~= nil,
                changed_from = changed_from,
            }
        end
    end
    return views
end
-- }}}

return edits
