// 208-stand-in-browser.js - the page without the page: the scripts the web
// client runs, loaded outside a browser so the referees can drive them
// (issue 401, decision 4), as they drive the reference device (190).
//
//   node src/web/tests/208-stand-in-browser.js <project> <command> [...]
//
// It reads the page's HTML (src/web/<n>-rao-chat.html), finds the scripts
// it names, in the order it names them, and runs each as a browser runs a
// classic script, in this process's one global scope.  Node gives the
// same WebCrypto (crypto.subtle, crypto.getRandomValues) and, from
// version 22, the same WebSocket the page uses in a browser; there is no
// `document`, so the page's own drawing script (207) defines its parts
// and starts nothing.  Node is a tool of the referees and the demo only;
// the page never needs it, and nothing is installed with npm.
//
// RAO_WEB_BROKEN, when set, names a broken version for a referee
// (rao.broken, 206).
//
// Commands (each later issue adds its own to COMMANDS):
//   load [--no-subtle]   load the page's scripts and print what they made:
//                        "script <name>" for each, "rao <parts>", "globals
//                        <names>" (every global the scripts added), and
//                        "crypto ok" or "crypto missing: <words>" (with
//                        --no-subtle, crypto.subtle is taken away first,
//                        as a browser does on a page it does not count as
//                        secure)
//   key --token <file>   the tying value of the token in <file> (its bytes,
//                        read as UTF-8 text as typed), in hex (402)
//   seal --token <file> --record <file> --out <file> [--no-pad]
//                        the record sealed into a whole frame (402)
//   open --token <file> --frame <file> --out <file>
//                        a whole frame opened: "record" and the record
//                        written to --out, or "nothing: <why>" (402)
//   records --in <file>  each line of <file> decoded and encoded again:
//                        "ok <kind> <the line again, hex> <field>=<hex>..."
//                        or "refused <why>"; "table" lines give the kinds,
//                        their fields, and the rule fields (402)
//   settings --settings <file> [--token <file>]
//                        "ok", or "refused: <why>" (403)
//   remember --settings <file>
//                        what the page would keep of the lines (403)
//   test --settings <file> [--token <file>] [--public]
//                        the connection test's words; exit 1 unless
//                        answered (403)
//   reach --settings <file> [--token <file>]
//                        "reached <address> <port> by way of <setting>",
//                        or why not; exit 1 unless reached (403)
//
// Exit status: 0 done, 1 the command failed (said on stderr), 2 usage.

"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const PROJECT = process.argv[2];
const COMMAND = process.argv[3];
const ARGS = process.argv.slice(4);

// {{{ the page's folder and its scripts
function webFolder(project) { return path.join(project, "src", "web"); }

function pageFile(project) {
    const names = fs.readdirSync(webFolder(project)).filter((name) => /^\d{3}-rao-chat\.html$/.test(name));
    if (names.length !== 1) { throw new Error("src/web holds " + names.length + " page files, not one"); }
    return path.join(webFolder(project), names[0]);
}

// the HTML's script names, in its order
function scriptsOf(html) {
    const names = [];
    const pattern = /<script\b([^>]*)>/g;
    let found;
    while ((found = pattern.exec(html)) !== null) {
        const source = /\bsrc="([^"]+)"/.exec(found[1]);
        if (!source) { throw new Error("a script tag with no src: the page has no inline scripts"); }
        names.push(source[1]);
    }
    return names;
}
// }}}

// {{{ load
// project -> the names of the scripts run, in order.  Each is run as a
// browser runs a classic script: in the one global scope, top to bottom.
function load(project) {
    globalThis.RAO_WEB_BROKEN = process.env.RAO_WEB_BROKEN || "";
    const names = scriptsOf(fs.readFileSync(pageFile(project), "utf8"));
    for (const name of names) {
        const file = path.join(webFolder(project), name);
        vm.runInThisContext(fs.readFileSync(file, "utf8"), { filename: file });
    }
    return names;
}
// }}}

// {{{ small helpers for the commands
function option(name) {
    const at = ARGS.indexOf(name);
    return at >= 0 ? ARGS[at + 1] : undefined;
}
function flag(name) { return ARGS.indexOf(name) >= 0; }
function say(line) { process.stdout.write(line + "\n"); }
// }}}

const COMMANDS = {};

// {{{ load
COMMANDS.load = function () {
    if (flag("--no-subtle")) {
        Object.defineProperty(globalThis, "crypto", { value: { getRandomValues: globalThis.crypto.getRandomValues.bind(globalThis.crypto) }, configurable: true });
    }
    globalThis.RAO_WEB_BROKEN = process.env.RAO_WEB_BROKEN || "";
    const before = new Set(Object.getOwnPropertyNames(globalThis));
    const names = load(PROJECT);
    names.forEach((name) => say("script " + name));
    say("rao " + Object.keys(globalThis.rao).sort().join(" "));
    const added = Object.getOwnPropertyNames(globalThis).filter((name) => !before.has(name)).sort();
    say("globals " + added.join(" "));
    const missing = globalThis.rao.bytes.cryptoMissing();
    say(missing ? "crypto missing: " + missing : "crypto ok");
};
// }}}

