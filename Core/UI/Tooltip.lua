-- Item tooltip lines from the market index (no history decoding on hover) + Alt-click to open the item chart.
local _, ns = ...

local W = ns.Widgets

local Tooltip = {}
ns.Tooltip = Tooltip

local function addLines(tooltip, itemID)
  local index = ns.AME and ns.AME.index
  local s = index and itemID and index.items[itemID]
  if not s then
    return
  end
  tooltip:AddDoubleLine(
    "|cff33ccffAME|r market",
    W.Money(s.market) .. "  " .. W.Percent(s.change7) .. " |cff9999997d|r",
    0.9,
    0.9,
    0.9,
    1,
    1,
    1
  )
  tooltip:AddDoubleLine(
    "|cff33ccffAME|r 30d avg · supply",
    W.Money(s.avg30) .. "  ·  " .. tostring(s.qty or 0),
    0.9,
    0.9,
    0.9,
    1,
    1,
    1
  )
  if s.signal ~= "none" then
    tooltip:AddDoubleLine("|cff33ccffAME|r signal", W.Signal(s.signal), 0.9, 0.9, 0.9, 1, 1, 1)
  end
end

function Tooltip:Install()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then
        addLines(tooltip, data and data.id)
      end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      addLines(tooltip, link and ns.AME.ItemIDFrom(link))
    end)
  end

  -- Alt-click an item (bags, chat links, AH) to open its chart
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if IsAltKeyDown() and link and not IsShiftKeyDown() and not IsControlKeyDown() then
        local id = ns.AME.ItemIDFrom(link)
        if id then
          ns.UI:ShowItem(id)
        end
      end
    end)
  end
end
