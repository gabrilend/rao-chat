# 217-test-catching-up-in-the-page.lua

Issue 404's referees: a new page's mirror equals the home's RAM folder;
a second catch-up gets only the new messages (broken: `from-start`); an
edit is caught (broken: `no-digest`), a lost file dropped, a room left
pruned, a late message fetched and a second catch-up at once gets none;
bad paths from a stand-in home refused and said (broken:
`no-path-check`), and a record not due ends the catch-up; the page's
catch-up lines are 192's.  Run under the loopback-only wrapper
(127.0.0.2, ports 46404 and 46414):
`luajit src/web/tests/217-test-catching-up-in-the-page.lua [project]`.
