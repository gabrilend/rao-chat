# 401 — The page's folder

**Phase:** 4 — The web client
**Blocked by:** 309, 310
**Blocks:** 402 to 409

## Current Behavior

A browser can reach the device port through 309's WebSocket upgrade, but
there is no page: phase 3's "browser" is the reference device (190)
speaking WebSocket.  Planning question 5 (how the page itself is
trusted) is open, and 309 decision 2 left serving the page to phase 4.

## Intended Behavior

Planning sections 6, 9 and 11: "plain HTML, CSS and JavaScript, no
framework", "served from one folder of static files, so what the browser
runs can be read in full".

- **One folder, `src/web/`**, holding everything the page runs: one HTML
  file, its stylesheets and its scripts, each numbered like every other
  source file.  No build step, no package manager, no file fetched from
  anywhere else, and nothing generated.  What is in the folder is what
  the browser runs.
- **The page is opened from a copy on the person's own computer**
  (`file://`), not fetched from the home (decision 1, planning question
  5).  The home serves no page; the only thing crossing the network is
  the sealed WebSocket.
- **Classic scripts, not modules**: each script adds its part to one
  object, `rao`, and touches no page element when it loads.  A browser
  will not load a module script from a `file://` page, and a script that
  only defines things can also be loaded by a stand-in outside a
  browser (decision 3).
- **The skeleton of section 9**: a top bar (the home's name, the
  connection state, the error strip), the room trees in a left column,
  the open room on the right with its compose line at the bottom, and
  People and Settings opening over the room view.  This issue draws the
  frame and says "not connected"; the later issues fill it.
- **One palette, defined once** (section 7): rmail's colours (section 8:
  black, goldenrod `#FFD040`, dim goldenrod `#B89020`, cyan `#00E5FF`)
  as CSS custom properties in one stylesheet; every other file names
  them and writes no colour of its own.  Monospace for message text and
  addresses.
- **Text is never read as HTML**: nothing the page shows is put in with
  `innerHTML` or its relatives, and no script builds code from text
  (`eval`, `new Function`, a string given to `setTimeout`).  A message
  holding `<script>` shows those characters.
- **A stand-in browser for the referees**:
  `node src/web/tests/<n>-stand-in-browser.js <project> <command> ...`
  loads the scripts the HTML lists, in its order, with Node's own
  WebCrypto and WebSocket standing in for the browser's, and runs the
  page's work without the page (decision 4).  Later issues add its
  commands, as 190 grew a command per phase 3 issue.

## Status

Built 2026-11-06: `src/web/203-rao-chat.html` (the frame of section 9),
`204-palette.css`, `205-layout.css`, `206-rao.js` (`rao` and its byte
helpers), `207-page.js` (the tabs and panels, the "not connected" state,
and the words when WebCrypto is missing); the stand-in browser,
`src/web/tests/208-stand-in-browser.js` (`load`).  Referees 1 to 5 pass,
1 to 4 also against copies of the folder made wrong on purpose
(`src/web/tests/209-test-the-pages-folder.lua`), with 5b (no WebCrypto:
the page says why) and 5c (a script touching the page as it loads is
caught).

## Rubric

