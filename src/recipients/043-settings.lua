-- 043-settings.lua — the setting names the recipients module (issues 103
-- and 103a) reads from a home's config.
--
-- 101's config reader (017-declared-settings) refuses any config line
-- whose name no module lists, so a retired setting, a typo or a setting
-- from a newer version stops the program instead of being quietly
-- ignored.  This is the recipients folder's one list: every name
-- 041-recipients and 042-ignore-list read, each owned here.  Plain data:
-- nothing here runs.
--
-- Retired and no longer read, so no longer listed (a line naming one is
-- now refused): recipients.flag-after-passing (round 4: a flag whose
-- member later passes clears by itself); ignore.hide-files and
-- ignore.match (round 3); recipients.split-shape, recipients.arrival-list,
-- recipients.split-parent and recipients.split-alone (round 2).

return {
    -- whole home only, or also one room: home | home-and-room
    -- (042-ignore-list, read on every ignore lookup and change)
    "ignore.scope",
    -- a member whose address two direct-message rooms hold: all-labels |
    -- address (041-recipients shown_as, read only in that case)
    "recipients.shared-address-label",
}