// {{{ bytes in and out of files: one character per byte (206)
function readBytes(file) { return fs.readFileSync(file).toString("latin1"); }
function writeBytes(file, bytes) { fs.writeFileSync(file, Buffer.from(bytes, "latin1")); }
function readToken(file) { return fs.readFileSync(file, "utf8"); }
function hexOf(bytes) { return Buffer.from(bytes, "latin1").toString("hex"); }
// }}}

// {{{ key / seal / open / records (402)
COMMANDS.key = function () {
    load(PROJECT);
    return globalThis.rao.sealing.keyPair(readToken(option("--token"))).then((pair) => say("tie " + hexOf(pair.tie)));
};
COMMANDS.seal = function () {
    load(PROJECT);
    const rao = globalThis.rao;
    return rao.sealing.keyPair(readToken(option("--token")))
        .then((pair) => rao.sealing.seal(pair, readBytes(option("--record")), { pad: !flag("--no-pad") }))
        .then((frame) => { writeBytes(option("--out"), frame); say("sealed " + frame.length); });
};
COMMANDS.open = function () {
    load(PROJECT);
    const rao = globalThis.rao;
    const frame = readBytes(option("--frame"));
    if (rao.sealing.lengthOf(frame.slice(0, 4)) !== frame.length - 4) { say("nothing: not a frame's length"); return 0; }
    return rao.sealing.keyPair(readToken(option("--token")))
        .then((pair) => rao.sealing.open(pair, frame.slice(4)))
        .then((opened) => {
            if (opened.why) { say("nothing: " + opened.why); return; }
            writeBytes(option("--out"), opened.record);
            say("record");
        });
};
COMMANDS.records = function () {
    load(PROJECT);
    const records = globalThis.rao.records;
    Object.keys(records.KINDS).sort().forEach((kind) => say("table " + kind + " " + records.KINDS[kind].join(" ")));
    say("rules " + Object.keys(records.RULES).sort().join(" "));
    const text = readBytes(option("--in"));
    text.split("\n").forEach((line) => {
        if (line === "") { return; }
        const decoded = records.decode(line);
        if (decoded.why) { say("refused " + decoded.why); return; }
        const fields = records.KINDS[decoded.record.kind].map((name) => name + "=" + hexOf(decoded.record[name]));
        say("ok " + decoded.record.kind + " " + hexOf(records.encode(decoded.record)) + " " + fields.join(" "));
    });
};
// }}}

// {{{ settings / remember / test / reach (403)
// the page's settings from the files given, or a thrown reason
function settingsOf() {
    const token = option("--token") ? readToken(option("--token")) : "";
    const read = globalThis.rao.link.readSettings(fs.readFileSync(option("--settings"), "utf8"), token);
    if (read.why) { throw new Error("the settings were refused: " + read.why); }
    return read.settings;
}
COMMANDS.settings = function () {
    load(PROJECT);
    const token = option("--token") ? readToken(option("--token")) : "";
    const read = globalThis.rao.link.readSettings(fs.readFileSync(option("--settings"), "utf8"), token);
    say(read.why ? "refused: " + read.why : "ok");
};
COMMANDS.remember = function () {
    load(PROJECT);
    process.stdout.write(globalThis.rao.link.rememberText(fs.readFileSync(option("--settings"), "utf8")));
};
COMMANDS.test = function () {
    load(PROJECT);
    return globalThis.rao.link.test(settingsOf(), flag("--public") ? "public" : "home-network").then((result) => {
        say(result.words);
        return result.ok ? 0 : 1;
    });
};
COMMANDS.reach = function () {
    load(PROJECT);
    return globalThis.rao.link.reach(settingsOf()).then((result) => {
        if (!result.link) { say(result.why); return 1; }
        say("reached " + result.where + " by way of " + result.setting);
        result.link.close();
        return 0;
    });
};
// }}}

module.exports = { load, scriptsOf, pageFile, webFolder, COMMANDS, option, flag, say };

// {{{ main
if (require.main === module) {
    if (!PROJECT || !COMMAND || !COMMANDS[COMMAND]) {
        process.stderr.write("usage: node 208-stand-in-browser.js <project> <command> [...]\ncommands: "
            + Object.keys(COMMANDS).join(", ") + "\n");
        process.exit(2);
    }
    Promise.resolve()
        .then(() => COMMANDS[COMMAND]())
        .then((status) => process.exit(typeof status === "number" ? status : 0))
        .catch((problem) => {
            process.stderr.write("stand-in: " + (problem && problem.message ? problem.message : String(problem)) + "\n");
            process.exit(1);
        });
}
// }}}
