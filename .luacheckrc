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
}

-- WoW API globals we read. Extend as code starts using more of the API.
read_globals = {
  -- Lua extensions provided by WoW
  "strsplit", "strtrim", "strjoin", "wipe", "tinsert", "tremove", "debugprofilestop", "date", "time",
  -- frames, timers, UI
  "CreateFrame", "C_Timer", "UIParent", "GameTooltip", "hooksecurefunc", "DEFAULT_CHAT_FRAME", "ReloadUI",
  "GetCoinTextureString", "SecondsToTime", "BackdropTemplateMixin", "GameFontNormal", "GameFontHighlight",
  "GameFontHighlightSmall", "GameFontNormalLarge", "GameFontDisableSmall", "UISpecialFrames", "GetCursorPosition",
  "IsAltKeyDown", "IsShiftKeyDown", "IsControlKeyDown", "Item", "TooltipDataProcessor", "Enum", "C_TooltipInfo",
  "GetItemInfo", "C_Item", "CreateFramePool", "CreateTexturePool", "Mixin", "CreateFromMixins", "ColorMixin",
  "CreateColor",
  -- namespaces
  "C_AuctionHouse", "C_ChatInfo", "C_AddOns", "LoadAddOn",
  -- unit / realm
  "GetServerTime", "GetNormalizedRealmName", "GetRealmName", "GetAutoCompleteRealms", "UnitName",
  "UnitFactionGroup",
  -- optional integrations
  "Auctionator", "LibStub",
}

globals = {
  "SlashCmdList",
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
