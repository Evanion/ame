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

S.LIST_W = 300
S.FORM_W = 260 -- the form's controls (its panel is 20 wider)

local money = W.Money

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

-- What the Tip column says to do with it: "auction" (list it: you're at the auction house), "craft" (make something
-- worth more first), "disenchant", "vendor", or nil (no price)
function S.Tip(e)
  if e.craft then
    return "craft"
  elseif e.signal == "vendor" or e.signal == "disenchant" then
    return e.signal
  elseif e.where == "ah" then
    return "auction"
  end
end

-- the Tip column's order: auction first, then make first, disenchant, vendor, then the rest; worth the most first
-- in each (one number, so the table sorts by it)
S.MARKET_GAP = 10 -- the Market pick, set off from AME's three prices (px)
S.TIP_RANK = { auction = 1, craft = 2, disenchant = 3, vendor = 4 }
function S.TipOrder(e)
  return (S.TIP_RANK[S.Tip(e) or ""] or 9) * 1e12 - (e.worth or 0)
end

-- Pure: entries (S.Group) valued and sorted by what all of each is worth, most first
--   summary(key) -> index summary; worth(key) -> what one unit nets and where ("ah" | "vendor"; Quote:BestSale)
function S.Rank(entries, summary, worth)
  for _, e in ipairs(entries) do
    local s = summary(e.key)
    e.each, e.where = worth(e.key)
    if e.where ~= "ah" and e.where ~= "vendor" then
      e.each, e.where = nil, nil
    end
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

