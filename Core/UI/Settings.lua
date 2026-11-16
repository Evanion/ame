-- Settings (AceConfig, shown in the game's AddOns options) and the minimap / broker launcher.
local ADDON, ns = ...

local W = ns.Widgets

local Settings = {}
ns.Settings = Settings

Settings.DEFAULTS = {
  tooltip = true,
  clickModifier = "alt", -- "alt" | "altshift" | "none"
  announceScans = true,
  syncGuild = true,
  minimap = { hide = false },
}

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
        name = "Records auction house prices from Auctionator's scans and your searches, per realm and auction house.\n"
          .. "Open the window with |cff33ccff/ame|r.",
      },
      display = {
        type = "group",
        inline = true,
        order = 10,
        name = "Display",
        args = {
          tooltip = {
            type = "toggle",
            order = 1,
            width = "full",
            name = "Show market data in item tooltips",
            get = get,
            set = set,
          },
          clickModifier = {
            type = "select",
            order = 2,
            name = "Open an item's chart with",
            desc = "Modified click on items in bags, chat links and the auction house. Choose Alt+Shift if another "
              .. "addon (e.g. AHDB) already uses Alt-click.",
            values = { alt = "Alt-click", altshift = "Alt+Shift-click", none = "Disabled" },
            get = get,
            set = set,
          },
          announceScans = {
            type = "toggle",
            order = 3,
            width = "full",
            name = "Announce recorded full scans in chat",
            get = get,
            set = set,
          },
          minimap = {
            type = "toggle",
            order = 4,
            width = "full",
            name = "Show minimap button",
            disabled = function()
              return not LibStub("LibDBIcon-1.0", true)
            end,
            get = function()
              return not AME_DB.settings.minimap.hide
            end,
            set = function(_, value)
              AME_DB.settings.minimap.hide = not value
              local icon = LibStub("LibDBIcon-1.0", true)
              if icon then
                if value then
                  icon:Show(ADDON)
                else
                  icon:Hide(ADDON)
                end
              end
            end,
          },
        },
      },
      sync = {
        type = "group",
        inline = true,
        order = 15,
        name = "Sharing",
        args = {
          syncGuild = {
            type = "toggle",
            order = 1,
            width = "full",
            name = "Share full scans with guild members who use AME",
            desc = "Announces your recent full scans to the guild and fetches ones you're missing, paced in the "
              .. "background so it never disrupts chat or raid addons. Received scans that disagree wildly with "
              .. "your own prices are rejected.",
            get = get,
            set = set,
          },
        },
      },
      data = {
        type = "group",
        inline = true,
        order = 20,
        name = "Data",
        args = {
          backfill = {
            type = "execute",
            order = 1,
            name = "Re-import Auctionator history",
            desc = "Fills days that have no AME data from Auctionator's recent price history (current realm).",
            func = function()
              ns.AME:Backfill(true)
            end,
          },
          index = {
            type = "execute",
            order = 2,
            name = "Rebuild market index",
            func = function()
              ns.AME:RebuildIndex()
            end,
          },
          selftest = {
            type = "execute",
            order = 3,
            name = "Run self-test",
            desc = "Checks every part of the addon, records timings, then reloads the UI.",
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

function Settings:Open()
  local AceConfigDialog = LibStub("AceConfigDialog-3.0", true)
  if AceConfigDialog then
    AceConfigDialog:Open(ADDON)
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
    icon = "Interface\\Icons\\INV_Misc_Coin_02",
    OnClick = function(_, button)
      if button == "RightButton" then
        Settings:Open()
      else
        ns.UI:Toggle()
      end
    end,
    OnTooltipShow = function(tt)
      tt:AddLine("|cff33ccffAzeroth|r Mercantile Exchange")
      tt:AddLine(ns.AME:CurrentShard(), 0.7, 0.7, 0.7)
      local last = AME_DB.stats.lastFull
      if last then
        tt:AddDoubleLine("Last full scan", date("%b %d %H:%M", last.at), 1, 1, 1, 1, 1, 1)
      end
      local index = ns.AME.index
      if index then
        tt:AddDoubleLine("Items tracked", tostring(index.count), 1, 1, 1, 1, 1, 1)
        local top = ns.MarketIndex.Rank(index, "score", function(s)
          return s.signal == "buy"
        end)
        if #top > 0 then
          tt:AddLine(" ")
          tt:AddLine("Top buy signals")
          for i = 1, math.min(3, #top) do
            local s = top[i]
            local name = W.ItemInfo(s.itemID) or ("item:" .. s.itemID)
            tt:AddDoubleLine(name, W.Money(s.market) .. "  " .. W.Percent(s.change7), 1, 1, 1, 1, 1, 1)
          end
        end
      end
      tt:AddLine(" ")
      tt:AddLine("|cffaaaaaaLeft-click: window   Right-click: settings|r")
    end,
  })
  local icon = LibStub("LibDBIcon-1.0", true)
  if icon and launcher then
    icon:Register(ADDON, launcher, AME_DB.settings.minimap)
  end
end
