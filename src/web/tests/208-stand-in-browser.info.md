# 208-stand-in-browser.js

The page without the page (issue 401, decision 4): loads the scripts the
page names, in its order, under Node, whose WebCrypto and WebSocket stand
in for the browser's, and runs the page's work from the command line for
the referees and the demo, as 190 does for a phone.
`node src/web/tests/208-stand-in-browser.js <project> <command> [...]`.
Commands: `load` (401); `key`, `seal`, `open`, `records` (402); `settings`, `remember`, `test`,
`reach` (403); `catch-up`, `positions` (404); `tree`, `room`, `draw`
(405, `draw` on a paper document: the least of a browser's document that
the page's script uses, so the referees read what it placed); each later
issue adds its own.
