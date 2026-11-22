-- At a vendor: what it sells that your shopping lists still need, beside the game's merchant window, to buy the
-- right amount in a click (per row, or all of it). Only shown when a list needs something this vendor sells.
--
--   need   what's still missing on your shopping lists (Shopping.Progress; summed over lists). The craft queue's
--          reagents count once "Missing to shopping list" has put them on its Craft queue list.
--   buys   rounded up to the vendor's stack (Empty Vial comes in 5s: need 23, buys 25)
-- Bought items land in your bags, so the rows count down on their own; the panel goes with the last one.
local _, ns = ...
local L = ns.L
local W = ns.Widgets

local V = { rows = {} }
ns.VendorPanel = V

V.WIDTH = 380
V.MAX_ROWS = 10

-- Pure: what your lists still need, per item: { [key] = units } (lists: { { items = { [key] = { need } } } })
function V.Needs(lists, holdings)
  -- every list's need added up first, what you hold taken off once (two lists wanting thread share your stock)
  local combined = {}
  for _, l in ipairs(lists or {}) do
    for key, want in pairs(l.items or {}) do
      combined[key] = { need = (combined[key] and combined[key].need or 0) + (want.need or 0) }
    end
  end
  local out = {}
  for _, r in ipairs(ns.Shopping.Progress(combined, holdings, nil)) do
    if r.missing > 0 then
      out[r.itemID] = r.missing
    end
  end
  return out
end

-- Pure: the vendor's goods your lists need. offers: { { index, key, price (per purchase), stack (units per
-- purchase), available (-1: unlimited) } } -> rows { index, key, need, buys (units), cost } in the vendor's order
function V.Rows(needs, offers)
  local rows = {}
  for _, o in ipairs(offers or {}) do
    local need = needs[o.key]
    if need and need > 0 and (o.price or 0) > 0 then
      local stack = math.max(1, o.stack or 1)
      local purchases = math.ceil(need / stack)
      if o.available and o.available >= 0 then
        purchases = math.min(purchases, o.available)
      end
      if purchases > 0 then
        rows[#rows + 1] = {
          index = o.index,
          key = o.key,
          itemID = o.key,
          need = need,
          stack = stack,
          buys = purchases * stack,
          cost = purchases * o.price,
          maxStack = o.maxStack,
        }
      end
    end
  end
  return rows
end

