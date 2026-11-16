-- luacheck config. WoW runs Lua 5.1.
std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
  "Libs/**", -- embedded third-party libraries (fetched by scripts/fetch-libs.sh / the packager)
  ".release/**",
}

ignore = {
  "212/self", -- unused self argument (method style)
  "432/self", -- shadowing self in nested script handlers (idiomatic in WoW UI code)
}

-- WoW API globals we read. Extend as code starts using more of the API.
read_globals = {
  -- Lua extensions provided by WoW
  "strsplit", "strtrim", "strjoin", "wipe", "tinsert", "tremove", "debugprofilestop", "date", "time",
  -- frames, timers, UI
  "CreateFrame", "C_Timer", "UIParent", "GameTooltip", "hooksecurefunc", "DEFAULT_CHAT_FRAME", "ReloadUI",
  "GetCoinTextureString", "SecondsToTime", "BackdropTemplateMixin", "GameFontNormal", "GameFontHighlight",
  "GameFontHighlightSmall", "GameFontNormalLarge", "GameFontDisableSmall", "UISpecialFrames", "GetCursorPosition",
  "StaticPopup_Show", "RELOADUI", "CANCEL", "ACCEPT", "DELETE", "UIErrorsFrame", "PlaySound", "SOUNDKIT",
  "IsAltKeyDown", "IsShiftKeyDown", "IsControlKeyDown", "Item", "TooltipDataProcessor", "debugstack", "Enum", "C_TooltipInfo",
  "GetItemInfo", "C_Item", "GetItemInfoInstant", "GetItemClassInfo", "GetItemSubClassInfo", "CreateFramePool", "CreateTexturePool", "Mixin", "CreateFromMixins", "ColorMixin",
  "CreateColor", "ITEM_QUALITY_COLORS", "ItemRefTooltip", "ChatEdit_InsertLink", "HandleModifiedItemClick",
  -- namespaces
  "C_AuctionHouse", "C_ChatInfo", "QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "C_AddOns", "LoadAddOn",
  -- unit / realm
  "GetServerTime", "GetNormalizedRealmName", "GetRealmName", "GetAutoCompleteRealms", "UnitName",
  "UnitFactionGroup", "IsInGuild", "C_FriendList",
  -- optional integrations
  "Auctionator", "LibStub",
}

globals = {
  "SlashCmdList", "StaticPopupDialogs",
  "AME_DB",
  "AME_HistoryDB",
  "SLASH_AZEROTHMERCANTILEEXCHANGE1",
  "SLASH_AZEROTHMERCANTILEEXCHANGE2",
}

files["spikes/AME_Spike/**"] = {
  globals = { "AME_SpikeDB", "SLASH_AMESPIKE1" },
}

files["spec/**"] = {
  std = "+busted",
}

files["bench/**"] = {
  max_line_length = false,
}
