-- 023-settings.lua — every config setting name the room-tree module reads,
-- handed to 101's config reader (contract, "Settings: every name is
-- declared").
--
-- The home's config file may hold only lines whose names some module
-- declares; a line nobody declares (a retired setting, a typo, a setting
-- from a newer version) is an error when the home is opened.  This list is
-- how the config reader learns the room tree's names.  Plain data: 101
-- reads this file by scanning src/, nothing here runs.
--
-- tree.filing-loop — what happens when a declared parent arrives that puts
--   a room you filed above the room it is filed under (unfile | refuse);
--   read only when such a ring is found.  Still an open choice (issue 102,
--   039-options.lua); declaring the name decides nothing about it.

return {
    "tree.filing-loop",
}
