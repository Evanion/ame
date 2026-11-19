-- Crafting tab (M16): what your characters' professions earn at today's prices. Shown only while Crafting is
-- switched on (Settings > General). Layout (UI.Slots): toolbar = Top earners | Sell or refine | Recipes to buy and a
-- character filter; the table of the mode; a right sidebar with the selected row's breakdown. The math is
-- Core/Crafting.lua; recipes come from what AME recorded in profession windows (Core/Professions.lua) and the crafting
-- data library (Core/CraftingData.lua, loaded on demand).
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

-- gathering professions craft nothing worth ranking
local GATHERING = { [182] = true, [356] = true, [393] = true }
local MODES = {
  { "earners", L["Top earners"] },
  { "refine", L["Sell or refine"] },
  { "recipes", L["Recipes to buy"] },
  { "leveling", L["Leveling"] },
}
local BREAKDOWN_ROWS = 14
UI.RECIPE_LISTING_DAYS = 2 -- recipe items seen on the AH within this many days count as for sale

local function charName(key)
  return (key or ""):gsub("^[^:]*:", "")
end

-- what a row is, across rebuilds: a leveling step by its recipe, a top earner by recipe, a material by item, a
-- recipe to buy by item and taught spell (nil: notes and nothing selected)
function UI.CraftRowKey(r)
  if not r or r.note then
    return nil
  elseif r.entry then
    return "step:" .. tostring(r.entry.recipe.id)
  elseif r.recipe and r.crafters then
    return "recipe:" .. tostring(r.recipe.id)
  elseif r.spell then
    return "buy:" .. tostring(r.item) .. ":" .. tostring(r.spell)
  end
  return "item:" .. tostring(r.itemID)
end

-- redraw the shown rows and breakdown (names that arrived)
function UI.RedrawCrafting()
  local v = UI.craftView
  if v and v:IsShown() and v.tables[UI.craftMode] then
    v.tables[UI.craftMode]:Render()
    UI:RenderCraftingDetail()
  end
end

local function itemName(id)
  return W.ItemNameOrLoad(id, UI.RedrawCrafting)
end

local function days(d)
  if not d then
    return W.Dim("-")
  elseif d < 1 then
    return L["under a day"]
  end
  return L["%d days"]:format(math.floor(d + 0.5))
end

---------------------------------------------------------------------------------------------------------------------
-- the model: recipes your characters know, prices, holdings

-- a recipe as Crafting wants it: the recorded catalog first (what the game showed), else the shipped data
local function recipeFor(profession, id)
  local recorded = ns.Professions:Catalog(profession)
  local r = recorded and recorded[id]
  if r then
    return {
      id = id,
      profession = profession,
      product = r.out,
      made = ((r.min or 1) + (r.max or r.min or 1)) / 2,
      reagents = r.r or {},
      cooldown = ns.CraftingData:Cooldown(id),
    }
  end
  local d = ns.CraftingData:Recipe(id)
  if d then
    return {
      id = id,
      profession = d.profession,
      product = d.product,
      made = d.made,
      reagents = d.reagents,
      cooldown = ns.CraftingData:Cooldown(id),
    }
  end
end

