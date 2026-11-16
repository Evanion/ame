-- Item tooltip lines from the market index (no history decoding on hover) + Alt-click to open the item chart.
local _, ns = ...

local W = ns.Widgets

local Tooltip = {}
ns.Tooltip = Tooltip

Tooltip.AVG_DAYS = { 3, 7, 14, 30 }
local HOUSE_NAME = { Alliance = "Alliance AH", Horde = "Horde AH", Neutral = "Goblin AH" }
Tooltip.HOUSE_NAME = HOUSE_NAME

local function ago(day, today)
  if not (day and today) then
    return nil
  end
  local d = today - day
  if d <= 0 then
    return "today"
  elseif d == 1 then
    return "yesterday"
  end
  return d .. " days ago"
end

local DIM = "|cff999999"

-- Pure: tooltip rows for an item summary.
--   s       market summary (index item)
--   opts    avgDays (3/7/14/30), detail (bool: full view), today (day number),
--           others = { { house, summary }, ... }  same item at the market's other auction houses
-- returns { { left, right }, ... } (a row with only left is a plain line)
function Tooltip.Lines(s, opts)
  opts = opts or {}
  local rows = {}
  local function row(left, right)
    rows[#rows + 1] = { "|cff33ccffAME|r " .. left, right }
  end
  local change = s.change7 and ("  " .. W.Percent(s.change7) .. DIM .. " 7d|r") or ""
  row("market", W.Money(s.market) .. change)
  local days = opts.avgDays or 7
  local avg = s["avg" .. days] or s.avg30
  if avg then
    row(days .. "-day average", W.Money(avg))
  end
  if s.signal and s.signal ~= "none" then
    row("signal", W.Signal(s.signal) .. (opts.detail and (DIM .. "  score %+d|r"):format(s.score or 0) or ""))
  end
  if not opts.detail then
    rows[#rows + 1] = { DIM .. "Hold Shift for more AME data|r" }
    return rows
  end
  row("lowest", W.Money(s.min))
  local trend = s.supplyTrend30 and ("  " .. W.Percent(s.supplyTrend30 * 7, 0) .. DIM .. "/week|r") or ""
  row("supply", tostring(s.qty or 0) .. DIM .. " listed|r" .. trend)
  if s.vol30 then
    row("volatility", ("%.1f%%"):format(s.vol30 * 100))
  end
  if s.signal == "none" or not s.signal then
    row("score", ("%+d"):format(s.score or 0))
  end
  for _, o in ipairs(opts.others or {}) do
    local name = HOUSE_NAME[o[1]] or o[1]
    row(name, W.Money(o[2].market))
  end
  local seen = ago(s.day, opts.today)
  if seen then
    row("last data", seen)
  end
  return rows
end

-- the same item at the market's other auction houses (only from indexes already built, nothing on hover)
local function others(itemID)
  local AME = ns.AME
  local out = {}
  local realm = AME:MarketRealmName()
  local current = AME:CurrentHouse()
  for _, house in ipairs({ "Alliance", "Horde", "Neutral" }) do
    if house ~= current then
      local index = AME.indexes and AME.indexes[ns.ShardKey(realm, house)]
      local s = index and index.items[itemID]
      if s and s.market then
        out[#out + 1] = { house, s }
      end
    end
  end
  return out
end

local function addLines(tooltip, itemID)
  if ns.Settings and not ns.Settings:Get("tooltip") then
    return
  end
  local index = ns.AME and ns.AME.index
  local s = index and itemID and index.items[itemID]
  if not s then
    return
  end
  local detail = ns.Settings:Get("tooltipDetail") or (IsShiftKeyDown and IsShiftKeyDown())
  local rows = Tooltip.Lines(s, {
    avgDays = ns.Settings:Get("tooltipAvgDays"),
    detail = detail,
    today = math.floor(GetServerTime() / 86400),
    others = detail and others(itemID) or nil,
  })
  for _, r in ipairs(rows) do
    if r[2] then
      tooltip:AddDoubleLine(r[1], r[2], 0.9, 0.9, 0.9, 1, 1, 1)
    else
      tooltip:AddLine(r[1])
    end
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

  -- modified click on an item (bags, chat links, AH) opens its chart; modifier is configurable
  if HandleModifiedItemClick then
    hooksecurefunc("HandleModifiedItemClick", function(link)
      if link and ns.Settings:ClickModifierDown() then
        local id = ns.AME.ItemIDFrom(link)
        if id then
          ns.UI:ShowItem(id)
        end
      end
    end)
  end
end
