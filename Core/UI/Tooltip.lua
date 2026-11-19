-- Item tooltip lines from the market index (no history decoding on hover), and the modified click (Settings) that
-- opens an item's chart.
local _, ns = ...
local L = ns.L

local W = ns.Widgets

local Tooltip = {}
ns.Tooltip = Tooltip

local Dim = W.Dim

-- Pure: tooltip rows for an item summary. Three lines by default - market (vs the average period), supply and
-- sells per day, signal - and more with Shift (or the "always" setting): average, lowest, supply trend, volatility,
-- score, data confidence and age.
--   s       market summary (index item)
--   opts    avgDays (3/7/14/30), detail (bool: full view), today (day number)
-- returns { { left, right }, ... } (a row with only left is a plain line)
function Tooltip.Lines(s, opts)
  opts = opts or {}
  local rows = {}
  local function row(left, right)
    rows[#rows + 1] = { W.Color("brand", "AME") .. " " .. left, right }
  end
  local days = opts.avgDays or 7
  local avg = s["avg" .. days] or s.avg30
  local vs = ""
  if s.market and avg and avg > 0 and s.days ~= 1 then
    vs = "  " .. W.Percent(s.market / avg - 1) .. Dim(" " .. L["vs %dd avg"]:format(days))
  end
  row(L["market"], W.Money(s.market) .. vs)
  row(
    L["supply"],
    W.Count(s.qty or 0) .. Dim(" " .. L["listed"]) .. (s.sellRate and ("  ·  " .. W.Rate(s.sellRate)) or "")
  )
  local phase = s.phase and ns.Analytics and ns.Analytics.PHASE_LABEL[s.phase]
  local hint = not opts.detail and Dim("  " .. L["Shift: more"]) or ""
  if s.signal and s.signal ~= "none" then
    row(L["signal"], W.Signal(s.signal) .. (phase and Dim("  " .. phase:lower()) or "") .. hint)
  elseif not opts.detail then
    rows[#rows + 1] = { Dim(L["Hold Shift for more AME data"]) }
  end
  if not opts.detail then
    return rows
  end
  if avg then
    row(L["%d-day average"]:format(days), W.Money(avg))
  end
  row(L["lowest"], W.Money(s.min))
  if s.change7 then
    row(L["7d change"], W.Percent(s.change7))
  end
  if s.supplyTrend30 then
    row(L["supply trend"], W.Percent(s.supplyTrend30 * 7, 0) .. Dim(L["/week"]))
  end
  if s.vol30 then
    row(L["volatility"], ("%.1f%%"):format(s.vol30 * 100))
  end
  row(L["score"], ("%+d"):format(s.score or 0))
  local seen = ns.Widgets.DaysAgo(s.day, opts.today)
  if seen then
    local level = ns.Analytics and ns.Analytics.Confidence(s, opts.today) or nil
    local scans = L["%d scans/7d, %s"]:format(s.scans7 or 0, seen)
    row(L["data"], Dim(level and W.Confidence(level) or "") .. "  " .. scans)
  end
  return rows
end

-- Tooltips always show your own faction's auction house (the market you trade in), never the goblin AH or the
-- other faction's - even right after visiting those. Cross-AH comparisons live on the Arbitrage tab.
local function factionIndex()
  return ns.AME and ns.AME:FactionIndex()
end

-- the item's summary at your faction's auction house (nil when unknown)
function Tooltip.Summary(itemID)
  local index = factionIndex()
  return index and itemID and index.items[itemID] or nil
end

local function addLines(tooltip, itemID)
  if ns.Settings and not ns.Settings:Get("tooltip") then
    return
  end
  local s = Tooltip.Summary(itemID)
  if not s then
    return
  end
  local detail = ns.Settings:Get("tooltipDetail") or (IsShiftKeyDown and IsShiftKeyDown())
  local rows = Tooltip.Lines(s, {
    avgDays = ns.Settings:Get("tooltipAvgDays"),
    detail = detail,
    today = ns.Today(GetServerTime()),
  })
  for _, r in ipairs(rows) do
    if r[2] then
      W.TipPair(tooltip, r[1], r[2])
    else
      tooltip:AddLine(r[1])
    end
  end
end

function Tooltip:Install()
  if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
      if tooltip == GameTooltip or tooltip == ItemRefTooltip then
        -- the link carries a random suffix (data.id is only the base item)
        local link = data and data.hyperlink
        if not link and tooltip.GetItem then
          link = select(2, tooltip:GetItem())
        end
        addLines(tooltip, link and ns.ItemCache.Learn(link) or (data and data.id))
      end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    GameTooltip:HookScript("OnTooltipSetItem", function(tooltip)
      local _, link = tooltip:GetItem()
      addLines(tooltip, link and ns.ItemCache.Learn(link))
    end)
  end

  -- modified click on an item (bags, chat links, AH) opens its chart; modifier is configurable
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if link and ns.Settings:ClickModifierDown() then
        local id = ns.ItemCache.Learn(link)
        if id then
          ns.UI:ShowItem(id)
        end
      elseif link and IsShiftKeyDown() and not IsAltKeyDown() and not IsControlKeyDown() then
        ns.UI:OnItemLinkClicked(link)
      end
    end)
  end
end
