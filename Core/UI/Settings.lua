-- Settings (AceConfig, shown in the game's AddOns options) and the minimap / broker launcher.
local ADDON, ns = ...
local L = ns.L

local W = ns.Widgets

local Settings = {}
ns.Settings = Settings

Settings.DEFAULTS = {
  tooltip = true,
  tooltipAvgDays = 7, -- average period shown in tooltips: 3 / 7 / 14 / 30
  tooltipDetail = false, -- full tooltip without holding Shift
  chartStyle = "line", -- "line" | "candles"
  theme = "auto", -- window colours: "auto" (follow the viewed market) | "Horde" | "Alliance" | "Neutral"
  clickModifier = "alt", -- "alt" | "altshift" | "none"
  announceScans = true,
  alertSound = true,
  cutFaction = 5, -- seller's cut in % at faction auction houses
  cutNeutral = 15, -- and at goblin (neutral) auction houses
  listingHours = 24, -- listing length used for deposit estimates (2 / 8 / 24)
  outlierFactor = 4, -- ignore days priced more than this many times off their neighbours (false = off)
  syncGuild = true,
  syncTrusted = true,
  minimap = { hide = false },
}

-- seller's cut (fraction) at a house: Alliance / Horde / Neutral
function Settings:AuctionCut(house)
  local pct = house == "Neutral" and self:Get("cutNeutral") or self:Get("cutFaction")
  return (tonumber(pct) or 0) / 100
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

function Settings:Init()
  AME_DB.settings = AME_DB.settings or {}
  for k, v in pairs(Settings.DEFAULTS) do
    if AME_DB.settings[k] == nil and type(v) == "table" then
      AME_DB.settings[k] = { hide = v.hide }
    end
  end
  self:RegisterOptions()
  self:CreateLauncher()
end

-- does the current modifier state match the configured chart-click modifier?
function Settings:ClickModifierDown()
  local mode = self:Get("clickModifier")
  if mode == "alt" then
    return IsAltKeyDown() and not IsShiftKeyDown() and not IsControlKeyDown()
  elseif mode == "altshift" then
    return IsAltKeyDown() and IsShiftKeyDown() and not IsControlKeyDown()
  end
  return false
end

function Settings:RegisterOptions()
  local AceConfig = LibStub("AceConfig-3.0", true)
  local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
  if not (AceConfig and AceConfigDialog) then
    return
  end
  local function get(info)
    return Settings:Get(info[#info])
  end
  local function set(info, value)
    Settings:Set(info[#info], value)
  end
  local options = {
    type = "group",
    name = "Azeroth Mercantile Exchange",
    args = {
      intro = {
        type = "description",
        order = 1,
        name = L["Records auction house prices from every scan and search you run (native APIs; works with any scanning addon), per realm and auction house."]
          .. "\n"
          .. L["Open the window with %s."]:format("|cff33ccff/ame|r"),
      },
      display = {
        type = "group",
        inline = true,
        order = 10,
        name = L["Display"],
        args = {
          tooltip = {
            type = "toggle",
            order = 1,
            width = "full",
            name = L["Show market data in item tooltips"],
            get = get,
            set = set,
          },
          clickModifier = {
            type = "select",
            order = 2,
            name = L["Open an item's chart with"],
            desc = L["Modified click on items in bags, chat links and the auction house. Choose Alt+Shift if another addon (e.g. AHDB) already uses Alt-click."],
            values = { alt = L["Alt-click"], altshift = L["Alt+Shift-click"], none = L["Disabled"] },
            get = get,
            set = set,
          },
          announceScans = {
            type = "toggle",
            order = 3,
            width = "full",
            name = L["Announce recorded full scans in chat"],
            get = get,
            set = set,
          },
          alertSound = {
            type = "toggle",
            order = 3.5,
            width = "full",
            name = L["Play a sound when a watchlist alert fires"],
            get = get,
            set = set,
          },
          minimap = {
            type = "toggle",
            order = 4,
            width = "full",
            name = L["Show minimap button"],
            disabled = function()
              return not LibStub("LibDBIcon-1.0", true)
            end,
            get = function()
              return not AME_DB.settings.minimap.hide
            end,
            set = function(_, value)
              Settings:SetMinimap(value)
            end,
          },
        },
      },
      sync = {
        type = "group",
        inline = true,
        order = 15,
        name = L["Sharing"],
        args = {
          syncGuild = {
            type = "toggle",
            order = 1,
            width = "full",
            name = L["Share full scans with guild members who use AME"],
            desc = L["Announces your recent full scans to the guild and fetches ones you're missing, paced in the background so it never disrupts chat or raid addons. Received scans that disagree wildly with your own prices are rejected."],
            get = get,
            set = set,
          },
        },
      },
      data = {
        type = "group",
        inline = true,
        order = 20,
        name = L["Data"],
        args = {
          backfill = {
            type = "execute",
            order = 1,
            name = L["Import history from Auctionator"],
            desc = L["If Auctionator is installed: fills days that have no AME data from its recent price history."],
            func = function()
              ns.AME:Backfill(true)
            end,
          },
          index = {
            type = "execute",
            order = 2,
            name = L["Rebuild market index"],
            func = function()
              ns.AME:RebuildIndex()
            end,
          },
          selftest = {
            type = "execute",
            order = 3,
            name = L["Run self-test"],
            desc = L["Checks every part of the addon, records timings, then reloads the UI."],
            func = function()
              ns.SelfTest.Run(ns.AME)
            end,
          },
        },
      },
    },
  }
  AceConfig:RegisterOptionsTable(ADDON, options)
  self.panel = AceConfigDialog:AddToBlizOptions(ADDON, "Azeroth Mercantile Exchange")
end

function Settings:SetMinimap(show)
  AME_DB.settings.minimap.hide = not show
  local icon = LibStub("LibDBIcon-1.0", true)
  if icon then
    if show then
      icon:Show(ADDON)
    else
      icon:Hide(ADDON)
    end
  end
end

function Settings:HasMinimapLibrary()
  return LibStub("LibDBIcon-1.0", true) ~= nil
end

-- /ame config: the Settings tab of the AME window (the same options are also in the game's AddOns settings)
function Settings:Open()
  if ns.UI then
    ns.UI:Create()
    ns.UI.frame:Show()
    ns.UI:ShowTab("settings")
  end
end

-- LibDataBroker launcher (+ LibDBIcon minimap button when that library is available)
function Settings:CreateLauncher()
  local LDB = LibStub("LibDataBroker-1.1", true)
  if not LDB then
    return
  end
  local launcher = LDB:NewDataObject(ADDON, {
    type = "launcher",
    label = "AME",
    icon = ns.ICON,
    OnClick = function(_, button)
      if button == "RightButton" then
        Settings:Open()
      else
        ns.UI:Toggle()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("|cff33ccffAzeroth|r Mercantile Exchange")
      tt:AddLine(ns.ShardLabel(ns.AME:CurrentShard()), 0.7, 0.7, 0.7)
      local last = AME_DB.stats.lastFull
      if last then
        tt:AddDoubleLine(L["Last full scan"], date("%b %d %H:%M", last.at), 1, 1, 1, 1, 1, 1)
      end
      local index = ns.AME.index
      if index then
        tt:AddDoubleLine(L["Items tracked"], tostring(index.count), 1, 1, 1, 1, 1, 1)
        local top = ns.MarketIndex.Rank(index, "score", function(s)
          return s.signal == "buy"
        end)
        if #top > 0 then
          tt:AddLine(" ")
          tt:AddLine(L["Top buy signals"])
          for i = 1, math.min(3, #top) do
            local s = top[i]
            local name = W.ItemInfo(s.itemID) or ("item:" .. s.itemID)
            tt:AddDoubleLine(name, W.Money(s.market) .. "  " .. W.Percent(s.change7), 1, 1, 1, 1, 1, 1)
          end
        end
      end
      tt:AddLine(" ")
      tt:AddLine("|cffaaaaaa" .. L["Left-click: window   Right-click: settings"] .. "|r")
    end,
  })
  local icon = LibStub("LibDBIcon-1.0", true)
  if icon and launcher then
    icon:Register(ADDON, launcher, AME_DB.settings.minimap)
  end
end
