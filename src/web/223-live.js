// 223-live.js - live while the page is open (issue 407), as 306 keeps a
// device live: after `caught-up` the connection stays open; each `file`
// the home pushes goes into the mirror (404's path check), each answer to
// a typed file into the outbox (406); a `ping` goes whenever the page has
// sent nothing for `keep-alive` seconds, so the home's idle limit never
// closes a page that only listens (306 decision 4).  A dropped connection
// is tried again after 5 seconds, the wait doubling to at most 5 minutes
// and back to 5 after a connection that catches up (407 decision 1); each
// try chooses an address as 403 does and catches up from the mirror held,
// then sends again what the outbox still waits on.
//
//   rao.live.nextWait(previous)      -> seconds: 5, 10, 20 ... 300, 300
//   rao.live.countdown(seconds)      -> "40s" under a minute, "4m" above
//   rao.live.problems(files)         -> the home's problem lines, as 183's
//                                       `problems`: "<mailbox, 8> <name>: <words>"
//   new rao.live.Session(settings, files, outbox, hooks)
//     .start()      reach, catch up, send what waits, listen; retry on loss
//     .retryNow()   try at once (the "retry now" button, the browser online)
//     .sendWaiting() send what the outbox holds unsent on this connection
//     .stop()       close, and try no more
//     .state        "connecting", "catching-up", "live", "waiting" or "stopped"
//     .wait, .retryAt (ms), .why
//   hooks (each optional): state(words, live), errors(lines, retrying),
//   changed() after the mirror or the outbox changed, caughtUp(summary).

