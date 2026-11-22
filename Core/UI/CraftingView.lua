-- Crafting tab: your professions, who can make what, the craft queue, and what your recipes earn. Always there (the
-- crafting data library comes with AME; without it only Recipes to buy and Leveling say what they need). Layout
-- (UI.Slots), the same on every page: a sidebar of the pages (Market-style lines; a dropdown when narrow), a toolbar
-- (character, profession, search - kept as you switch pages - and the page's own controls), the page's table, and a
-- card with the picked row's breakdown. The math is Core/Crafting.lua; recipes come from what AME recorded in
-- profession windows (Core/Professions.lua) and the crafting data library (Core/CraftingData.lua, loaded on demand).
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

-- gathering professions craft nothing worth ranking (Core/CraftModel.lua)
local GATHERING = ns.CraftModel.GATHERING
-- the pages, as the sidebar lists them (headings between groups)
local PAGES = {
  { heading = L["Crafting"] },
  { key = "professions", label = L["Your professions"] },
  { key = "crafters", label = L["Find a crafter"] },
  { key = "queue", label = L["Craft queue"] },
  { heading = L["Make money"] },
  { key = "earners", label = L["Top earners"] },
  { key = "refine", label = L["Sell or refine"] },
  { key = "recipes", label = L["Recipes to buy"] },
  { heading = L["Level up"] },
  { key = "leveling", label = L["Leveling"] },
}
local MODES = {}
for _, p in ipairs(PAGES) do
  if p.key then
    MODES[#MODES + 1] = { p.key, p.label }
  end
end
UI.CRAFT_PAGES = PAGES
-- pages that need the crafting data library's full recipe list
local NEEDS_DATA = { recipes = true, leveling = true }
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
  elseif r.skillLine then
    return "prof:" .. tostring(r.key) .. ":" .. tostring(r.skillLine)
  elseif r.crafter then
    return "crafter:" .. tostring(r.recipe) .. ":" .. tostring(r.crafter)
  elseif r.step then
    return "queue:" .. tostring(r.s.recipe) .. ":" .. tostring(r.itemID)
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
  return ns.Recipes.Get(id, profession)
end

-- the Crafting model and "craft it instead" live in Core/CraftModel.lua
function UI:CraftInstead(itemID)
  return ns.CraftModel.Instead(itemID)
end

function UI:CraftingModel()
  return ns.CraftModel.Build(self.craftChar)
end

-- does a row match the toolbar's profession and search? (rows about an item: its name)
function UI:CraftFilter(row, profession)
  if self.craftProf and profession and profession ~= self.craftProf then
    return false
  end
  local text = self.craftSearch
  if text and text ~= "" and self.craftMode ~= "crafters" then
    local id = row.itemID
    local name = (id and ns.ItemCache.Name(id))
      or row.name
      or (type(row.recipe) == "table" and ns.Crafters.RecipeName(row.recipe.id))
      or ""
    return name:lower():find(text:lower(), 1, true) ~= nil
  end
  return true
end

-- Your professions: one row per character and profession, with its best earner
function UI:ProfessionRows(m)
  local best = {}
  for _, e in ipairs(m.craft:TopEarners(m.entries, m.heldSet)) do
    for _, key in ipairs(e.crafters) do
      local k = key .. ":" .. tostring(e.profession)
      if not best[k] and e.eval.perDay then
        best[k] = e
      end
    end
  end
  local now, rows = GetServerTime(), {}
  for key, c in pairs(m.chars) do
    if not self.craftChar or key == self.craftChar then
      for skillLine, p in pairs(c.professions or {}) do
        local known = 0
        for _ in pairs(p.learned or {}) do
          known = known + 1
        end
        local ready, wait = false, nil
        for _, t in pairs(p.cooldowns or {}) do
          if t <= now then
            ready = true
          else
            wait = math.min(wait or math.huge, t - now)
          end
        end
        local b = best[key .. ":" .. tostring(skillLine)]
        local row = {
          key = key,
          char = charName(key),
          skillLine = skillLine,
          profession = p.name or "?",
          skill = p.skill,
          max = p.max,
          known = known,
          ready = ready,
          wait = wait,
          best = b,
          itemID = b and b.recipe.product,
          perDay = b and b.eval.perDay,
        }
        if self:CraftFilter({ name = row.profession }, skillLine) then
          rows[#rows + 1] = row
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.char ~= b.char then
      return a.char < b.char
    end
    return a.profession < b.profession
  end)
  return rows
end

-- Find a crafter: everyone who knows a recipe matching the search (an item or an enchant), online first
function UI:CrafterRows()
  local crafters = ns.Crafters and ns.Crafters.Shared()
  local text = self.craftSearch or ""
  if not crafters or text == "" then
    return {}
  end
  local rows = {}
  for _, res in ipairs(crafters:Search(text)) do
    local r = ns.ProfessionBar and ns.ProfessionBar.Recipe(res.recipe)
    local d = not r and ns.CraftingData:Recipe(res.recipe)
    local product = (r and r.product) or (d and d.product)
    for _, c in ipairs(res.who) do
      rows[#rows + 1] = {
        recipe = res.recipe,
        name = res.name,
        itemID = product,
        crafter = c.name,
        mine = c.mine,
        online = c.online,
        skill = c.skill,
        seen = c.t,
        count = #res.who,
      }
    end
  end
  return rows
end

-- the craft queue's steps (the profession window's queue, planned the same way)
function UI:QueueRows()
  local PB = ns.ProfessionBar
  if not (PB and PB.Plan) then
    return {}
  end
  local plan = PB.Plan()
  self.craftPlan = plan
  local rows = {}
  for k, s in ipairs(plan.steps) do
    rows[#rows + 1] = {
      step = k,
      itemID = s.item,
      made = s.made or s.count,
      who = s.crafter and (s.mine and L["you"] or charName(s.crafter)) or nil,
      part = s.part,
      profit = s.profit,
      s = s,
    }
  end
  return rows
end

-- rows for the current mode, filtered by the toolbar's profession and search
function UI:CraftingRows(m)
  local mode = self.craftMode
  local rows = self:CraftingModeRows(m)
  if mode == "professions" or mode == "crafters" then
    return rows -- filtered as they're made
  end
  local out = {}
  for _, r in ipairs(rows) do
    local profession = r.profession or (r.recipe and r.recipe.profession)
    if self:CraftFilter(r, type(profession) == "number" and profession or nil) then
      out[#out + 1] = r
    end
  end
  return out
end

function UI:CraftingModeRows(m)
  local mode = self.craftMode
  if mode == "professions" then
    return self:ProfessionRows(m)
  elseif mode == "crafters" then
    return self:CrafterRows()
  elseif mode == "queue" then
    return self:QueueRows()
  elseif mode == "earners" then
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
  -- the character you're on: the game itself says what it knows (a recipe learned since its window last opened)
  local me = ns.Trading.CharKey()
  local function knows(key, spell)
    return key == me and _G.IsPlayerSpell and _G.IsPlayerSpell(spell) or false
  end
  local rows = m.craft:RecipesToBuy(listings, teaches, recipe, chars, knows)
  -- who else already makes it: your guild and trusted players (Crafters); the toolbar's toggle keeps only the gaps
  local shared = ns.Crafters and ns.Crafters.Shared()
  local out = {}
  for _, r in ipairs(rows) do
    r.itemID = r.item
    r.perDay, r.profit = r.eval.perDay, r.eval.profit
    local others = 0
    for _, c in ipairs(shared and r.spell and shared:WhoKnows(r.spell) or {}) do
      if not c.mine then
        others = others + 1
      end
    end
    r.network = others
    local learnable = false
    for _, l in ipairs(r.learners) do
      learnable = learnable or (l.char == me and l.ready)
    end
    if (not self.craftGaps or others == 0) and (not self.craftLearnable or learnable) then
      out[#out + 1] = r
    end
  end
  return out
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
        return e.cost and W.Money(e.cost, true) or W.Dim("-")
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
      label = L["Market/day"], -- the whole market's daily profit: you'd earn a share of it, not all of it
      term = "marketDay",
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
  professions = {
    { key = "char", label = L["Character"], width = 100, align = "LEFT" },
    { key = "profession", label = L["Profession"], width = 110, align = "LEFT" },
    {
      key = "skill",
      label = L["Skill"],
      width = 64,
      text = function(r)
        return ("%d / %d"):format(r.skill or 0, r.max or 0)
      end,
    },
    { key = "known", label = L["Recipes"], width = 56, format = "count" },
    {
      key = "wait",
      drop = 1,
      label = L["Cooldown"],
      width = 80,
      text = function(r)
        if r.ready then
          return W.Color("good", L["ready"])
        elseif r.wait then
          return SecondsToTime(r.wait, true)
        end
        return W.Dim("-")
      end,
    },
    {
      key = "name",
      label = L["Best earner"],
      width = 170,
      item = true,
      sortKey = false,
      fallback = function()
        return W.Dim("-")
      end,
    },
    {
      key = "perDay",
      money = true,
      label = L["Market/day"],
      term = "marketDay",
      width = 72,
      text = function(r)
        return r.perDay and W.Money(r.perDay, true) or W.Dim("-")
      end,
    },
  },
  crafters = {
    {
      key = "name",
      label = L["Makes"],
      width = 200,
      item = true,
      fallback = function(r)
        return r.name
      end,
    },
    {
      key = "crafter",
      label = L["Crafter"],
      width = 130,
      align = "LEFT",
      text = function(r)
        -- online: green; offline: dim
        local name = r.online and W.Color("good", r.crafter) or W.Dim(r.crafter)
        return r.mine and (name .. W.Dim("  " .. L["you"])) or name
      end,
    },
    {
      key = "skill",
      label = L["Skill"],
      width = 50,
      text = function(r)
        return r.skill and tostring(r.skill) or W.Dim("-")
      end,
    },
  },
  queue = {
    { key = "step", label = "#", width = 28, format = "count" },
    {
      key = "name",
      label = L["Craft"],
      width = 200,
      item = true,
      sortKey = false,
      suffix = function(r)
        return W.Dim("  ×" .. tostring(r.made or 1)) .. (r.part and W.Dim("  " .. L["(part)"]) or "")
      end,
    },
    {
      key = "who",
      label = L["Crafter"],
      width = 110,
      align = "LEFT",
      text = function(r)
        return r.who or W.Color("warn", L["nobody"])
      end,
    },
    {
      key = "profit",
      money = true,
      label = L["Profit"],
      width = 72,
      text = function(r)
        return r.profit and W.SignedMoney(r.profit) or W.Dim("-")
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
        return r.price and W.Money(r.price, true) or W.Dim("-")
      end,
    },
    {
      -- profit per craft of what it teaches (how long it takes to pay back is in the sidebar)
      key = "profit",
      money = true,
      label = L["Profit"],
      width = 72,
      text = function(r)
        return r.profit and W.SignedMoney(r.profit) or W.Dim("-")
      end,
    },
    {
      key = "perDay",
      money = true,
      label = L["Market/day"],
      term = "marketDay",
      width = 72,
      text = function(r)
        return r.perDay and W.Money(r.perDay, true) or W.Dim("-")
      end,
    },
    {
      -- your guild and trusted players who already know it (Crafters); "nobody": a gap your network can't fill
      key = "network",
      drop = 2,
      label = L["Network"],
      width = 80,
      text = function(r)
        return (r.network or 0) == 0 and W.Color("warn", L["nobody"]) or L["%d in network"]:format(r.network)
      end,
    },
  },
  leveling = UI.LEVELING_COLUMNS, -- Core/UI/LevelingView.lua
}

-- What each page's toolbar holds (UI.CraftingToolbar), left to right: the search box (search = true, or its hint),
-- the scope (the character and profession pickers, kept as you switch pages), the page's checks (the toolbar's own,
-- by name: v.gaps, v.learnable), then the page's own controls (extra, set by the page's file: Leveling's), and its
-- buttons on the right (actions = { { label, onClick, width = 90, primary = true }, ... }). status(info) is the
-- footer's text; info.recorded lists the characters' recorded professions.
local function recordedStatus(info)
  local recorded = info.recorded or {}
  return #recorded > 0
      and L["Recorded: %s"]:format(table.concat(recorded, "; ")) .. W.SEP .. L["prices: your faction's auction house"]
    or ""
end
UI.CRAFT_TOOLBAR = {
  professions = { search = true, scope = true },
  crafters = { search = L["Who can make... (an item or enchant)"] },
  queue = { search = true, scope = true },
  earners = { search = true, scope = true },
  refine = { search = true, scope = true },
  recipes = { search = true, scope = true, checks = { "gaps", "learnable" } },
  leveling = {},
}
for _, page in pairs(UI.CRAFT_TOOLBAR) do
  page.status = page.status or recordedStatus
end

-- The Crafting tab's toolbar, the same on every page. The controls it holds are v.page (the pages, when narrow),
-- v.search, v.char, v.prof, v.gaps, v.learnable and v.details (the Details panel, when narrow); each page shows what
-- UI.CRAFT_TOOLBAR declares for it. -> toolbar, with :Layout() (also v:LayoutToolbar()),
-- :SetExtra(page, fn(place, compact)) for a page's own controls (place(widget, gap) puts one after the last), and
-- :StatusText(page, info).
function UI.CraftingToolbar(v)
  local slots = v.slots
  local bar = slots.toolbar
  local tb = { actions = {} }
  v.page = W.Dropdown(bar, 130, MODES, function(key)
    if key then
      UI:ShowCraftingPage(key)
    end
  end, { neutral = true, default = "professions" })

  -- the filters, kept as you switch pages: search, character, profession
  v.search = W.Input(bar, {
    width = UI.SIDEBAR_W,
    hint = L["Search recipes or items..."],
    onChange = function(text) -- every key: refreshed once typing pauses
      UI.craftSearch = text
      UI.craftSearchGen = (UI.craftSearchGen or 0) + 1
      local gen = UI.craftSearchGen
      C_Timer.After(0.25, function()
        if gen == UI.craftSearchGen then
          UI.craftSelected = nil
          UI:RefreshCrafting()
        end
      end)
    end,
    clearOnEscape = true,
  })
  v.char = W.Dropdown(bar, 140, { { false, L["All characters"] } }, function(key)
    UI.craftChar = key or nil
    UI:RefreshCrafting()
  end, { neutral = true, default = false })
  v.prof = W.Dropdown(bar, 130, { { false, L["All professions"] } }, function(key)
    UI.craftProf = key or nil
    UI:RefreshCrafting()
  end, { neutral = true, default = false })
  -- Recipes to buy: only the recipes nobody in your network knows yet (the gaps to close)
  v.gaps = W.Check(bar, L["Only what nobody has"], function(on)
    UI.craftGaps = on or nil
    UI.craftSelected = nil
    UI:RefreshCrafting()
  end)
  -- Recipes to buy: only what the character you're on can learn right now (its profession, skill high enough, not
  -- known yet) - the game's own term for it
  v.learnable = W.Check(bar, L["Usable only"], function(on)
    UI.craftLearnable = on or nil
    UI.craftSelected = nil
    UI:RefreshCrafting()
  end)
  tb.checks = { gaps = v.gaps, learnable = v.learnable }
  v.details = W.Button(bar, L["Details"], 64, 20, function()
    slots:ToggleDetails()
    v.details:SetSelected(slots.details)
  end)
  v.details:SetPoint("RIGHT", 0, 0)

  function tb:SetExtra(page, fn)
    UI.CRAFT_TOOLBAR[page].extra = fn
  end

  -- a page's buttons, made the first time it shows
  local function actionButtons(mode, decl)
    local list = tb.actions[mode]
    if not list then
      list = {}
      for i, a in ipairs(decl.actions or {}) do
        local b = W.Button(bar, a[1], a.width or 90, 20, a[2])
        if a.primary then
          W.Primary(b)
        end
        list[i] = b
      end
      tb.actions[mode] = list
    end
    return list
  end

  function tb:Layout()
    local compact = slots.compact
    local mode = UI.craftMode
    local decl = UI.CRAFT_TOOLBAR[mode] or {}
    local last
    local function place(w, gap)
      w:ClearAllPoints()
      if last then
        w:SetPoint("LEFT", last, "RIGHT", gap or 6, 0)
      elseif compact or w == v.search then
        w:SetPoint("LEFT", 0, 0)
      else
        -- nothing before it, wide: the page's controls line up with the content beside the sidebar
        w:SetPoint("LEFT", UI.SIDEBAR_W + UI.SLOT_GAP, 0)
      end
      last = w
    end
    v.page:SetShown(compact)
    if compact then
      place(v.page)
    end
    v.search:SetShown(decl.search and true or false)
    if decl.search then
      place(v.search)
      v.search:SetWidth(compact and 140 or UI.SIDEBAR_W) -- wide: lines up with the sidebar under it
      v.search:SetHint(type(decl.search) == "string" and decl.search or L["Search recipes or items..."])
    end
    v.char:SetShown(decl.scope and true or false)
    v.prof:SetShown(decl.scope and true or false)
    if decl.scope then
      place(v.char, compact and 6 or UI.SLOT_GAP)
      place(v.prof)
    end
    local shown = {}
    for i, key in ipairs(decl.checks or {}) do
      local c = self.checks[key]
      shown[c] = true
      place(c, i == 1 and 10 or 12)
      last = c.label -- the next one goes after this one's label
    end
    for _, c in pairs(self.checks) do
      c:SetShown(shown[c] or false)
    end
    if decl.extra then
      decl.extra(place, compact)
    end
    -- the page's buttons, right to left from Details (when it shows) or the toolbar's end
    for m, list in pairs(self.actions) do
      for _, b in ipairs(list) do
        b:SetShown(m == mode)
      end
    end
    local right = compact and v.details or nil
    local buttons = actionButtons(mode, decl)
    for i = #buttons, 1, -1 do
      local b = buttons[i]
      b:ClearAllPoints()
      if right then
        b:SetPoint("RIGHT", right, "LEFT", -6, 0)
      else
        b:SetPoint("RIGHT", 0, 0)
      end
      b:Show()
      right = b
    end
  end
  function v:LayoutToolbar()
    tb:Layout()
  end

  function tb:StatusText(mode, info)
    local decl = UI.CRAFT_TOOLBAR[mode]
    return decl and decl.status and decl.status(info or {}) or ""
  end
  return tb
