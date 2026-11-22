-- Crafting tab: your professions, who can make what, the craft queue, and what your recipes earn. Always there (the
-- crafting data library comes with AME; without it only Recipes to buy and Leveling say what they need). Layout
-- (UI.Slots), the same on every page: a side menu of the pages (UI.SideList, with counts; a dropdown when narrow), a
-- toolbar (search, character, profession - kept as you switch pages - and the page's own controls), the page's
-- heading and table, and a right column of cards and small tables for the picked row, its buttons at the foot. The
-- math is Core/Crafting.lua; recipes come from what AME recorded in
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
UI.CRAFT_HEADING_H = 22 -- a page's heading over its table
UI.CRAFT_DETAIL_GAP = 8 -- between the right column's cards and tables
-- pages whose table fades some rows: mode -> rowAlpha(row)
UI.CRAFT_ROW_ALPHA = {
  -- Top earners: what binds when made can't be sold, so it's faded
  earners = function(e)
    return e.eval and e.eval.why == "unsellable" and 0.5 or 1
  end,
}
UI.CRAFT_BEST_EARNERS = 3 -- Your professions: best earners in the card
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
  -- each character's profession's best earners, best first (the card lists the first few)
  local best = {}
  for _, e in ipairs(m.craft:TopEarners(m.entries, m.heldSet)) do
    for _, key in ipairs(e.crafters) do
      local k = key .. ":" .. tostring(e.profession)
      if e.eval.perDay then
        best[k] = best[k] or {}
        local list = best[k]
        if #list < UI.CRAFT_BEST_EARNERS then
          list[#list + 1] = e
        end
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
        local earners = best[key .. ":" .. tostring(skillLine)] or {}
        local b = earners[1]
        local row = {
          earners = earners,
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

-- how many steps the craft queue has, for the side menu (worked out only while something is queued)
function UI:QueueStepCount()
  local PB = ns.ProfessionBar
  local db = AME_DB and AME_DB.craftQueue
  if not (PB and PB.Plan and db and db.items and #db.items > 0) then
    return 0
  end
  return #PB.Plan().steps
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
  local recipe = ns.Recipes.Get
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
    -- what to craft from it, as an item link; nothing worth more: sell it as it is
    {
      key = "use",
      label = L["Best use"],
      width = 170,
      sortKey = false,
      item = function(r)
        return r.best and r.best.recipe.product or nil
      end,
      fallback = function(r)
        return r.best and "" or W.Color("hold", L["Sell it raw"])
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
-- buttons on the right (actions = { { label, onClick, width = 90, primary = true }, ... }).
-- The page itself: title and subtitle (its heading over the table; none: the table starts at the top), note (a dim
-- line under the table's rows), status(info) (the footer's text). info: recorded (the characters' recorded
-- professions, as text), chars (how many characters), professions (how many professions), leveling (UI.leveling).
local function recordedStatus(info)
  local recorded = info.recorded or {}
  return #recorded > 0
      and L["Recorded: %s"]:format(table.concat(recorded, "; ")) .. W.SEP .. L["prices: your faction's auction house"]
    or ""
end
UI.CRAFT_TOOLBAR = {
  professions = {
    search = true,
    scope = true,
    title = L["Your professions"],
    subtitle = L["every character on this market, as their profession windows last showed them"],
    note = L["Click a row for its best earners on the right. A profession counts once its window has been opened on that character."],
    status = function(info)
      return L["Characters: %d · professions recorded: %d · open a profession once on a character to add it"]:format(
        info.chars or 0,
        info.professions or 0
      )
    end,
  },
  crafters = {
    search = L["Who can make... (an item or enchant)"],
    title = L["Find a crafter"],
    subtitle = L["type an item or enchant above; pick who makes it"],
    note = L["Your guild, trusted players and your own characters, as their profession windows recorded them."],
    status = function()
      return L["Recipes from your guild, trusted players and your characters: they arrive with the guild's sync"]
    end,
  },
  queue = {
    search = true,
    scope = true,
    title = L["Craft queue"],
    subtitle = L["what you queued, parts first"],
    note = L["Parts first. Craft next works in the profession window; here you see the plan and send what has to be bought to a shopping list."],
    status = function()
      return L["The queue is kept per account: an alt sees its steps when you log in there"]
    end,
  },
  earners = {
    search = true,
    scope = true,
    title = L["Top earners"],
    subtitle = L["what your recipes make a day, at what the market takes"],
    note = L["Market/day = profit per craft × the whole market's sales a day: the size of the opportunity, not your income. Reagents you hold count at what selling them would net."],
  },
  refine = {
    search = true,
    scope = true,
    title = L["Sell or refine"],
    subtitle = L["materials your characters hold, and the best thing to do with each"],
    note = L["Takes: how long the market needs to absorb what you'd list, at today's sales a day."],
    status = function()
      return L["Holdings: bags and bank as each character last saw them"]
        .. W.SEP
        .. L["prices: your faction's auction house"]
    end,
  },
  recipes = {
    search = true,
    scope = true,
    checks = { "gaps", "learnable" },
    title = L["Recipes to buy"],
    subtitle = L["on the auction house, and not known by your characters yet; Network: who else already makes it"],
    note = L["Network: your guild, trusted players and your characters, as their profession windows recorded them. Profit: per craft, after the cut; how soon it pays back is in the card."],
    status = function(info)
      return L["Recipes seen on the auction house in the last %d days"]:format(UI.RECIPE_LISTING_DAYS)
        .. W.SEP
        .. L["Characters: %d · professions recorded: %d"]:format(info.chars or 0, info.professions or 0)
    end,
  },
  leveling = {
    note = L["Recalculated from today's prices. Results sell as far as the market takes them in about %d days; the rest go to a vendor, are disenchanted or kept for a later step."]:format(
      ns.Leveling.HORIZON
    ),
    status = function(info)
      local c = info.leveling and info.leveling.choice
      if not c then
        return ""
      end
      return L["%s · %s %d / %d"]:format(charName(c.key), c.p.name or "?", c.p.skill or 0, c.p.max or 0)
    end,
  },
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
  self.craftCounts = {}
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

  -- the pages: a side menu under its group headings, with counts (narrow windows: a dropdown on the toolbar).
  -- v.pageLinks[key] is the line showing that page.
  v.pageLinks = {}
  v.nav = UI.SideList(slots.left, {
    rows = #PAGES,
    onClick = function(e)
      if e.key then
        UI:ShowCraftingPage(e.key)
      end
    end,
  })
  v.toolbar = UI.CraftingToolbar(v)

  -- each page's heading over its table (Leveling has its cards there instead)
  v.heading = W.PageHeading(slots.main)
  v.heading:SetPoint("TOPLEFT", 0, 0)
  v.heading:SetPoint("RIGHT", 0, 0)
  v.tables = {}
  for mode, columns in pairs(COLUMNS) do
    local decl = UI.CRAFT_TOOLBAR[mode] or {}
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
      top = decl.title and -UI.CRAFT_HEADING_H or 0,
      note = decl.note,
      itemID = function(e)
        return e.itemID
      end,
      selected = function(e)
        return UI.craftSelected == e
      end,
      rowAlpha = UI.CRAFT_ROW_ALPHA[mode],
      onClick = function(e)
        UI.craftSelected = e
        UI:RenderCraftingDetail()
        v.tables[UI.craftMode]:Render()
      end,
    })
    t.frame:Hide()
    v.tables[mode] = t
  end

  -- the picked row, in the right column: cards and small tables, in the order the page gives them
  -- (UI:LayoutCraftingDetail), then a dim note; the buttons stay at the column's foot
  local side = slots.right
  local actions = CreateFrame("Frame", nil, side)
  actions:SetHeight(26)
  actions:SetPoint("BOTTOMLEFT", 0, 0)
  actions:SetPoint("BOTTOMRIGHT", 0, 0)
  side.pane:ClearAllPoints()
  side.pane:SetPoint("TOPLEFT", 0, 0)
  side.pane:SetPoint("BOTTOMRIGHT", 0, 26 + UI.SLOT_GAP)
  local content = side.content
  v.detail = { stack = UI.Stack(content, 0), cards = {}, heads = {}, tables = {}, content = content }
  v.note = W.Text(content, "GameFontDisableSmall")
  v.note:SetWordWrap(true)
  v.note:SetJustifyV("TOP")
  -- Leveling: the step's skill colours, a bar under the title card
  v.colorRow = CreateFrame("Frame", nil, content)
  v.colorRow:SetHeight(14)
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

-- the side menu's lines: the pages under their headings, the open one selected, with counts where a page has a
-- list worth counting (professions recorded, queue steps, recipes to buy as last worked out)
function UI:RenderCraftingNav(v)
  local counts = self.craftCounts or {}
  local entries = {}
  for _, p in ipairs(PAGES) do
    if p.heading then
      entries[#entries + 1] = { heading = p.heading }
    else
      local n = counts[p.key]
      entries[#entries + 1] = {
        key = p.key,
        label = p.label,
        count = n and n > 0 and n or nil,
        selected = p.key == self.craftMode,
      }
    end
  end
  v.nav:SetEntries(entries)
  v.pageLinks = {}
  for _, line in ipairs(v.nav.lines) do
    if line.entry and line.entry.key then
      v.pageLinks[line.entry.key] = line
    end
  end
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
  local decl = UI.CRAFT_TOOLBAR[mode] or {}
  v.heading:Set(decl.title, decl.subtitle)
  v.heading:SetShown(decl.title ~= nil)
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
  local profs, names, recordedN = {}, {}, 0
  for _, c in pairs(ns.Professions:Characters()) do
    for skillLine, p in pairs(c.professions or {}) do
      recordedN = recordedN + 1
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
  self.craftCounts.professions = recordedN
  self.craftCounts.queue = self:QueueStepCount()
  self:RenderCraftingNav(v)

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
  if mode == "recipes" then -- the side menu counts them from the last time they were worked out
    self.craftCounts.recipes = #rows
    self:RenderCraftingNav(v)
  end
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
  v.slots.status:SetText(v.toolbar:StatusText(mode, {
    recorded = recorded,
    chars = #keys,
    professions = recordedN,
    leveling = leveling and self.leveling or nil,
  }))
  self:RenderCraftingDetail()
end

-- the item a row is about, for the right column's title
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

-- an item's name as a link inside a card's text (quality colour, its tooltip, Shift-click); redrawn once the client
-- has a name it didn't
local function link(id, count)
  return W.LinkText(id, count, UI.RedrawCrafting)
end
UI.CraftLink = link

---------------------------------------------------------------------------------------------------------------------
-- the right column

-- The right column's small tables, by name: made the first time a page shows one. Each fills a holder frame that is
-- as tall as its rows (up to rows; more scroll).
UI.CRAFT_DETAIL_TABLES = {}

function UI:CraftDetailTable(name)
  local d = self.craftView.detail
  local t = d.tables[name]
  if t then
    return t
  end
  local def = UI.CRAFT_DETAIL_TABLES[name]
  local holder = CreateFrame("Frame", nil, d.content)
  holder:SetHeight(1)
  local opts = { fill = true, rows = def.rows or 6, rowHeight = def.rowHeight or 20, top = 0 }
  for k, val in pairs(def) do
    opts[k] = opts[k] == nil and val or opts[k]
  end
  t = ns.DataTable.New(holder, opts)
  t.holder, t.maxRows = holder, def.rows or 6
  d.tables[name] = t
  return t
end

-- Lays the right column out from the page's blocks, top to bottom, then its note:
--   { card = content }             a card (card:SetContent: title or item, subtitle, rows, note)
--   { heading = text }             a small gold heading over a table
--   { table = name, rows = list }  one of the column's small tables (UI.CRAFT_DETAIL_TABLES[name])
--   { colors = true }              Leveling's skill-colour bar (v.colorRow)
-- v.detail.cards[i] are the cards in order (cards[1] is the title card on every page).
function UI:LayoutCraftingDetail(blocks, note)
  local v = self.craftView
  local d = v.detail
  local content = d.content
  local width = content:GetWidth()
  if type(width) ~= "number" or width < 20 then
    width = UI.SIDE_PANEL_W - 8
  end
  local y, nc, nh, used = 0, 0, 0, {}
  local function place(obj, h)
    obj:ClearAllPoints()
    obj:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
    obj:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    obj:Show()
    y = y + h + UI.CRAFT_DETAIL_GAP
  end
  for _, b in ipairs(blocks) do
    if b.card then
      nc = nc + 1
      local card = d.cards[nc]
      if not card then
        card = d.stack:Card()
        W.EnableLinks(card) -- item links in its subtitle and note ("Teaches X")
        d.cards[nc] = card
      end
      card:SetContent(b.card)
      card:Fit(width)
      place(card, card:GetHeight() or 0)
    elseif b.heading then
      nh = nh + 1
      local h = d.heads[nh] or W.Text(content, "GameFontNormal")
      d.heads[nh] = h
      h:SetText(b.heading)
      place(h, 14)
    elseif b.table then
      local t = self:CraftDetailTable(b.table)
      used[t] = true
      local rows = b.rows or {}
      local h = t.headH + math.max(1, math.min(#rows, t.maxRows)) * t.rowH + t:NoteSpace()
      t.holder:SetHeight(h)
      t:SetData(rows)
      t:Render()
      place(t.holder, h)
    elseif b.colors then
      used.colors = true
      place(v.colorRow, 14)
    end
  end
  for i = nc + 1, #d.cards do
    d.cards[i]:Hide()
  end
  for i = nh + 1, #d.heads do
    d.heads[i]:Hide()
  end
  for _, t in pairs(d.tables) do
    if not used[t] then
      t.holder:Hide()
    end
  end
  v.colorRow:SetShown(used.colors or false)
  v.note:SetText(note or "")
  if (note or "") ~= "" then
    v.note:SetWidth(width) -- wrapped text measures at its real width now
    place(v.note, v.note:GetStringHeight() or 12)
  else
    v.note:Hide()
  end
end

-- the right column, then its scroll pane re-measured (its pieces change height with their text)
function UI:RenderCraftingDetail()
  local v = self.craftView
  if not v then
    return
  end
  local blocks, note = self:CraftingDetailBlocks()
  self:LayoutCraftingDetail(blocks, note)
  v.slots.right.pane:Measure()
end

-- A page's breakdown as one title card and one card of rows: d = { item | title, subtitle, rows, colors }.
local function blocksOf(d)
  local blocks = { { card = { item = d.item, title = d.title, subtitle = d.subtitle } } }
  if d.colors then
    blocks[#blocks + 1] = { colors = true }
  end
  if d.rows and #d.rows > 0 then
    blocks[#blocks + 1] = { card = { rows = d.rows } }
  end
  for _, b in ipairs(d.after or {}) do
    blocks[#blocks + 1] = b
  end
  return blocks
end
UI.CraftBlocksOf = blocksOf

-- the picked row's blocks and note, and the buttons for it
function UI:CraftingDetailBlocks()
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
  v.colorBar:SetShown(false) -- Leveling's step shows it again
  if self.craftMode == "leveling" and (not e or e.note) then
    local noteText = e and e.text
    if type(noteText) == "function" then -- learn / train notes build their text when shown
      noteText = noteText()
    end
    v.action:SetText(L["Add all reagents to a shopping list"])
    v.action:SetShown(e ~= nil and self.leveling ~= nil) -- a step picked (learn / train steps too); none: no button
    return blocksOf({
      title = W.Dim(L["Select a step"]),
      subtitle = noteText or L["Click a step for its skill colors, the reagents to buy and where the results go."],
    }),
      ""
  end
  if not e then
    return blocksOf({
      title = W.Dim(L["Select a row"]),
      subtitle = L["Click a row for its breakdown: where each reagent comes from, what selling nets, and how much the market takes."],
    }),
      ""
  end
  local page = UI.CRAFT_DETAIL[self.craftMode]
  local d, note = page(self, v, e)
  return d.blocks or blocksOf(d), note
end

local SOURCE = {
  buy = L["buy"],
  vendor = L["vendor"],
  held = L["you hold it"],
  craft = L["craft it"],
}

-- Each page's breakdown of its picked row: page(UI, v, row) -> d (blocksOf's table, or d.blocks), note. It also
-- sets the main button's label (and whether it shows).
UI.CRAFT_DETAIL = {}

UI.CRAFT_DETAIL.leveling = function(self, v, e)
  local d = self:LevelingDetail(v, e)
  v.action:SetText(L["Add all reagents to a shopping list"])
  return d,
    e.entry.estimated
        and not e.entry.known
        and L["Trained at a trainer; the game data has no training level for it, so the level here is estimated."]
      or ""
end

-- a coloured dot before a crafter's name: online in green, offline dim (a small square: the game's fonts have no
-- round bullet)
function UI.CrafterDot(online)
  return W.Swatch(W.RGB(online and "good" or "dim"))
end

local function itemID(d)
  return d.itemID
end

-- the right column's small tables
UI.CRAFT_DETAIL_TABLES.reagents = { -- Top earners: a craft's reagents and where each comes from
  rows = 6,
  itemID = itemID,
  itemMenu = {},
  columns = {
    {
      key = "name",
      label = L["Reagent"],
      width = 120,
      item = true,
      sortKey = false,
      suffix = function(d)
        return "  " .. W.Dim(d.countText)
      end,
    },
    { key = "cost", label = L["Cost"], width = 60, format = "money", sortKey = false },
  },
}
UI.CRAFT_DETAIL_TABLES.earners = { -- Your professions: its best earners
  rows = UI.CRAFT_BEST_EARNERS,
  itemID = itemID,
  itemMenu = {},
  columns = {
    { key = "name", label = L["Makes"], width = 120, item = true, sortKey = false },
    { key = "perDay", label = L["Market/day"], width = 70, format = "money", term = "marketDay", sortKey = false },
  },
}
UI.CRAFT_DETAIL_TABLES.crafters = { -- Find a crafter: everyone who can make the picked recipe
  rows = 8,
  onClick = function() end, -- the rows are people, not items: nothing to open
  columns = {
    {
      key = "crafter",
      label = L["Crafter"],
      width = 110,
      align = "LEFT",
      sortKey = false,
      text = function(r)
        local name = r.online and r.crafter or W.Dim(r.crafter)
        return UI.CrafterDot(r.online) .. " " .. name .. (r.mine and W.Dim("  " .. L["you"]) or "")
      end,
    },
    {
      key = "skill",
      label = L["Skill"],
      width = 36,
      sortKey = false,
      text = function(r)
        return r.skill and tostring(r.skill) or W.Dim("-")
      end,
    },
    {
      key = "whisper",
      label = "",
      width = 60,
      button = {
        label = L["Whisper"],
        shown = function(r)
          return not r.mine
        end,
        onClick = function(r)
          ns.CraftersView.Whisper(r.crafter, r.recipe)
        end,
      },
    },
  },
}
UI.CRAFT_DETAIL_TABLES.materials = { -- the craft queue: every material, how many, and where it comes from
  rows = 8,
  itemID = itemID,
  itemMenu = {},
  columns = {
    { key = "name", label = L["Item"], width = 90, item = true, sortKey = false },
    { key = "needText", label = L["Need"], width = 34, sortKey = false },
    { key = "source", label = L["Source"], width = 90, format = "tag", sortKey = false },
  },
}

UI.CRAFT_DETAIL.professions = function(_, v, e)
  local rows = {
    { label = L["Skill"], text = ("%d / %d"):format(e.skill or 0, e.max or 0) },
    { label = L["Recipes"], text = W.Thousands(e.known) },
  }
  if e.ready then
    rows[#rows + 1] = { label = L["Cooldown"], text = L["ready"], color = "good" }
  elseif e.wait then
    rows[#rows + 1] = { label = L["Cooldown"], text = SecondsToTime(e.wait) }
  end
  local blocks = {
    { card = { title = ("%s · %s"):format(e.char, e.profession), titleColor = "gold", rows = rows } },
  }
  if #e.earners > 0 then
    local list = {}
    for i, b in ipairs(e.earners) do
      list[i] = { itemID = b.recipe.product, perDay = b.eval.perDay }
    end
    blocks[#blocks + 1] = { heading = L["Best earners"] }
    blocks[#blocks + 1] = { table = "earners", rows = list }
  end
  v.action:SetText(L["Plan leveling"])
  v.action:SetShown(not GATHERING[e.skillLine])
  return { blocks = blocks }, ""
end

UI.CRAFT_DETAIL.crafters = function(self, v, e)
  -- everyone the table lists for this recipe, in its order (online first)
  local who = {}
  for _, r in ipairs(self.craftRows or {}) do
    if r.recipe == e.recipe then
      who[#who + 1] = r
    end
  end
  v.action:SetText(L["Whisper %s"]:format(e.crafter))
  v.action:SetShown(not e.mine)
  local subtitle = L["%d can make it"]:format(e.count)
  if e.seen and not e.mine then
    subtitle = subtitle
      .. W.SEP
      .. L["%s shared %s ago"]:format(e.crafter, SecondsToTime(math.max(60, GetServerTime() - e.seen)))
  end
  return {
    blocks = {
      { card = { item = e.itemID, title = not e.itemID and e.name or nil, subtitle = subtitle } },
      { table = "crafters", rows = who },
    },
  },
    L["Whisper opens a chat to them with the recipe linked: you send it."]
end

-- a material's sources as one tag: every place but your bags, in the AH's amber when some has to be bought
local function sourceTag(mat)
  local tags = ns.ProfessionBar.SourceTags(mat)
  if #tags == 0 then
    return nil
  end
  local texts, kind = {}, tags[1].kind
  for _, t in ipairs(tags) do
    texts[#texts + 1] = t.text
    if t.kind == "ah" or (t.kind == "made" and kind ~= "ah") then
      kind = t.kind
    end
  end
  return { text = table.concat(texts, ", "), kind = kind }
end

UI.CRAFT_DETAIL.queue = function(self, v, e)
  local plan = self.craftPlan or {}
  local mats = {}
  for _, mat in ipairs(plan.materials or {}) do
    local buy = false
    for _, src in ipairs(mat.sources) do
      buy = buy or src.kind == "ah"
    end
    mats[#mats + 1] = {
      itemID = mat.item,
      -- green when what you have covers it
      needText = buy and tostring(mat.need) or W.Color("good", tostring(mat.need)),
      source = sourceTag(mat),
    }
  end
  v.action:SetText(L["Missing to shopping list"])
  return {
    blocks = {
      {
        card = {
          item = e.itemID,
          count = "×" .. tostring(e.made or 1),
          subtitle = (e.who and L["crafted by %s"]:format(e.who) or W.Color("warn", L["nobody recorded knowing it"]))
            .. (e.part and (W.SEP .. L["a part for a later step"]) or ""),
          rows = e.profit and { { label = L["Profit"], copper = e.profit, signed = true } } or nil,
        },
      },
      {
        card = {
          title = L["Materials"],
          titleColor = "gold",
          rows = {
            { label = L["To buy"], copper = plan.toBuy or 0 },
            { label = L["Profit"], copper = plan.profit or 0, signed = true, total = true },
          },
        },
      },
      { table = "materials", rows = mats },
    },
  },
    L["Nothing for what's in your bags; the count is green when you have it all."]
end

UI.CRAFT_DETAIL.earners = function(_, v, e)
  local ev = e.eval
  local names = {}
  for _, k in ipairs(e.crafters) do
    names[#names + 1] = charName(k)
  end
  local reagents = {}
  for _, r in ipairs(ev.reagents) do
    reagents[#reagents + 1] = {
      itemID = r.item,
      countText = SOURCE[r.source] and ("%d · %s"):format(r.n, SOURCE[r.source]) or tostring(r.n),
      cost = r.each * r.n,
    }
  end
  local function money(copper, signed, extra)
    local row = extra or {}
    row.copper, row.signed = copper, signed
    if copper == nil then
      row.text = W.Dim("-")
    end
    return row
  end
  local rows = {
    money(ev.cost, false, { label = L["Reagents cost"] }),
    money(ev.revenue, false, { label = L["Sells for, after cut"] }),
    money(ev.profit, true, { label = L["Profit per craft"], total = true }),
    { label = L["Sells a day"], text = ev.sellRate and W.Rate(ev.sellRate) or W.Dim("-") },
  }
  if ev.canPerDay then
    rows[#rows + 1] = { label = L["Your cooldown"], text = UI.CooldownText(ev.canPerDay) }
  end
  rows[#rows + 1] = money(ev.perDay, false, { label = L["Market a day"] })
  local why = ev.why == "unsellable" and L["Can't be sold: it binds when made."]
    or ev.why == "unpriced" and L["Missing a price: scan the auction house (or it's never listed)."]
    or ev.why == "enchant" and L["Enchants make no item to sell; valued later."]
    or ""
  if e.cooldown then
    local left = e.cooldown - GetServerTime()
    why = (left > 0 and L["On cooldown for %s."]:format(SecondsToTime(left)) or L["Cooldown ready."]) .. " " .. why
  end
  v.action:SetText(L["Add reagents to a shopping list"])
  return {
    blocks = {
      {
        card = {
          item = e.recipe.product,
          title = not e.recipe.product and W.Dim(L["Enchant"]) or nil,
          subtitle = L["%s · makes %s"]:format(table.concat(names, ", "), tostring(e.recipe.made)),
        },
      },
      { heading = L["Reagents"] },
      { table = "reagents", rows = reagents },
      {
        card = {
          title = L["Selling it"],
          titleColor = "gold",
          rows = rows,
          note = L["The whole market's daily profit at this price: you'd sell a share of it, after the other sellers."],
        },
      },
    },
  },
    why
end

UI.CRAFT_DETAIL.refine = function(_, v, e)
  local blocks = {
    { card = { item = e.itemID, count = W.Count(e.qty) } },
    {
      card = {
        title = L["Sell it raw"],
        rows = { { label = L["After the cut and deposit"], copper = e.raw } },
      },
    },
  }
  -- each way to craft it, best first: what it nets and how much more than selling it raw
  for i, o in ipairs(e.options) do
    if i > UI.CRAFT_REFINE_OPTIONS then
      break
    end
    local better = o.gain > 0
    blocks[#blocks + 1] = {
      card = {
        title = L["Craft %s ×%d"]:format(link(o.recipe.product), o.crafts),
        titleColor = (i == 1 and better) and "good" or nil,
        subtitle = (i == 1 and better) and L["Best use"] or nil,
        rows = {
          { label = L["That nets"], copper = o.net },
          better and { label = L["More than selling it raw"], copper = o.gain, signed = true, total = true }
            or { label = L["Less than selling it raw"], copper = o.gain, signed = true, total = true },
        },
        note = o.days and L["The market takes it in %s."]:format(days(o.days)) or nil,
      },
    }
  end
  v.action:SetText(L["Search the AH"])
  return { blocks = blocks },
    L["Materials you'd craft count at what they would sell for, not at their buy price: listing costs a cut, buying doesn't."]
end
UI.CRAFT_REFINE_OPTIONS = 3 -- Sell or refine: ways to craft a material, one card each

UI.CRAFT_DETAIL.recipes = function(self, v, e)
  local rows = {}
  local function money(label, copper, signed)
    rows[#rows + 1] = { label = label, copper = copper, signed = signed, text = copper == nil and W.Dim("-") or nil }
  end
  money(L["On the AH now"], e.price)
  local s = self.craftModel and self.craftModel.index.items[e.item]
  if s and s.avg30 then
    money(L["Usually"], s.avg30)
  end
  local ev = e.eval
  money(L["Cost per craft"], ev.cost)
  money(L["Profit per craft"], ev.profit, true)
  money(L["Market a day"], ev.perDay)
  if ev.canPerDay then
    rows[#rows + 1] = { label = L["Your cooldown"], text = UI.CooldownText(ev.canPerDay) }
  end
  rows[#rows + 1] = { label = L["Pays back, at best"], text = days(e.payback), total = true }
  for _, l in ipairs(e.learners) do
    rows[#rows + 1] = {
      label = charName(l.char),
      text = l.ready and W.Color("good", L["can learn it (%d)"]:format(l.skill))
        or W.Dim(L["needs %d, has %d"]:format(e.rank or 0, l.skill)),
    }
  end
  rows[#rows + 1] = {
    label = L["Network"],
    text = (e.network or 0) == 0 and W.Color("warn", L["nobody"]) or L["%d in network"]:format(e.network),
  }
  v.action:SetText(L["Search the AH"])
  return {
    blocks = {
      {
        card = {
          item = e.item,
          subtitle = L["Teaches %s"]:format(e.recipe.product and link(e.recipe.product) or L["an enchant"])
            .. W.SEP
            .. L["needs %d"]:format(e.rank or 0),
          rows = rows,
          note = (e.network or 0) == 0
              and L["Nobody in your guild or trusted players knows it: learning it fills a gap. Players who don't run AME aren't counted."]
            or nil,
        },
      },
    },
  },
    ""
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
