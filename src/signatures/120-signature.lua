-- 120-signature.lua — reads a message's signature out of its text, by the
-- one rule every reader of rao-chat messages must follow (issue 214).
--
-- The sender of a message is unknowable by design; the signature is what a
-- message says about itself.  It is never stored apart: the log keeps the
-- text exactly as written (105), and the signature is worked out from it
-- each time it is shown or copied, by this function (the text copies, 215;
-- the viewer's inbox, 301).  The owner's rule (2026-09-27):
--
--   1. Split the text at its last blank line (two line breaks in a row).
--   2. If the part after it is exactly one line of at most 80 characters,
--      and not empty, that line is the signature and the part before is
--      the body.
--   3. Otherwise the whole text is the body, and the signature is the last
--      word of the body (the last run of characters that are not spaces,
--      tabs or line breaks).
--
-- Settled here, where the rule left a choice (issue 214's decisions):
--
--   - A line break is "\n"; "\r\n" (a browser's) reads as "\n" first.  A
--     lone "\r" is an ordinary character.
--   - Line breaks at the very end of the text are not a line: they are
--     set aside before the rule runs, so "hi\n\nsorelu\n" (a file's last
--     newline) is signed "sorelu" the same as "hi\n\nsorelu".
--   - The body never ends with the line breaks that came before the split:
--     "hi\n\n\nsorelu" is body "hi", signature "sorelu".
--   - The 80 is counted in characters (Unicode code points, read from
--     UTF-8), not bytes.  A byte that is not part of a well-formed UTF-8
--     character counts as one character.
--   - A last line of only spaces and tabs is empty: not a signature.
--   - The last word keeps its punctuation ("sorelu." stays "sorelu.").
--   - A text with no word at all (empty, or only spaces and line breaks)
--     has no signature: "".
--
-- Every implementation (Lua here; the phone's Kotlin and the web page's
-- JavaScript when they come) is graded by the same table of examples,
-- 121-signature-examples.tsv beside this file.

local M = {}

M.LONGEST = 80          -- characters a signature line may hold

-- {{{ function M.characters
-- How many characters (code points) a string holds when read as UTF-8.  A
-- well-formed character of 1 to 4 bytes is one; any byte that does not
-- start or finish a well-formed character is one on its own, so a run of
-- bad bytes can never pass for a short line.
function M.characters(text)
    local count, at, size = 0, 1, #text
    while at <= size do
        local byte = text:byte(at)
        local length = 1
        -- Path: a lead byte of a 2-, 3- or 4-byte character — check that its
        -- continuation bytes (0x80-0xBF) are all there, and that it isn't an
        -- overlong or out-of-range spelling.  Anything else is one byte.
        if byte >= 0xC2 and byte <= 0xDF then
            length = 2
        elseif byte >= 0xE0 and byte <= 0xEF then
            length = 3
        elseif byte >= 0xF0 and byte <= 0xF4 then
            length = 4
        end
        if length > 1 then
            local whole = at + length - 1 <= size
            for k = at + 1, at + length - 1 do
                local next_byte = whole and text:byte(k)
                if not next_byte or next_byte < 0x80 or next_byte > 0xBF then
                    whole = false
                    break
                end
            end
            -- the second byte's narrower ranges: no overlong 3- or 4-byte
            -- spellings, no surrogates, nothing past U+10FFFF
            if whole then
                local second = text:byte(at + 1)
                if (byte == 0xE0 and second < 0xA0) or (byte == 0xED and second > 0x9F)
                   or (byte == 0xF0 and second < 0x90) or (byte == 0xF4 and second > 0x8F) then
                    whole = false
                end
            end
            if not whole then length = 1 end
        end
        count = count + 1
        at = at + length
    end
    return count
end
-- }}}

-- {{{ function M.last_word
-- The last run of characters that are not spaces, tabs or line breaks; ""
-- when there is none.
function M.last_word(text)
    return text:match("([^ \t\n\r]+)[ \t\n\r]*$") or ""
end
-- }}}

-- {{{ function M.read
-- text: a message's text as written.  Gives body (string), signature
-- (string, "" when there is none) and how it was found: "line" (the last
-- line after a blank line), "last-word" or "none".
function M.read(text)
    text = text:gsub("\r\n", "\n"):gsub("\n+$", "")
    -- the last blank line: the last place two line breaks stand together
    local split
    local from = 1
    while true do
        local at = text:find("\n\n", from, true)
        if not at then break end
        split = at
        from = at + 1
    end
    -- Path: a blank line, and after it one non-empty line short enough —
    -- that line signs the message.  Anything else — the last word does.
    if split then
        local after = text:sub(split + 2)
        if after ~= "" and not after:find("\n", 1, true) and after:find("[^ \t]")
           and M.characters(after) <= M.LONGEST then
            local body = text:sub(1, split - 1):gsub("\n+$", "")
            return body, after, "line"
        end
    end
    local word = M.last_word(text)
    if word == "" then
        return text, "", "none"
    end
    return text, word, "last-word"
end
-- }}}

return M
