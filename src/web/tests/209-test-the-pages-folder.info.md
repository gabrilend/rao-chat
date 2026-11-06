# 209-test-the-pages-folder.lua

Issue 401's referees: every file the page names is in `src/web` and every
file there is named; nothing names an outside address or loads a module;
no text is read as markup or code; colours only in the palette; the
stand-in loads the page's scripts in order, adding only `rao`, and says
why when WebCrypto is missing.  The checks are also run on copies of the
folder made wrong on purpose.  No network:
`luajit src/web/tests/209-test-the-pages-folder.lua [project]`.
