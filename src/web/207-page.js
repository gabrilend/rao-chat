// 207-page.js - the page's own script: the part that draws (issue 401).
//
// Everything the page shows is worked out by the other scripts as plain
// lists and words; this one only places them in the page, always as text
// (textContent, never markup: 401's referee 3), and wires the page's
// buttons to them.  It is the one script the stand-in browser (tests/208)
// loads but never starts, since outside a browser there is no page.
//
// Section 9's frame: a top bar (the home's name, the connection state,
// the tabs), the error strip, the room trees on the left, the open room
// on the right with its compose line, and the Homes, People and Settings
// panels opening over the room view.  A panel closes with its own button
// or Escape, and the room behind it keeps its place.

(function (rao) {
    "use strict";
    var page = rao.page = {};

    // {{{ small helpers
    function byId(id) { return page.doc.getElementById(id); }
    // a new element holding text (never markup)
    function element(name, className, text) {
        var made = page.doc.createElement(name);
        if (className) { made.className = className; }
        if (text !== undefined && text !== null) { made.textContent = text; }
        return made;
    }
    page.byId = byId;
    page.element = element;
    // }}}

    // {{{ panels
    var PANELS = { homes: "homes-panel", people: "people-panel", settings: "settings-panel" };
    function openPanel(name) {
        Object.keys(PANELS).forEach(function (key) {
            byId(PANELS[key]).hidden = key !== name;
        });
        Array.prototype.forEach.call(page.doc.querySelectorAll(".tab"), function (tab) {
            tab.classList.toggle("selected", tab.getAttribute("data-panel") === (name || "rooms"));
        });
    }
    page.openPanel = openPanel;
    // }}}

    // {{{ the top bar and the error strip
    page.setState = function (words, live) {
        var state = byId("connection-state");
        state.textContent = words;
        state.classList.toggle("live", !!live);
    };
    // lines: a list of strings; an empty list hides the strip
    page.showErrors = function (lines, retrying) {
        var list = byId("error-lines");
        list.textContent = "";
        lines.forEach(function (line) { list.appendChild(element("li", null, line)); });
        byId("error-strip").hidden = lines.length === 0;
        byId("retry-now").hidden = !retrying;
    };
    // }}}

    // {{{ page.start
    // doc: the page's document.  Wires the tabs and panels, and says
    // whether this browser gives the page what it needs.
    page.start = function (doc) {
        page.doc = doc;
        Array.prototype.forEach.call(doc.querySelectorAll(".tab"), function (tab) {
            tab.addEventListener("click", function () {
                var name = tab.getAttribute("data-panel");
                openPanel(name === "rooms" ? null : name);
            });
        });
        Array.prototype.forEach.call(doc.querySelectorAll(".panel-close"), function (button) {
            button.addEventListener("click", function () { openPanel(null); });
        });
        doc.addEventListener("keydown", function (event) {
            if (event.key === "Escape") { openPanel(null); }
        });
        byId("home-name").addEventListener("click", function () { openPanel("homes"); });
        openPanel(null);
        page.setState("not connected", false);
        var missing = rao.bytes.cryptoMissing();
        page.showErrors(missing ? [missing] : [], false);
    };
    // }}}

    if (typeof document !== "undefined") {
        document.addEventListener("DOMContentLoaded", function () { page.start(document); });
    }
})(globalThis.rao);