end

function UI:CreateCraftingView(parent, contentArea)
  local v = contentArea(parent)
  self.craftView = v
  self.craftMode = "professions"
  local slots = UI.Slots(v, {
    toolbar = 22,
    header = 42,
    headerBelow = true,
    left = UI.SIDEBAR_W,
    right = UI.SIDE_PANEL_W,
    rightCards = true,
    status = true,
  })
  v.slots = slots

  -- the pages: Market-style lines under their group headings (narrow windows: a dropdown on the toolbar)
  local list = slots.left.content
  v.pageLinks = {}
  local y = -6
  for _, p in ipairs(PAGES) do
    if p.heading then
      local h = W.Text(list, "GameFontNormalSmall")
      h:SetPoint("TOPLEFT", 10, y - (y < -6 and 6 or 2))
      h:SetText(p.heading)
      y = y - (y < -6 and 26 or 22)
    else
      local b = CreateFrame("Button", nil, list)
      b:SetHeight(20)
      b:SetPoint("TOPLEFT", 4, y)
      b:SetPoint("RIGHT", list, "RIGHT", -4, 0)
      b.sel = b:CreateTexture(nil, "BACKGROUND")
      b.sel:SetAllPoints()
      W.Fill(b.sel, W.COLORS.rowSelected)
      b.hl = b:CreateTexture(nil, "HIGHLIGHT")
      b.hl:SetAllPoints()
      W.Fill(b.hl, W.COLORS.rowHover)
      b.text = W.Text(b, "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", 12, 0)
      b.text:SetPoint("RIGHT", -4, 0)
      b.text:SetWordWrap(false)
      b.text:SetText(p.label)
      b:SetScript("OnClick", function()
        UI:ShowCraftingPage(p.key)
      end)
      v.pageLinks[p.key] = b
      y = y - 22
    end
  end
  list:SetHeight(6 - y)
  v.toolbar = UI.CraftingToolbar(v)

  v.tables = {}
  for mode, columns in pairs(COLUMNS) do
    local t = ns.DataTable.New(slots.main, {
      columns = columns,
      action = mode == "crafters" and {
        label = L["Whisper"],
        width = 64,
        shown = function(d)
          return not d.mine
        end,
        onClick = function(d)
          ns.CraftersView.Whisper(d.crafter, d.recipe)
        end,
      } or nil,
      -- Top earners and Recipes to buy open on profit per craft (Market/day is the whole market's, not what you'd earn)
      sort = (mode == "earners" or mode == "recipes") and { key = "profit", ascending = false } or nil,
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
  W.Primary(v.action) -- every page's main action, Leveling's too
  -- its label changes with the tab ("Add all reagents to a shopping list"): kept inside the button, cut short with
  -- "..." when the sidebar is narrow
  v.action.label:ClearAllPoints()
  v.action.label:SetPoint("LEFT", 6, 0)
  v.action.label:SetPoint("RIGHT", -6, 0)
  v.action.label:SetWordWrap(false)
  v.chart = W.Button(actions, L["Chart"], 64, 26, function()
    local id = UI.CraftRowItem(UI.craftMode, UI.craftSelected)
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
    self:LayoutToolbar()
  end
  v:SetCompact(slots.compact)
  v:SetScript("OnShow", function()
    UI:RefreshCrafting()
  end)
  ns.Events.On("RecipesChanged", function()
    if v:IsShown() then
      UI:RefreshCrafting()
    end
  end)
  return v
end

-- switch the Crafting tab to a page (the sidebar, its dropdown, a card's button)
function UI:ShowCraftingPage(key)
  self.craftMode, self.craftSelected = key, nil
  self:RefreshCrafting()
end

function UI:RefreshCrafting()
  local v = self.craftView
  if not (v and v:IsShown()) then
    return
  end
  local mode = self.craftMode
  for key, b in pairs(v.pageLinks) do
    b.sel:SetShown(key == mode)
  end
  v.page:SetValue(mode)
  v.gaps:SetChecked(self.craftGaps or false)
  v.learnable:SetChecked(self.craftLearnable or false)
  local leveling = mode == "leveling"
  self:ShowLevelingControls(v, leveling)
  v:LayoutToolbar()
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
  -- the profession filter: every profession a character has recorded
  local profs, names = {}, {}
  for _, c in pairs(ns.Professions:Characters()) do
    for skillLine, p in pairs(c.professions or {}) do
      if not names[skillLine] then
        names[skillLine] = p.name or tostring(skillLine)
        profs[#profs + 1] = skillLine
      end
    end
  end
  table.sort(profs, function(a, b)
    return names[a] < names[b]
  end)
  local profOptions = { { false, L["All professions"] } }
  for _, skillLine in ipairs(profs) do
    profOptions[#profOptions + 1] = { skillLine, names[skillLine] }
  end
  v.prof:SetOptions(profOptions)
  if self.craftProf and not names[self.craftProf] then
    self.craftProf = nil
  end
  v.prof:SetValue(self.craftProf or false)

  local m = self:CraftingModel()
  -- Recipes to buy and Leveling need every recipe in the game: the data library
  local blocked = m ~= nil and NEEDS_DATA[mode] and not m.hasData
  local noChars = #keys == 0 and mode ~= "crafters" -- Find a crafter works from your network alone
  for key, t in pairs(v.tables) do
    t.frame:SetShown(m ~= nil and not blocked and key == mode)
  end
  v.message:SetShown(m == nil or blocked or noChars)
  if not m or blocked then
    v.message:SetText(
      blocked
          and L["This page needs the AME Crafting Data addon, which comes with AME: install or enable it (CurseForge installs it with AME), then /reload."]
        or L["Building market index..."]
    )
    v.slots.status:SetText("")
    self.craftRows = nil
    self:RenderCraftingDetail()
    return
  end
  if noChars then
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
  local empty
  if mode == "crafters" then
    empty = (self.craftSearch or "") == ""
        and L["Search for an item or an enchant to see who can make it: your characters, your guild and the players you trust."]
      or L["Nobody you know of can make that. Players share what they craft when they run AME too."]
  elseif mode == "queue" then
    empty = L["The craft queue is empty: queue crafts from a profession window (the panel beside it)."]
  elseif mode == "recipes" then
    empty = self.craftGaps
        and L["Every recipe on the auction house that your characters could learn is already known in your network."]
      or L["No recipe on the auction house that your characters could learn and don't know yet."]
  elseif mode == "refine" then
    empty = L["Nothing your characters hold is a reagent of a recipe they know."]
  elseif mode == "professions" then
    empty = L["No professions match."]
  else
    empty = L["No known recipes yet."]
  end
  t:SetMessage(((#keys > 0 or mode == "crafters") and #rows == 0) and empty or nil)
  local recorded = {}
  for _, key in ipairs(keys) do
    local crafts = {}
    for profession, p in pairs(m.chars[key].professions or {}) do
      if not GATHERING[profession] then
        crafts[#crafts + 1] = p.name
      end
    end
    table.sort(crafts)
    if #crafts > 0 then -- characters with only gathering, or only spellbook data, aren't listed
      recorded[#recorded + 1] = ("%s (%s)"):format(charName(key), table.concat(crafts, ", "))
    end
  end
  v.slots.status:SetText(v.toolbar:StatusText(mode, { recorded = recorded }))
  self:RenderCraftingDetail()
end

-- A frame about an item (frame.itemID, nil: none) acts like one: click searches the AH (or opens the chart),
-- Shift-click links it in chat, hover shows its tooltip.
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

-- crafts a day a cooldown allows, in words: "1 every 2 days", "1 a day", "3 a day"
function UI.CooldownText(perDay)
  if perDay < 1 then
    return L["1 every %d days"]:format(math.floor(1 / perDay + 0.5))
  end
  return L["%d a day"]:format(math.floor(perDay + 0.5))
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
  v.chart:SetShown(UI.CraftRowItem(self.craftMode, e) ~= nil)
  v.colorBar:SetShown(false)
  if self.craftMode == "leveling" and (not e or e.note) then
    v.title:SetText(W.Dim(L["Select a step"]))
    local noteText = e and e.text
    if type(noteText) == "function" then -- learn / train notes build their text when shown
      noteText = noteText()
    end
    v.subtitle:SetText(
      noteText or L["Click a step for its skill colors, the reagents to buy and where the results go."]
    )
    setLines(v, {})
    v.note:SetText("")
    v.action:SetText(L["Add all reagents to a shopping list"])
    v.action:SetShown(e ~= nil and self.leveling ~= nil) -- a step picked (learn / train steps too); none: no button
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
  elseif mode == "professions" then
    v.title:SetText(("%s %s"):format(e.profession, W.Dim(e.char)))
    v.subtitle:SetText(L["Skill %d of %d · %d recipes known"]:format(e.skill or 0, e.max or 0, e.known))
    if e.best then
      local product = e.best.recipe.product
      lines[#lines + 1] = { L["Best earner"], product and itemName(product) or W.Dim(L["Enchant"]), product }
      lines[#lines + 1] = { L["Profit per craft"], W.SignedMoney(e.best.eval.profit or 0) }
      lines[#lines + 1] = { L["Market a day"], W.Money(e.perDay, true) }
    end
    v.note:SetText(
      e.ready and L["Cooldown ready."] or e.wait and L["On cooldown for %s."]:format(SecondsToTime(e.wait)) or ""
    )
    v.action:SetText(L["Plan leveling"])
    v.action:SetShown(not GATHERING[e.skillLine])
  elseif mode == "crafters" then
    v.title:SetText(e.itemID and itemName(e.itemID) or e.name)
    v.subtitle:SetText(L["%d know it"]:format(e.count))
    lines[#lines + 1] = { L["Crafter"], e.mine and (e.crafter .. W.Dim("  " .. L["you"])) or e.crafter }
    lines[#lines + 1] = { L["Skill"], e.skill and tostring(e.skill) or W.Dim("-") }
    lines[#lines + 1] = { L["Online"], e.online and W.Color("good", L["yes"]) or W.Dim(L["no"]) }
    if e.seen and not e.mine then
      lines[#lines + 1] = { L["Shared"], L["%s ago"]:format(SecondsToTime(math.max(60, GetServerTime() - e.seen))) }
    end
    v.note:SetText(e.mine and "" or L["Whisper opens a chat to them with the recipe linked: you send it."])
    v.action:SetText(L["Whisper %s"]:format(e.crafter))
    v.action:SetShown(not e.mine)
  elseif mode == "queue" then
    local s = e.s
    v.title:SetText(("%s %s"):format(itemName(e.itemID), W.Dim("×" .. tostring(e.made or 1))))
    v.subtitle:SetText(
      (e.who and L["crafted by %s"]:format(e.who) or W.Color("warn", L["nobody recorded knowing it"]))
        .. (e.part and (W.SEP .. L["a part for a later step"]) or "")
    )
    local PB = ns.ProfessionBar
    local r = PB.Recipe(s.recipe)
    local mats = {}
    for _, mat in ipairs(self.craftPlan and self.craftPlan.materials or {}) do
      mats[mat.item] = mat
    end
    for _, rg in ipairs(r and r.reagents or {}) do
      local mat = mats[rg[1]]
      lines[#lines + 1] = {
        ("%d %s"):format(rg[2] * (s.count or 1), itemName(rg[1])),
        mat and PB.SourcesText(mat) or W.Dim(L["made by a step"]),
        rg[1],
      }
    end
    if e.profit then
      lines[#lines + 1] = { L["Profit"], W.SignedMoney(e.profit) }
    end
    v.note:SetText(L["The whole queue's missing materials go on the Craft queue shopping list."])
    v.action:SetText(L["Missing to shopping list"])
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
    if ev.canPerDay then
      lines[#lines + 1] = { L["Your cooldown"], UI.CooldownText(ev.canPerDay) }
    end
    lines[#lines + 1] = { L["Market a day"], ev.perDay and W.Money(ev.perDay, true) or W.Dim("-") }
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
        o.recipe.product,
      }
      if o.days then
        lines[#lines + 1] = { W.Dim(L["   the market takes it in"]), W.Dim(days(o.days)) }
      end
    end
    v.note:SetText(
      L["Materials you'd craft count at what they would sell for, not at their buy price: listing costs a cut, buying doesn't."]
    )
    v.action:SetText(L["Search the AH"])
  elseif mode == "recipes" then
    v.title:SetText(itemName(e.item))
    v.subtitle:SetText(
      L["Teaches %s"]:format(e.recipe.product and itemName(e.recipe.product) or L["an enchant"])
        .. W.SEP
        .. L["needs %d"]:format(e.rank or 0)
    )
    if e.recipe.product then -- what it makes, as an item (click: search / chart)
      lines[#lines + 1] = { L["Makes"], itemName(e.recipe.product), e.recipe.product }
    end
    lines[#lines + 1] = { L["On the AH now"], W.Money(e.price, true) }
    local s = self.craftModel and self.craftModel.index.items[e.item]
    if s and s.avg30 then
      lines[#lines + 1] = { L["Usually"], W.Money(s.avg30, true) }
    end
    local ev = e.eval
    lines[#lines + 1] = { L["Cost per craft"], ev.cost and W.Money(ev.cost, true) or W.Dim("-") }
    lines[#lines + 1] = { L["Profit per craft"], ev.profit and W.SignedMoney(ev.profit) or W.Dim("-") }
    lines[#lines + 1] = { L["Market a day"], ev.perDay and W.Money(ev.perDay, true) or W.Dim("-") }
    lines[#lines + 1] = { L["Pays back, at best"], days(e.payback) }
    if ev.canPerDay then
      lines[#lines + 1] = { L["Your cooldown"], UI.CooldownText(ev.canPerDay) }
    end
    for _, l in ipairs(e.learners) do
      lines[#lines + 1] = {
        charName(l.char),
        l.ready and W.Color("good", L["can learn it (%d)"]:format(l.skill))
          or W.Dim(L["needs %d, has %d"]:format(e.rank or 0, l.skill)),
      }
    end
    lines[#lines + 1] = {
      L["Network"],
      (e.network or 0) == 0 and W.Color("warn", L["nobody"]) or L["%d in network"]:format(e.network),
    }
    v.note:SetText(
      (e.network or 0) == 0
          and L["Nobody in your guild or trusted players knows it: learning it fills a gap. Players who don't run AME aren't counted."]
        or ""
    )
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
  if self.craftMode == "professions" then
    self.levelChoice = { key = e.key, profession = e.skillLine }
    self:ShowCraftingPage("leveling")
  elseif self.craftMode == "crafters" then
    if not e.mine then
      ns.CraftersView.Whisper(e.crafter, e.recipe)
    end
  elseif self.craftMode == "queue" then
    ns.ProfessionBar:QueueToShopping()
  elseif self.craftMode == "earners" then
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
