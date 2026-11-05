-- 169-signature.lua — a message's signature, read from its text by the
-- owner's one rule (issue 214, steps 1 and 2; built with 215, whose text
-- copies carry a `signature:` line).
--
-- The owner (2026-09-27): "body text, newline newline, signature. If the
-- signature is longer than one line, then it is the body text still, and
-- the last word is used."  "last line over 80 characters is a body text,
-- not a signature. Use the last word of the body text as the signature if
-- there's no signature."
--
--   1. Line breaks are read as "\n": a "\r\n" (a browser's) is first
--      turned into "\n".
--   2. The text is split at its last blank line: the last run of two or
--      more line breaks.
--   3. If the part after it is exactly one line, not empty, of at most 80
--      characters, that line is the signature and the part before is the
--      body.  One line break at the very end is allowed (and is not part
--      of the signature): a text file's last line ends with one.
--   4. Otherwise the whole text is the body and the signature is the last
--      word of the body: the last run of characters that are not spaces,
--      tabs or line breaks.  A text with no word has the signature "".
--
-- "Characters" are Unicode code points, counted in the UTF-8 the text is
-- stored in (every byte that does not continue a character starts one), so
-- a signature in a script whose letters take three bytes keeps its place
-- (214's open question 1, decided 2026-11-05).
--
-- Read, never stored apart: every reader calls `read` (the text copies of
-- 215 now; the viewer's inbox, 301, later).  The examples every
-- implementation is graded by are 170-signature-examples.txt, read by
-- `examples`.

local M = {}

M.MOST_CHARACTERS = 80

-- {{{ function M.characters
-- text → how many code points it holds (bytes that are not 10xxxxxx).
function M.characters(text)
    local _, continuing = text:gsub("[\128-\191]", "")
    return #text - continuing
end
-- }}}

-- {{{ local function last_word
local function last_word(text)
    return text:match("([^ \t\r\n]+)[ \t\r\n]*$") or ""
end
-- }}}

-- {{{ local function split_at_last_blank
-- text → the part before the last run of two or more "\n" and the part
-- after it, or nil when there is no blank line.  `first` (a broken
-- version for the referees) splits at the first run instead.
local function split_at_last_blank(text, first)
    local start, stop
    local from = 1
    while true do
        local s, e = text:find("\n\n+", from)
        if not s then break end
        start, stop = s, e
        if first then break end
        from = e + 1
    end
    if not start then return nil end
    return text:sub(1, start - 1), text:sub(stop + 1)
end
-- }}}

-- {{{ function M.read
-- text (string, as written) → body, signature (strings).
-- broken (referees only): "bytes" counts bytes for the 80, "first-blank"
-- splits at the first blank line.
function M.read(text, broken)
    text = text:gsub("\r\n", "\n")
    local before, after = split_at_last_blank(text, broken == "first-blank")
    if before then
        local line = after:gsub("\n$", "", 1)
        local length = broken == "bytes" and #line or M.characters(line)
        if line ~= "" and not line:find("\n", 1, true) and length <= M.MOST_CHARACTERS then
            return before, line
        end
    end
    return text, last_word(text)
end
-- }}}

-- {{{ function M.signature
function M.signature(text)
    local _, signature = M.read(text)
    return signature
end
-- }}}

-- {{{ local function unescape
local function unescape(field)
    return (field:gsub("\\(.)", { n = "\n", r = "\r", t = "\t", ["\\"] = "\\" }))
end
-- }}}

-- {{{ function M.examples
-- path (optional; the table beside this file) → list of
-- {text, body, signature, line}.  The file: one example per line, three
-- fields separated by tabs, "\n", "\r", "\t" and "\\" written escaped
-- (083's tsv escapes); lines starting with "#" and empty lines are notes.
function M.examples(path)
    if not path then
        local here = debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")
        path = here .. "/170-signature-examples.txt"
    end
    local handle = assert(io.open(path, "rb"))
    local list, n = {}, 0
    for line in handle:lines() do
        n = n + 1
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local text, body, signature = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)$")
            if not text then
                handle:close()
                error(path .. ":" .. n .. ": an example is three fields separated by tabs", 0)
            end
            list[#list + 1] = { text = unescape(text), body = unescape(body), signature = unescape(signature), line = n }
        end
    end
    handle:close()
    return list
end
-- }}}

return M
