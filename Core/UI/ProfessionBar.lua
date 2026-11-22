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

-- Pure: the queue as lines of text, for the panel: { { text, kind, step / material } }
function PB.QueueLines(plan)
  local lines = {}
  local function add(text, kind, ref)
    lines[#lines + 1] = { text = text, kind = kind, ref = ref }
  end
  add(W.Dim(L["In order"]), "head")
  for k, s in ipairs(plan.steps) do
    local who = ""
    if s.crafter and not s.mine then
      who = W.Color("warn", "  " .. L["on %s"]:format(charName(s.crafter)))
    elseif not s.crafter then
      who = W.Color("bad", "  " .. L["nobody of yours knows it"])
    end
    local tail = s.profit and ("  " .. signed(s.profit)) or (s.part and W.Dim("  " .. L["a part"]) or "")
    add(("%d.  %s x%d"):format(k, name(s.item), s.made or s.count) .. who .. tail, "step", s)
  end
  add(W.Dim(L["Materials"]) .. W.Dim("  ·  " .. L["need, and its source"]), "head")
  for _, m in ipairs(plan.materials) do
    local parts = {}
    for _, src in ipairs(m.sources) do
      local where = SOURCE[src.kind] and SOURCE[src.kind](src) or src.kind
      local text = ("%d %s"):format(src.qty, where)
      if src.kind == "ah" then
        text = W.Color("warn", text .. (src.cost and (" " .. money(src.cost)) or ""))
      end
      parts[#parts + 1] = text
    end
    add(("%s x%d  ·  "):format(name(m.item), m.need) .. table.concat(parts, W.Dim(", ")), "material", m)
  end
  add(
    W.Dim(L["Profit"] .. " ") .. signed(plan.profit) .. W.Dim("   " .. L["to buy"] .. " ") .. money(plan.toBuy),
    "total"
  )
  return lines
end

function PB:CreateQueue(host)
  local p = CreateFrame("Frame", nil, host, "BackdropTemplate")
  W.Skin(p, W.COLORS.bg)
  p:SetWidth(PB.QUEUE_W)
  p:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, 0)
  p:SetPoint("BOTTOMLEFT", host, "BOTTOMRIGHT", 4, 0)
  p.title = W.Text(p, "GameFontNormal")
  p.title:SetPoint("TOPLEFT", 10, -10)
  p.title:SetText(L["Craft queue"])
  p.close = W.CloseButton(p)
  p.close:SetPoint("TOPRIGHT", -4, -4)
  p.close:SetScript("OnClick", function()
    PB:ShowQueue(false)
  end)
  p.rows = {}
  p.next = W.Button(p, L["Craft next"], 110, 22, function()
    PB:CraftNext()
  end)
  p.next:SetPoint("BOTTOMLEFT", 10, 10)
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

local function row(p, i)
  local r = p.rows[i]
  if r then
    return r
  end
  r = CreateFrame("Frame", nil, p)
  r:SetHeight(18)
  r.text = W.Text(r, "GameFontHighlightSmall")
  r.text:SetPoint("LEFT", 0, 0)
  r.text:SetPoint("RIGHT", -70, 0)
  r.text:SetWordWrap(false)
  r.toggle = W.Button(r, "", 42, 16)
  r.toggle:SetPoint("RIGHT", -20, 0)
  r.remove = W.Button(r, "x", 16, 16)
  r.remove:SetPoint("RIGHT", 0, 0)
  p.rows[i] = r
  return r
end

function PB:RenderQueue()
  local p = self.panel
  if not (p and p:IsShown()) then
    return
  end
  local lines = PB.QueueLines(PB.Plan())
  local y = -34
  for i, line in ipairs(lines) do
    local r = row(p, i)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 10, y)
    r:SetPoint("RIGHT", -10, 0)
    r.text:SetText(line.text)
    r.text:SetFontObject(line.kind == "head" and "GameFontNormalSmall" or "GameFontHighlightSmall")
    -- a part: make it or buy it; a queued item: remove it
    local s = line.kind == "step" and line.ref
    local m = line.kind == "material" and line.ref
    r.toggle:SetShown((s and s.part) or (m and m.part and m.choice == "buy") or false)
    r.remove:SetShown(s and not s.part or false)
    if s and s.part then
      r.toggle:SetText(L["Buy"])
      r.toggle:SetScript("OnClick", function()
        queue():SetChoice(s.item, "buy")
        PB:Refresh()
      end)
    elseif m and m.part then
      r.toggle:SetText(L["Make"])
      r.toggle:SetScript("OnClick", function()
        queue():SetChoice(m.item, "make")
        PB:Refresh()
      end)
    end
    r.remove:SetScript("OnClick", function()
      if s then
        queue():Remove(s.recipe)
        PB:Refresh()
      end
    end)
    r:Show()
    y = y - (line.kind == "head" and 22 or 18)
  end
  for i = #lines + 1, #p.rows do
    p.rows[i]:Hide()
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