- **What the browser runs can be read in full** (planning section 9).
- **The one real risk is the page itself** (planning section 6, "The web
  client"): code fetched unencrypted from outside the home network could
  be changed to steal the token as it is typed.
- **Nothing is deleted by swiping** (section 8): no gesture or single
  click removes anything; this page has no delete at all.

## Where we differ

rmail's phone app is installed from a package; its web side (none) is
not a neighbour.  The formation here is **the page as a folder you keep**,
like the mailbox's git repository that already carries the running
source code (section 15, 2026-09-27): the copy a person opens is one they
can read, compare and keep.

- **Gains:** nothing executable crosses the network; WebCrypto works (a
  page opened from a file counts as a secure context); the page can be
  checked with `sha256sum` against the home's own copy.
- **Costs:** the person copies a folder once, and again when it changes;
  "served by the home server, so nothing is installed" (section 6)
  becomes "copied from the home, so nothing is installed".

## Referees

1. **The folder is whole.**  Every stylesheet and script the HTML names
   is a file in the folder, and every file in the folder (outside
   `tests/`) is named by the HTML.  *Broken:* a script tag naming a file
   that is not there.
2. **Nothing comes from elsewhere.**  No file of the folder names an
   outside address (`http:`, `https:`, `//host`, `ws:`/`wss:` with a
   host written in), or loads a module.  *Broken:* a copy of the folder
   given a script from a content network is refused by the check.
3. **No text is read as HTML or as code**: none of `innerHTML`,
   `outerHTML`, `insertAdjacentHTML`, `document.write`, `eval(`,
   `new Function`, or a string handed to `setTimeout`/`setInterval`.
4. **One palette.**  A colour value (`#…`, `rgb(`, `hsl(`, a named
   colour in a colour property) appears only in the palette file.
5. **The stand-in loads the page's scripts** in the HTML's order, each
   adding its part to `rao` without touching a page element.

## Suggested Implementation Steps

1. The HTML, the palette, the layout stylesheet, the first script (the
   `rao` object and its byte helpers) and the page's own script.
2. The stand-in browser (Node, no packages) and the referees.

## Blockers that are not the owner's

- Needs 309 (the WebSocket way in).  Node 18 or later on the machine that
  runs the referees (it is already on the build machine; nothing is
  installed).

## Open questions

(None left: see Decisions.)

## Decisions (2026-11-06)

Made by the builder under the owner's standing instruction of 2026-11-02;
the owner can overturn each.

1. **Planning question 5: the page is a copy kept on the person's
   computer and opened from there** (the planning document's third
   choice).  The other two fall away on their own: WebCrypto runs only in
   a "secure context", which a page fetched over plain HTTP from a home
   address is not (as remembered of the Secure Contexts rule; not
   checked in a browser here), so "only on the home network" would
   still need HTTPS, and HTTPS needs a certificate for a home address.
   A page opened from a file is a secure context, and only the sealed
   connection crosses the network.  The copy comes from the project
   folder (or the mailbox's git repository, which carries the running
   source); 401's folder is all of it.
2. **The home serves no page** in phase 4 (309 decision 2 left it here).
   Serving the same folder to a browser on the home machine itself
   (`http://127.0.0.1`, also a secure context) is a later choice, not
   made here.
3. **Classic scripts on one object, `rao`**, not ES modules: a browser
   refuses module scripts from `file://` pages.  Each script is wrapped
   in a function so nothing else leaks into the page's global names.
4. **Node stands in for the browser in the referees**: it has the same
   WebCrypto (`crypto.subtle`) and, from version 22, the same
   `WebSocket`, so the scripts the page runs are the scripts tested.
   Only the page's own script (the part that draws) is not run outside
   a browser.  Node is a tool of the referees and the demo, never of the
   page; nothing is installed with npm.
5. **No Content-Security-Policy tag**: how browsers match `'self'` for a
   `file://` page differs between them, and a wrong policy would stop
   the page in a way no referee here can see.  Referees 2 and 3 hold the
   same aims over the files themselves.
6. **The referees are Lua files**, as every other referee, which drive
   the stand-in as they drive 190, so the suite finds them as it finds
   the others.

### While building, 2026-11-06

7. **The page says why when the browser gives it no WebCrypto** (a page
   opened from a network address is not a secure context): the error
   strip names the cause and the cure, instead of every later step
   failing without a word.
8. **The stand-in loads the page's own script too**: it starts nothing
   without a `document`, so loading it checks that it touches nothing as
   it loads, like the others.
9. **The checks of referees 2 to 4 are by pattern over the files**, and
   are shown to work by running them on copies made wrong; they hold the
   folder to its rules, not a browser.  An address in a comment counts
   too, so the files name none.

## Related documents

- `notes/vision-planning.md` sections 6 ("The web client"), 7, 9, 11,
  13 (question 5)
- issue 309 (decision 2)
