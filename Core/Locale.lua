-- Localization: ns.L[<English text>] gives the text in the client's language (AceLocale-3.0, the community standard).
-- The English text is the key, so code stays readable; enUS is the default locale (keys = true) and any string a
-- translation doesn't have falls back to English. Without AceLocale (specs, a broken install) L returns the key.
local ADDON, ns = ...

local AceLocale = LibStub and LibStub("AceLocale-3.0", true)
local L = AceLocale and AceLocale:GetLocale(ADDON, true)
ns.L = L or setmetatable({}, {
  __index = function(_, key)
    return key
  end,
})