(function (rao) {
    "use strict";
    var FIRST_WAIT = 5;
    var MOST_WAIT = 300;

    // {{{ the waits and their countdown
    function nextWait(previous) {
        if (!previous) { return FIRST_WAIT; }
        return Math.min(previous * 2, MOST_WAIT);
    }
    function countdown(seconds) {
        seconds = Math.max(0, Math.ceil(seconds));
        return seconds < 60 ? seconds + "s" : Math.round(seconds / 60) + "m";
    }
    // }}}

    // {{{ problems: each mailbox's state, its problem.<name> lines (301 decision 7)
    function problems(files) {
        var out = [];
        var mailboxes = [];
        files.forEach(function (content, path) {
            var where = rao.mirror.checkPath(path);
            if (where.kind === "state") { mailboxes.push(where.mailbox); }
        });
        mailboxes.sort(rao.mirror.byBytes).forEach(function (mailbox) {
            var lines = [];
            rao.bytes.toText(files.get(mailbox + "/state")).split("\n").forEach(function (line) {
                var found = /^problem\.([A-Za-z0-9.\-_]+) = (.*)$/.exec(line);
                if (found) { lines.push({ name: found[1], words: found[2] }); }
            });
            lines.sort(function (a, b) { return rao.mirror.byBytes(a.name, b.name); });
            lines.forEach(function (line) { out.push(mailbox.slice(0, 8) + " " + line.name + ": " + line.words); });
        });
        return out;
    }
    // }}}

    // {{{ Session
    function Session(settings, files, outbox, hooks) {
        this.settings = settings;
        this.files = files;
        this.outbox = outbox;
        this.hooks = hooks || {};
        this.link = null;
        this.wait = 0;
        this.retryAt = null;
        this.timer = null;
        this.why = "";
        this.state = "stopped";
        this.tries = 0;
    }
    Session.prototype.hook = function (name) {
        var run = this.hooks[name];
        if (typeof run === "function") { run.apply(null, Array.prototype.slice.call(arguments, 1)); }
    };
    Session.prototype.start = function () {
        this.stopped = false;
        return this.connect();
    };
    Session.prototype.connect = function () {
        var session = this;
        if (session.timer) { clearTimeout(session.timer); session.timer = null; }
        if (session.stopped || session.state === "connecting" || session.state === "catching-up") { return Promise.resolve(); }
        session.tries += 1;
        session.state = "connecting";
        session.retryAt = null;
        session.hook("state", "connecting…", false);
        return rao.link.reach(session.settings).then(function (reached) {
            if (session.stopped) { if (reached.link) { reached.link.close(); } return; }
            if (!reached.link) { session.lost(reached.why); return; }
            var link = reached.link;
            session.link = link;
            session.state = "catching-up";
            session.hook("state", "catching up with " + link.where + "…", false);
            return rao.mirror.catchUp(link, session.files, session.settings).then(function (summary) {
                if (session.link !== link) { return; }
                if (summary.why) { link.close(); session.lost(summary.why); return; }
                session.wait = 0;
                session.why = "";
                session.state = "live";
                session.hook("state", "live: " + link.where, true);
                session.hook("caughtUp", summary);
                session.showErrors(summary.refused.map(function (why) { return "refused from the home: " + why; }));
                session.hook("changed");
                session.sendWaiting();
                session.listen(link);
            });
        });
    };
    // the strip: the session's own trouble, then the home's problems
    Session.prototype.showErrors = function (own) {
        var lines = own.slice();
        if (this.state === "waiting") {
            lines.unshift("connection lost: " + this.why + " (retrying in "
                + countdown((this.retryAt - Date.now()) / 1000) + ")");
        }
        this.hook("errors", lines.concat(problems(this.files)), this.state === "waiting");
    };
    Session.prototype.sendWaiting = function () {
        var link = this.link;
        if (!link || this.state !== "live") { return Promise.resolve(); }
        var sends = this.outbox.waiting().filter(function (item) { return item.sentOn !== link; }).map(function (item) {
            item.sentOn = link;
            return link.send({ kind: "typed", id: item.name, content: item.content });
        });
        return Promise.all(sends);
    };
    // the one reader of a live connection
    Session.prototype.listen = function (link) {
        var session = this;
        var keepAlive = session.settings["keep-alive"];
        function due() { return Math.max(0, keepAlive - (Date.now() - (link.lastSent || 0)) / 1000); }
        function step() {
            if (session.link !== link || session.stopped) { return Promise.resolve(); }
            if (due() <= 0 && rao.broken !== "no-keep-alive") {
                return link.send({ kind: "ping", id: rao.bytes.hex(rao.bytes.random(8)) }).then(step);
            }
            return link.next(rao.broken === "no-keep-alive" ? null : due()).then(function (got) {
                if (session.link !== link) { return; }
                if (got.lost === "timeout") { return step(); }
                if (got.lost === "closed") { session.lost((link.where || "the home") + " closed the connection"); return; }
                if (got.lost) { link.close(); session.lost(rao.link.silence(session.settings, link.where || "the home", got.lost)); return; }
                var record = got.record;
                if (record.kind === "file") {
                    var summary = { files: 0, messages: 0, changed: 0, dropped: 0, refused: [] };
                    rao.mirror.take(session.files, record, summary);
                    if (summary.refused.length > 0) { session.showErrors(["refused from the home: " + summary.refused[0]]); }
                    session.hook("changed");
                    return step();
                }
                if (session.outbox.answer(record)) { session.hook("changed"); return step(); }
                if (record.kind === "pong") { return step(); }
                link.close();
                session.lost((link.where || "the home") + " sent a " + record.kind + " where it was not due");
            });
        }
        return step();
    };
    Session.prototype.lost = function (why) {
        var session = this;
        if (session.link) { session.link.close(); }
        session.link = null;
        session.why = why;
        if (session.stopped) { session.state = "stopped"; return; }
        if (rao.broken === "no-retry") {
            session.state = "stopped";
            session.hook("state", "not connected", false);
            session.hook("errors", ["connection lost: " + why], false);
            return;
        }
        session.wait = nextWait(session.wait);
        session.retryAt = Date.now() + session.wait * 1000;
        session.state = "waiting";
        session.hook("state", "not connected", false);
        session.showErrors([]);
        session.timer = setTimeout(function () { session.timer = null; session.connect(); }, session.wait * 1000);
    };
    Session.prototype.retryNow = function () {
        if (this.state !== "waiting") { return Promise.resolve(); }
        return this.connect();
    };
    Session.prototype.stop = function () {
        this.stopped = true;
        if (this.timer) { clearTimeout(this.timer); this.timer = null; }
        if (this.link) { this.link.close(); }
        this.link = null;
        this.state = "stopped";
    };
    // }}}

    rao.live = { nextWait: nextWait, countdown: countdown, problems: problems, Session: Session,
        FIRST_WAIT: FIRST_WAIT, MOST_WAIT: MOST_WAIT };
})(globalThis.rao);
