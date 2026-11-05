-- 159-phase-2-scenes.lua — the scenes of the phase 2 demo (issue 210).
--
-- Each scene builds homes on disk (real rao-homes, each with its own RAM
-- folder, under tmp/shared-memory/phase-2-demo/), runs phase 2's real code
-- between them in 143's simulated world (a clock of its own and an
-- in-memory relay: nothing reaches a network), and gives back the lines to
-- print: figures read from the homes' files and the stages' state, never
-- text about them.  Every home listens on, and sends from, its own
-- loopback address (127.0.0.2, .3, .4, ...) on a port written in its own
-- mailboxes file, so the relay's record of who connected from where shows
-- three homes, not one.
--
-- A scene is a function(c) → {lines = {...}, gaps = {...}}.  `gaps` names
-- a part of the scene that could not run and why (fail2ban-regex not
-- installed, say); the scene still ran.  A scene that needs an issue not
-- built yet is not a function but {waits = "issue: why"}, and the demo
-- reports it as waiting.
--
-- c (from 158): T (143's world), dir, scratch, m (the modules by short
-- name), break_scene (a scene to fail on purpose: 160's broken version).
--
-- The real processes the issue asks for (each gatherer of each home its
-- own process, the demo watching from outside) wait on 211, which builds
-- the gatherer; until then the stages run as threads of this program, on
-- the simulated clock.  Times are given on that clock and say so.

local M = {}

-- The scenes, in the order the demo shows them.  key: the scene's name;
-- title: its heading; issues: what it shows.
M.ORDER = {
    { key = "delivery",   title = "A message to every pair at once (202)", issues = "202" },
    { key = "down",       title = "A member down, its pile, and delivery when it returns (202)", issues = "202" },
    { key = "join",       title = "Joining with a token and one pair; a direct message (204, 205, 212)", issues = "204 205 212" },
    { key = "keys",       title = "Two rooms with one label, and the keys tried per frame (201, 201a)", issues = "201 201a" },
    { key = "child",      title = "A child room flags an outsider of its parent; approving clears it (207, 103)", issues = "207" },
    { key = "syncing",    title = "Contact syncing: digest then list; an ignored pair; a replayed list (207, 208)", issues = "207 208" },
    { key = "token",      title = "A token changed by hand and given out by direct message (101, 201)", issues = "201" },
    { key = "leaving",    title = "A genuine leave and a forged one (208)", issues = "208" },
    { key = "crosscheck", title = "A two-faced sender caught, and a gap filled with its own id (209)", issues = "209" },
    { key = "housemates", title = "Housemates found on the home network (213)", issues = "213" },
    { key = "failed",     title = "Failed decryption: the files, and fail2ban's matcher (203)", issues = "203" },
    { key = "signatures", title = "A signature table (214)", issues = "214" },
    { key = "git",        title = "Each mailbox's git repository (215, 215a, 215b)", issues = "215 215a 215b" },
    { key = "acknowledge", title = "The gatherer.acknowledge-after switch, both ways (211)", issues = "211" },
    { key = "phase1",     title = "Phase 1's tools on phase 2's homes: people/, the tree, the tally", issues = "104 102 106" },
}

local RULE = "  " .. string.rep("·", 60)

-- Contact syncing (207) never lists a loopback pair (nor a private,
-- carrier-grade or link-local one): a home's member list carries only
-- pairs others could reach.  So the scenes that need a pair passed on in a
-- list (child, syncing) give their homes documentation addresses instead,
-- 198.51.100.0/24 (RFC 5737's TEST-NET-2, never routed), still one address
-- per home and still only inside 143's in-memory relay; the syncing scene
-- first shows the loopback homes' lists coming out empty.
local LISTED = "198.51.100."

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- {{{ local function pair
local function pair(address, port) return { address = address, port = port } end
-- }}}

-- {{{ local function key_of
local function key_of(p) return p.address .. ":" .. p.port end
-- }}}

-- {{{ local function seconds
local function seconds(value) return string.format("%.2f s", value) end
-- }}}

-- {{{ local function read_all
local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end
-- }}}

-- {{{ local function file_lines
-- The lines of a file, each indented, at most `most` (the rest counted).
local function file_lines(out, path, most, indent)
    indent = indent or "      "
    local text = read_all(path)
    if not text then
        out[#out + 1] = indent .. "(no file at " .. path .. ")"
        return
    end
    local n = 0
    for line in text:gmatch("([^\n]*)\n") do
        n = n + 1
        if n <= (most or 1e9) then
            if #line > 150 then line = line:sub(1, 147) .. "..." end
            out[#out + 1] = indent .. line
        end
    end
    if most and n > most then out[#out + 1] = indent .. "(" .. (n - most) .. " more lines)" end
    if n == 0 then out[#out + 1] = indent .. "(empty)" end
end
-- }}}

-- {{{ local function shell
-- A command's output, as lines.
local function shell(command)
    local p = io.popen(command .. " 2>&1")
    local lines = {}
    for line in p:lines() do lines[#lines + 1] = line end
    p:close()
    return lines
end
-- }}}

-- {{{ local function quote
local function quote(text) return "'" .. text:gsub("'", "'\\''") .. "'" end
-- }}}

-- {{{ local function world_of
-- The scene's tools, after a fresh world: now, idle, run_until, member,
-- attempts, home (a new announcing home), connect (each a member of the
-- other), start.
local function world_of(c)
    local T, m = c.T, c.m
    local sim, world = T.sim, T.world
    sim.reset()
    world.reset()
    local w = { T = T, sim = sim, world = world }
    function w.now() return math.floor(sim.now) end
    function w.idle(s) T.run_until(function() return false end, s) end
    w.run_until = T.run_until
    function w.member(node, p) return m.recipients.is_member(node.home, node.tag, p.address, p.port) end
    function w.attempts(from_address, p)
        local n = 0
        for _, a in ipairs(world.attempts) do
            if a.from == from_address and a.address == p.address and a.port == p.port then n = n + 1 end
        end
        return n
    end
    -- name, hosts, port, options → a home that states its pairs (212)
    function w.home(name, hosts, port, options)
        options = options or {}
        if options.announce == nil then options.announce = true end
        local node = T.new_node(name, hosts, port, options)
        node.pair = pair(hosts[1], port)
        return node
    end
    -- each home a member of every other's room, by each one's pairs
    function w.connect(nodes, extra)
        for _, node in ipairs(nodes) do
            for _, other in ipairs(nodes) do
                if other ~= node then
                    for _, p in ipairs((extra and extra[other]) or { other.pair }) do
                        m.recipients.add_member(node.home, node.tag, p.address, p.port)
                    end
                end
            end
        end
    end
    function w.start(nodes)
        for _, node in ipairs(nodes) do node.stage:start(w.now()) end
    end
    return w
end
-- }}}

-- {{{ local function ack_times
-- Runs the world in 50 ms steps until `node` has nothing missing for each
-- pair, or `limit` seconds pass.  → {pair key → seconds after the start}.
local function ack_times(w, node, pairs, limit)
    local start, acked = w.sim.now, {}
    while w.sim.now < start + limit do
        local all = true
        for _, p in ipairs(pairs) do
            local k = key_of(p)
            if not acked[k] then
                if w.T.missing(node, p.address, p.port) == 0 then acked[k] = w.sim.now - start else all = false end
            end
        end
        if all then break end
        w.sim.run(w.sim.now + 0.05)
    end
    return acked
end
-- }}}

-- {{{ local function connections_from
-- The relay's record, grouped: "from → to" and how many connections.
local function connections_from(w, out, since)
    local counts, order = {}, {}
    for i = (since or 0) + 1, #w.world.attempts do
        local a = w.world.attempts[i]
        local k = a.from .. " → " .. a.address .. ":" .. a.port
        if not counts[k] then order[#order + 1] = k end
        counts[k] = (counts[k] or 0) + 1
    end
    table.sort(order)
    for _, k in ipairs(order) do out[#out + 1] = string.format("      %-34s %3d connection(s)", k, counts[k]) end
end
-- }}}

-- {{{ local function mailbox_line
-- The home's mailboxes file: the ports it states (no default ports).
local function mailbox_lines(c, out, node)
    for _, mailbox in ipairs(c.m.rooms.read_mailboxes(node.home)) do
        out[#out + 1] = string.format("      %s: %s mailbox, port %s", node.name, mailbox.kind, tostring(mailbox.port))
    end
end
-- }}}

-- {{{ local function three_homes
-- A at 127.0.0.2, B at .3, C at .4 (and C also at .5 when two_pairs), each
-- on its own port, each a member of the others, started and settled.
local function three_homes(c, w, two_pairs)
    local a = w.home("A", { "127.0.0.2" }, 7602)
    local b = w.home("B", { "127.0.0.3" }, 7603)
    local c_hosts = two_pairs and { "127.0.0.4", "127.0.0.5" } or { "127.0.0.4" }
    local cc = w.home("C", c_hosts, 7604)
    local extra = {}
    if two_pairs then extra[cc] = { pair("127.0.0.4", 7604), pair("127.0.0.5", 7604) } end
    w.connect({ a, b, cc }, extra)
    w.start({ a, b, cc })
    w.idle(20)
    return a, b, cc
end
-- }}}

------------------------------------------------------------------------------
-- The scenes
------------------------------------------------------------------------------

-- {{{ scene delivery
function M.delivery(c)
    local w = world_of(c)
    local out = {}
    local a, b, cc = three_homes(c, w, true)
    out[#out + 1] = "  three homes, each its own rao-home and RAM folder, each with its port in its own mailboxes file:"
    for _, node in ipairs({ a, b, cc }) do
        out[#out + 1] = "      " .. node.name .. ": " .. node.home_path
        mailbox_lines(c, out, node)
    end
    local since = #w.world.attempts
    local t0 = w.sim.now
    local id = w.T.write(a, "to every pair at once")
    local targets = { b.pair, pair("127.0.0.4", 7604), pair("127.0.0.5", 7604) }
    local acked = ack_times(w, a, targets, 60)
    w.idle(2)
    out[#out + 1] = ""
    out[#out + 1] = "  A writes one message (id " .. id .. "); A's send list has three pairs, C holding two:"
    for _, p in ipairs(targets) do
        local t = acked[key_of(p)]
        out[#out + 1] = string.format("      to %-18s acknowledged %s after writing (test world's clock)",
            key_of(p), t and seconds(t) or "NEVER")
    end
    out[#out + 1] = string.format("  copies in each home's log: B %d, C %d (C received at both pairs and filed one)",
        w.T.holds(b, id), w.T.holds(cc, id))
    out[#out + 1] = "  connections the relay saw while it went out (each home from its own address):"
    connections_from(w, out, since)
    out[#out + 1] = "  A's delivered file (the last id each pair acknowledged):"
    file_lines(out, c.m.delivered.path(a.home, a.tag), 6)
    out[#out + 1] = "  the record in C's log file:"
    local log_text = read_all(c.m.rooms.log_path(cc.home, cc.tag)) or ""
    for line in log_text:gmatch("([^\n]*)\n") do
        if line:find(id, 1, true) then out[#out + 1] = "      " .. line end
    end
    out[#out + 1] = "  (" .. string.format("%.1f", w.sim.now - t0) .. " s on the test world's clock in all)"
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene down
function M.down(c)
    local w = world_of(c)
    local out = {}
    local a, b = three_homes(c, w)
    local listener = w.world.listeners[b.pair.address .. " " .. b.pair.port]
    listener.up = false
    out[#out + 1] = "  B stops listening.  A writes one message every 60 s; what A holds for B, read from A's"
    out[#out + 1] = "  delivered file after each (202's pile; the gatherer's due/ folder is 211's, not built):"
    out[#out + 1] = string.format("      %-10s %-14s %-12s %s", "minute", "missing for B", "attempts", "next try in")
    local ids = {}
    for minute = 1, 5 do
        ids[#ids + 1] = w.T.write(a, "while B is down, " .. minute)
        w.idle(60)
        local job = w.T.job_of(a, b.pair.address, b.pair.port)
        local due = job.timer.due and (job.timer.due - w.sim.now) or 0
        out[#out + 1] = string.format("      %-10d %-14d %-12d %s", minute,
            w.T.missing(a, b.pair.address, b.pair.port), job.attempts, seconds(math.max(0, due)))
    end
    listener.up = true
    local back = w.sim.now
    local all = w.run_until(function()
        for _, id in ipairs(ids) do if w.T.holds(b, id) ~= 1 then return false end end
        return true
    end, 900)
    out[#out + 1] = string.format("  B listens again: all %d messages in B's log %s after it came back (A's retry timer);",
        #ids, all and seconds(w.sim.now - back) or "NOT within 900 s")
    out[#out + 1] = string.format("  missing for B now: %d", w.T.missing(a, b.pair.address, b.pair.port))
    return { lines = out, gaps = { "the pile as the gatherer's due/ folder: 211 (the gatherer) is not built" } }
end
-- }}}

-- {{{ local function direct_room
-- A direct mailbox on `port` and a direct room with `token` holding the
-- other's direct pair.  → the room's tag.
local function direct_room(c, node, port, label, token, other)
    c.m.rooms.make_mailbox(node.home, { label = "direct messages", kind = "direct", port = port })
    local tag = c.m.rooms.make_room(node.home, { label = label, token = token, kind = "direct", parent = "",
        members = {}, filed_under = "", mailbox_port = "" })
    c.m.recipients.add_member(node.home, tag, other.address, other.port)
    return tag
end
-- }}}

-- {{{ scene join
function M.join(c)
    local w = world_of(c)
    local out = {}
    local a = w.home("A", { "127.0.0.2" }, 7602, { ports = { 7612 } })
    local b = w.home("B", { "127.0.0.3" }, 7603)
    w.connect({ a, b })
    w.start({ a, b })
    w.idle(20)
    local d = w.home("D", { "127.0.0.6" }, 7606, { no_room = true, ports = { 7616 } })
    local since = #w.world.attempts
    local t0 = w.sim.now
    d.tag = c.m.hello.join(d.home, d.stage, { label = "joined", token = c.T.TOKEN, kind = "group", parent = "",
        mailbox_port = 7606, pair = a.pair }, w.now())
    out[#out + 1] = "  D has the room's token and one pair, A's (" .. key_of(a.pair) .. "), and joins:"
    local added = w.run_until(function() return w.member(a, d.pair) end, 60)
    out[#out + 1] = string.format("      A added D %s after the hello; A called D back %d time(s) first",
        added and seconds(w.sim.now - t0) or "NEVER (within 60 s)", w.attempts(a.pair.address, d.pair))
    out[#out + 1] = string.format("      B learns D only from a member list (scene 6); A's list would name %d of the %d"
        .. " pairs A holds, since 207 never lists a loopback pair", #c.m.members.held(a.stage, a.tag),
        #c.m.recipients.members(a.home, a.tag))
    out[#out + 1] = "  the hello D sent states its pairs from its outside-ports file (212):"
    file_lines(out, d.home_path .. "/outside-ports", 4)
    out[#out + 1] = "  A's members file for the room (entry), after the call-back:"
    for _, member in ipairs(c.m.recipients.members(a.home, a.tag)) do
        out[#out + 1] = string.format("      %-18s heard %s", key_of(member), tostring(member.heard))
    end
    out[#out + 1] = "  connections the relay saw (D from 127.0.0.6, A calling back from 127.0.0.2):"
    connections_from(w, out, since)

    -- a direct message between A and D, sealed and filed by the same code
    local dm_token = "a direct message between A and D"
    local a_dm = direct_room(c, a, 7612, "D", dm_token, pair("127.0.0.6", 7616))
    local d_dm = direct_room(c, d, 7616, "A", dm_token, pair("127.0.0.2", 7612))
    local _, id = a.stage:write(a_dm, { kind = "message", text = "just for you, D" }, w.now())
    local got = w.run_until(function()
        for _, r in ipairs(c.m.message_log.read(d.home, d_dm)) do if r.id == id then return true end end
        return false
    end, 60)
    out[#out + 1] = string.format("  a direct message A → D on the direct mailboxes' ports (7612 → 7616): %s",
        got and "filed in D's direct room" or "NOT received")
    out[#out + 1] = "  D's log files, group room then direct room (one format, one code path):"
    file_lines(out, c.m.rooms.log_path(d.home, d.tag), 2)
    file_lines(out, c.m.rooms.log_path(d.home, d_dm), 2)
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene keys
function M.keys(c)
    local w = world_of(c)
    local out = {}
    local home = w.home("H", { "127.0.0.2" }, 7602, { no_room = true, announce = false })
    local specs = {
        { label = "house",   token = "the house's token" },
        { label = "kitchen", token = "the first kitchen's token" },
        { label = "garden",  token = "the garden's token" },
        { label = "kitchen", token = "the second kitchen's token" },
        { label = "work",    token = "the work room's token" },
    }
    -- the first room starts the mailbox on 7602; the rest are its children,
    -- so they join that mailbox (one port, one keyring)
    local house = c.m.tokens.token_fingerprint(specs[1].token)
    for i, spec in ipairs(specs) do
        c.m.rooms.make_room(home.home, { label = spec.label, token = spec.token, kind = "group",
            parent = i == 1 and "" or house, members = {}, filed_under = "", mailbox_port = i == 1 and 7602 or "" })
    end
    local ring = c.m.keyring.for_port(c.m.rooms, home.home, 7602)
    out[#out + 1] = string.format("  one home, one mailbox on port 7602, %d rooms in it (a room and its children);"
        .. " two are labelled \"kitchen\":", #specs)
    for i, entry in ipairs(ring.entries) do
        local room = c.m.rooms.read_entry(home.home, entry.room)
        out[#out + 1] = string.format("      key %d: room %s  %-10s token fingerprint %s...", i, entry.room:sub(1, 8),
            "\"" .. room.label .. "\"", c.m.tokens.token_fingerprint(room.token):sub(1, 12))
    end
    out[#out + 1] = "  a frame sealed for each room, opened by trial against the keyring (stopping at the first"
    out[#out + 1] = "  key whose check passes and whose tying value is its own):"
    out[#out + 1] = string.format("      %-28s %-20s %-12s %s", "sealed with", "opened as", "keys tried", "time")
    for i, spec in ipairs(specs) do
        local frame = c.m.seal.seal(c.m.room_key.key_pair(spec.token),
            c.m.records.encode({ kind = "message", id = "m" .. i, written = 1, target = "", text = "hello" }))
        local t = os.clock()
        local room, _, tried = c.m.keyring.open_frame(ring, frame:sub(5), 1)
        local took = (os.clock() - t) * 1e6
        local label = room and ("\"" .. c.m.rooms.read_entry(home.home, room).label .. "\" " .. room:sub(1, 8)) or "nothing"
        out[#out + 1] = string.format("      %-28s %-20s %-12d %.0f µs", spec.token, label, tried, took)
    end
    local garbage = string.rep("\170", 64)
    local t = os.clock()
    local room, _, tried = c.m.keyring.open_frame(ring, garbage, 1)
    out[#out + 1] = string.format("      %-28s %-20s %-12d %.0f µs", "no room's key (garbage)", room and "?!" or "nothing",
        tried, (os.clock() - t) * 1e6)
    local first = c.m.seal.seal(c.m.room_key.key_pair(specs[1].token), "x")
    out[#out + 1] = string.format("  the same token's frame under the other kitchen's key: %s",
        select(2, c.m.seal.open(c.m.room_key.key_pair(specs[3].token), first:sub(5))) or "opened (!)")
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene child
function M.child(c)
    local w = world_of(c)
    local out = {}
    local parent_token, child_token = "the parent room's token", "the child room's token"
    local a = w.home("A", { LISTED .. "2" }, 7602, { token = child_token })
    local b = w.home("B", { LISTED .. "3" }, 7603, { no_room = true })
    local parent = c.m.rooms.make_room(b.home, { label = "the parent", token = parent_token, kind = "group", parent = "",
        members = {}, filed_under = "", mailbox_port = 7603 })
    c.m.recipients.add_member(b.home, parent, a.pair.address, a.pair.port)
    b.tag = c.m.rooms.make_room(b.home, { label = "the child", token = child_token, kind = "group",
        parent = c.m.tokens.token_fingerprint(parent_token), members = {}, filed_under = "", mailbox_port = "" })
    w.connect({ a, b })
    w.start({ a, b })
    w.idle(20)
    local cc = w.home("C", { LISTED .. "4" }, 7604, { no_room = true })
    cc.tag = c.m.hello.join(cc.home, cc.stage, { label = "joined", token = child_token, kind = "group", parent = "",
        mailbox_port = 7604, pair = a.pair }, w.now())
    w.run_until(function() return w.member(b, cc.pair) end, 120)
    out[#out + 1] = "  (homes at " .. LISTED .. "2, .3, .4: C must reach B by a member list, which carries no loopback pair)"
    out[#out + 1] = "  B holds the parent and its child; C, a member of the child only, reaches B by A's list:"
    out[#out + 1] = "  B's flagged file for the child room:"
    file_lines(out, c.m.rooms.flagged_path(b.home, b.tag), 4)
    local function on_send_list()
        for _, p in ipairs(c.m.recipients.send_list(b.home, b.tag)) do
            if p.address == cc.pair.address and p.port == cc.pair.port then return true end
        end
        return false
    end
    local id = w.T.write(b, "to the child room, before approving")
    w.idle(60)
    out[#out + 1] = string.format("  C on B's send list: %s; B's message reached C: %d copies",
        tostring(on_send_list()), w.T.holds(cc, id))
    c.m.recipients.approve(b.home, b.tag, cc.pair.address, cc.pair.port)
    out[#out + 1] = "  B approves C; the flagged file now:"
    file_lines(out, c.m.rooms.flagged_path(b.home, b.tag), 4)
    local id2 = w.T.write(b, "to the child room, after approving")
    w.run_until(function() return w.T.holds(cc, id2) == 1 end, 60)
    out[#out + 1] = string.format("  C on B's send list: %s; B's next message reached C: %d copy",
        tostring(on_send_list()), w.T.holds(cc, id2))
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene syncing
function M.syncing(c)
    local w = world_of(c)
    local out = {}
    local seen = {}
    local real = c.m.members.answer
    c.m.members.answer = function(stage, tag, record, peer, at)
        seen[#seen + 1] = { at = stage.home.dir, kind = record.kind }
        return real(stage, tag, record, peer, at)
    end
    local ok, problem = pcall(function()
        -- first on loopback, as the other scenes: what A's list would carry
        local la, lb, lc = three_homes(c, w)
        out[#out + 1] = string.format("  on loopback (A, B, C at 127.0.0.2, .3, .4): A holds %d members; its member list"
            .. " would name %d (207 never lists a loopback pair), so here a newcomer is reached only by call-back",
            #c.m.recipients.members(la.home, la.tag), #c.m.members.held(la.stage, la.tag))
        local _ = lb, lc
        w = world_of(c)
        seen = {}
        out[#out + 1] = "  the same with documentation addresses (" .. LISTED .. "2, .3, .4, .7; in the relay only):"
        local a = w.home("A", { LISTED .. "2" }, 7602)
        local b = w.home("B", { LISTED .. "3" }, 7603)
        local e_pair = pair(LISTED .. "7", 7607)
        c.m.ignore.ignore(b.home, e_pair.address, e_pair.port, "hide", "*", w.now())
        w.connect({ a, b })
        w.start({ a, b })
        w.idle(20)
        local t0 = w.sim.now
        local cc = w.home("C", { LISTED .. "4" }, 7604, { no_room = true })
        cc.tag = c.m.hello.join(cc.home, cc.stage, { label = "joined", token = c.T.TOKEN, kind = "group", parent = "",
            mailbox_port = 7604, pair = a.pair }, w.now())
        w.run_until(function() return w.member(b, cc.pair) and w.member(cc, b.pair) end, 120)
        out[#out + 1] = "  C joins through A.  The members frames each home answered, in order:"
        local names = { [a.home.dir] = "A", [b.home.dir] = "B", [cc.home.dir] = "C" }
        for _, s in ipairs(seen) do out[#out + 1] = "      " .. (names[s.at] or "?") .. " answered a " .. s.kind end
        out[#out + 1] = string.format("  B holds C: %s, C holds B: %s, %s after C's hello; B called C back %d time(s)",
            tostring(w.member(b, cc.pair)), tostring(w.member(cc, b.pair)), seconds(w.sim.now - t0),
            w.attempts(b.pair.address, cc.pair))
        -- an ignored pair, on A's list
        local e = w.home("E", { e_pair.address }, e_pair.port)
        c.m.recipients.add_member(a.home, a.tag, e_pair.address, e_pair.port)
        c.m.members.vouch(a.home, a.tag, e_pair, string.rep("7e", 16), w.now())
        a.stage:notice_members(a.tag, w.now())
        w.idle(120)
        out[#out + 1] = string.format("  A's list now names E (%s), which B ignores: B holds E: %s, B called E back %d time(s)",
            key_of(e_pair), tostring(w.member(b, e_pair)), w.attempts(b.pair.address, e_pair))
        -- a replayed list after a leave
        local recorded = c.m.records.decode(c.m.records.encode(c.m.members.list_record(b.stage, b.tag, w.now())))
        w.sim.now = w.sim.now + 2
        cc.stage:leave(cc.tag, w.now())
        w.run_until(function() return not w.member(a, cc.pair) end, 60)
        local reply = c.m.members.answer(a.stage, a.tag, recorded, { host = LISTED .. "9", port = 40999 }, w.now())
        w.idle(60)
        out[#out + 1] = string.format("  C leaves; B's list from before the leave is replayed to A: A answers %s, A holds C: %s",
            reply.kind, tostring(w.member(a, cc.pair)))
        out[#out + 1] = "  A's left file:"
        file_lines(out, c.m.leaving.path(a.home, a.tag), 3)
        local _ = e
    end)
    c.m.members.answer = real
    if not ok then error(problem, 0) end
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene token
function M.token(c)
    local w = world_of(c)
    local out = {}
    local a = w.home("A", { "127.0.0.2" }, 7602, { ports = { 7612 } })
    local b = w.home("B", { "127.0.0.3" }, 7603, { ports = { 7613 } })
    local cc = w.home("C", { "127.0.0.4" }, 7604)
    w.connect({ a, b, cc })
    w.start({ a, b, cc })
    w.idle(20)
    local before = w.T.write(a, "said while C could still read the room")
    w.run_until(function() return w.T.holds(cc, before) == 1 and w.T.holds(b, before) == 1 end, 60)
    local function count(node) return #c.m.message_log.read(node.home, node.tag) end
    local old_fp = c.m.tokens.token_fingerprint(c.m.rooms.read_entry(a.home, a.tag).token)
    local a_dm = direct_room(c, a, 7612, "B", "A and B's direct token", pair("127.0.0.3", 7613))
    local b_dm = direct_room(c, b, 7613, "A", "A and B's direct token", pair("127.0.0.2", 7612))
    local new_token = "the room's new token, given by hand"
    local records_before = count(a)
    c.m.rooms.change_token(a.home, a.tag, new_token)
    out[#out + 1] = "  A changes the room's token by hand, to shut C out:"
    out[#out + 1] = string.format("      fingerprint %s... → %s...; the room's folder, label, members and log stay",
        old_fp:sub(1, 12), c.m.tokens.token_fingerprint(new_token):sub(1, 12))
    out[#out + 1] = string.format("      records in A's log before and after the change: %d and %d", records_before, count(a))
    local _, dm_id = a.stage:write(a_dm, { kind = "message", text = "the new token is: " .. new_token }, w.now())
    local got = w.run_until(function()
        for _, r in ipairs(c.m.message_log.read(b.home, b_dm)) do if r.id == dm_id then return true end end
        return false
    end, 60)
    out[#out + 1] = "  A gives the new token to B by direct message; in B's direct room's log:"
    for _, r in ipairs(c.m.message_log.read(b.home, b_dm)) do
        if r.id == dm_id then out[#out + 1] = "      \"" .. r.text .. "\"" end
    end
    if got then
        -- B's person reads it and types it in
        local typed
        for _, r in ipairs(c.m.message_log.read(b.home, b_dm)) do
            if r.id == dm_id then typed = r.text:match("^the new token is: (.*)$") end
        end
        c.m.rooms.change_token(b.home, b.tag, typed)
    end
    local after = w.T.write(a, "said after the change")
    w.run_until(function() return w.T.holds(b, after) == 1 end, 60)
    w.idle(60)
    out[#out + 1] = string.format("  A's next message: B holds %d, C holds %d (C still holds the old token)",
        w.T.holds(b, after), w.T.holds(cc, after))
    out[#out + 1] = string.format("  A still owes C %d record(s), retried, because C cannot open what it is sent",
        w.T.missing(a, cc.pair.address, cc.pair.port))
    out[#out + 1] = string.format("  history kept: B's log holds the message from before the change: %d copy, and %d records in all",
        w.T.holds(b, before), count(b))
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene leaving
function M.leaving(c)
    local w = world_of(c)
    local out = {}
    local a = w.home("A", { "127.0.0.2" }, 7602)
    local b = w.home("B", { "127.0.0.3" }, 7603)
    w.connect({ a, b })
    w.start({ a, b })
    local id = w.T.write(b, "before anyone leaves")
    w.run_until(function() return w.T.holds(a, id) == 1 end, 60)
    w.idle(5)
    -- a forged leave first: C claims A's pair is leaving
    local cc = w.home("C", { "127.0.0.4" }, 7604)
    c.m.recipients.add_member(cc.home, cc.tag, b.pair.address, b.pair.port)
    cc.stage.seams.own_pairs = function() return { { kind = "public", address = a.pair.address, port = a.pair.port } } end
    local forged = cc.stage:leave(cc.tag, w.now())[1]
    w.run_until(function() return forged.done end, 60)
    w.idle(60)
    out[#out + 1] = string.format("  C, holding the token, sends B a leave naming A's pair (%s):", key_of(a.pair))
    out[#out + 1] = string.format("      B called A back %d time(s); A answered no; B still holds A: %s; B's left file:",
        w.attempts(b.pair.address, a.pair), tostring(w.member(b, a.pair)))
    file_lines(out, c.m.leaving.path(b.home, b.tag), 3)
    -- a genuine leave
    w.sim.now = w.sim.now + 2
    local job = a.stage:leave(a.tag, w.now())[1]
    local t0 = w.sim.now
    w.run_until(function() return not w.member(b, a.pair) end, 60)
    out[#out + 1] = string.format("  A leaves: B removed A %s later (after calling back: %d calls to A in all); the leave acknowledged: %s",
        seconds(w.sim.now - t0), w.attempts(b.pair.address, a.pair), tostring(job.done))
    out[#out + 1] = "  B's left file:"
    file_lines(out, c.m.leaving.path(b.home, b.tag), 3)
    out[#out + 1] = "  B's delivered file (A's line dropped):"
    file_lines(out, c.m.delivered.path(b.home, b.tag), 3)
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene crosscheck
function M.crosscheck(c)
    local w = world_of(c)
    local out = {}
    local a, b, cc = three_homes(c, w)
    local function append(node, from, id, text, written, arrived)
        c.m.message_log.append(node.home, node.tag, { id = id, from = from.address .. " " .. from.port,
            written = written, arrived = arrived or written, text = text })
    end
    local function round(node)
        local jobs = node.stage:crosscheck_round(w.now())
        w.run_until(function()
            for _, job in ipairs(jobs) do if not job.done then return false end end
            return true
        end, 60)
        return jobs
    end
    local t = w.now()
    append(b, a.pair, "honest1", "the same words", t - 50, t - 49)
    append(cc, a.pair, "honest1", "the same words", t - 50, t - 40)
    append(b, a.pair, "twofaced", "X, for B", t - 30)
    append(cc, a.pair, "twofaced", "Y, for C", t - 30)
    out[#out + 1] = "  A's pair sent one id with two texts: \"X, for B\" to B and \"Y, for C\" to C.  B runs its cross-check:"
    round(b)
    w.idle(10)
    for _, node in ipairs({ b, cc }) do
        local list = node.stage.conflicts or {}
        out[#out + 1] = string.format("      %s raised %d discrepancy(ies); its conflicts file:", node.name, #list)
        file_lines(out, c.m.crosscheck.conflicts_path(node.home, node.tag), 4)
    end
    -- a gap filled with the original id
    local id = w.T.write(a, "the gap")
    w.run_until(function() return w.T.holds(b, id) == 1 end, 60)
    w.idle(5)
    local path = c.m.rooms.log_path(b.home, b.tag)
    local kept = {}
    for line in (read_all(path) or ""):gmatch("[^\n]*\n") do
        if not line:find(id, 1, true) then kept[#kept + 1] = line end
    end
    c.m.disk.write_atomic(path, table.concat(kept))
    c.m.message_log.forget_remembered_ids(path)
    out[#out + 1] = string.format("  A's message %s is removed from B's log by hand (B holds %d); B's next round:", id, w.T.holds(b, id))
    local t0 = w.sim.now
    round(b)
    w.run_until(function() return w.T.holds(b, id) == 1 end, 120)
    out[#out + 1] = string.format("      B holds it again %s later, with the same id: %s", seconds(w.sim.now - t0),
        tostring(w.T.holds(b, id) == 1))
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene housemates
function M.housemates(c)
    local w = world_of(c)
    local out = {}
    local public, router = "203.0.113.5", "192.168.1.1"
    local networks = { { network = "192.168.1.0", bits = 24, iface = "eth0" } }
    local a_home, b_home = pair("192.168.1.10", 7602), pair("192.168.1.20", 41000)
    local function at_home(name, home)
        local node = c.T.new_node(name, { public, home.address }, home.port, { announce = true, lan = "home",
            private = home.address, networks = networks })
        node.pair = pair(public, home.port)
        return node
    end
    local a, b = at_home("A", a_home), at_home("B", b_home)
    w.world.refuse = function(from, p) return from:match("^192%.168%.1%.") ~= nil and p.address == public end
    c.m.recipients.add_member(a.home, a.tag, public, b_home.port)
    c.m.recipients.add_member(b.home, b.tag, public, a_home.port)
    out[#out + 1] = "  A and B behind one router (public " .. public .. ") that cannot loop a connection back in;"
    out[#out + 1] = "  each holds the other by its public pair.  (The home network here is the test world's: nothing"
    out[#out + 1] = "  is sent on a real network.)"
    local first = w.T.write(a, "before searching")
    w.idle(60)
    out[#out + 1] = string.format("  before searching: A's message reached B: %d copies", w.T.holds(b, first))
    local sent_before = #w.world.datagrams
    a.housemates:start(w.now())
    local t0 = w.sim.now
    local found = w.run_until(function()
        local function kept(node, p)
            for _, e in ipairs(node.housemates:list(node.tag)) do
                if e.home.address == p.address and e.home.port == p.port then return true end
            end
        end
        return kept(a, b_home) and kept(b, a_home)
    end, 60)
    out[#out + 1] = string.format("  A searches: %d datagram(s) sent (to the multicast group, time-to-live 1, and the /24); each",
        #w.world.datagrams - sent_before)
    out[#out + 1] = string.format("  keeps the other %s: %s later", found and "as a housemate" or "NOT", seconds(w.sim.now - t0))
    out[#out + 1] = "  A's housemates file in its RAM folder:"
    for _, path in ipairs(shell("find " .. quote(a.ram) .. " -name 'housemates*' -type f")) do file_lines(out, path, 3) end
    out[#out + 1] = string.format("  A routes B's public pair %s to %s", public .. ":" .. b_home.port,
        key_of(a.housemates:route(pair(public, b_home.port))))
    w.T.write(a, "through the house")
    w.run_until(function() return w.T.holds(b, first) == 1 end, 600)
    out[#out + 1] = string.format("  the waiting message reached B through the home network: %d copy; connections A → B's home pair: %d",
        w.T.holds(b, first), w.attempts(a_home.address, b_home))
    return { lines = out, gaps = {} }
end
-- }}}

-- {{{ scene failed
function M.failed(c)
    local w = world_of(c)
    local out, gaps = {}, {}
    local a = w.home("A", { "127.0.0.2" }, 7602, { announce = false })
    local folder = a.ram .. "/mailbox-7602"
    os.execute("mkdir -p " .. quote(folder))
    local log = c.m.fd.open(folder, 4096, 3)
    local ring = c.m.keyring.for_port(c.m.rooms, a.home, 7602)
    local function stand_in(bytes)
        local conn = { at = 1 }
        function conn:receive(n)
            local piece = bytes:sub(self.at, self.at + n - 1)
            self.at = self.at + #piece
            if #piece < n then return nil, "closed", piece end
            return piece
        end
        function conn:send(_, _, j) return j end
        function conn:close() end
        function conn:settimeout() end
        return conn
    end
    local senders = { { "127.0.0.66", 50001 }, { "127.0.0.66", 50002 }, { "127.0.0.67", 50003 } }
    for i, s in ipairs(senders) do
        local seams = c.m.fd.seams(log, 7602, function() return 1793878367 + i end)
        seams.peer = { host = s[1], port = s[2] }
        seams.ring = function() return ring end
        seams.now = function() return 1793878367 + i end
        seams.home = a.home
        c.m.receive.serve(stand_in(c.m.seal.uint32_be(40) .. string.rep("\170", 40)), seams)
    end
    local seams = c.m.fd.seams(log, 7602, function() return 1793878400 end)
    seams.peer, seams.ring = { host = "127.0.0.68", port = 50004 }, function() return ring end
    seams.now, seams.home = function() return 1793878400 end, a.home
    c.m.receive.serve(stand_in(c.m.seal.uint32_be(0x7fffffff)), seams)
    log:close()
    out[#out + 1] = "  three garbage frames and one impossible length sent to A's port 7602; A's RAM folder now:"
    local files = shell("ls -l " .. quote(folder))
    for _, line in ipairs(files) do out[#out + 1] = "      " .. line end
    local logged = shell("ls " .. quote(folder) .. "/*")
    for _, path in ipairs(logged) do
        out[#out + 1] = "    " .. path:match("[^/]*$") .. ":"
        file_lines(out, path, 6)
    end
    local filter = c.dir .. "/docs/fail2ban/rao-chat-failed-decryption.conf"
    local where = shell("command -v fail2ban-regex")[1]
    if where and where ~= "" then
        out[#out + 1] = "  fail2ban-regex with the shipped filter:"
        for _, path in ipairs(logged) do
            for _, line in ipairs(shell("fail2ban-regex " .. quote(path) .. " " .. quote(filter))) do
                if line:match("[Mm]atched") or line:match("Lines:") then out[#out + 1] = "      " .. line end
            end
        end
    else
        gaps[#gaps + 1] = "fail2ban-regex: not installed here, so the filter was not run by fail2ban itself"
        out[#out + 1] = "  fail2ban-regex is not installed here.  The shipped filter's failregex, expanded as fail2ban"
        out[#out + 1] = "  documents <HOST>, applied by Python to each line (the stand-in 140's referee uses):"
        local script = c.scratch .. "/stand-in.py"
        local f = assert(io.open(script, "w"))
        f:write([[
import re, sys
conf = open(sys.argv[1]).read()
regex = re.search(r'^failregex\s*=\s*(.+)$', conf, re.M).group(1).strip()
regex = regex.replace('<HOST>', r'(?:::f{4,6}:)?(?P<host>[\w\-.^_]*\w)')
pattern = re.compile(regex)
for path in sys.argv[2:]:
    for line in open(path).read().split('\n'):
        if line:
            m = pattern.search(line)
            print((m.group('host') if m else 'NO MATCH') + '   <- ' + line[:60])
]])
        f:close()
        local paths = {}
        for _, path in ipairs(logged) do paths[#paths + 1] = quote(path) end
        for _, line in ipairs(shell("python3 -I " .. quote(script) .. " " .. quote(filter) .. " " .. table.concat(paths, " "))) do
            out[#out + 1] = "      " .. line
        end
    end
    return { lines = out, gaps = gaps }
end
-- }}}

-- Scenes whose issues are not built: what each waits on.
M.signatures = { waits = "214 (signatures read from each message's text by one rule) is not built" }
M.git = { waits = "215, 215a and 215b (one git repository per mailbox: text copies, the running log, "
    .. "the shared upstream) are not built" }
M.acknowledge = { waits = "211 (the gatherer, whose gatherer.acknowledge-after switch this is) is not built" }

-- {{{ scene phase1
function M.phase1(c)
    local w = world_of(c)
    local out = {}
    local a = w.home("A", { "127.0.0.2" }, 7602, { ports = { 7612 }, token = "the family's token" })
    c.m.rooms.write_label(a.home, a.tag, "family")
    local kitchen = c.m.rooms.make_room(a.home, { label = "kitchen", token = "the kitchen's token", kind = "group",
        parent = c.m.tokens.token_fingerprint("the family's token"), members = {}, filed_under = "", mailbox_port = "" })
    c.m.recipients.add_member(a.home, a.tag, "127.0.0.3", 7603)
    c.m.recipients.add_member(a.home, kitchen, "127.0.0.3", 7603)
    direct_room(c, a, 7612, "bea", "A and bea's direct token", pair("127.0.0.3", 7613))
    c.m.recipients.add_member(a.home, (function()
        for _, tag in ipairs(c.m.rooms.list_rooms_by_kind(a.home, "direct")) do return tag end
    end)(), "127.0.0.3", 7603)
    out[#out + 1] = "  home A (" .. a.home_path .. "), with phase 2's rooms, through phase 1's tools:"
    out[#out + 1] = "  people/ (104):"
    for _, line in ipairs(shell("cd " .. quote(a.home_path) .. " && find people -mindepth 1 | sort")) do
        out[#out + 1] = "      " .. line
    end
    out[#out + 1] = "  the tree of rooms (102):"
    for line in c.m.forest_text.text(c.m.tree.forest(a.home)):gmatch("([^\n]*)\n?") do
        if line ~= "" then out[#out + 1] = "      " .. line end
    end
    out[#out + 1] = "  the tally of choices still open (106's scripts/tally-options), its last lines:"
    local tally = shell("cd /tmp && luajit " .. quote(c.dir .. "/scripts/tally-options") .. " " .. quote(c.dir))
    for i = math.max(1, #tally - 3), #tally do out[#out + 1] = "      " .. tally[i] end
    return { lines = out, gaps = {} }
end
-- }}}

M.RULE = RULE
return M