-- the cut where you post: the auction house you're at
local function cut()
  return ns.Quote.Cut(ns.AME:CurrentHouse())
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
  -- items you've hidden (the item menu's Hide, as everywhere in AME) stay out of the list
  local watch = ns.AME.watch
  local shown = {}
  for _, e in ipairs(S.ScanBags()) do
    if not (watch and watch:IsHidden(e.key)) then
      shown[#shown + 1] = e
    end
  end
  -- what a unit nets where you post (Quote:BestSale: listed after the cut and deposit, or at a vendor)
  local q = ns.Quote.For(ns.AME:FactionShard(), index, { house = ns.AME:CurrentHouse(), fresh = false })
  -- (no index yet - it's loaded a few seconds after login: no verdicts, rather than a vendor's price for
  -- everything; IndexReady lists them again)
  self.items = S.Rank(shown, function(k)
    return items[k]
  end, function(k)
    if not index then
      return nil
    end
    return q:BestSale(k)
  end)
  -- a VENDOR item: a recipe you know may make it worth more (UI:CraftInstead)
  for _, e in ipairs(self.items) do
    if e.signal == "vendor" and ns.UI.CraftInstead then
      e.craft = ns.UI:CraftInstead(e.key)
    end
    e.tip = S.TipOrder(e)
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
        width = 120,
        item = true,
        suffix = function(e)
          return e.qty > 1 and W.Dim("  " .. W.Count(e.qty)) or ""
        end,
      },
      -- the tip, one short word in a narrow column of its own (the item gets the width): list it ("Sell"), make
      -- something worth more first ("Arbitrate": what to make shows when you pick it), disenchant it, vendor it
      {
        key = "hint",
        label = L["Tip"],
        width = 52,
        sortKey = "tip",
        ascendingFirst = true, -- what to list at the top
        text = function(e)
          local tip = S.Tip(e)
          if tip == "auction" then
            return L["Sell"]
          elseif tip == "craft" then
            return W.Color("warn", L["Arbitrate"])
          elseif tip == "vendor" then
            return W.Dim(L["vendor"])
          elseif tip == "disenchant" then
            return W.Color("disenchant", L["DE"])
          end
          return ""
        end,
      },
      {
        key = "worth",
        label = L["Worth"],
        width = 64,
        text = function(e)
          return e.worth > 0 and W.Money(e.worth, true) or W.Dim("·")
        end,
      },
    },
    fill = true,
    rows = 12,
    rowHeight = 20,
    note = L["Worth: all of it, on the AH after the cut, or at a vendor when that pays more."],
    sort = { key = "worth", ascending = false },
    itemMenu = { hide = true }, -- right-click: the item menu as in the AME window, Hide included
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

  -- the form, in a panel of its own
  local formPanel, form = ns.AHShopping.Panel(p, 10)
  formPanel:SetPoint("TOPLEFT", list, "TOPRIGHT", 10, 0)
  formPanel:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 10, 0)
  formPanel:SetWidth(S.FORM_W + 20)
  p.formPanel = formPanel
  p.form = form
  -- the item you're posting, as a link (hover: its tooltip; Shift-click: link it in chat), with how many you have
  p.item = W.ItemLink(form, { icon = 32, font = "GameFontNormal", top = true, maxWidth = S.FORM_W })
  p.item:SetPoint("TOPLEFT", 0, 0)
  p.icon, p.itemName = p.item.icon, p.item.name
  -- under it: the market price, the signal as a badge, how many sell a day
  p.itemInfo = W.Text(form, "GameFontDisableSmall")
  p.itemInfo:SetPoint("TOPLEFT", p.item.name, "BOTTOMLEFT", 0, -3)
  p.itemInfo:SetWordWrap(false)
  p.signal = W.SignalBadge(form)
  p.signal:SetPoint("LEFT", p.itemInfo, "RIGHT", 6, 0)
  p.itemRate = W.Text(form, "GameFontDisableSmall")
  p.itemRate:SetWordWrap(false)
  local priceHead = W.Text(form, "GameFontNormalSmall")
  priceHead:SetPoint("TOPLEFT", 0, -44)
  priceHead:SetText(L["Price each"])
  p.picks = {}
  -- AME's three prices, then the item's market price as it is (Posting:Suggest's advice.market)
  for i, key in ipairs({ "quick", "normal", "patient", "market" }) do
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
  -- under the picks (RenderForm places it: as many picks as show)
  local inputs = CreateFrame("Frame", nil, form)
  inputs:SetPoint("TOPLEFT", 0, -178)
  inputs:SetSize(S.FORM_W, 36)
  p.inputs = inputs
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
  p.qty:SetWidth(56)
  p.qty:SetPoint("TOPLEFT", 0, -13)
  local priceLabel = W.Text(inputs, "GameFontDisableSmall")
  priceLabel:SetPoint("TOPLEFT", 64, 0)
  priceLabel:SetText(L["Price each"])
  p.price = W.MoneyInput(inputs, L["gold"], function(copper, user)
    if user then
      S.price, S.picked = copper, nil
      S:RenderForm()
    end
  end)
  p.price:SetWidth(90)
  p.price:SetPoint("TOPLEFT", 64, -13)
  local durLabel = W.Text(inputs, "GameFontDisableSmall")
  durLabel:SetPoint("TOPLEFT", 164, 0)
  durLabel:SetText(L["Duration"])
  p.duration = W.Dropdown(inputs, 80, durations(), function(v)
    S.duration = v
    S:Suggest()
  end, { neutral = true, default = self.duration })
  p.duration:SetPoint("TOPLEFT", 164, -13)
  -- the deposit and what you get: a label on the left, the money on the right
  local function line(y)
    local row = CreateFrame("Frame", nil, form)
    row:SetHeight(16)
    row:SetPoint("TOPLEFT", inputs, "BOTTOMLEFT", 0, y)
    row:SetPoint("RIGHT", 0, 0)
    row.label = W.Text(row, "GameFontDisableSmall")
    row.label:SetPoint("LEFT", 0, 0)
    row.value = W.Text(row, "GameFontHighlightSmall", "RIGHT")
    row.value:SetPoint("RIGHT", 0, 0)
    row.value:SetPoint("LEFT", row.label, "RIGHT", 6, 0)
    row.value:SetWordWrap(false)
    return row
  end
  p.depositRow = line(-10)
  p.depositRow.label:SetText(L["Deposit"])
  p.deposit = p.depositRow.value
  p.netRow = line(-30)
  p.net = p.netRow.value
  p.hint = W.Text(form, "GameFontHighlightSmall")
  p.hint:SetPoint("TOPLEFT", p.netRow, "BOTTOMLEFT", 0, -8)
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
    rows = 10,
    rowHeight = 20,
    onClick = function(r)
      S:Undercut(r)
    end,
  })

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
    ns.AHSearch:Push(entry.key, function() -- ahead of a running search, which goes on after it
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

-- an item hidden or shown again (the item menu): the list without it, and nothing selected that's gone
function S:HiddenChanged()
  local p = self.panel
  if not (p and p:IsShown()) then
    return
  end
  self:Refresh()
  if self.entry and ns.AME.watch and ns.AME.watch:IsHidden(self.entry.key) then
    self.entry, self.advice, self.price = nil, nil, nil
  end
  self:Render()
end

-- the market index arrived (or was rebuilt): the bags valued with it
ns.Events.On("IndexReady", function(shard)
  if shard == ns.AME:FactionShard() then
    S:OnBagsChanged()
  end
end)

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
    ns.AHSearch:Push(key, function()
      S:Render()
    end)
  end
  self:Render()
end

function S:RenderList()
  local p = self.panel
  local items = self.items or {}
  p.bags:SetMessage(#items == 0 and L["Nothing in your bags can be listed here."] or nil)
  p.bags:SetData(items)
  p.bags:Render()
end

function S:RenderForm()
  local p, e, a = self.panel, self.entry, self.advice
  p.form:SetShown(e ~= nil)
  if not e then
    return
  end
  p.item:SetItem(e.key, e.qty)
  local s = e.summary
  p.itemInfo:SetText(s and s.market and L["market %s"]:format(money(s.market)) or "")
  local signal = s and s.signal and s.signal ~= "none" and s.signal or nil
  p.signal:SetShown(signal ~= nil)
  if signal then
    p.signal:SetSignal(signal)
  end
  p.itemRate:ClearAllPoints()
  p.itemRate:SetPoint("LEFT", signal and p.signal or p.itemInfo, "RIGHT", 6, 0)
  p.itemRate:SetText(s and s.soldPerDay and L["~%s sold/day"]:format(W.Count(s.soldPerDay)) or "")
  local labels = { quick = L["Quick"], normal = L["Normal"], patient = L["Patient"], market = L["Market"] }
  -- Quick no cheaper than Normal: one option, so the buttons close up. Market stands apart (S.MARKET_GAP): it isn't
  -- a step on the Quick / Normal / Patient ladder
  local y = 0
  for _, b in ipairs(p.picks) do
    local same = b.key == "quick" and a and a.quickSame
    b:SetShown(not same)
    if not same then
      if b.key == "market" then
        y = y + S.MARKET_GAP
      end
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 0, -60 - y)
      y = y + 28
    end
  end
  p.inputs:ClearAllPoints()
  p.inputs:SetPoint("TOPLEFT", 0, -60 - y - 6)
  for _, b in ipairs(p.picks) do
    local c = a and a[b.key]
    if c then
      -- the market price is the item's, as it is: the model doesn't say how fast it sells
      local when = b.key == "market" and L["the market price"]
        or c.hours and L["sells in %s"]:format(W.Hours(c.hours))
        or L["may not sell"]
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
  p.deposit:SetText(deposit and money(deposit) or W.NONE)
  local c = cut()
  p.netRow.label:SetText(L["You get, after the %d%% cut"]:format(W.CutPct(c)))
  p.netRow:SetShown(self.price ~= nil)
  p.net:SetText(self.price and money(self.price * (e.commodity and qty or 1) * (1 - c)) or "")
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
  -- (spelled out: "book and (... or nil) or searching" fell through to searching once listings were in)
  local message
  if not e then
    message = L["Pick an item on the left."]
  elseif not book then
    message = L["searching..."]
  elseif #book.rows == 0 then
    message = L["none listed"]
  end
  p.listings:SetMessage(message)
  -- the note under the listings, once there are some
  local listed = book and #book.rows > 0
  p.listings:SetNote(
    listed
        and L["Click a listing to price just under it. The item's chart is in the main window beside the auction house."]
      or nil
  )
  p.listings:Render()
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
