-- The profession window (the game's Professions frame on WoW Forever and retail): AME adds
--   - a profit figure on each recipe in the list (what it sells for after the AH cut, minus reagents at market)
--   - a bar under the window for the selected recipe: cost to craft, what it sells for, profit; Make N with the
--     batch's profit and what you'd actually spend; Queue, Add to shopping list, and Search AH at the auction house
--   - the craft queue beside the window (CraftQueue): steps parts first, each material's sources, what to do, and
--     Craft next
-- Recipes come from the open window (C_TradeSkillUI), and from what your characters' windows recorded
-- (Professions: the catalog, and who knows what) for parts and for queued crafts of another profession.
local _, ns = ...
local L = ns.L
local W = ns.Widgets

local PB = {}
ns.ProfessionBar = PB

PB.ROW_PROFIT = true -- the profit figure on recipe rows
PB.QUEUE_W = 360

---------------------------------------------------------------------------------------------------------------------
-- data

-- a recipe as Crafting and CraftQueue take it: { id, product, made, reagents = { {itemID, n}, ... } }
local function shape(id, r)
  if not r then
    return nil
  end
  local reagents = {}
  for _, g in ipairs(r.r or {}) do
    reagents[#reagents + 1] = { g[1], g[2] }
  end
  return { id = id, product = r.out, made = ((r.min or 1) + (r.max or r.min or 1)) / 2, reagents = reagents }
end

-- a recipe by ID: from the open profession window, else as one of your characters' windows recorded it
local recipeCache = {}
function PB.Recipe(recipeID)
  if not recipeID then
    return nil
  end
  local live = C_TradeSkillUI and ns.Professions.Recipe(C_TradeSkillUI, recipeID)
  if live and live.out then
    local r = shape(recipeID, live)
    recipeCache[recipeID] = r
    return r
  end
  if recipeCache[recipeID] then
    return recipeCache[recipeID]
  end
  for _, c in pairs(AME_DB and AME_DB.crafting and AME_DB.crafting.catalog or {}) do
    local r = c.recipes and c.recipes[recipeID]
    if r then
      recipeCache[recipeID] = shape(recipeID, r)
      return recipeCache[recipeID]
    end
  end
  return nil
end

-- item -> { { recipe, crafters = { charKey, ... } } }: what your characters' windows recorded (built once per change)
local producers, producersKey
local function producerMap()
  local db = AME_DB and AME_DB.crafting or {}
  local key = 0
  for _, c in pairs(db.catalog or {}) do
    key = key + (c.at or 0)
  end
  for _, ch in pairs(db.chars or {}) do
    for _, p in pairs(ch.professions or {}) do
      key = key + (p.at or 0)
    end
  end
  if producers and producersKey == key then
    return producers
  end
  producers, producersKey = {}, key
  for skillLine, c in pairs(db.catalog or {}) do
    for id, r in pairs(c.recipes or {}) do
      if r.out then
        local crafters = {}
        for charKey, ch in pairs(db.chars or {}) do
          local p = ch.professions and ch.professions[skillLine]
          if p and p.learned and p.learned[id] then
            crafters[#crafters + 1] = charKey
          end
        end
        table.sort(crafters)
        local list = producers[r.out] or {}
        producers[r.out] = list
        list[#list + 1] = { recipe = id, crafters = crafters }
      end
    end
  end
  return producers
end

function PB.Producers(itemID)
  return producerMap()[itemID] or {}
end

-- prices at your faction's auction house (what Crafting values with), or nil before there's a market index
function PB.Craft()
  local index = ns.AME and ns.AME:FactionIndex()
  if not index then
    return nil
  end
  local shard = ns.AME:FactionShard()
  local _, house = ns.SplitShard(shard)
  local data = ns.CraftingData
  return ns.Crafting.New({
    market = function(id)
      return index.items[id]
    end,
    vendorBuy = function(id)
      return data and data.VendorPrice and data:VendorPrice(id)
    end,
    vendorSell = function(id)
      return ns.ItemCache.Get(id).sellPrice
    end,
    cut = ns.Settings:AuctionCut(house),
    deposit = function(id)
      local sell = ns.ItemCache.Get(id).sellPrice
      return sell and ns.Arbitrage.Deposit(sell, house, ns.Settings:Get("listingHours")) or 0
    end,
    factor = ns.Settings:Get("outlierFactor"),
  })
end

-- one recipe's numbers for count crafts: { cost (each craft, reagents at market), sells (what a craft's items sell
-- for after the cut), profit (each craft), made (items a craft), toBuy (what's missing, at market, for all count),
-- missing = { { itemID, qty } } } - pure given craft (Crafting) and held(itemID) -> units you have
function PB.Summary(recipe, craft, count, held)
  local out = { made = recipe.made or 1, missing = {}, toBuy = 0 }
  local e = craft:Evaluate(recipe)
  out.cost, out.sells, out.profit = e.cost, e.revenue, e.profit
  for _, g in ipairs(recipe.reagents or {}) do
    local short = g[2] * count - (held and held(g[1]) or 0)
    if short > 0 then
      out.missing[#out.missing + 1] = { g[1], short }
      local p = craft:Price(g[1])
      if p then
        out.toBuy = out.toBuy + p * short
      end
    end
  end
  return out
end

local function queue()
  AME_DB.craftQueue = AME_DB.craftQueue or {}
  PB.queue = PB.queue and PB.queue.db == AME_DB.craftQueue and PB.queue or ns.CraftQueue.New(AME_DB.craftQueue)
  return PB.queue
end
PB.Queue = queue

local function heldTotal(itemID)
  local h = ns.Trading.Held(itemID)
  return h.bags + h.bank + h.guildBank -- what's on the auction house is for sale, not at hand
end

function PB.Plan()
  return ns.CraftQueue.Plan(queue().db, {
    recipe = PB.Recipe,
    producers = PB.Producers,
    held = function(id)
      return ns.Trading.Held(id)
    end,
    me = ns.Trading.CharKey(),
    craft = PB.Craft(),
    vendorBuy = function(id)
      local data = ns.CraftingData
      return data and data.VendorPrice and data:VendorPrice(id)
    end,
  })
end

local function name(id)
  return ns.ItemCache.Name(id) or ("item:" .. tostring(id))
end

local function charName(key)
  return key and (key:gsub("^[^:]*:", "")) or "?"
end

---------------------------------------------------------------------------------------------------------------------
-- actions

-- the shopping list the queue (or a recipe) fills: one named "Craft queue", made when missing
local function craftList()
  local shop = ns.AME.shopping
  if not shop then
    return nil
  end
  local listName = L["Craft queue"]
  for i, l in ipairs(shop:Lists()) do
    if l.name == listName then
      return i, shop
    end
  end
  return shop:AddList(listName), shop
end

-- the queue's auction house buys, as the "Craft queue" shopping list (replacing what it held)
function PB:QueueToShopping()
  local i, shop = craftList()
  if not i then
    return
  end
  local plan = PB.Plan()
  for key in pairs(shop:Lists()[i].items) do
    shop:SetItem(i, key, 0)
  end
  -- the list counts down from what you hold, so it asks for the whole need of what has to be bought
  for _, m in ipairs(plan.materials) do
    for _, src in ipairs(m.sources) do
      if src.kind == "ah" then
        shop:SetItem(i, m.item, src.qty + heldTotal(m.item))
      end
    end
  end
  if ns.UI.ShoppingChanged then
    ns.UI:ShoppingChanged(i)
  end
  print(
    "|cff33ccffAME|r " .. L["the craft queue's missing materials are on the %s shopping list"]:format(L["Craft queue"])
  )
end

-- the selected recipe's reagents (for count crafts) onto a shopping list (picked from a menu, or a new one)
function PB:RecipeToShopping(recipe, count, anchor)
  local shop = ns.AME.shopping
  if not (shop and recipe) then
    return
  end
  local function fill(i)
    for _, g in ipairs(recipe.reagents) do
      shop:AddItem(i, g[1], g[2] * count)
    end
    if ns.UI.ShoppingChanged then
      ns.UI:ShoppingChanged(i)
    end
  end
  local entries = {}
  for i, l in ipairs(shop:Lists()) do
    entries[#entries + 1] = {
      text = l.name,
      func = function()
        fill(i)
      end,
    }
  end
  entries[#entries + 1] = {
    text = L["New list"],
    func = function()
      local i = shop:AddList(name(recipe.product))
      if i then
        fill(i)
      end
    end,
  }
  W.Menu(anchor, entries)
end

-- search the open auction house for the crafted item and every reagent
function PB:Search(recipe)
  if not recipe then
    return
  end
  local keys = { recipe.product }
  for _, g in ipairs(recipe.reagents) do
    keys[#keys + 1] = g[1]
  end
  if ns.AME:AuctionatorSearch(keys) then
    return
  end
  if ns.UI.SearchItems then
    ns.UI:SearchItems(keys, name(recipe.product))
  else
    ns.AME:SearchAuctionHouse(recipe.product)
  end
end

-- can this character craft a step now? (the open window knows the recipe and says how many can be made)
local function available(step)
  local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(step.recipe)
  return info and info.learned and (info.numAvailable or 0) or 0
end

function PB:CraftNext()
  local plan = PB.Plan()
  local step = ns.CraftQueue.Next(plan, function(s)
    return available(s) > 0
  end)
  if not step then
    print("|cff33ccffAME|r " .. L["nothing in the queue can be crafted here yet"])
    return
  end
  local n = math.min(step.count, available(step))
  if C_TradeSkillUI and C_TradeSkillUI.CraftRecipe then
    C_TradeSkillUI.CraftRecipe(step.recipe, n)
  end
end

-- a finished craft (the recipe's spell went off): count it off the queue
function PB:OnCrafted(spellID)
  if queue():Crafted(spellID, 1) then
    self:Refresh()
  end
end

---------------------------------------------------------------------------------------------------------------------
-- the bar

local function money(c)
  return c and W.Money(math.floor(c + 0.5)) or W.NONE
end

local function signed(c)
  if not c then
    return W.NONE
  end
  return W.Color(c >= 0 and "good" or "bad", c < 0 and "-" or "+") .. money(math.abs(c))
end

function PB:SelectedRecipe()
  return self.selected and PB.Recipe(self.selected)
end

function PB:CreateBar(host)
  local bar = CreateFrame("Frame", nil, host, "BackdropTemplate")
  W.Skin(bar, W.COLORS.bg)
  bar:SetHeight(84)
  bar:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, 2)
  bar:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, 2)
  bar.line = W.Text(bar, "GameFontHighlightSmall")
  bar.line:SetPoint("TOPLEFT", 10, -10)
  bar.line:SetPoint("RIGHT", -10, 0)
  bar.line:SetWordWrap(false)
  bar.batch = W.Text(bar, "GameFontHighlightSmall")
  bar.batch:SetPoint("TOPLEFT", bar.line, "BOTTOMLEFT", 92, -9)
  bar.batch:SetPoint("RIGHT", -10, 0)
  bar.batch:SetWordWrap(false)
  local makeLabel = W.Text(bar, "GameFontDisableSmall")
  makeLabel:SetPoint("TOPLEFT", bar.line, "BOTTOMLEFT", 0, -9)
  makeLabel:SetText(L["Make"])
  bar.count = W.Input(bar, { numeric = true })
  bar.count:SetSize(44, 20)
  bar.count:SetPoint("LEFT", makeLabel, "RIGHT", 6, 0)
  bar.count:SetText("1")
  bar.count:SetScript("OnTextChanged", function(box, user)
    if user then
      PB.count = math.max(1, math.floor(tonumber(box:GetText()) or 1))
      PB:RenderBar()
    end
  end)
  bar.queue = W.Button(bar, L["Queue"], 90, 22, function()
    local r = PB:SelectedRecipe()
    if r then
      queue():Add(r.id, PB.count or 1)
      PB:Refresh()
      PB:ShowQueue(true)
    end
  end)
  bar.queue:SetPoint("BOTTOMLEFT", 10, 8)
  W.Primary(bar.queue)
  bar.shop = W.Button(bar, L["Add to shopping list"], 150, 22)
  bar.shop:SetScript("OnClick", function(b)
    PB:RecipeToShopping(PB:SelectedRecipe(), PB.count or 1, b)
  end)
  bar.shop:SetPoint("LEFT", bar.queue, "RIGHT", 6, 0)
  bar.search = W.Button(bar, L["Search AH"], 100, 22, function()
    PB:Search(PB:SelectedRecipe())
  end)
  bar.search:SetPoint("LEFT", bar.shop, "RIGHT", 6, 0)
  bar.showQueue = W.Button(bar, L["Queue"], 90, 22, function()
    PB:ShowQueue(not (PB.panel and PB.panel:IsShown()))
  end)
  bar.showQueue:SetPoint("BOTTOMRIGHT", -10, 8)
  self.bar = bar
  return bar
end

function PB:RenderBar()
  local bar = self.bar
  if not bar then
    return
  end
  local recipe = self:SelectedRecipe()
  local craft = PB.Craft()
  local brand = ""
  bar.search:SetShown(ns.AME.ahOpen and true or false)
  local n = #queue().db.items
  bar.showQueue:SetText(n > 0 and L["Queue (%d)"]:format(n) or L["Queue"])
  if not (recipe and recipe.product) then
    bar.line:SetText(brand .. W.Dim(recipe and L["enchants make no item to price"] or L["pick a recipe"]))
    bar.batch:SetText("")
    return
  end
  if not craft then
    bar.line:SetText(brand .. W.Dim(L["no market data yet: scan the auction house"]))
    bar.batch:SetText("")
    return
  end
  local count = self.count or 1
  local s = PB.Summary(recipe, craft, count, heldTotal)
  bar.line:SetText(
    brand
      .. W.Dim(L["Cost to craft"] .. " ")
      .. money(s.cost)
      .. "     "
      .. W.Dim(L["Sells for"] .. " ")
      .. money(s.sells)
      .. "     "
      .. W.Dim(L["Profit"] .. " ")
      .. signed(s.profit)
  )
  local batch = W.Dim(("x%d: "):format(count) .. L["profit"] .. " ") .. signed(s.profit and s.profit * count)
  if #s.missing > 0 then
    batch = batch .. W.Dim("  ·  " .. L["to buy"] .. " ") .. money(s.toBuy)
  else
    batch = batch .. W.Dim("  ·  " .. L["you have every reagent"])
  end
  bar.batch:SetText(batch)
  bar.queue:SetText(L["Queue %d"]:format(count))
end

---------------------------------------------------------------------------------------------------------------------
-- the queue panel

local SOURCE = {
  carried = function()
    return L["your bags"]
  end,
  bank = function()
    return L["your bank"]
  end,
  alt = function(s)
    return L["%s's bags or bank"]:format(s.char or "?")
  end,
  guild = function(s)
    return L["<%s> guild bank"]:format(s.char or "?")
  end,
  vendor = function()
    return L["a vendor"]
  end,
  made = function()
    return L["made in the queue"]
  end,
  ah = function()
    return L["buy on the AH"]
  end,
}

-- Pure: a to-do line (plan.todo) in words. me: this character's key
function PB.TodoText(t, me)
  local what = ("%d %s"):format(t.qty or 0, name(t.item))
  if t.kind == "buy" then
    return L["Buy %s"]:format(what) .. (t.cost and W.Dim("  " .. money(t.cost)) or "")
  elseif t.kind == "vendor" then
    return L["Buy %s from a vendor"]:format(what)
  elseif t.kind == "bank" then
    return L["Take %s from your bank"]:format(what)
  elseif t.kind == "alt" then
    return L["Get %s from %s"]:format(what, t.char or "?")
  elseif t.kind == "guild" then
    return L["Take %s from the <%s> guild bank"]:format(what, t.char or "?")
  elseif t.kind == "craft" then
    if t.char and t.char ~= me then
      return L["On %s: craft %s"]:format(charName(t.char), what)
    end
    return L["Craft %s"]:format(what)
  end
  return nil -- already in your bags: nothing to do
end

-- a material's sources in words: "3 your bags, 5 buy on the AH 5g 10s"
function PB.SourcesText(m)
  local parts = {}
  for _, src in ipairs(m.sources) do
    local where = SOURCE[src.kind] and SOURCE[src.kind](src) or src.kind
    local text = ("%d %s"):format(src.qty, where)
    if src.kind == "ah" then
      text = W.Color("warn", text .. (src.cost and (" " .. money(src.cost)) or ""))
    elseif src.kind == "carried" then
      text = W.Color("good", text)
    end
    parts[#parts + 1] = text
  end
  return table.concat(parts, W.Dim(", "))
end

-- beside the profession window, clear of whatever sticks out of its right edge (its side tabs, other addons' buttons)
function PB.PlaceQueue(p, host)
  local right, edge = host.GetRight and host:GetRight(), 0
  if type(right) == "number" and host.GetChildren then
    for _, child in ipairs({ host:GetChildren() }) do
      local r = child ~= p and child.IsShown and child:IsShown() and child.GetRight and child:GetRight()
      if type(r) == "number" and r > right and r - right < 120 then
        edge = math.max(edge, r - right)
      end
    end
  end
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", host, "TOPRIGHT", edge + 4, 0)
  p:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", edge + 4, 0)
end

-- The panel, as the design draws it: the title and totals; then, scrolling, the steps in order (a card each: Make /
-- Buy for a part, remove for what you queued), the materials and where each comes from, and the to-do list; the
-- buttons at the bottom (Craft next is the main one).
function PB:CreateQueue(host)
  local p = CreateFrame("Frame", nil, host, "BackdropTemplate")
  W.Skin(p, W.COLORS.bg)
  p:SetWidth(PB.QUEUE_W)
  PB.PlaceQueue(p, host)
  p:HookScript("OnShow", function(self)
    PB.PlaceQueue(self, host)
  end)
  p.title = W.Text(p, "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 10, -10)
  p.title:SetText(L["Craft queue"])
  p.close = W.CloseButton(p)
  p.close:SetPoint("TOPRIGHT", -4, -4)
  p.close:SetScript("OnClick", function()
    PB:ShowQueue(false)
  end)
  p.totals = W.Text(p, "GameFontDisableSmall", "RIGHT")
  p.totals:SetPoint("TOPRIGHT", -28, -12)
  local body = CreateFrame("Frame", nil, p)
  body:SetPoint("TOPLEFT", 10, -32)
  body:SetPoint("BOTTOMRIGHT", -10, 40)
  p.pane = W.ScrollPane(body)
  p.content = p.pane.content
  p.heads, p.cards, p.mats, p.todos = {}, {}, {}, {}
  p.empty = W.Text(p.content, "GameFontDisableSmall")
  p.empty:SetPoint("TOPLEFT", 0, 0)
  p.empty:SetPoint("RIGHT", 0, 0)
  p.empty:SetText(L["Nothing queued. Pick a recipe and click Queue under the profession window."])
  p.next = W.Button(p, L["Craft next"], 110, 22, function()
    PB:CraftNext()
  end)
  p.next:SetPoint("BOTTOMLEFT", 10, 10)
  W.Primary(p.next)
  p.shop = W.Button(p, L["Missing to shopping list"], 160, 22, function()
    PB:QueueToShopping()
  end)
  p.shop:SetPoint("LEFT", p.next, "RIGHT", 6, 0)
  p.clear = W.Button(p, L["Clear"], 60, 22, function()
    queue():Clear()
    PB:Refresh()
  end)
  p.clear:SetPoint("BOTTOMRIGHT", -10, 10)
  p:Hide()
  self.panel = p
  return p
end

-- pooled pieces of the scrolling body
local function head(p, i)
  local h = p.heads[i]
  if not h then
    h = W.Text(p.content, "GameFontDisableSmall")
    p.heads[i] = h
  end
  return h
end

local function card(p, i)
  local c = p.cards[i]
  if c then
    return c
  end
  c = CreateFrame("Frame", nil, p.content, "BackdropTemplate")
  W.Skin(c, W.COLORS.panel)
  c.num = W.Text(c, "GameFontDisableSmall", "RIGHT")
  c.num:SetWidth(14)
  c.num:SetPoint("TOPLEFT", 6, -6)
  c.text = W.Text(c, "GameFontHighlightSmall")
  c.text:SetPoint("TOPLEFT", c.num, "TOPRIGHT", 8, 0)
  c.text:SetPoint("RIGHT", -100, 0)
  c.text:SetWordWrap(false)
  c.sub = W.Text(c, "GameFontDisableSmall")
  c.sub:SetPoint("TOPLEFT", c.text, "BOTTOMLEFT", 0, -3)
  c.sub:SetPoint("RIGHT", -8, 0)
  c.sub:SetWordWrap(false)
  c.make = W.Button(c, L["Make"], 42, 18)
  c.buy = W.Button(c, L["Buy"], 42, 18)
  c.buy:SetPoint("TOPRIGHT", -6, -4)
  c.make:SetPoint("RIGHT", c.buy, "LEFT", -2, 0)
  c.profit = W.Text(c, "GameFontHighlightSmall", "RIGHT")
  c.profit:SetPoint("TOPRIGHT", -28, -6)
  c.remove = W.Button(c, "x", 18, 18)
  c.remove:SetPoint("TOPRIGHT", -6, -4)
  p.cards[i] = c
  return c
end

local function line(pool, parent, i, cols)
  local r = pool[i]
  if r then
    return r
  end
  r = CreateFrame("Frame", nil, parent)
  r:SetHeight(18)
  r.text = W.Text(r, "GameFontHighlightSmall")
  r.text:SetWordWrap(false)
  if cols then
    r.need = W.Text(r, "GameFontHighlightSmall", "RIGHT")
    r.need:SetWidth(30)
    r.need:SetPoint("LEFT", 110, 0)
    r.text:SetPoint("LEFT", 0, 0)
    r.text:SetWidth(104)
    r.make = W.Button(r, L["Make"], 42, 16) -- a part you chose to buy: make it again
    r.make:SetPoint("RIGHT", 0, 0)
    r.make:Hide()
    r.src = W.Text(r, "GameFontHighlightSmall")
    r.src:SetPoint("LEFT", r.need, "RIGHT", 10, 0)
    r.src:SetPoint("RIGHT", r.make, "LEFT", -4, 0)
    r.src:SetWordWrap(false)
  else
    r.text:SetPoint("LEFT", 0, 0)
    r.text:SetPoint("RIGHT", 0, 0)
  end
  pool[i] = r
  return r
end

function PB:RenderQueue()
  local p = self.panel
  if not (p and p:IsShown()) then
    return
  end
  local plan = PB.Plan()
  local me = ns.Trading and ns.Trading.CharKey and ns.Trading.CharKey()
  p.totals:SetText(
    #plan.steps > 0
        and (W.Dim(L["profit"] .. " ") .. signed(plan.profit) .. W.Dim("  ·  " .. L["to buy"] .. " ") .. money(
          plan.toBuy
        ))
      or ""
  )
  p.empty:SetShown(#plan.steps == 0)
  local y, heads = 0, 0
  local function heading(text)
    heads = heads + 1
    local h = head(p, heads)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
    h:SetText(text:upper())
    h:Show()
    y = y + 16
  end
  -- the steps, in order
  if #plan.steps > 0 then
    heading(L["In order"])
  end
  for k, s in ipairs(plan.steps) do
    local c = card(p, k)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
    c:SetPoint("RIGHT", p.content, "RIGHT", 0, 0)
    c.num:SetText(tostring(k))
    local itemName = select(1, W.ItemInfo(s.item))
    local quality = select(3, W.ItemInfo(s.item))
    c.text:SetText(("%d "):format(s.made or s.count) .. W.QualityText(quality, itemName or name(s.item)))
    local sub
    if s.crafter and not s.mine then
      sub = W.Color("warn", L["on %s"]:format(charName(s.crafter)))
    elseif not s.crafter then
      sub = W.Color("bad", L["nobody of yours knows it"])
    elseif s.part then
      sub = L["a part"]
    end
    c.sub:SetText(sub or "")
    c:SetHeight(sub and 38 or 26)
    -- a part: make it or buy it (the plan's choice); what you queued: its profit, and remove it
    c.make:SetShown(s.part or false)
    c.buy:SetShown(s.part or false)
    c.profit:SetShown(not s.part)
    c.remove:SetShown(not s.part)
    if s.part then
      local buying = s.choice == "buy"
      c.make:SetSelected(not buying)
      c.buy:SetSelected(buying)
      c.make:SetScript("OnClick", function()
        queue():SetChoice(s.item, "make")
        PB:Refresh()
      end)
      c.buy:SetScript("OnClick", function()
        queue():SetChoice(s.item, "buy")
        PB:Refresh()
      end)
    else
      c.profit:SetText(s.profit and signed(s.profit) or "")
      c.remove:SetScript("OnClick", function()
        queue():Remove(s.recipe)
        PB:Refresh()
      end)
    end
    c:Show()
    y = y + (sub and 38 or 26) + 4
  end
  for k = #plan.steps + 1, #p.cards do
    p.cards[k]:Hide()
  end
  -- materials: what's needed and where it comes from
  if #plan.materials > 0 then
    y = y + 6
    heading(L["Materials"])
  end
  for k, m in ipairs(plan.materials) do
    local r = line(p.mats, p.content, k, true)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
    r:SetPoint("RIGHT", p.content, "RIGHT", 0, 0)
    local itemName, _, quality = W.ItemInfo(m.item)
    r.text:SetText(W.QualityText(quality, itemName or name(m.item)))
    r.need:SetText(W.Count(m.need))
    r.src:SetText(PB.SourcesText(m))
    local back = m.part and m.choice == "buy" or false
    r.make:SetShown(back)
    r.src:SetPoint("RIGHT", back and r.make or r, back and "LEFT" or "RIGHT", back and -4 or 0, 0)
    r.make:SetScript("OnClick", function()
      queue():SetChoice(m.item, "make")
      PB:Refresh()
    end)
    r:Show()
    y = y + 18
  end
  for k = #plan.materials + 1, #p.mats do
    p.mats[k]:Hide()
  end
  -- what to do, in order
  local todo = {}
  for _, t in ipairs(plan.todo or {}) do
    local text = PB.TodoText(t, me)
    if text then
      todo[#todo + 1] = text
    end
  end
  if #todo > 0 then
    y = y + 6
    heading(L["To do"])
  end
  for k, text in ipairs(todo) do
    local r = line(p.todos, p.content, k)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
    r:SetPoint("RIGHT", p.content, "RIGHT", 0, 0)
    r.text:SetText(W.Dim(k .. ".") .. "  " .. text)
    r:Show()
    y = y + 18
  end
  for k = #todo + 1, #p.todos do
    p.todos[k]:Hide()
  end
  for k = heads + 1, #p.heads do
    p.heads[k]:Hide()
  end
  p.content:SetHeight(math.max(1, y))
  if p.pane.Measure then
    p.pane:Measure()
  end
  p.next:SetEnabled(not queue():Empty())
end

function PB:ShowQueue(on)
  if not self.panel then
    return
  end
  self.panel:SetShown(on)
  self:RenderQueue()
end

function PB:Refresh()
  self:RenderBar()
  self:RenderQueue()
end

---------------------------------------------------------------------------------------------------------------------
-- profit on the recipe list's rows

local rowProfit = {} -- [recipeID] = profit (for this market index), cleared when prices change
local profitIndex

local function profitFor(recipeID)
  local index = ns.AME and ns.AME:FactionIndex()
  if index ~= profitIndex then
    rowProfit, profitIndex = {}, index
  end
  local v = rowProfit[recipeID]
  if v == nil then
    local recipe, craft = PB.Recipe(recipeID), PB.Craft()
    local e = recipe and recipe.product and craft and craft:Evaluate(recipe)
    v = e and e.profit or false
    rowProfit[recipeID] = v
  end
  return v or nil
end

local function decorateRow(frame, node)
  local data = node and node.GetData and node:GetData()
  local info = data and data.recipeInfo
  local fs = rawget(frame, "ameProfit")
  if not fs then
    fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("RIGHT", -6, 0)
    frame.ameProfit = fs
  end
  local profit = PB.ROW_PROFIT and info and info.recipeID and profitFor(info.recipeID)
  fs:SetText(profit and signed(profit) or "")
end

---------------------------------------------------------------------------------------------------------------------
-- hooking into the game's window

local function selectedFrom(info)
  local id = type(info) == "table" and info.recipeID
  if id and id ~= PB.selected then
    PB.selected = id
    PB:RenderBar()
  end
end

function PB:Attach()
  local frame = _G.ProfessionsFrame
  if self.attached or not frame then
    return
  end
  self.attached = true
  local page = rawget(frame, "CraftingPage")
  self:CreateBar(frame)
  self:CreateQueue(frame)
  if page and page.SelectRecipe then
    hooksecurefunc(page, "SelectRecipe", function(_, info)
      selectedFrom(info)
    end)
  end
  local form = page and rawget(page, "SchematicForm")
  if form and form.Init then
    hooksecurefunc(form, "Init", function(_, info)
      selectedFrom(info)
    end)
  end
  local events = _G.EventRegistry
  if events and events.RegisterCallback then
    pcall(events.RegisterCallback, events, "ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, info)
      selectedFrom(info)
    end, PB)
  end
  -- the recipe list's rows: a profit figure on each (rows are made as the list scrolls)
  local mixin = _G.ProfessionsRecipeListRecipeMixin
  if mixin and mixin.Init then
    hooksecurefunc(mixin, "Init", decorateRow)
  end
  frame:HookScript("OnShow", function()
    PB:Refresh()
    if not queue():Empty() then
      PB:ShowQueue(true)
    end
  end)
  frame:HookScript("OnHide", function()
    PB:ShowQueue(false)
  end)
end

function PB:Start()
  if self.frame then
    return
  end
  local f = CreateFrame("Frame")
  self.frame = f
  f:RegisterEvent("ADDON_LOADED")
  pcall(f.RegisterEvent, f, "UNIT_SPELLCAST_SUCCEEDED")
  pcall(f.RegisterEvent, f, "BAG_UPDATE_DELAYED")
  f:SetScript("OnEvent", function(_, event, a, _, spellID)
    if event == "ADDON_LOADED" then
      if a == "Blizzard_Professions" then
        PB:Attach()
      end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
      if a == "player" and spellID then
        PB:OnCrafted(spellID)
      end
    elseif PB.bar and PB.bar:IsVisible() then
      PB:Refresh() -- what you hold changed: what's missing did too
    end
  end)
  self:Attach() -- already loaded
end
