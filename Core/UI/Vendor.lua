-- At a vendor (board VendorSell): beside the game's merchant window, when your bags hold something to sell here -
-- what AME tips Vendor (a vendor pays more than the auction house would net) and grey junk. One button sells them;
-- the game's buyback keeps them until you leave. Right-click a row to keep that item (it stays off the list).
-- Its own small frame, drawn by its own layout renderer (the frametitle, table, keyvalue, button and check widgets).
--
--   Vendor.Rows(slots, worth, opts) -> rows      pure: slots { { key, count, quality, sellPrice, bag, slot,
--                                                noValue? } }, worth(key) -> net, where, listed (Quote:BestSale and
--                                                whether the item has an auction house price); opts.keep { [key] },
--                                                opts.junk (grey items too). Rows { key, item, count, why, pays,
--                                                slots = { {bag, slot}, ... } }: Vendor first, then Junk, most first
--   Vendor.Selling(rows, junk) -> rows           the rows the button sells
--   Vendor.Plan(rows, limit) -> { {bag, slot}, ... }   the slots one click sells (at most the buyback's 12)
--   Vendor.Tree(rows, total, count, junk) -> layout tree
local _, ns = ...
local L = ns.L

local Layout, Kit = ns.Layout, ns.Kit

local Vendor = { BUYBACK = 12, W = 360, H = 440 }
ns.Vendor = Vendor

function Vendor.Rows(slots, worth, opts)
  opts = opts or {}
  local keep = opts.keep or {}
  local byKey, out = {}, {}
  for _, s in ipairs(slots or {}) do
    local key = s.key
    local each = s.sellPrice or 0
    if key and each > 0 and not s.noValue and not keep[key] then
      local why
      if s.quality == 0 then
        why = "junk"
      else
        local _, where, listed = worth(key)
        if where == "vendor" and listed then
          why = "vendor"
        end
      end
      if why then
        local r = byKey[key]
        if not r then
          r = { key = key, item = key, count = 0, pays = 0, why = why, slots = {} }
          byKey[key] = r
          out[#out + 1] = r
        end
        r.count = r.count + (s.count or 1)
        r.pays = r.pays + each * (s.count or 1)
        r.slots[#r.slots + 1] = { bag = s.bag, slot = s.slot }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.why ~= b.why then
      return a.why == "vendor"
    end
    if a.pays ~= b.pays then
      return a.pays > b.pays
    end
    return a.key < b.key
  end)
  return out
end

function Vendor.Selling(rows, junk)
  local out = {}
  for _, r in ipairs(rows) do
    if r.why == "vendor" or junk then
      out[#out + 1] = r
    end
  end
  return out
end

function Vendor.Plan(rows, limit)
  limit = limit or Vendor.BUYBACK
  local out = {}
  for _, r in ipairs(rows) do
    for _, s in ipairs(r.slots) do
      if #out >= limit then
        return out
      end
      out[#out + 1] = s
    end
  end
  return out
end

-- the table's rows: the item, how many, why, what the vendor pays for all of them
local function tableRows(rows)
  local out = {}
  for i, r in ipairs(rows) do
    out[i] = {
      key = r.key,
      item = r.item,
      count = r.count,
      why = r.why == "vendor" and { text = L["Vendor"], color = "vendor" } or { text = L["Junk"], color = "dim" },
      pays = r.pays,
    }
  end
  return out
end
Vendor.TableRows = tableRows

function Vendor.Tree(_, total, count, junk)
  return {
    id = "vendor",
    type = "column",
    props = { gap = 6, pad = 10 },
    children = {
      {
        id = "vendor.title",
        type = "frametitle",
        props = { title = L["Sell to this vendor"], note = count == 1 and L["1 item"] or L["%d items"]:format(count) },
        meta = { h = 20 },
      },
      {
        id = "vendor.table",
        type = "table",
        props = {
          source = "vendor",
          columns = {
            { key = "name", label = L["In your bags"], width = 150, item = true },
            { key = "count", label = "", width = 34, format = "count" },
            { key = "why", label = L["Why"], width = 54, align = "LEFT" },
            { key = "pays", label = L["Vendor pays"], width = 76, format = "money" },
          },
          note = L["Vendor: it pays more than the auction house would net. Junk: grey items. Right-click one to keep it."],
          action = "row",
          empty = L["Nothing to sell here"],
        },
        meta = { grow = 1 },
      },
      { id = "vendor.total", type = "keyvalue", props = { label = L["All of it"], copper = total }, meta = { h = 18 } },
      {
        id = "vendor.actions",
        type = "row",
        props = { gap = 8, align = "center" },
        meta = { h = 24 },
        children = {
          {
            id = "vendor.sell",
            type = "button",
            props = {
              label = count == 1 and L["Sell 1 item"] or L["Sell %d items"]:format(count),
              action = "sell",
              variant = count > 0 and "primary" or "disabled",
            },
          },
          {
            id = "vendor.junk",
            type = "check",
            props = { label = L["Junk too"], checked = junk, action = "junk" },
            meta = { h = 18 },
          },
        },
      },
      {
        id = "vendor.note",
        type = "text",
        props = { text = L["Sold by mistake? The vendor's buyback has it until you leave."], color = "dim", size = 11 },
        meta = { h = 16 },
      },
    },
  }
end

-- ------------------------------------------------------------------------------------------------ in game

local function state()
  AME_DB.vendorSell = AME_DB.vendorSell or { keep = {}, junk = true }
  local s = AME_DB.vendorSell
  s.keep = s.keep or {}
  if s.junk == nil then
    s.junk = true
  end
  return s
end

-- what's in your bags, slot by slot
function Vendor.Slots()
  local C = C_Container
  if not (C and C.GetContainerNumSlots and C.GetContainerItemInfo) then
    return {}
  end
  local out = {}
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    for slot = 1, C.GetContainerNumSlots(bag) or 0 do
      local info = C.GetContainerItemInfo(bag, slot)
      if info and info.itemID and not info.isLocked then
        local key = info.itemID
        if ItemLocation and ItemLocation.CreateFromBagAndSlot and ns.ItemCache and ns.ItemCache.KeyAt then
          local ok, k = pcall(ns.ItemCache.KeyAt, ItemLocation:CreateFromBagAndSlot(bag, slot))
          if ok and k and ns.BaseID(k) == info.itemID then
            key = k
          end
        end
        local item = ns.ItemCache and ns.ItemCache.Get(info.itemID) or {}
        out[#out + 1] = {
          key = key,
          count = info.stackCount or 1,
          quality = info.quality or item.quality,
          sellPrice = item.sellPrice,
          noValue = info.hasNoValue,
          bag = bag,
          slot = slot,
        }
      end
    end
  end
  return out
end

-- what one unit nets at the auction house or a vendor, and whether the auction house has a price for it
local function worthFn()
  local AME = ns.AME
  local index = AME and AME.FactionIndex and AME:FactionIndex()
  local q = index and ns.Quote.For(AME:FactionShard(), index, { fresh = false })
  return function(key)
    if not q then
      return nil
    end
    local net, where = q:BestSale(key)
    return net, where, q:ListingNet(key) ~= nil
  end
end

function Vendor:Work()
  local s = state()
  return Vendor.Rows(Vendor.Slots(), worthFn(), { keep = s.keep, junk = true })
end

function Vendor:Sell()
  if not (_G.MerchantFrame and _G.MerchantFrame:IsShown()) then
    return 0
  end
  local C = C_Container
  local use = C and C.UseContainerItem or _G.UseContainerItem
  if not use then
    return 0
  end
  local plan = Vendor.Plan(Vendor.Selling(self.rows or {}, state().junk))
  for _, s in ipairs(plan) do
    pcall(use, s.bag, s.slot)
  end
  return #plan
end

local handlers = {
  close = function()
    Vendor.closed = true -- until the next vendor
    if Vendor.frame then
      Vendor.frame:Hide()
    end
  end,
  -- the real click: the game's selling runs from it
  sell = function()
    Vendor:Sell()
  end,
  junk = function(p)
    state().junk = p and p.checked and true or false
    Vendor:Refresh()
  end,
  row = function(p)
    if p and p.button == "RightButton" and p.key then
      state().keep[p.key] = true -- kept: off the list
      Vendor:Refresh()
    end
  end,
}

function Vendor:Create(host)
  local f = CreateFrame("Frame", "AMEVendorSell", host, "BackdropTemplate")
  Kit.Box(f, "bg", "frame")
  f:SetSize(Vendor.W, Vendor.H)
  f:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  f:Hide()
  self.ctx = Layout.Context(handlers, { sources = {} })
  self.renderer = Layout.Renderer(f, self.ctx)
  self.frame = f
  return f
end

function Vendor.Enabled()
  return ns.App and ns.App.Enabled and ns.App.Enabled() or false
end

-- shown only at a merchant, while your bags hold something to sell there
function Vendor:Refresh()
  local host = _G.MerchantFrame
  if not (Vendor.Enabled() and host and host.IsShown and host:IsShown()) or Vendor.closed then
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
  local junk = state().junk
  local selling = Vendor.Selling(rows, junk)
  local total = 0
  for _, r in ipairs(selling) do
    total = total + r.pays
  end
  self.ctx.sources.vendor = tableRows(rows)
  f:Show()
  self.renderer:Render(Vendor.Tree(rows, total, #selling, junk))
end

if CreateFrame then
  local events = CreateFrame("Frame")
  for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "BAG_UPDATE_DELAYED" }) do
    pcall(events.RegisterEvent, events, e)
  end
  events:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_CLOSED" then
      Vendor.closed = false
      if Vendor.frame then
        Vendor.frame:Hide()
      end
    elseif event == "MERCHANT_SHOW" then
      Vendor.closed = false
      Vendor:Refresh()
    elseif Vendor.frame and Vendor.frame:IsShown() then
      Vendor:Refresh()
    end
  end)
end
