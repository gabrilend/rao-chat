# 207-page.js

The page's own script, the part that draws (issue 401): places what the
other scripts work out, always as text, and wires the tabs, panels and
buttons.  It starts only when a browser's page has loaded; the stand-in
browser loads it but has no page to start it on.  From 405 it draws the room tree (nested lists that fold, with unread
marks kept in the page) and the open room from what `rao.view` works out.  From 406 it has the compose line (Enter sends, Shift+Enter a new
line, growing to eight lines), the signature field, the outbox's sending
after each catch-up, the marker and the refused items with their reasons.  From 407 Connect starts a live session (223) that stays connected
while the page is open; "retry now" and the browser coming back online
try at once, and the strip's countdown moves each second.  From 408 it fills the top bar (the home's name and the state's words),
the People panel (direct-message rooms, opened on a click) and the Homes
panel (the homes remembered, chosen on a click), and keeps each home's
lines and signature under its name.
