-- 016-settings.lua — the setting names room-folders reads from a home's config.
--
-- Every module keeps one of these lists (src/<module>/<index>-settings.lua):
-- the names of every config line it reads, switched choice or fixed
-- setting alike.  A config line naming something no module lists is an
-- error when the home's config is read (017-declared-settings), so a
-- retired setting, a typo or a setting from a newer version is noticed
-- rather than quietly ignored.  Plain data: nothing here runs.
--
-- Retired in round 4 and no longer read (so no longer listed, and a line
-- naming it is now refused): mailboxes.unheld-parent (a child room whose
-- parent is not held here always starts its own mailbox; the owner's
-- answer).  rooms.suggested-token-words went in round 3.

return {
    -- once a child room's declared parent arrives, move its own mailbox's
    -- rooms into the parent's mailbox: automatic | ask (002-room-folders).
    "mailboxes.merge-when-parent-arrives",
}
