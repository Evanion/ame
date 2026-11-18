-- Posting price help in the auction house's own sell window: a bar under the auction house with Quick / Normal /
-- Patient prices for the item in the sell slot (Posting:Suggest). A click fills in the price; you still click Post
-- yourself. Works with the default auction house (and the old one); inside other addons' sell tabs the bar shows
-- while the default sell frame is open.
local _, ns = ...
local L = ns.L
local W = ns.Widgets

local Sell = {}
ns.SellAssist = Sell

Sell.REFRESH = 0.5 -- seconds between checks of the sell slot
Sell.RECOMPUTE = 3 -- recompute at least this often (a new search of the item updates its order book)

local function itemIDAt(location)
  local ok, id = pcall(function()
    return C_Item.GetItemID(location)
  end)
  return ok and id or nil
end

local function call(obj, method, ...)
  if obj and obj[method] then
    local ok, v = pcall(obj[method], obj, ...)
    if ok then
      return v
    end
  end
  return nil
end

-- the sell frames of the current auction house: { frame, read() -> itemID, qty, hours; set(price, qty) }
local function sources()
  local out = {}
  local ah = AuctionHouseFrame
  if ah then
    for _, key in ipairs({ "CommoditiesSellFrame", "ItemSellFrame" }) do
      local f = rawget(ah, key) or ah[key]
      if type(f) == "table" then
        out[#out + 1] = {
          frame = f,
          read = function()
            local location = call(f, "GetItem")
            local id = location and itemIDAt(location)
            if not id then
              return nil
            end
            return id, call(f, "GetQuantity") or 1, ns.Posting.DurationHours(call(f, "GetDuration") or 3)
          end,
          set = function(price)
            call(f.PriceInput, "SetAmount", price) -- unit price (commodities) / buyout per item (items)
            call(f, "UpdatePostState")
          end,
        }
      end
    end
  end
  if AuctionFrameAuctions and GetAuctionSellItemInfo then -- the old auction house
    local f = AuctionFrameAuctions
    out[#out + 1] = {
      frame = f,
      read = function()
        local name, _, count, _, _, _, _, _, _, id = GetAuctionSellItemInfo()
        if not (name and id) then
          return nil
        end
        local d = f.duration or 3
        return id, count or 1, d > 3 and math.floor(d / 60) or ns.Posting.DurationHours(d)
      end,
      set = function(price, qty)
        if MoneyInputFrame_SetCopper and BuyoutPrice then
          local total = f.priceType == 1 and price or price * qty -- per unit, or per stack (the classic default)
          MoneyInputFrame_SetCopper(BuyoutPrice, total)
          if StartPrice then
            MoneyInputFrame_SetCopper(StartPrice, total)
          end
        end
      end,
    }
  end
  return out
end

-- recompute on the next check (new listings for the item in the sell slot)
function Sell:Invalidate()
  self.key = nil
end

function Sell:Active()
  for _, src in ipairs(sources()) do
    if src.frame and src.frame.IsVisible and src.frame:IsVisible() then
      return src
    end
  end
  return nil
end

function Sell:Build(parent)
  local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  W.Skin(bar, W.COLORS.bg or W.COLORS.panel, W.COLORS.border)
  bar:SetHeight(30)
  bar:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 0, -2)
  bar:SetPoint("TOPRIGHT", parent, "BOTTOMRIGHT", 0, -2)
  bar:EnableMouse(true)
  ns.Help.Explain(bar, "posting")
  bar.title = W.Text(bar, "GameFontNormalSmall")
  bar.title:SetPoint("LEFT", 8, 0)
  bar.buttons = {}
  local prev = bar.title
  for _, key in ipairs({ "quick", "normal", "patient" }) do
    local b = W.Button(bar, "", 170, 20, function()
      local a, src = Sell.advice, Sell.src
      if a and src then
        src.set(a[key].price, a.qty)
      end
    end)
    b:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    b.key = key
    bar.buttons[#bar.buttons + 1] = b
    prev = b
  end
  bar.info = W.Text(bar, "GameFontDisableSmall")
  bar.info:SetPoint("LEFT", prev, "RIGHT", 10, 0)
  bar.info:SetPoint("RIGHT", -8, 0)
  bar.info:SetJustifyH("LEFT")
  bar.info:SetWordWrap(false)
  bar:Hide()
  return bar
end

local LABEL = { quick = L["Quick %s"], normal = L["Normal %s"], patient = L["Patient %s"] }

function Sell:Refresh()
  local bar = self.bar
  local src = self:Active()
  local id, qty, hours
  if src then
    id, qty, hours = src.read()
  end
  if not id then
    bar:Hide()
    self.key, self.advice = nil, nil
    return
  end
  local key = ("%d:%d:%d"):format(id, qty, hours)
  local t = GetTime()
  if key == self.key and t - (self.at or 0) < Sell.RECOMPUTE then
    return
  end
  self.key, self.at, self.src = key, t, src
  local ok, advice = pcall(ns.Posting.Suggest, ns.Posting, ns.AME:CurrentShard(), id, qty, hours)
  if not ok then
    ns.AME:ReportError("posting price", advice)
  end
  advice = ok and advice or nil
  self.advice = advice
  bar.title:SetText(W.Confidence(advice and advice.confidence or "low") .. " " .. W.Color("gold", L["Post at"]))
  for _, b in ipairs(bar.buttons) do
    b:SetShown(advice ~= nil)
    if advice then
      b.label:SetText(LABEL[b.key]:format(W.PostChoice(advice[b.key])))
    end
  end
  if not advice then
    bar.info:SetText(L["Posting price: not enough data on this item yet."])
  else
    local info = L["%d ahead"]:format(advice.normal.ahead)
      .. "  ·  "
      .. L["deposit %s"]:format(W.Money(advice.deposit))
    if advice.hold then
      info = info .. "  ·  " .. W.Color("bad", L["unlikely to sell soon: consider holding"])
    end
    bar.info:SetText(info)
  end
  bar:Show()
end

-- attach to whichever auction house window the game shows (once)
function Sell:Attach()
  local parent = AuctionHouseFrame or AuctionFrame
  if self.bar or not parent then
    return
  end
  self.bar = self:Build(parent)
  local ticker = CreateFrame("Frame", nil, parent) -- runs only while the auction house is open
  local elapsed = 0
  ticker:SetScript("OnUpdate", function(_, dt)
    elapsed = elapsed + dt
    if elapsed >= Sell.REFRESH then
      elapsed = 0
      Sell:Refresh()
    end
  end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("AUCTION_HOUSE_SHOW")
events:SetScript("OnEvent", function()
  Sell:Attach()
end)
