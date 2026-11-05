-- 131-retry-timer.lua — when a pair is tried again after a failed
-- attempt (issue 202, step 4).
--
-- A new message goes out at once (134 wakes the pair); this timer governs
-- only what follows a failure.  Each pair has its own timer (R7), and one
-- failed attempt moves it once, however many records waited (R8):
--
--   interval   starts at the floor; each failed attempt waits about the
--              interval, then the interval doubles, up to the ceiling.
--              An attempt that delivered everything puts it back to the
--              floor.  It never gives up (R11).
--   the wait   interval + card × unit, where unit = floor(interval / 12)
--              and the card is dealt from this timer's own shuffled deck
--              of the eleven whole numbers -5 .. 5, without putting cards
--              back; an empty deck is reshuffled.  The cards add up to
--              zero, so over one deck at one interval the waits add up to
--              exactly 11 × interval (planning section 6, the phone's
--              locked-screen device), while timers that failed together
--              spread out, between 7/12 and 17/12 of the interval.
--   shuffling  from the kernel's random source (getrandom, through 124),
--              never a generator seeded once (structure note R7: rmail's
--              unseeded generator gave every start the same schedule).
--
-- The deck's cards and the unit are a decision of 2026-11-05 (the
-- planning document's open question 4 for the phone; issue 202 for
-- retries); the owner may overturn it: CARDS and SPREAD below.
--
-- The floor is the first wait after a failure (decision of 2026-11-05,
-- issue 202 open question 4): nothing healthy is polled, so the floor is
-- never a polling period.
--
-- Settings (no defaults; 135-settings declares them):
--   delivery.retry-floor     whole seconds ≥ 1 (rmail's 30 is a start)
--   delivery.retry-ceiling   whole seconds ≥ the floor (rmail's 7200)

local seal = require("124-seal")
local rooms = require("002-room-folders")

local M = {}

M.CARDS = { -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5 }
M.SPREAD = 12

-- {{{ function M.random_below
-- A whole number in 0 .. n-1, evenly, from the kernel (rejection sampling
-- over 24-bit draws, so no value is favoured).
function M.random_below(n)
    local limit = 16777216 - (16777216 % n)
    while true do
        local a, b, c = seal.nonce():byte(1, 3)
        local value = (a * 256 + b) * 256 + c
        if value < limit then return value % n end
    end
end
-- }}}

-- {{{ function M.shuffled
-- A shuffled copy of the cards (Fisher-Yates).
function M.shuffled(cards)
    local deck = {}
    for i, card in ipairs(cards) do deck[i] = card end
    for i = #deck, 2, -1 do
        local j = M.random_below(i) + 1
        deck[i], deck[j] = deck[j], deck[i]
    end
    return deck
end
-- }}}

-- {{{ function M.deal
-- timer → the next card, without replacement.
function M.deal(timer)
    if #timer.deck == 0 then timer.deck = M.shuffled(M.CARDS) end
    return table.remove(timer.deck)
end
-- }}}

-- {{{ function M.settings
-- home → floor, ceiling (whole seconds), read strictly: absent or not a
-- whole number is an error naming the key.
function M.settings(home)
    local function whole(key)
        local text = rooms.config_value(home, key)
        local value = tonumber(text)
        if not text:match("^%d+$") or value < 1 then
            error(key .. " must be a whole number of seconds ≥ 1, got '" .. text .. "'", 0)
        end
        return value
    end
    local floor, ceiling = whole("delivery.retry-floor"), whole("delivery.retry-ceiling")
    if ceiling < floor then
        error("delivery.retry-ceiling (" .. ceiling .. ") is below delivery.retry-floor (" .. floor .. ")", 0)
    end
    return floor, ceiling
end
-- }}}

local Timer = {}
Timer.__index = Timer

-- {{{ function M.new
-- floor, ceiling (whole seconds) → a timer: not due, at the floor.
function M.new(floor, ceiling)
    if type(floor) ~= "number" or floor < 1 or type(ceiling) ~= "number" or ceiling < floor then
        error("retry timer: needs 1 ≤ floor ≤ ceiling, got " .. tostring(floor) .. ", " .. tostring(ceiling), 2)
    end
    return setmetatable({ floor = floor, ceiling = ceiling, interval = floor, due = nil,
        failing = false, deck = {}, failures = 0 }, Timer)
end
-- }}}

-- {{{ function Timer:wake
-- Something new to send.  A healthy pair is due now; a pair waiting out a
-- failure keeps its time, so a pile written while it is away is one
-- attempt, not one per message (R8).
function Timer:wake(now)
    if not self.failing then self.due = now end
end
-- }}}

-- {{{ function Timer:due_now
-- Due now whatever the state (start-up, and hearing from the pair's
-- address: open questions 1 and 2).  The interval is kept.
function Timer:due_now(now)
    self.due = now
end
-- }}}

-- {{{ function Timer:is_due
function Timer:is_due(now)
    return self.due ~= nil and self.due <= now
end
-- }}}

-- {{{ function Timer:failed
-- One failed attempt at `now` → the wait until the next.
function Timer:failed(now)
    local unit = math.floor(self.interval / M.SPREAD)
    local wait = self.interval + M.deal(self) * unit
    self.due = now + wait
    self.failing = true
    self.failures = self.failures + 1
    self.interval = math.min(self.interval * 2, self.ceiling)
    return wait
end
-- }}}

-- {{{ function Timer:succeeded
-- Everything waiting was acknowledged: back to the floor, not due.
function Timer:succeeded()
    self.interval = self.floor
    self.failing = false
    self.due = nil
end
-- }}}

-- {{{ function Timer:held
-- Nothing was missing, so nothing was tried: not a failure, and the
-- interval does not move (R7).  Nothing is outstanding, so the timer is
-- not due, and the next new message wakes it at once.
function Timer:held()
    self.due = nil
    self.failing = false
end
-- }}}

return M
