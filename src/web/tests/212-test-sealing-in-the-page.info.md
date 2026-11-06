# 212-test-sealing-in-the-page.lua

Issue 402's referees: frames the page seals open with 124 at 124's
padded size and frames 124 seals open in the page, for every record kind
with escapes and odd bytes; opening is all or nothing (broken:
`no-tie-check`); the page's record table and rules are 186's (broken:
`short-kind`); the page's key follows 123's token rule.  No network:
`luajit src/web/tests/212-test-sealing-in-the-page.lua [project]`.
