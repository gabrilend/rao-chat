# 207-page.js

The page's own script, the part that draws (issue 401): places what the
other scripts work out, always as text, and wires the tabs, panels and
buttons.  It starts only when a browser's page has loaded; the stand-in
browser loads it but has no page to start it on.  From 405 it draws the room tree (nested lists that fold, with unread
marks kept in the page) and the open room from what `rao.view` works out.  From 406 it has the compose line (Enter sends, Shift+Enter a new
line, growing to eight lines), the signature field, the outbox's sending
after each catch-up, the marker and the refused items with their reasons.
