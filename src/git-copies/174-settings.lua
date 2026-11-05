-- 174-settings.lua — every config setting name the text copies read
-- (issue 215), handed to 101's config reader.  Plain data.
--
-- git.home-name — this home's name in its mailbox repositories: the
--   commit author (`<name> <name@rao-chat.invalid>`) and the code branch
--   `code/<name>` (open question 4, decided 2026-11-05).  Letters,
--   digits, '.', '_' and '-'.  No default: a name chosen by the person,
--   since a pushed author name says who ran the home (215b).

return {
    "git.home-name",
}
