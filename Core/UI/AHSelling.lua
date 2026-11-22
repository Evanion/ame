-- The Selling tab on the game's auction house window (next to Shopping, without Auctionator): what in your bags can
-- be listed, sorted by what it's worth, with AME's hints (VENDOR, DE, a recipe that makes it worth more). Click one
-- for AME's Quick / Normal / Patient prices (Posting:Suggest), the quantity, listing time, deposit and what you get,
-- and post it with the game's own posting (C_AuctionHouse.PostCommodity / PostItem: one click per post). What's on
-- sale now shows beside it, yours marked; click a listing to price just under it.
-- The game's Sell tab stays as it is (right-clicking an item in your bags fills it).
local _, ns = ...
local L = ns.L
local W = ns.Widgets

local S = { offset = 0 }
ns.AHSelling = S

S.LIST_W = 260
S.FORM_W = 280

local function money(c)
  return c and W.Money(math.floor(c + 0.5)) or W.NONE
end

-- Pure: bag slots -> one entry per item, with every slot holding it.
--   slots = { { key, count, loc, quality, icon, link, commodity } }
--   -> { { key, qty, locs = { loc, ... }, quality, icon, link, commodity } } in the order first seen
function S.Group(slots)
  local out, byKey = {}, {}
  for _, s in ipairs(slots) do
    local e = byKey[s.key]
    if not e then
      e =
        { key = s.key, qty = 0, locs = {}, quality = s.quality, icon = s.icon, link = s.link, commodity = s.commodity }
      byKey[s.key] = e
      out[#out + 1] = e
    end
    e.qty = e.qty + (s.count or 1)
    e.locs[#e.locs + 1] = s.loc
  end
  return out
end

-- Pure: what one unit nets, where: on the AH after the cut (s: the item's index summary), or at a vendor when that
-- pays more. -> each (copper), "ah" | "vendor", or nil
function S.Worth(s, vendor, cut)
  local ah = s and s.market and s.market > 0 and s.market * (1 - (cut or 0)) or nil
  if vendor and vendor > 0 and (not ah or vendor > ah) then
    return vendor, "vendor"
  end
  return ah, ah and "ah" or nil
end

-- Pure: entries (S.Group) valued and sorted by what all of each is worth, most first
--   summary(key) -> index summary; vendor(key) -> sell price; cut
function S.Rank(entries, summary, vendor, cut)
  for _, e in ipairs(entries) do
    local s = summary(e.key)
    e.each, e.where = S.Worth(s, vendor(e.key), cut)
    e.worth = (e.each or 0) * e.qty
    e.signal = s and s.signal
    e.summary = s
  end
  table.sort(entries, function(a, b)
    if a.worth ~= b.worth then
      return a.worth > b.worth
    end
    return a.key < b.key
  end)
  return entries
end

---------------------------------------------------------------------------------------------------------------------
-- in game: the bags

local function cut()
  local house = ns.AME:CurrentHouse()
  return ns.Settings:AuctionCut(house == "Neutral" and "Neutral" or house)
end

-- what in your bags can be listed here
function S.ScanBags()
  local C = C_Container
  local ah = C_AuctionHouse
  if not (C and C.GetContainerNumSlots and ah and ah.IsSellItemValid and ItemLocation) then
    return {}
  end
  local reagent = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or (NUM_BAG_SLOTS or 4)
  local commodity = Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity
  local slots = {}
  for bag = 0, math.max(NUM_BAG_SLOTS or 4, reagent) do
    for slot = 1, C.GetContainerNumSlots(bag) or 0 do
      local info = C.GetContainerItemInfo(bag, slot)
      if info and info.itemID then
        local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
        local ok, valid = pcall(ah.IsSellItemValid, loc, false)
        if ok and valid then
          local status = ah.GetItemCommodityStatus and ah.GetItemCommodityStatus(loc)
          slots[#slots + 1] = {
            key = ns.ItemCache.KeyAt(loc) or info.itemID,
            count = info.stackCount or 1,
            loc = loc,
            quality = info.quality,
            icon = info.iconFileID,
            link = info.hyperlink,
            commodity = commodity ~= nil and status == commodity,
          }
        end
      end
    end
  end
  return S.Group(slots)
end

function S:Refresh()
  local index = ns.AME:FactionIndex()
  local items = index and index.items or {}
  self.items = S.Rank(S.ScanBags(), function(k)
    return items[k]
  end, function(k)
    return ns.ItemCache.Get(k).sellPrice
  end, cut())
  -- a VENDOR item: a recipe you know may make it worth more (UI:CraftInstead)
  for _, e in ipairs(self.items) do
    if e.signal == "vendor" and ns.UI.CraftInstead then
      e.craft = ns.UI:CraftInstead(e.key)
    end
  end
end

---------------------------------------------------------------------------------------------------------------------
-- the panel

local function durations()
  local out = {}
  for i = 1, 3 do
    out[i] = { i, L["%d h"]:format(ns.Posting.DurationHours(i)) }
  end
  return out
end

local function defaultDuration()
  local want = ns.Settings:Get("listingHours")
  for i = 1, 3 do
    if ns.Posting.DurationHours(i) == want then
      return i
    end
  end
  return 2
end

function S:Create(ah)
  local p = CreateFrame("Frame", nil, ah, "BackdropTemplate")
  W.Skin(p, W.COLORS.bg)
  p:SetPoint("TOPLEFT", ah, "TOPLEFT", 8, -60)
  p:SetPoint("BOTTOMRIGHT", ah, "BOTTOMRIGHT", -8, 28)
  p:Hide()
  self.panel = p
  self.duration = defaultDuration()

  -- your bags: the main window's item table (icon, quality colour, tooltip), worth the most first
  local list, listInner = ns.AHShopping.Panel(p, 4)
  list:SetPoint("TOPLEFT", 0, 0)
  list:SetPoint("BOTTOMLEFT", 0, 0)
  list:SetWidth(S.LIST_W)
  p.list = list
  p.bags = ns.DataTable.New(listInner, {
    columns = {
      {
        key = "name",
        label = L["In your bags"],
        width = 150,
        item = true,
        suffix = function(e)
          local hint = ""
          if e.craft then
            hint = "  " .. W.Color("warn", L["make %s"]:format(ns.ItemCache.Name(e.craft.product) or "?"))
          elseif e.signal == "vendor" then
            hint = "  " .. W.Dim(L["vendor"])
          elseif e.signal == "disenchant" then
            hint = "  " .. W.Color("warn", L["DE"])
          end
          return (e.qty > 1 and W.Dim("  " .. W.Count(e.qty)) or "") .. hint
        end,
      },
      {
        key = "worth",
        label = L["Worth"],
        width = 64,
        text = function(e)
          return e.worth > 0 and W.Money(math.floor(e.worth + 0.5), true) or W.Dim("·")
        end,
      },
    },
    fill = true,
    rows = 12,
    rowHeight = 20,
    sort = { key = "worth", ascending = false },
    itemID = function(e)
      return e.key
    end,
    onClick = function(e)
      S:Select(e)
    end,
    selected = function(e)
      return S.entry ~= nil and S.entry.key == e.key
    end,
    rowAlpha = function(e)
      return e.signal == "vendor" and not e.craft and 0.6 or 1
    end,
  })
  p.empty = W.Text(listInner, "GameFontDisableSmall")
  p.empty:SetPoint("TOPLEFT", 6, -28)
  p.empty:SetPoint("RIGHT", -6, 0)
  p.empty:SetText(L["Nothing in your bags can be listed here."])

  -- the form, in a panel of its own
  local formPanel, form = ns.AHShopping.Panel(p, 10)
  formPanel:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
  formPanel:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 10, 0)
  formPanel:SetWidth(S.FORM_W + 20)
  p.formPanel = formPanel
  p.form = form
  p.icon = form:CreateTexture(nil, "ARTWORK")
  p.icon:SetSize(32, 32)
  p.icon:SetPoint("TOPLEFT", 0, 0)
  p.itemName = W.Text(form, "GameFontNormal")
  p.itemName:SetPoint("TOPLEFT", p.icon, "TOPRIGHT", 8, -1)
  p.itemName:SetPoint("RIGHT", 0, 0)
  p.itemName:SetWordWrap(false)
  p.itemInfo = W.Text(form, "GameFontDisableSmall")
  p.itemInfo:SetPoint("TOPLEFT", p.itemName, "BOTTOMLEFT", 0, -3)
  p.itemInfo:SetPoint("RIGHT", 0, 0)
  p.itemInfo:SetWordWrap(false)
  local priceHead = W.Text(form, "GameFontNormalSmall")
  priceHead:SetPoint("TOPLEFT", 0, -44)
  priceHead:SetText(L["Price each"])
  p.picks = {}
  for i, key in ipairs({ "quick", "normal", "patient" }) do
    local b = W.Button(form, "", S.FORM_W, 24, function()
      S:Pick(key)
    end)
    b:SetPoint("TOPLEFT", 0, -60 - (i - 1) * 28)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", 8, 0)
    b.label:SetJustifyH("LEFT")
    b.price = W.Text(b, "GameFontHighlightSmall", "RIGHT")
    b.price:SetPoint("RIGHT", -8, 0)
    b.key = key
    p.picks[i] = b
  end
  local inputs = CreateFrame("Frame", nil, form)
  inputs:SetPoint("TOPLEFT", 0, -150)
  inputs:SetSize(S.FORM_W, 36)
  local qtyLabel = W.Text(inputs, "GameFontDisableSmall")
  qtyLabel:SetPoint("TOPLEFT", 0, 0)
  qtyLabel:SetText(L["Quantity"])
  p.qty = W.Input(inputs, {
    width = 60,
    numeric = true,
    onChange = function(_, n, user)
      if user then
        S.qty = n
        S:Suggest()
      end
    end,
  })
  p.qty:SetPoint("TOPLEFT", 0, -13)
  local priceLabel = W.Text(inputs, "GameFontDisableSmall")
  priceLabel:SetPoint("TOPLEFT", 72, 0)
  priceLabel:SetText(L["Price each"])
  p.price = W.MoneyInput(inputs, L["gold"], function(copper, user)
    if user then
      S.price, S.picked = copper, nil
      S:RenderForm()
    end
  end)
  p.price:SetWidth(100)
  p.price:SetPoint("TOPLEFT", 72, -13)
  local durLabel = W.Text(inputs, "GameFontDisableSmall")
  durLabel:SetPoint("TOPLEFT", 186, 0)
  durLabel:SetText(L["Duration"])
  p.duration = W.Dropdown(inputs, 80, durations(), function(v)
    S.duration = v
    S:Suggest()
  end, { neutral = true, default = self.duration })
  p.duration:SetPoint("TOPLEFT", 186, -13)
  p.deposit = W.Text(form, "GameFontHighlightSmall")
  p.deposit:SetPoint("TOPLEFT", 0, -196)
  p.deposit:SetPoint("RIGHT", 0, 0)
  p.net = W.Text(form, "GameFontHighlightSmall")
  p.net:SetPoint("TOPLEFT", p.deposit, "BOTTOMLEFT", 0, -4)
  p.net:SetPoint("RIGHT", 0, 0)
  p.hint = W.Text(form, "GameFontHighlightSmall")
  p.hint:SetPoint("TOPLEFT", p.net, "BOTTOMLEFT", 0, -8)
  p.hint:SetPoint("RIGHT", 0, 0)
  p.post = W.Button(form, L["Post"], S.FORM_W, 28, function()
    S:Post()
  end)
  p.post:SetPoint("BOTTOMLEFT", 0, 0)
  W.Primary(p.post)
  p.result = W.Text(form, "GameFontDisableSmall")
  p.result:SetPoint("BOTTOMLEFT", p.post, "TOPLEFT", 0, 6)
  p.result:SetPoint("RIGHT", 0, 0)

  -- on sale now: a table like the others, yours marked; a click prices just under a listing
  local sale, saleInner = ns.AHShopping.Panel(p, 4)
  sale:SetPoint("TOPLEFT", formPanel, "TOPRIGHT", 10, 0)
  sale:SetPoint("BOTTOMRIGHT", 0, 0)
  p.sale = sale
  p.listings = ns.DataTable.New(saleInner, {
    columns = {
      {
        key = "price",
        label = L["On sale now"],
        width = 90,
        align = "LEFT",
        sortKey = false,
        text = function(r)
          return money(r.price)
        end,
      },
      { key = "qty", label = L["Qty"], width = 44, format = "count", sortKey = false },
      {
        key = "mine",
        label = "",
        width = 40,
        align = "LEFT",
        sortKey = false,
        text = function(r)
          return r.mine and W.Color("gold", L["yours"]) or ""
        end,
      },
    },
    fill = true,
    bottom = 28,
    rows = 10,
    rowHeight = 20,
    onClick = function(r)
      S:Undercut(r)
    end,
  })
  p.saleNote = W.Text(saleInner, "GameFontDisableSmall")
  p.saleNote:SetPoint("BOTTOMLEFT", 6, 4)
  p.saleNote:SetPoint("RIGHT", -6, 0)
  p.saleNote:SetText(L["Click a listing to price just under it."])

  p:HookScript("OnShow", function()
    S:Refresh()
    S:Render()
  end)
  return p
end

-- an item picked from the list: its listings searched, AME's prices worked out
function S:Select(entry)
  self.entry = entry
  self.picked, self.price = "normal", nil
  self.qty = entry and (entry.commodity and entry.qty or 1) or nil
  self.panel.result:SetText("")
  if entry then
    ns.AHSearch:Start({ entry.key }, function()
      S:Suggest()
    end)
    -- the AME window beside the auction house shows the item (its chart), as it does for a search
    if ns.UI.FollowAuctionItem then
      ns.UI:FollowAuctionItem(entry.key)
    end
  end
  self:Suggest()
end

-- AME's prices for the item, quantity and listing time (Posting:Suggest)
function S:Suggest()
  local e = self.entry
  self.advice = nil
  if e then
    local hours = ns.Posting.DurationHours(self.duration)
    local ok, advice = pcall(ns.Posting.Suggest, ns.Posting, ns.AME:CurrentShard(), e.key, self.qty or 1, hours)
    self.advice = ok and advice or nil
    if self.picked and self.advice and self.advice[self.picked] then
      self.price = self.advice[self.picked].price
    end
  end
  self:Render()
end

function S:Pick(key)
  self.picked = key
  local a = self.advice and self.advice[key]
  if a then
    self.price = a.price
  end
  self:RenderForm()
end

-- a listing clicked: just under it (yours: the same price)
function S:Undercut(row)
  if not row then
    return
  end
  self.picked = nil
  self.price = row.mine and row.price or math.max(1, row.price - 1)
  self:RenderForm()
end

-- the deposit the game asks for this post (nil when it can't say)
function S:Deposit()
  local e, a = self.entry, C_AuctionHouse
  if not (e and a and e.locs[1]) then
    return nil
  end
  local qty = self.qty or 1
  local ok, d
  if e.commodity and a.CalculateCommodityDeposit then
    ok, d = pcall(a.CalculateCommodityDeposit, ns.BaseID(e.key), self.duration, qty)
  elseif a.CalculateItemDeposit then
    ok, d = pcall(a.CalculateItemDeposit, e.locs[1], self.duration, qty)
  end
  return ok and d or nil
end

-- post it with the game's own posting: a stackable all at once, gear one at a time
function S:Post()
  local e, a = self.entry, C_AuctionHouse
  local price, qty = self.price, self.qty or 1
  if not (e and a and price and price > 0 and qty > 0) then
    return false
  end
  local loc = e.locs[1]
  local ok, err
  if e.commodity then
    ok, err = pcall(a.PostCommodity, loc, self.duration, math.min(qty, e.qty), price)
  else
    ok, err = pcall(a.PostItem, loc, self.duration, 1, nil, price)
  end
  local p = self.panel
  if ok then
    p.result:SetText(W.Color("good", L["Posted %s at %s each"]:format(W.Count(e.commodity and qty or 1), money(price))))
    self.posted = e.key
  else
    p.result:SetText(W.Color("bad", L["The game didn't take the post: %s"]:format(tostring(err))))
  end
  return ok
end

-- after a post (or any bag change): the bags again, the same item kept selected while it's still there
function S:OnBagsChanged()
  local p = self.panel
  if not (p and p:IsShown()) then
    return
  end
  local key = self.entry and self.entry.key
  self:Refresh()
  self.entry = nil
  for _, e in ipairs(self.items or {}) do
    if e.key == key then
      self.entry = e
      self.qty = math.min(self.qty or 1, e.qty)
    end
  end
  if key and self.posted == key then
    self.posted = nil
    ns.AHSearch:Start({ key }, function()
      S:Render()
    end)
  end
  self:Render()
end

function S:RenderList()
  local p = self.panel
  local items = self.items or {}
  p.empty:SetShown(#items == 0)
  p.bags:SetData(items)
  p.bags:Render()
end

function S:RenderForm()
  local p, e, a = self.panel, self.entry, self.advice
  p.form:SetShown(e ~= nil)
  if not e then
    return
  end
  p.icon:SetTexture(e.icon or 134400)
  p.itemName:SetText(W.QualityText(e.quality, ns.ItemCache.Name(e.key) or ("item:" .. e.key)))
  local s = e.summary
  local info = {}
  if s and s.market then
    info[#info + 1] = L["market %s"]:format(money(s.market))
  end
  if s and s.signal and s.signal ~= "none" then
    info[#info + 1] = W.Signal(s.signal)
  end
  if s and s.sellRate then
    info[#info + 1] = L["~%s sold/day"]:format(W.Count(s.sellRate))
  end
  p.itemInfo:SetText(table.concat(info, W.Dim("  ·  ")))
  local labels = { quick = L["Quick"], normal = L["Normal"], patient = L["Patient"] }
  for _, b in ipairs(p.picks) do
    local c = a and a[b.key]
    if c then
      local when = c.hours and L["sells in %s"]:format(W.Hours(c.hours)) or L["may not sell"]
      b.label:SetText(labels[b.key] .. "  " .. W.Dim(when))
      b.price:SetText(money(c.price))
      b:Enable()
    else
      b.label:SetText(labels[b.key] .. "  " .. W.Dim(L["no suggestion yet"]))
      b.price:SetText("")
    end
    b:SetSelected(self.picked == b.key)
  end
  if not p.qty:HasFocus() then
    p.qty:SetText(tostring(self.qty or 1))
  end
  if not p.price:HasFocus() then
    p.price:SetCopper(self.price)
  end
  p.duration:SetValue(self.duration)
  local qty = self.qty or 1
  local deposit = self:Deposit()
  p.deposit:SetText(W.Dim(L["Deposit"] .. "  ") .. (deposit and money(deposit) or W.NONE))
  if self.price then
    local c = cut()
    p.net:SetText(
      W.Dim(L["You get, after the %d%% cut"]:format(math.floor(c * 100 + 0.5)) .. "  ")
        .. money(self.price * (e.commodity and qty or 1) * (1 - c))
    )
  else
    p.net:SetText("")
  end
  if e.craft then
    p.hint:SetText(W.Color("warn", ns.UI.CraftInsteadText(e.craft)))
  elseif e.where == "vendor" then
    p.hint:SetText(W.Color("bad", L["Vendor it: a vendor pays %s"]:format(money(e.each))))
  elseif a and a.hold then
    p.hint:SetText(W.Color("bad", L["unlikely to sell soon: consider holding"]))
  else
    p.hint:SetText("")
  end
  local n = e.commodity and math.min(qty, e.qty) or 1
  p.post:SetText(L["Post %s"]:format(W.Count(n)))
  p.post:SetEnabled((self.price or 0) > 0 and n > 0)
end

function S:RenderListings()
  local p, e = self.panel, self.entry
  local book = e and ns.AHSearch.results[e.key]
  p.listings:SetData(book and book.rows or {})
  p.listings:SetMessage(
    e and (book and (#book.rows == 0 and L["none listed"] or nil) or L["searching..."])
      or L["Pick an item on the left."]
  )
  p.listings:Render()
  p.saleNote:SetShown(book ~= nil and #book.rows > 0)
end

function S:Render()
  local p = self.panel
  if not (p and p:IsShown()) then
    return
  end
  self:RenderList()
  self:RenderForm()
  self:RenderListings()
end

if CreateFrame then -- not in the pure specs
  local events = CreateFrame("Frame")
  pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED")
  pcall(events.RegisterEvent, events, "AUCTION_HOUSE_AUCTION_CREATED")
  events:SetScript("OnEvent", function()
    S:OnBagsChanged()
  end)
end
