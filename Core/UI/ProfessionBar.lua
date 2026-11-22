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
PB.QUEUE_W = 420

---------------------------------------------------------------------------------------------------------------------
-- data

-- recipes by ID and what makes an item: Core/Recipes.lua
PB.Recipe = function(recipeID)
  return ns.Recipes.Recorded(recipeID)
end
PB.Producers = function(itemID)
  return ns.Recipes.Producers(itemID)
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
  return h.bags + h.bank + (h.mail or 0) + h.guildBank -- what's on the auction house is for sale, not at hand
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
  return W.ItemLabel(id)
end

-- an item's name in its quality colour; while the client hasn't loaded it, the queue redraws once it has
local function redrawQueue()
  PB:RenderQueue()
end
local function itemText(id)
  return W.ItemNameOrLoad(id, redrawQueue)
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
  -- what has to be bought, on the AH or from a vendor (the vendor panel buys those): the list counts down from what
  -- you hold, so it asks for the whole need of it
  for _, m in ipairs(plan.materials) do
    local buy = 0
    for _, src in ipairs(m.sources) do
      if src.kind == "ah" or src.kind == "vendor" then
        buy = buy + src.qty
      end
    end
    if buy > 0 then
      shop:SetItem(i, m.item, buy + heldTotal(m.item))
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
-- Pure: crafts the reagents in your bags make (bags: { [itemID] = count })
function PB.CraftsFromBags(recipe, bags)
  local n
  for _, g in ipairs(recipe and recipe.reagents or {}) do
    local each = math.floor((bags[g[1]] or 0) / math.max(1, g[2]))
    n = n and math.min(n, each) or each
  end
  return n or 0
end

