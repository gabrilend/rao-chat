-- 123-room-key.lua — a room's sealing key and its key-tying value, made
-- from the room's token (issue 201, step 1).
--
-- Everyone in a room holds the same token, a line of text, and seals with
-- the same key made from it, so the rule that turns the token into the key
-- has to be one rule everywhere: a stray line ending, or one spelling of a
-- letter on the phone and another on the computer, would give an
-- unrelated key, and every frame would silently fail to open (rubric R5).
--
-- The rule (decision of 2026-11-05, issue 201 open question 3; the owner
-- may overturn it):
--
--   the token's bytes exactly as stored in the room's entry — no Unicode
--   normalising, no trimming — and a token holding a line break is an
--   error, never a token with its line ending quietly cut off.
--
-- This is the rule phase 1 already uses for the fingerprint, so no room's
-- fingerprint changes.  A token typed or pasted somewhere must reach this
-- function exactly as the entry holds it; a reader that keeps a line's
-- "\n" gets an error here, not a different key.
--
--   key           32 raw bytes, SHA-256(token)
--   tying value   32 raw bytes, SHA-256(key): the room's fingerprint as
--                 bytes (phase 1 writes the same value as 64 hex
--                 characters).  It begins every sealed body (201a).

local tokens = require("007-tokens")

-- {{{ local function room_key
-- token (string) → 32 raw bytes.  Errors on a token that is empty, not a
-- string, or holds a line break (007's check_token).
local function room_key(token)
    tokens.check_token(token)
    return tokens.sha256(token)
end
-- }}}

-- {{{ local function tying_value
-- token (string) → 32 raw bytes: SHA-256 of the key, so the hex of this
-- is exactly 007's token_fingerprint(token).
local function tying_value(token)
    return tokens.sha256(room_key(token))
end
-- }}}

-- {{{ local function key_pair
-- token → { key = 32 bytes, tie = 32 bytes }: what sealing and opening
-- need for one room, worked out once.
local function key_pair(token)
    local key = room_key(token)
    return { key = key, tie = tokens.sha256(key) }
end
-- }}}

return {
    room_key = room_key,
    tying_value = tying_value,
    key_pair = key_pair,
    KEY_BYTES = 32,
    TIE_BYTES = 32,
}
