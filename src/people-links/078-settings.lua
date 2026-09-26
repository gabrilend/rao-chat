-- 078-settings.lua — every config setting name the people-links module
-- reads, handed to 101's config reader (contract, "Settings: every name is
-- declared").
--
-- The home's config file may hold only lines whose names some module
-- declares; a line nobody declares (a retired setting, a typo, a setting
-- from a newer version) is an error when the home is opened.  This list is
-- how the config reader learns people/'s names.  Plain data: 101 reads this
-- file by scanning src/, nothing here runs.
--
-- All five are open choices (079-options.lua); declaring a name decides
-- nothing about it.  The values each accepts are listed in
-- 061-people-links.lua's CHOICES table, which must name the same five.
--   people.link-collision           two top rooms with one label
--   people.slash-in-link-name       a label with "/", or exactly "." / ".."
--                                   (read only in that case)
--   people.direct-message-link      the person's own direct message linked?
--   people.members-without-dm       a member no direct message holds
--   people.person-folder-collision  two direct messages with one label
--                                   (read only in that case)

return {
    "people.link-collision",
    "people.slash-in-link-name",
    "people.direct-message-link",
    "people.members-without-dm",
    "people.person-folder-collision",
}
