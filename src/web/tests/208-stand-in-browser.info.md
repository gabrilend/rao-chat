# 208-stand-in-browser.js

The page without the page (issue 401, decision 4): loads the scripts the
page names, in its order, under Node, whose WebCrypto and WebSocket stand
in for the browser's, and runs the page's work from the command line for
the referees and the demo, as 190 does for a phone.
`node src/web/tests/208-stand-in-browser.js <project> <command> [...]`.
Commands: `load` (401); `key`, `seal`, `open`, `records` (402); each
later issue adds its own.