-- Pure: the game's purchases for a row: units per BuyMerchantItem call, whole stacks, at most maxStack units each
function V.Purchases(buys, stack, maxStack)
  stack = math.max(1, stack or 1)
  local per = math.max(stack, math.floor((maxStack or buys) / stack) * stack)
  local out, left = {}, buys
  while left > 0 do
    local n = math.min(left, per)
    out[#out + 1] = n
    left = left - n
  end
  return out
end

---------------------------------------------------------------------------------------------------------------------
-- in game

-- what the open vendor sells for gold: offers as V.Rows wants them
function V.Offers()
  local n = _G.GetMerchantNumItems and _G.GetMerchantNumItems() or 0
  local out = {}
  for i = 1, n do
    local id = _G.GetMerchantItemID and _G.GetMerchantItemID(i)
    local info = C_MerchantFrame and C_MerchantFrame.GetItemInfo and C_MerchantFrame.GetItemInfo(i)
    local price, stack, available, extended
    if info then
      price, stack, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
    elseif _G.GetMerchantItemInfo then
      local _, _, p, q, a, _, _, e = _G.GetMerchantItemInfo(i)
      price, stack, available, extended = p, q, a, e
    end
    if id and price and price > 0 and not extended then
      out[#out + 1] = {
        index = i,
        key = id,
        price = price,
        stack = stack or 1,
        available = available or -1,
        maxStack = _G.GetMerchantItemMaxStack and _G.GetMerchantItemMaxStack(i) or nil,
      }
    end
  end
  return out
end

function V:Work()
  local shop = ns.AME and ns.AME.shopping
  local needs = V.Needs(shop and shop:Lists() or {}, AME_DB and AME_DB.holdings or {})
  return V.Rows(needs, V.Offers())
end

function V:Buy(row)
  if not (row and _G.BuyMerchantItem) then
    return false
  end
  for _, n in ipairs(V.Purchases(row.buys, row.stack, row.maxStack)) do
    _G.BuyMerchantItem(row.index, n)
  end
  return true
end

-- everything, as far as your gold goes
function V:BuyAll()
  local money = _G.GetMoney and _G.GetMoney() or math.huge
  for _, row in ipairs(self.rows or {}) do
    if row.cost <= money then
      self:Buy(row)
      money = money - row.cost
    end
  end
end

function V:Create(host)
  local f = CreateFrame("Frame", nil, host, "BackdropTemplate")
  W.Skin(f, W.COLORS.bg)
  f:SetWidth(V.WIDTH)
  f:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
  f:Hide()
  f.title = W.Text(f, "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 10, -10)
  f.title:SetText(L["For your lists"])
  f.sub = W.Text(f, "GameFontDisableSmall")
  f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.sub:SetPoint("RIGHT", -10, 0)
  f.sub:SetText(L["what this vendor sells that your shopping lists still need"])
  local box = CreateFrame("Frame", nil, f)
  box:SetPoint("TOPLEFT", 8, -44)
  box:SetPoint("RIGHT", -8, 0)
  box:SetPoint("BOTTOM", 0, 40)
  f.table = ns.DataTable.New(box, {
    columns = {
      { key = "name", label = L["Item"], width = 130, item = true },
      { key = "need", label = L["Need"], width = 40, format = "count" },
      {
        key = "buys",
        label = L["Buys"],
        width = 60,
        text = function(r)
          return r.stack > 1 and (W.Count(r.buys) .. W.Dim((" (%d×%d)"):format(r.buys / r.stack, r.stack)))
            or W.Count(r.buys)
        end,
      },
      { key = "cost", label = L["Cost"], width = 60, format = "money" },
    },
    fill = true,
    rows = V.MAX_ROWS,
    rowHeight = 20,
    itemID = function(r)
      return r.key
    end,
    action = {
      label = L["Buy"],
      width = 40,
      onClick = function(r)
        V:Buy(r)
      end,
      enabled = function(r)
        return not _G.GetMoney or r.cost <= _G.GetMoney()
      end,
    },
  })
  f.totalLabel = W.Text(f, "GameFontDisableSmall")
  f.totalLabel:SetPoint("BOTTOMLEFT", 10, 14)
  f.total = W.Text(f, "GameFontHighlightSmall")
  f.total:SetPoint("LEFT", f.totalLabel, "RIGHT", 6, 0)
  f.buyAll = W.Button(f, L["Buy all"], 80, 22, function()
    V:BuyAll()
  end)
  f.buyAll:SetPoint("BOTTOMRIGHT", -10, 9)
  W.Primary(f.buyAll)
  self.frame = f
  return f
end

-- shown only when a list needs something this vendor sells
function V:Refresh()
  local host = _G.MerchantFrame
  if not (host and host.IsShown and host:IsShown()) then
    if self.frame then
      self.frame:Hide()
    end
    return
  end
  local ok, rows = pcall(self.Work, self)
  rows = ok and rows or {}
  self.rows = rows
  if #rows == 0 then
    if self.frame then
      self.frame:Hide()
    end
    return
  end
  local f = self.frame or self:Create(host)
  f:SetHeight(44 + 20 + math.min(#rows, V.MAX_ROWS) * 20 + 48)
  f:Show()
  local total = 0
  for _, r in ipairs(rows) do
    total = total + r.cost
  end
  f.totalLabel:SetText(L["All of it"])
  local money = _G.GetMoney and _G.GetMoney()
  f.total:SetText(W.Money(total) .. (money and W.Dim("  ·  " .. L["you have"] .. " ") .. W.Money(money) or ""))
  f.buyAll:SetEnabled(not money or total <= money or rows[1].cost <= money)
  f.table:SetData(rows)
  f.table:Render()
end

if CreateFrame then -- not in the pure specs
  local events = CreateFrame("Frame")
  for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED", "PLAYER_MONEY" }) do
    pcall(events.RegisterEvent, events, e)
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
      if V.frame then
        V.frame:Hide()
      end
    elseif event == "MERCHANT_SHOW" or (V.frame and V.frame:IsShown()) or event == "MERCHANT_UPDATE" then
      V:Refresh()
    end
  end)
end
