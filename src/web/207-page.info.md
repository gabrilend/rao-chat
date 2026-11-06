# 207-page.js

The page's own script, the part that draws (issue 401): places what the
other scripts work out, always as text, and wires the tabs, panels and
buttons.  It starts only when a browser's page has loaded; the stand-in
browser loads it but has no page to start it on.  From 405 it draws the room tree (nested lists that fold, with unread
marks kept in the page) and the open room from what `rao.view` works out.
