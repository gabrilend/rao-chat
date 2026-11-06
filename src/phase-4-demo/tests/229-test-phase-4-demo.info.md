# 229-test-phase-4-demo.lua

Issue 409's referee: the demo, run the way the owner would
(`run-phase-demo 4` from another folder), shows each scene and passes or
fails it.

It checks input/ first and the goodbye last, that the exit status agrees
with the goodbye's counts, that every scene ran, and what each printed:
the page's folder whole and the stand-in named; both pages paired (no
token printed whole) and tested; both mirrors their homes'; page A's
message pushed to page B and page B's answer pushed to page A, with
times; each page's room showing its own message on its side and the
other's on the other, and each mirror's `from:` lines; page A losing its
connection, coming back by itself and getting what B typed meanwhile.
Nothing is left behind: the demo's folder is gone and none of its
processes runs.

Broken versions it must catch:
1. A scene made to fail (`RAO_PHASE4_DEMO_BREAK=drop`): reported as
   could-not with the reason, the scenes before it ran, exit 1.
2. A project copy without the stand-in browser: named as not there,
   every scene could not run, exit 1.

Run it under the loopback-only wrapper:
`luajit src/phase-4-demo/tests/229-test-phase-4-demo.lua [project folder]`
Prints PASS/FAIL per check, then "counts <passed> <failed>".
