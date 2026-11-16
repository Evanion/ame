-- luacheck config. WoW runs Lua 5.1.
std = "lua51"
max_line_length = 120
codes = true

exclude_files = {
  "**/Libs/**", -- embedded third-party libraries (fetched by the packager)
  ".release/**",
}

ignore = {
  "212/self", -- unused self argument (method style)
}

-- WoW API globals we read. Extend as code starts using more of the API.
read_globals = {
  -- Lua extensions provided by WoW
  "strsplit", "strtrim", "strjoin", "wipe", "tinsert", "tremove", "debugprofilestop", "date", "time",
  -- frames and timers
  "CreateFrame", "C_Timer", "UIParent", "GameTooltip",
  -- namespaces
  "C_AuctionHouse", "C_ChatInfo", "C_Item", "Enum",
  -- unit / realm
  "GetServerTime", "GetNormalizedRealmName", "GetRealmName", "GetAutoCompleteRealms", "UnitName",
  "UnitFactionGroup",
  -- optional integrations
  "Auctionator", "LibStub",
}

globals = {
  "SlashCmdList",
}

files["spikes/AME_Spike/**"] = {
  globals = { "AME_SpikeDB", "SLASH_AMESPIKE1" },
}

files["spec/**"] = {
  std = "+busted",
}
