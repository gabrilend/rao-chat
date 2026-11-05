-- 171-test-signature.lua — issue 214's referees: every example in
-- 170-signature-examples.txt read by 169's rule, and the two broken
-- readers the table must catch (counting bytes; splitting at the first
-- blank line).
--
-- Run: luajit src/signature/tests/171-test-signature.lua [PROJECT_DIR]
-- Prints PASS/FAIL per check, then "counts <passed> <failed>".

local DIR = arg[1]
if not DIR or DIR == "" then
    local source = debug.getinfo(1, "S").source:gsub("^@", "")
    if source:sub(1, 1) ~= "/" then source = os.getenv("PWD") .. "/" .. source end
    DIR = source:match("^(.*)/src/signature/tests/[^/]+$")
end
dofile(DIR .. "/src/room-folders/001-load-path.lua")(DIR)
local signature = require("169-signature")

local passed, failed = 0, 0
local function check(claim, ok, detail)
    if ok then passed = passed + 1; print("PASS " .. claim)
    else failed = failed + 1; print("FAIL " .. claim .. (detail and (": " .. detail) or "")) end
end

-- {{{ local function grade
-- broken → how many examples the reader gets wrong, and the first one.
local function grade(broken)
    local wrong, first = 0, nil
    for _, e in ipairs(signature.examples()) do
        local body, sig = signature.read(e.text, broken)
        if body ~= e.body or sig ~= e.signature then
            wrong = wrong + 1
            first = first or string.format("line %d: got body %q, signature %q", e.line, body, sig)
        end
    end
    return wrong, first
end
-- }}}

local examples = signature.examples()
check("the table has every referee of 214 and the decided cases (at least 15 rows)", #examples >= 15, #examples .. " rows")
local wrong, first = grade(nil)
check("every example reads as the table says", wrong == 0, first)
for _, broken in ipairs({ "bytes", "first-blank" }) do
    local w, f = grade(broken)
    check("the table catches the broken reader '" .. broken .. "'", w > 0, "it passed every row")
    if w > 0 then print("     caught: " .. f) end
end
check("characters are code points", signature.characters("€é a") == 4, tostring(signature.characters("€é a")))

print(string.format("counts %d %d", passed, failed))
os.exit(failed == 0 and 0 or 1)
