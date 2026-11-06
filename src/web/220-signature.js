// 220-signature.js - a message's signature, read from its text by the
// owner's one rule (issue 406; the rule is 214's, written in 169, and
// graded by src/signature/170-signature-examples.txt, the table every
// reader of a signature is graded by).
//
// The owner (2026-09-27): "body text, newline newline, signature. If the
// signature is longer than one line, then it is the body text still, and
// the last word is used."  "last line over 80 characters is a body text,
// not a signature. Use the last word of the body text as the signature if
// there's no signature."
//
//   1. "\r\n" is read as "\n".
//   2. The text is split at its last blank line: the last run of two or
//      more line breaks.
//   3. If the part after it is exactly one line, not empty, of at most 80
//      characters (one line break at the very end allowed), that line is
//      the signature and the part before is the body.
//   4. Otherwise the whole text is the body and the signature is its last
//      word (the last run of characters that are not spaces, tabs or line
//      breaks), or "".
//
// Text here is a byte string (206): characters are counted as 169 counts
// them, every byte that is not 10xxxxxx starting one.
//
//   rao.signature.read(bytes)        -> {body, signature} (byte strings)
//   rao.signature.characters(bytes)  -> how many characters
//   rao.signature.MOST_CHARACTERS    80

(function (rao) {
    "use strict";
    var MOST_CHARACTERS = 80;

    function characters(bytes) {
        var count = 0;
        for (var i = 0; i < bytes.length; i++) {
            var code = bytes.charCodeAt(i);
            if (code < 0x80 || code > 0xBF) { count += 1; }
        }
        return count;
    }
    function lastWord(text) {
        var found = /([^ \t\r\n]+)[ \t\r\n]*$/.exec(text);
        return found ? found[1] : "";
    }
    // text -> [before, after] at the last run of two or more "\n", or null
    function splitAtLastBlank(text) {
        var pattern = /\n\n+/g;
        var found, last = null;
        while ((found = pattern.exec(text)) !== null) { last = found; }
        if (!last) { return null; }
        return [text.slice(0, last.index), text.slice(last.index + last[0].length)];
    }
    function read(bytes) {
        var text = bytes.replace(/\r\n/g, "\n");
        var parts = splitAtLastBlank(text);
        if (parts) {
            var line = parts[1].replace(/\n$/, "");
            var length = rao.broken === "bytes" ? line.length : characters(line);
            if (line !== "" && line.indexOf("\n") < 0 && length <= MOST_CHARACTERS) {
                return { body: parts[0], signature: line };
            }
        }
        return { body: text, signature: lastWord(text) };
    }

    rao.signature = { read: read, characters: characters, MOST_CHARACTERS: MOST_CHARACTERS };
})(globalThis.rao);
