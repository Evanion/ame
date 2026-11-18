-- Settings: defaults and saved values (AME_DB.settings). Not UI: the scan pipeline, pricing and sync read them too.
-- The Settings tab (UI/SettingsView.lua) edits them; UI/Launcher.lua has the minimap button and the game options page.
local _, ns = ...

local Settings = {}
ns.Settings = Settings

Settings.DEFAULTS = {
  tooltip = true,
  tooltipAvgDays = 7, -- average period shown in tooltips, the screener and the item page: 3 / 7 / 14 / 30
  tooltipDetail = false, -- full tooltip without holding Shift
  chartStyle = "line", -- "line" | "candles"
  theme = "auto", -- window colours: "auto" (follow the viewed market) | "Horde" | "Alliance" | "Neutral"
  -- open an item's chart with a modified click on items and links: "none" | "alt" | "altshift" | "ctrlalt". Off by
  -- default: loot and raid addons (Gargul, AHDB...) use modified clicks on items and item links.
  clickModifier = "none",
  announceScans = true,
  openWithAH = false, -- open the AME window when the auction house opens
  dockToAH = true, -- place AME beside the auction house window when there's room
  windowScale = 1, -- AME's own scale (0.7-1.2), on top of the game's UI scale
  closeWithAH = false, -- and close it again with the AH (only when the AH opened it)
  sellSwitchesTab = true, -- putting an item up for sale switches an open AME window to the Item tab for it
  alertSound = true,
  cutFaction = 5, -- seller's cut in % at faction auction houses
  cutNeutral = 15, -- and at goblin (neutral) auction houses
  listingHours = 24, -- listing length used for deposits and posting prices (2 / 8 / 24)
  outlierFactor = 4, -- ignore days priced more than this many times off their neighbours (false = off)
  syncGuild = true,
  syncTrusted = true,
  minimap = { hide = false },
}

function Settings:Init()
  AME_DB.settings = AME_DB.settings or {}
  for k, v in pairs(Settings.DEFAULTS) do
    if AME_DB.settings[k] == nil and type(v) == "table" then
      AME_DB.settings[k] = { hide = v.hide }
    end
  end
  if ns.Launcher then
    ns.Launcher:Init()
  end
end

function Settings:Get(key)
  local s = AME_DB.settings
  if s[key] == nil then
    return Settings.DEFAULTS[key]
  end
  return s[key]
end

function Settings:Set(key, value)
  AME_DB.settings[key] = value
end

-- seller's cut (fraction) at a house: Alliance / Horde / Neutral
function Settings:AuctionCut(house)
  local pct = house == "Neutral" and self:Get("cutNeutral") or self:Get("cutFaction")
  return (tonumber(pct) or 0) / 100
end

-- does the current modifier state match the configured chart-click modifier?
function Settings:ClickModifierDown()
  local mode = self:Get("clickModifier")
  if mode == "alt" then
    return IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()
  elseif mode == "altshift" then
    return IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown()
  elseif mode == "ctrlalt" then
    return IsAltKeyDown() and IsControlKeyDown() and not IsShiftKeyDown()
  end
  return false
end

-- /ame config: the Settings tab of the AME window
function Settings:Open()
  if ns.UI then
    ns.UI:Create()
    ns.UI.frame:Show()
    ns.UI:ShowTab("settings")
  end
end