-- how many of a step this character can craft now: the game's count when its window has the recipe open, else
-- what the reagents in your bags make (the game's count lags behind your bags, and knows only the open profession)
local function available(step)
  local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(step.recipe)
  local game = info and info.learned and (info.numAvailable or 0) or 0
  local h = AME_DB and AME_DB.holdings and AME_DB.holdings[ns.Trading.CharKey()]
  local bags = PB.CraftsFromBags(PB.Recipe(step.recipe), h and h.bags or {})
  return math.max(game, bags)
end

-- the next step this character can craft now (it knows it and has what it takes): step, or nil
function PB:NextStep(plan)
  return ns.CraftQueue.Next(plan or PB.Plan(), function(s)
    return available(s) > 0
  end)
end

-- show a recipe in the game's window (the window picks its top recipe when it opens; the queue's next step is
-- what you're about to craft)
function PB:ShowRecipe(recipeID)
  local frame = _G.ProfessionsFrame
  local page = frame and rawget(frame, "CraftingPage")
  local info = recipeID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(recipeID)
  if page and page.SelectRecipe and info and info.learned and PB.selected ~= recipeID then
    pcall(page.SelectRecipe, page, info)
  end
end

function PB:CraftNext()
  local plan = PB.Plan()
  local step = self:NextStep(plan)
  if not step then
    print("|cff33ccffAME|r " .. L["nothing in the queue can be crafted here yet"])
    return
  end
  local n = math.min(step.count, available(step))
  -- the game crafts only from the profession window that's open: another one is, say which to open
  local info = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(step.recipe)
  if not (info and info.learned) then
    local profession
    for skillLine, c in pairs(AME_DB.crafting and AME_DB.crafting.catalog or {}) do
      if c.recipes and c.recipes[step.recipe] then
        local get = C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID
        local ok, info2 = pcall(get or error, skillLine)
        profession = ok and info2 and info2.professionName or c.name
      end
    end
    print("|cff33ccffAME|r " .. L["open %s to craft %s"]:format(profession or L["its profession"], name(step.item)))
    return
  end
  self:ShowRecipe(step.recipe) -- the window shows what's being crafted
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

local money = W.Money
local function signed(c)
  return W.SignedMoney(c, { full = true })
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
    return L["bank"]
  end,
  mail = function()
    return L["mailbox"]
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
  local what = ("%d %s"):format(t.qty or 0, itemText(t.item))
  if t.kind == "buy" then
    return L["Buy %s"]:format(what) .. (t.cost and W.Dim("  " .. money(t.cost)) or "")
  elseif t.kind == "vendor" then
    return L["Buy %s from a vendor"]:format(what)
  elseif t.kind == "bank" then
    return L["Take %s from the bank"]:format(what)
  elseif t.kind == "mail" then
    return L["Take %s from the mailbox"]:format(what)
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

-- a material's sources as tags: { text, kind } ("4 · bank", "5 · buy on the AH 5g 10s"); what's in your bags
-- needs no tag (that's where it should be)
function PB.SourceTags(m)
  local out = {}
  for _, src in ipairs(m.sources) do
    local where = SOURCE[src.kind] and SOURCE[src.kind](src) or src.kind
    if src.kind == "carried" then
      where = nil
    end
    local text = where and ("%d · %s"):format(src.qty, where)
    if src.kind == "ah" and src.cost then
      text = text .. " " .. money(src.cost)
    end
    if text then
      out[#out + 1] = { text = text, kind = src.kind }
    end
  end
  return out
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

-- an item's icon and name, as a link (tooltip, Shift-click, click opens it in the AME window)
local function itemLink(parent)
  local icon = parent:CreateTexture(nil, "ARTWORK")
  icon:SetSize(16, 16)
  local text = W.Text(parent, "GameFontHighlightSmall")
  text:SetPoint("LEFT", icon, "RIGHT", 6, 0)
  text:SetWordWrap(false)
  local hover = W.ItemHover(parent, icon, text)
  return icon, text, hover
end

local function showItem(icon, text, hover, key, before)
  local _, _, _, tex = W.ItemInfo(key)
  icon:SetTexture(tex or 134400)
  text:SetText((before or "") .. itemText(key))
  hover:SetItem(key)
end

-- source tags: a small panel per source, coloured by where it comes from
local TAG_COLORS = {
  carried = { { 0.10, 0.20, 0.14, 1 }, "good" },
  ah = { { 0.23, 0.16, 0.10, 1 }, "warn" },
}
local function tag(pool, parent, i)
  local t = pool[i]
  if not t then
    t = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    t:SetHeight(16)
    t.text = W.Text(t, "GameFontHighlightSmall")
    t.text:SetPoint("LEFT", 5, 0)
    pool[i] = t
  end
  return t
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
  c.num:SetPoint("TOPLEFT", 6, -7)
  c.icon, c.text, c.hover = itemLink(c)
  c.icon:SetPoint("TOPLEFT", 26, -5)
  c.text:SetPoint("RIGHT", -100, 0)
  c.sub = W.Text(c, "GameFontDisableSmall")
  c.sub:SetPoint("TOPLEFT", 48, -24)
  c.sub:SetPoint("RIGHT", -8, 0)
  c.sub:SetWordWrap(false)
  c.make = W.Button(c, L["Make"], 42, 18)
  c.buy = W.Button(c, L["Buy"], 42, 18)
  c.buy:SetPoint("TOPRIGHT", -6, -4)
  c.make:SetPoint("RIGHT", c.buy, "LEFT", -2, 0)
  c.profit = W.Text(c, "GameFontHighlightSmall", "RIGHT")
  c.profit:SetPoint("TOPRIGHT", -30, -7)
  c.remove = W.Button(c, "x", 18, 18)
  c.remove:SetPoint("TOPRIGHT", -6, -4)
  p.cards[i] = c
  return c
end

local NEED_X, SOURCE_X = 150, 192

local function material(p, i)
  local r = p.mats[i]
  if r then
    return r
  end
  r = CreateFrame("Frame", nil, p.content)
  r.icon, r.text, r.hover = itemLink(r)
  r.icon:SetPoint("TOPLEFT", 0, -1)
  r.text:SetWidth(NEED_X - 30)
  r.need = W.Text(r, "GameFontHighlightSmall", "RIGHT")
  r.need:SetWidth(32)
  r.need:SetPoint("TOPLEFT", NEED_X, -2)
  r.make = W.Button(r, L["Make"], 42, 16) -- a part you chose to buy: make it again
  r.make:SetPoint("TOPRIGHT", 0, 0)
  r.make:Hide()
  r.tags = {}
  p.mats[i] = r
  return r
end

local function todoLine(p, i)
  local r = p.todos[i]
  if r then
    return r
  end
  r = CreateFrame("Frame", nil, p.content)
  r:SetHeight(18)
  r.num = W.Text(r, "GameFontDisableSmall", "RIGHT")
  r.num:SetWidth(16)
  r.num:SetPoint("LEFT", 0, 0)
  r.text = W.Text(r, "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", r.num, "RIGHT", 6, 0)
  r.text:SetPoint("RIGHT", 0, 0)
  r.text:SetWordWrap(false)
  r.hover = W.ItemHover(r, r.text, r.text) -- the line links its item
  p.todos[i] = r
  return r
end

-- the second line of a step's card: what you queued lists its reagents; a part says what making it saves
local function stepSub(s)
  local parts = {}
  if s.crafter and not s.mine then
    parts[#parts + 1] = W.Color("warn", L["on %s"]:format(charName(s.crafter)))
  elseif not s.crafter then
    parts[#parts + 1] = W.Color("bad", L["nobody of yours knows it"])
  end
  if s.part then
    parts[#parts + 1] = L["a part"]
    if s.saves and s.saves > 0 then
      parts[#parts + 1] = L["making saves %s each"]:format(money(s.saves))
    end
  else
    local r = PB.Recipe(s.recipe)
    local list = {}
    for _, reagent in ipairs(r and r.reagents or {}) do
      list[#list + 1] = ("%d %s"):format(reagent[2] * (s.count or 1), ns.ItemCache.Name(reagent[1]) or "?")
    end
    if #list > 0 then
      parts[#parts + 1] = table.concat(list, ", ")
    end
  end
  return table.concat(parts, W.Dim("  ·  "))
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
  local width = (p.content:GetWidth() or 0) > 0 and p.content:GetWidth() or (PB.QUEUE_W - 28)
  local y, heads = 0, 0
  local function heading(text, x)
    heads = heads + 1
    local h = head(p, heads)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", p.content, "TOPLEFT", x or 0, -y)
    h:SetText(text)
    h:Show()
  end
  -- the steps, in order: a card each
  if #plan.steps > 0 then
    heading(L["In order"]:upper())
    y = y + 16
  end
  for k, s in ipairs(plan.steps) do
    local c = card(p, k)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
    c:SetPoint("RIGHT", p.content, "RIGHT", 0, 0)
    c.num:SetText(tostring(k))
    showItem(c.icon, c.text, c.hover, s.item, ("%d "):format(s.made or s.count))
    c.text:SetText(("%d "):format(s.made or s.count) .. itemText(s.item))
    c.hover:SetItem(s.item)
    local sub = stepSub(s)
    c.sub:SetText(sub)
    local h = sub ~= "" and 40 or 26
    c:SetHeight(h)
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
    y = y + h + 4
  end
  for k = #plan.steps + 1, #p.cards do
    p.cards[k]:Hide()
  end
  -- materials: what's needed, and where it comes from (a tag per source)
  if #plan.materials > 0 then
    y = y + 8
    heading(L["Materials"]:upper())
    heading(L["need"], NEED_X + 4)
    heading(L["source"], SOURCE_X)
    y = y + 16
  end
  local tagWidth = width - SOURCE_X
  for k, m in ipairs(plan.materials) do
    local r = material(p, k)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
    r:SetPoint("RIGHT", p.content, "RIGHT", 0, 0)
    showItem(r.icon, r.text, r.hover, m.item)
    local tags = PB.SourceTags(m)
    -- all of it in your bags: no tags, the count in green
    r.need:SetText(#tags == 0 and W.Color("good", W.Count(m.need)) or W.Count(m.need))
    local back = m.part and m.choice == "buy" or false
    r.make:SetShown(back)
    r.make:SetScript("OnClick", function()
      queue():SetChoice(m.item, "make")
      PB:Refresh()
    end)
    -- the tags, left to right, onto a new line when the row is full
    local tx, ty = 0, 0
    local room = tagWidth - (back and 46 or 0)
    for j, src in ipairs(tags) do
      local t = tag(r.tags, r, j)
      local color = TAG_COLORS[src.kind]
      W.Skin(t, color and color[1] or W.COLORS.panelHover)
      t.text:SetText(color and W.Color(color[2], src.text) or src.text)
      local w = math.ceil((t.text:GetStringWidth() or 0) + 10)
      t:SetWidth(w)
      if tx > 0 and tx + w > room then
        tx, ty = 0, ty + 18
      end
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", r, "TOPLEFT", SOURCE_X + tx, -ty)
      t:Show()
      tx = tx + w + 4
    end
    for j = #tags + 1, #r.tags do
      r.tags[j]:Hide()
    end
    local h = ty + 20
    r:SetHeight(h)
    r:Show()
    y = y + h
  end
  for k = #plan.materials + 1, #p.mats do
    p.mats[k]:Hide()
  end
  -- what to do, in order (each line links its item)
  local todo = {}
  for _, t in ipairs(plan.todo or {}) do
    local text = PB.TodoText(t, me)
    if text then
      todo[#todo + 1] = { text = text, item = t.item }
    end
  end
  if #todo > 0 then
    y = y + 8
    heading(L["To do"]:upper())
    y = y + 16
  end
  for k, t in ipairs(todo) do
    local r = todoLine(p, k)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", p.content, "TOPLEFT", 0, -y)
    r:SetPoint("RIGHT", p.content, "RIGHT", 0, 0)
    r.num:SetText(k .. ".")
    r.text:SetText(t.text)
    r.hover:SetItem(t.item)
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
  -- Craft next: only when a step can be crafted here and now (known, and its materials in your bags)
  local nextStep = not queue():Empty() and self:NextStep(plan) or nil
  p.next:SetEnabled(nextStep ~= nil)
  p.next.step = nextStep
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
      -- the window opens on its top recipe: show the queue's next step instead, once its list is in
      C_Timer.After(0.3, function()
        local step = PB:NextStep()
        if step then
          PB:ShowRecipe(step.recipe)
        end
      end)
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
  pcall(f.RegisterEvent, f, "TRADE_SKILL_LIST_UPDATE") -- the game's craftable counts changed
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
