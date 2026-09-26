-- 102-demo-probes.lua — the demo's measuring tools: reading what is really on disk.
--
-- The phase 1 demo shows figures, not descriptions: the actual folder
-- listings, the actual links, the actual bytes in each file, and how long
-- things took.  This file holds the small instruments that take those
-- readings — list a folder, follow a link, weigh a file, time a step — and
-- the one tool that clears a scratch folder before a scene is built in it.
--
-- Nothing here knows about rooms or messages; it only looks at files.  The
-- listings come from running the ordinary `find` command, so what the demo
-- prints is exactly what a person would see typing the same thing.

local ffi = require("ffi")

local probes = {}

ffi.cdef([[
    typedef struct { long tv_sec; long tv_nsec; } rao_demo_timespec;
    int clock_gettime(int clock_id, rao_demo_timespec *tp);
]])
-- CLOCK_MONOTONIC on Linux: a clock that only moves forward, unaffected by
-- the wall clock being set, so a timing is never negative.
local CLOCK_MONOTONIC = 1

-- {{{ function probes.now
-- Seconds (a float with nanosecond resolution) on the monotonic clock.  Only
-- differences between two readings mean anything.
function probes.now()
    local reading = ffi.new("rao_demo_timespec")
    if ffi.C.clock_gettime(CLOCK_MONOTONIC, reading) ~= 0 then
        -- the clock refused: a timing would be made up, so stop
        error("demo-probes: clock_gettime failed")
    end
    -- (the clock answered: turn it into seconds)
    return tonumber(reading.tv_sec) + tonumber(reading.tv_nsec) / 1e9
end
-- }}}

-- {{{ function probes.run
-- Runs a shell command; gives its whole output (stdout and stderr together,
-- so a complaint from the command is shown rather than lost) and whether it
-- exited cleanly (bool).
function probes.run(command)
    local pipe = io.popen(command .. ' 2>&1; printf "\\n%d" "$?"')
    local output = pipe:read("*a")
    pipe:close()
    local body, status = output:match("^(.*)\n(%d+)$")
    return body, status == "0"
end
-- }}}

-- {{{ function probes.must_run
-- As probes.run, but a failing command stops the demo with its output.
function probes.must_run(command)
    local output, clean = probes.run(command)
    if not clean then
        -- the command failed: a listing would be wrong or empty, so stop
        error("demo-probes: command failed: " .. command .. "\n" .. output)
    end
    -- (it worked: hand back what it printed)
    return output
end
-- }}}

-- {{{ local function quote
-- Single-quotes a path for the shell; a path holding a single quote is
-- refused rather than escaped, since no demo path should ever hold one.
local function quote(path)
    if path:find("'", 1, true) then
        -- would need escaping: the path is not one the demo made
        error("demo-probes: refusing a path with a quote in it: " .. path)
    end
    -- (a plain path: wrap it)
    return "'" .. path .. "'"
end
-- }}}

-- {{{ function probes.lines
-- Splits text into a list of lines (a trailing line break adds no empty line).
function probes.lines(text)
    local list = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
        list[#list + 1] = line
    end
    if list[#list] == "" then
        -- the text ended with a line break: drop the empty piece after it
        list[#list] = nil
    end
    -- (otherwise the last piece is a real line)
    return list
end
-- }}}

-- {{{ function probes.files_with_sizes
-- Every regular file under `dir`, as "path-inside-dir  N bytes" lines,
-- sorted.  `find -printf` gives the size the file system reports.
function probes.files_with_sizes(dir)
    local output = probes.must_run("cd " .. quote(dir) .. " && find . -type f -printf '%P  %s bytes\\n' | sort")
    return probes.lines(output)
end
-- }}}

-- {{{ function probes.links_with_targets
-- Every symbolic link under `dir`, as "path -> target" lines, sorted.  The
-- target is the link's text exactly as stored (these are relative links).
function probes.links_with_targets(dir)
    local output = probes.must_run("cd " .. quote(dir) .. " && find . -type l -printf '%P -> %l\\n' | sort")
    return probes.lines(output)
end
-- }}}

-- {{{ function probes.entries
-- The names directly inside `dir`, sorted, one per line (like `ls -1`).
function probes.entries(dir)
    return probes.lines(probes.must_run("ls -1 " .. quote(dir)))
end
-- }}}

-- {{{ function probes.link_resolves
-- True when the link at `path` leads to something that exists.
function probes.link_resolves(path)
    local _, clean = probes.run("test -e " .. quote(path))
    return clean
end
-- }}}

-- {{{ function probes.read_text
-- The whole content of a file.  A missing file is an error, not "".
function probes.read_text(path)
    local file = io.open(path, "rb")
    if not file then
        -- nothing there: the scene was not built as the demo expects
        error("demo-probes: cannot read " .. path)
    end
    -- (opened: read it all)
    local text = file:read("*a")
    file:close()
    return text
end
-- }}}

-- {{{ function probes.write_text
function probes.write_text(path, text)
    local file = io.open(path, "wb")
    if not file then
        -- cannot write: say where
        error("demo-probes: cannot write " .. path)
    end
    -- (opened: write it)
    file:write(text)
    file:close()
end
-- }}}

-- {{{ function probes.bytes
-- The size of one file in bytes (integer).
function probes.bytes(path)
    local file = io.open(path, "rb")
    if not file then
        -- nothing there to weigh
        error("demo-probes: cannot weigh " .. path)
    end
    -- (opened: its end is its size)
    local size = file:seek("end")
    file:close()
    return size
end
-- }}}

-- {{{ function probes.fresh_dir
-- Empties and recreates a scratch folder for one scene.  Only folders under
-- `scratch_root` (the demo's own space in tmp/shared-memory) may be cleared:
-- a path anywhere else is refused, so a mistake can never empty a real home.
function probes.fresh_dir(scratch_root, path)
    if path:sub(1, #scratch_root + 1) ~= scratch_root .. "/" then
        -- outside the demo's space: never delete it
        error("demo-probes: refusing to clear " .. path .. " (not under " .. scratch_root .. ")")
    end
    -- (inside the demo's space: safe to clear)
    probes.must_run("rm -rf " .. quote(path) .. " && mkdir -p " .. quote(path))
    return path
end
-- }}}

return probes