-- everything the three modes need, for the faction auction house's prices
function UI:CraftingModel()
  local index = ns.AME:FactionIndex()
  if not index then
    return nil, "loading"
  end
  if not ns.CraftingData:Load() then
    return nil, "nodata"
  end
  local chars = ns.Professions:Characters()
  local house = ns.AME:CurrentHouse() == "Neutral" and (UnitFactionGroup("player") or "Horde") or ns.AME:CurrentHouse()
  local cut, hours = ns.Settings:AuctionCut(house), ns.Settings:Get("listingHours")
  local only = self.craftChar -- nil: every character

  -- known recipes, one entry per recipe with every character who knows it; product -> recipes (chains)
  local byRecipe, producers, uses, entries = {}, {}, {}, {}
  for key, c in pairs(chars) do
    for profession, p in pairs(c.professions or {}) do
      if not GATHERING[profession] then
        for id in pairs(p.learned or {}) do
          local r = recipeFor(profession, id)
          if r then
            local e = byRecipe[id]
            if not e then
              e = { recipe = r, crafters = {}, profession = profession, cooldown = nil }
              byRecipe[id] = e
              if r.product then
                producers[r.product] = producers[r.product] or {}
                table.insert(producers[r.product], r)
              end
              for _, reagent in ipairs(r.reagents) do
                uses[reagent[1]] = uses[reagent[1]] or {}
                table.insert(uses[reagent[1]], r)
              end
            end
            e.crafters[#e.crafters + 1] = key
            local ready = p.cooldowns and p.cooldowns[id]
            if ready then
              e.cooldown = math.min(e.cooldown or ready, ready)
            end
          end
        end
      end
    end
  end
  for _, e in pairs(byRecipe) do
    local mine = not only
    for _, k in ipairs(e.crafters) do
      mine = mine or k == only
    end
    if mine then
      table.sort(e.crafters)
      entries[#entries + 1] = e
    end
  end

  -- what you hold (bags and bank), per item across the characters in view
  local held = {}
  for key, h in pairs(ns.Trading:Holdings()) do
    if not only or key == only then
      for _, place in ipairs({ "bags", "bank" }) do
        for id, n in pairs(h[place] or {}) do
          held[id] = (held[id] or 0) + n
        end
      end
    end
  end
  local heldSet = {}
  for id, n in pairs(held) do
    heldSet[id] = n > 0 or nil
  end

  local craft = ns.Crafting.New({
    market = function(id)
      return index.items[id]
    end,
    vendorBuy = function(id)
      return ns.CraftingData:VendorPrice(id)
    end,
    vendorSell = function(id)
      return ns.ItemCache.Get(id).sellPrice
    end,
    cut = cut,
    deposit = function(id)
      local sell = ns.ItemCache.Get(id).sellPrice
      return sell and ns.Arbitrage.Deposit(sell, house, hours) or 0
    end,
    sellable = function(id)
      local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
      local bind = getInfo and select(14, getInfo(id))
      return bind ~= 1 -- 1: binds when picked up
    end,
    producers = function(id)
      return producers[id]
    end,
    factor = ns.Settings:Get("outlierFactor"),
  })
  return {
    index = index,
    craft = craft,
    entries = entries,
    held = held,
    heldSet = heldSet,
    uses = uses,
    chars = chars,
  }
end

-- rows for the current mode
function UI:CraftingRows(m)
  local mode = self.craftMode
  if mode == "earners" then
    local list = m.craft:TopEarners(m.entries, m.heldSet)
    for _, e in ipairs(list) do
      e.itemID = e.recipe.product
      e.cost, e.profit, e.perDay, e.sellRate = e.eval.cost, e.eval.profit, e.eval.perDay, e.eval.sellRate
      e.revenue = e.eval.revenue
    end
    return list
  elseif mode == "refine" then
    local rows = {}
    for id, n in pairs(m.held) do
      local recipes = m.uses[id]
      if recipes and n > 0 then
        local r = m.craft:SellOrRefine(id, n, recipes)
        if r.raw > 0 or r.best then
          r.itemID = id
          r.net = r.best and r.best.net or r.raw
          r.gain = r.best and r.best.gain or 0
          r.daysNeeded = r.best and r.best.days
          rows[#rows + 1] = r
        end
      end
    end
    table.sort(rows, function(a, b)
      if a.gain ~= b.gain then
        return a.gain > b.gain
      end
      return a.itemID < b.itemID
    end)
    return rows
  end
  -- recipes to buy: recipe items seen on the AH lately, cheapest listing
  local listings = {}
  local today = m.index.day
  for id, s in pairs(m.index.items) do
    if
      ns.CraftingData:Teaches(id)
      and s.min
      and (s.qty or 0) > 0
      and (not today or not s.day or today - s.day <= UI.RECIPE_LISTING_DAYS)
    then
      listings[#listings + 1] = { item = id, price = s.min }
    end
  end
  local teaches = function(id)
    return ns.CraftingData:Teaches(id)
  end
  local recipe = function(spell)
    return recipeFor(nil, spell)
  end
  local chars = m.chars
  if self.craftChar then
    chars = { [self.craftChar] = m.chars[self.craftChar] }
  end
  local rows = m.craft:RecipesToBuy(listings, teaches, recipe, chars)
  for _, r in ipairs(rows) do
    r.itemID = r.item
    r.perDay = r.eval.perDay
  end
  return rows
end

---------------------------------------------------------------------------------------------------------------------
-- the view

local COLUMNS = {
  earners = {
    { key = "name", label = L["Recipe"], width = 190, item = true, sortKey = false },
    {
      key = "crafter",
      label = L["Crafter"],
      width = 110,
      sortKey = false,
      text = function(e)
        local names = {}
        for _, k in ipairs(e.crafters) do
          names[#names + 1] = charName(k)
        end
        return table.concat(names, ", ")
      end,
    },
    {
      key = "cost",
      money = true,
      label = L["Cost"],
      width = 72,
      text = function(e)
        return UI.CostText(e.cost)
      end,
    },
    { key = "revenue", label = L["Sells for"], width = 72, format = "money" },
    {
      key = "profit",
      money = true,
      label = L["Profit"],
      width = 72,
      text = function(e)
        return e.profit and W.SignedMoney(e.profit) or W.Dim("-")
      end,
    },
    { key = "sellRate", drop = 1, label = L["Sales/day"], width = 60, format = "rate" },
    {
      key = "perDay",
      money = true,
      label = L["Gold/day"],
      width = 72,
      text = function(e)
        return e.perDay and W.Money(e.perDay, true) or W.Dim("-")
      end,
    },
  },
  refine = {
    { key = "name", label = L["Material"], width = 170, item = true, sortKey = false },
    { key = "qty", label = L["Held"], width = 50, format = "count" },
    { key = "raw", label = L["Sell raw"], width = 72, format = "money" },
    {
      key = "use",
      label = L["Best use"],
      width = 170,
      sortKey = false,
      text = function(r)
        if not r.best then
          return W.Color("hold", L["Sell it raw"])
        end
        return W.Color("good", L["Craft %s"]:format(itemName(r.best.recipe.product)))
      end,
    },
    { key = "net", label = L["That nets"], width = 72, format = "money" },
    {
      key = "gain",
      money = true,
      label = L["Gain"],
      width = 64,
      text = function(r)
        return r.gain > 0 and W.SignedMoney(r.gain) or W.Dim("-")
      end,
    },
    {
      key = "daysNeeded",
      drop = 1,
      label = L["Takes"],
      width = 64,
      text = function(r)
        return r.best and days(r.daysNeeded) or ""
      end,
    },
  },
  recipes = {
    { key = "name", label = L["Recipe"], width = 200, item = true, sortKey = false },
    {
      key = "for",
      label = L["For"],
      width = 130,
      sortKey = false,
      text = function(r)
        local l = r.learners[1]
        if l.ready then
          return charName(l.char)
        end
        return L["%s needs %d (has %d)"]:format(charName(l.char), r.rank or 0, l.skill)
      end,
    },
    {
      key = "price",
      money = true,
      label = L["Price"],
      width = 72,
      text = function(r)
        return UI.CostText(r.price)
      end,
    },
    {
      key = "perDay",
      money = true,
      label = L["Earns/day"],
      width = 72,
      text = function(r)
        return r.perDay and W.Money(r.perDay, true) or W.Dim("-")
      end,
    },
    {
      key = "payback",
      label = L["Pays back"],
      width = 72,
      text = function(r)
        return days(r.payback)
      end,
    },
  },
  leveling = UI.LEVELING_COLUMNS, -- Core/UI/LevelingView.lua
}

function UI:CreateCraftingView(parent, contentArea)
  local v = contentArea(parent)
  self.craftView = v
  self.craftMode = "earners"
  local slots = UI.Slots(
    v,
    { toolbar = 22, header = 42, headerBelow = true, right = UI.SIDE_PANEL_W, rightCards = true, status = true }
  )
  v.slots = slots
  local bar = slots.toolbar
  v.modes = W.Segmented(bar, MODES, {
    minWidth = 80,
    onSelect = function(mode)
      UI.craftMode, UI.craftSelected = mode, nil
      UI:RefreshCrafting()
    end,
  })
  v.modes:SetPoint("LEFT", 0, 0)
  v.modes:Select("earners", true)
  v.char = W.Dropdown(bar, 140, { { false, L["All characters"] } }, function(key)
    UI.craftChar = key or nil
    UI:RefreshCrafting()
  end, { neutral = true, default = false })
  v.char:SetPoint("LEFT", v.modes, "RIGHT", 12, 0)
  v.details = W.Button(bar, L["Details"], 64, 20, function()
    slots:ToggleDetails()
    v.details:SetSelected(slots.details)
  end)
  v.details:SetPoint("RIGHT", 0, 0)

  v.tables = {}
  for mode, columns in pairs(COLUMNS) do
    local t = ns.DataTable.New(slots.main, {
      columns = columns,
      rows = 16,
      fill = true,
      top = 0,
      itemID = function(e)
        return e.itemID
      end,
      selected = function(e)
        return UI.craftSelected == e
      end,
      onClick = function(e)
        UI.craftSelected = e
        UI:RenderCraftingDetail()
        v.tables[UI.craftMode]:Render()
      end,
    })
    t.frame:Hide()
    v.tables[mode] = t
  end

  -- the breakdown: a title, a subtitle and reusable label / value rows
  local col = UI.Stack(slots.right.content, 0)
  v.detailCol = col
  local st = col:Card(0).stack
  v.title = st:Text("GameFontNormalLarge")
  -- the title is the row's item (product, material or recipe): it acts like one too (UI.ItemLine)
  v.titleHit = CreateFrame("Frame", nil, slots.right.content)
  v.titleHit:SetPoint("TOPLEFT", v.title, "TOPLEFT")
  v.titleHit:SetPoint("BOTTOMRIGHT", v.title, "BOTTOMRIGHT")
  UI.ItemLine(v.titleHit)
  v.subtitle = st:Text("GameFontDisableSmall", 4)
  v.colorRow = st:Row(14, 6) -- Leveling: the step's skill colors
  st = col:Card().stack
  v.lines = {}
  for i = 1, BREAKDOWN_ROWS do
    local line = st:Pair("", nil, i == 1 and 0 or 2)
    v.lines[i] = line
    -- a line about an item (a reagent) acts like one: click searches the AH (or opens the chart), Shift-click
    -- links it in chat, hover shows its tooltip
    UI.ItemLine(line)
  end
  v.note = col:Text("GameFontDisableSmall", 6)
  local actions = col:Row(26, 10)
  v.action = W.Button(actions, "", 140, 26, function()
    UI:CraftingAction()
  end)
  v.action:SetPoint("LEFT")
  v.action:SetPoint("RIGHT", -70, 0)
  v.chart = W.Button(actions, L["Chart"], 64, 26, function()
    local e = UI.craftSelected
    local id = e and (e.recipe and e.recipe.product or e.itemID)
    if id then
      UI:ShowItem(id)
    end
  end)
  v.chart:SetPoint("RIGHT")

  self:CreateLevelingControls(v, slots)
  self:ShowLevelingControls(v, false)

  v.message = W.Text(slots.main, "GameFontDisable")
  v.message:SetPoint("TOPLEFT", 20, -40)
  v.message:SetPoint("RIGHT", -20, 0)
  v.message:SetJustifyH("CENTER")

  function v:SetCompact(on)
    slots:SetCompact(on)
    self.details:SetShown(on)
    self.details:SetSelected(false)
  end
  v:SetCompact(slots.compact)
  v:SetScript("OnShow", function()
    UI:RefreshCrafting()
  end)
  ns.Professions.onChange = function()
    if v:IsShown() then
      UI:RefreshCrafting()
    end
  end
  return v
end

function UI:RefreshCrafting()
  local v = self.craftView
  if not (v and v:IsShown()) then
    return
  end
  v.modes:Select(self.craftMode, true)
  local leveling = self.craftMode == "leveling"
  self:ShowLevelingControls(v, leveling)
  -- the character filter: characters with recorded professions
  local options = { { false, L["All characters"] } }
  local keys = {}
  for key in pairs(ns.Professions:Characters()) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    options[#options + 1] = { key, charName(key) }
  end
  v.char:SetOptions(options)
  v.char:SetValue(self.craftChar or false)

  local m, why = self:CraftingModel()
  for mode, t in pairs(v.tables) do
    t.frame:SetShown(m ~= nil and mode == self.craftMode)
  end
  v.message:SetShown(m == nil or #keys == 0)
  if not m then
    v.message:SetText(
      why == "nodata"
          and (ns.CraftingData.failed == "DISABLED" and L["Crafting needs the AME Crafting Data addon, which is installed but switched off: enable it in the AddOns list at character select."] or ns.CraftingData.failed == "INTERFACE_VERSION" and L["Your AME Crafting Data addon is out of date for this game version: update it from CurseForge."] or L["Crafting needs the AME Crafting Data addon (recipe data, loaded only when you use this tab). Install it from CurseForge: AME Crafting Data. A newly installed addon shows up after you log out to character select."])
        or L["Building market index..."]
    )
    v.slots.status:SetText("")
    self.craftRows = nil
    self:RenderCraftingDetail()
    return
  end
  if #keys == 0 then
    v.message:SetText(
      L["Open each of your professions once - on every character - so AME knows what they can craft. It records them as you do."]
    )
  end
  self.craftModel = m
  -- the selection survives a rebuild (each craft re-records the profession): the new row for the same thing
  local selected = UI.CraftRowKey(self.craftSelected)
  local rows = leveling and self:LevelingRows(m) or self:CraftingRows(m)
  self.craftRows = rows
  self.craftSelected = nil
  if selected then
    for _, r in ipairs(rows) do
      if UI.CraftRowKey(r) == selected then
        self.craftSelected = r
        break
      end
    end
  end
  if leveling then
    self:RenderLevelingHeader(v)
  end
  local t = v.tables[self.craftMode]
  t:SetData(rows)
  t:Render()
  t:SetMessage(
    #keys > 0
        and #rows == 0
        and (self.craftMode == "recipes" and L["No recipe on the auction house that your characters could learn and don't know yet."] or self.craftMode == "refine" and L["Nothing your characters hold is a reagent of a recipe they know."] or L["No known recipes yet."])
      or nil
  )
  local recorded = {}
  for _, key in ipairs(keys) do
    local names = {}
    for profession, p in pairs(m.chars[key].professions or {}) do
      if not GATHERING[profession] then
        names[#names + 1] = p.name
      end
    end
    table.sort(names)
    if #names > 0 then -- characters with only gathering, or only spellbook data, aren't listed
      recorded[#recorded + 1] = ("%s (%s)"):format(charName(key), table.concat(names, ", "))
    end
  end
  v.slots.status:SetText(
    #recorded > 0
        and L["Recorded: %s"]:format(table.concat(recorded, "; ")) .. W.SEP .. L["prices: your faction's auction house"]
      or ""
  )
  self:RenderCraftingDetail()
end

-- A frame about an item (frame.itemID, nil: none) acts like one: click searches the AH (or opens the chart), Shift-click
-- links it in chat, hover shows its tooltip.
function UI.ItemLine(frame)
  frame:EnableMouse(true)
  frame:SetScript("OnMouseUp", function(self)
    UI:CraftingLineClick(self.itemID)
  end)
  W.Tooltip(frame, function(tip, self)
    if not self.itemID then
      return false
    end
    W.SetItemTip(tip, self.itemID)
    tip:AddLine(" ")
    tip:AddLine(
      ns.AME.ahOpen and L["Click: search the auction house  ·  Shift-click: link in chat"]
        or L["Click: price chart  ·  Shift-click: link in chat"],
      0.6,
      0.6,
      0.6
    )
  end)
end

-- the item a row is about, for the breakdown's title
function UI.CraftRowItem(mode, e)
  if not e or e.note then
    return nil
  elseif mode == "leveling" then
    return e.entry and e.entry.recipe.product
  elseif mode == "earners" then
    return e.recipe and e.recipe.product
  elseif mode == "recipes" then
    return e.item
  end
  return e.itemID
end

-- the breakdown's lines: { label, value, itemID (optional: the line is about that item) }
local function setLines(v, pairsList)
  for i, line in ipairs(v.lines) do
    local p = pairsList[i]
    line.label:SetText(p and p[1] or "")
    line.value:SetText(p and p[2] or "")
    line.itemID = p and p[3] or nil
  end
end

-- a click on an item line: Shift links it in chat; otherwise search the open auction house, or show its chart
function UI:CraftingLineClick(itemID)
  if not itemID then
    return
  end
  if IsShiftKeyDown() then
    local link = ns.ItemCache.Link(itemID)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or _G.ChatEdit_InsertLink
    if link and insert then
      insert(link)
    end
  elseif ns.AME.ahOpen then
    ns.AME:SearchAuctionHouse(itemID)
  else
    self:ShowItem(itemID)
  end
end

local SOURCE = {
  buy = L["buy"],
  vendor = L["vendor"],
  held = L["you hold it"],
  craft = L["craft it"],
}

-- the breakdown, then the sidebar re-measured (its rows change height with their text)
function UI:RenderCraftingDetail()
  local v = self.craftView
  if not v then
    return
  end
  self:RenderCraftingDetailRows()
  v.titleHit.itemID = UI.CraftRowItem(self.craftMode, self.craftSelected)
  local width = v.slots.right.content:GetWidth()
  v.detailCol:Height(width and width > 0 and width or UI.SIDE_PANEL_W)
  v.slots.right.pane:Measure()
end

function UI:RenderCraftingDetailRows()
  local v = self.craftView
  local e = self.craftSelected
  local found = false
  for _, r in ipairs(self.craftRows or {}) do
    found = found or r == e
  end
  if not found then
    e = nil
    self.craftSelected = nil
  end
  v.action:SetShown(e ~= nil and not e.note)
  v.chart:SetShown(e ~= nil and not e.note)
  v.colorBar:SetShown(false)
  if self.craftMode == "leveling" and (not e or e.note) then
    v.title:SetText(W.Dim(L["Select a step"]))
    v.subtitle:SetText(
      e and e.text
        or L["Click a step for its skill colors, the reagents to buy and where the results go. The button puts the whole path's reagents on a shopping list."]
    )
    setLines(v, {})
    v.note:SetText("")
    v.action:SetText(L["Add all reagents to a shopping list"])
    v.action:SetShown(self.leveling ~= nil)
    return
  end
  if not e then
    v.title:SetText(W.Dim(L["Select a row"]))
    v.subtitle:SetText(
      L["Click a row for its breakdown: where each reagent comes from, what selling nets, and how much the market takes."]
    )
    setLines(v, {})
    v.note:SetText("")
    return
  end
  local mode = self.craftMode
  local lines = {}
  if mode == "leveling" then
    lines = self:LevelingDetail(v, e)
    v.note:SetText(
      e.entry.estimated
          and not e.entry.known
          and L["Trained at a trainer; the game data has no training level for it, so the level here is estimated."]
        or ""
    )
    v.action:SetText(L["Add all reagents to a shopping list"])
  elseif mode == "earners" then
    local ev = e.eval
    v.title:SetText(e.recipe.product and itemName(e.recipe.product) or W.Dim(L["Enchant"]))
    local names = {}
    for _, k in ipairs(e.crafters) do
      names[#names + 1] = charName(k)
    end
    v.subtitle:SetText(L["%s · makes %s"]:format(table.concat(names, ", "), tostring(e.recipe.made)))
    for _, r in ipairs(ev.reagents) do
      lines[#lines + 1] = {
        ("%d %s  %s"):format(r.n, itemName(r.item), W.Dim(SOURCE[r.source] or "")),
        W.Money(r.each * r.n, true),
        r.item,
      }
    end
    lines[#lines + 1] = { L["Cost"], W.Money(ev.cost, true) }
    lines[#lines + 1] = { L["Sells for, after cut"], ev.revenue and W.Money(ev.revenue, true) or W.Dim("-") }
    lines[#lines + 1] = { L["Profit per craft"], ev.profit and W.SignedMoney(ev.profit) or W.Dim("-") }
    lines[#lines + 1] = { L["Sells a day"], ev.sellRate and W.Rate(ev.sellRate) or W.Dim("-") }
    lines[#lines + 1] = { L["Gold a day"], ev.perDay and W.Money(ev.perDay, true) or W.Dim("-") }
    local why = ev.why == "unsellable" and L["Can't be sold: it binds when made."]
      or ev.why == "unpriced" and L["Missing a price: scan the auction house (or it's never listed)."]
      or ev.why == "enchant" and L["Enchants make no item to sell; valued later."]
      or ""
    if e.cooldown then
      local left = e.cooldown - GetServerTime()
      why = (left > 0 and L["On cooldown for %s."]:format(SecondsToTime(left)) or L["Cooldown ready."]) .. " " .. why
    end
    v.note:SetText(why)
    v.action:SetText(L["Add reagents to a shopping list"])
  elseif mode == "refine" then
    v.title:SetText(("%s %s"):format(W.Count(e.qty), itemName(e.itemID)))
    v.subtitle:SetText(L["Selling it raw nets %s (after the cut and deposit)."]:format(W.Money(e.raw, true)))
    for i, o in ipairs(e.options) do
      if i > 4 then
        break
      end
      lines[#lines + 1] = {
        L["Craft %s ×%d"]:format(itemName(o.recipe.product), o.crafts),
        W.Money(o.net, true) .. " " .. (o.gain > 0 and W.SignedMoney(o.gain) or W.Dim(L["less"])),
      }
      if o.days then
        lines[#lines + 1] = { W.Dim(L["   the market takes it in"]), W.Dim(days(o.days)) }
      end
    end
    v.note:SetText(
      L["Materials you'd craft count at what they would sell for, not at their buy price: listing costs a cut, buying doesn't."]
    )
    v.action:SetText(L["Search the AH"])
  else
    v.title:SetText(itemName(e.item))
    v.subtitle:SetText(
      L["Teaches %s"]:format(e.recipe.product and itemName(e.recipe.product) or L["an enchant"])
        .. W.SEP
        .. L["needs %d"]:format(e.rank or 0)
    )
    lines[#lines + 1] = { L["On the AH now"], W.Money(e.price, true) }
    local s = self.craftModel and self.craftModel.index.items[e.item]
    if s and s.avg30 then
      lines[#lines + 1] = { L["Usually"], W.Money(s.avg30, true) }
    end
    local ev = e.eval
    lines[#lines + 1] = { L["Cost per craft"], ev.cost and W.Money(ev.cost, true) or W.Dim("-") }
    lines[#lines + 1] = { L["Profit per craft"], ev.profit and W.SignedMoney(ev.profit) or W.Dim("-") }
    lines[#lines + 1] = { L["Earns a day"], ev.perDay and W.Money(ev.perDay, true) or W.Dim("-") }
    lines[#lines + 1] = { L["Pays back"], days(e.payback) }
    for _, l in ipairs(e.learners) do
      lines[#lines + 1] = {
        charName(l.char),
        l.ready and W.Color("good", L["can learn it (%d)"]:format(l.skill))
          or W.Dim(L["needs %d, has %d"]:format(e.rank or 0, l.skill)),
      }
    end
    v.note:SetText("")
    v.action:SetText(L["Search the AH"])
  end
  setLines(v, lines)
end

-- the sidebar's main button: a shopping list of one craft's reagents (top earners), or search the auction house
function UI:CraftingAction()
  local e = self.craftSelected
  if not e and self.craftMode ~= "leveling" then
    return
  end
  if self.craftMode == "leveling" then
    self:LevelingShoppingList()
    return
  end
  if self.craftMode == "earners" then
    local shop = ns.AME.shopping
    local name = W.Plain(itemName(e.recipe.product or e.itemID or 0))
    local index
    for i, l in ipairs(shop:Lists()) do
      if l.name == name then
        index = i
      end
    end
    index = index or shop:AddList(name)
    if index then
      for _, r in ipairs(e.recipe.reagents) do
        shop:AddItem(index, r[1], r[2])
      end
      self:ShoppingChanged(index)
      ns.AME.Say(L["Added the reagents for one %s to the shopping list %s."], name, name)
    end
  else
    ns.AME:SearchAuctionHouse(e.itemID)
  end
end

-- Settings: Crafting switched on or off - the tab and its recording follow
function UI:CraftingChanged(on)
  if on then
    ns.Professions:RecordSpellbook()
    ns.Professions:Record() -- a profession window that's already open
  elseif self.current == "crafting" then
    self:ShowTab("market")
  end
  self:LayoutTabs()
end
