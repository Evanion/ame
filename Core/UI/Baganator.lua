-- Baganator (bag addon) plugins, from its API (Baganator.API, when it's installed):
--   two icon corner widgets - "AME: signal" (the item's market signal, as its icon) and "AME: value" (what the stack
--   is worth: Quote:BestSale x count, as the Selling tab values it). Players pick corners in Baganator's settings
--   (Icons); AME places none by itself.
--   a junk plugin - "AME: vendor is better": grey items, and items whose listing nets less than a vendor pays (the
--   VENDOR signal; the Selling tab's "vendor" tip). Baganator greys junk out and can sort it last.
-- Built on AME's public API (Core/API.lua), so it shows the same numbers as AME's tooltip and tabs.
local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Bag = {}
ns.Baganator = Bag

-- what fits on a bag slot: one unit, rounded - "1.2kg", "12g", "2.5g", "45s", "8c"
function Bag.SlotMoney(copper)
  if not copper or copper <= 0 then
    return nil
  end
  local g = copper / 10000
  local text, unit
  if g >= 1000 then
    local k = g / 1000
    text, unit = k < 10 and ("%.1fk"):format(math.floor(k * 10) / 10) or ("%dk"):format(math.floor(k)), "g"
  elseif g >= 10 then
    text, unit = tostring(math.floor(g + 0.5)), "g"
  elseif g >= 1 then
    local t = math.floor(g * 10 + 0.5) / 10
    text, unit = (t == math.floor(t)) and tostring(t) or ("%.1f"):format(t), "g"
  elseif copper >= 100 then
    text, unit = tostring(math.floor(copper / 100 + 0.5)), "s"
  else
    text, unit = tostring(math.floor(copper + 0.5)), "c"
  end
  text = text:gsub("%.0([kg]?)$", "%1")
  return "|cff" .. W.COIN_HEX[unit] .. text .. unit .. "|r"
end

-- junk: grey items, and items AME prices whose listing nets less than a vendor pays
function Bag.IsJunk(api, quality, item)
  if quality == 0 then
    return true
  end
  return api.GetSignal(item) == "vendor"
end

function Bag:Install()
  local B = _G.Baganator
  local api = ns.API and ns.API.v1
  if self.installed or not (B and B.API and B.API.RegisterCornerWidget and api) then
    return
  end
  self.installed = true

  B.API.RegisterCornerWidget(L["AME: signal"], "ame_signal", function(icon, details)
    if not details.itemLink then
      return nil
    end
    local signal = api.GetSignal(details.itemLink)
    local file = signal and W.SIGNAL_ICON[signal]
    if not file then
      return false
    end
    icon:SetTexture(W.SIGNAL_MEDIA .. file)
    local c = W.RGB(W.SignalRole(signal))
    icon:SetVertexColor(c[1], c[2], c[3])
    return true
  end, function(button)
    local icon = button:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon.padding = 0
    return icon
  end)

  B.API.RegisterCornerWidget(L["AME: value"], "ame_value", function(text, details)
    if not details.itemLink then
      return nil
    end
    local each = api.GetWorth(details.itemLink)
    local shown = each and Bag.SlotMoney(each * (details.itemCount or 1))
    if not shown then
      return false
    end
    text:SetText(shown)
    return true
  end, function(button)
    local text = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    text.sizeFont = true
    return text
  end)

  if B.API.RegisterJunkPlugin then
    B.API.RegisterJunkPlugin(L["AME: vendor is better"], "ame_vendor", function(_, _, _, itemLink)
      if not itemLink then
        return false
      end
      local key = ns.API.KeyOf(itemLink)
      local quality = key and ns.ItemCache.Get(key).quality
      return Bag.IsJunk(api, quality, itemLink)
    end)
  end

  -- new prices: Baganator redraws its slots
  api.RegisterForUpdates("Baganator", function()
    if B.API.RequestItemButtonsRefresh then
      B.API.RequestItemButtonsRefresh()
    end
  end)
end
