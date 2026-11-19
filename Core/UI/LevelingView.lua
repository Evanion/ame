-- Crafting tab, Leveling mode (M16 phase 6): the cheapest path to raise a profession at today's prices
-- (Core/Leveling.lua). Toolbar: which character's profession, the target skill, the goal. Header: what the path
-- costs, gets back and nets (and the net under the other goals). Table: the steps, with learn / train rows between
-- them. Sidebar: the selected step - skill colors, chance, reagents, where the results go.
local _, ns = ...
local L = ns.L

local W = ns.Widgets
local UI = ns.UI

local GATHERING = { [182] = true, [356] = true, [393] = true }
local GOALS = {
  { "cheapest", L["Cheapest"] },
  { "recovery", L["Best recovery"] },
  { "fewest", L["Fewest crafts"] },
  { "materials", L["My materials"] },
}
local TARGETS = { 75, 150, 225, 300 }
UI.LEVEL_TRAINER_GUESS = 20 -- trainer recipes without a known level: assume they're trained this far before yellow
UI.LEVEL_RECIPE_DAYS = 2 -- recipe items seen on the AH within this many days can be bought for the path

local function charName(key)
  return (key or ""):gsub("^[^:]*:", "")
end

local function itemName(id)
  local name, _, quality = W.ItemInfo(id)
  return W.QualityText(quality, name or ns.ItemCache.Name(id) or ("item:" .. tostring(id)))
end

local function cost(v)
  return v and v > 0 and W.Color("bad", "-" .. W.Plain(W.Money(v, true))) or W.Dim("-")
end
local function gain(v)
  return v and v > 0 and W.Color("good", "+" .. W.Plain(W.Money(v, true))) or W.Dim("-")
end
local function signed(v)
  if not v or math.abs(v) < 1 then
    return W.Dim("0")
  end
  return v > 0 and gain(v) or cost(-v)
end
UI.CostText, UI.GainText, UI.SignedText = cost, gain, signed

-- the professions the dropdown offers: every recorded (character, crafting profession)
function UI:LevelingChoices()
  local out = {}
  for key, c in pairs(ns.Professions:Characters()) do
    for profession, p in pairs(c.professions or {}) do
      if not GATHERING[profession] then
        out[#out + 1] = { key = key, profession = profession, p = p }
      end
    end
  end
  table.sort(out, function(a, b)
    if a.key ~= b.key then
      return a.key < b.key
    end
    return (a.p.name or "") < (b.p.name or "")
  end)
  return out
end

-- the candidate recipes for a character's profession: known ones, trainer ones (level estimated), and ones whose
-- recipe item is on the auction house (its price added)
local function candidates(m, choice)
  local index = m.index
  local teachers = {} -- spell -> recipe items that teach it
  for item, row in pairs(ns.CraftingData.data.items or {}) do
    for i = 3, #row do
      teachers[row[i]] = teachers[row[i]] or {}
      table.insert(teachers[row[i]], { item = item, rank = row[2] })
    end
  end
  local learned = choice.p.learned or {}
  local recorded = ns.Professions:Catalog(choice.profession) or {}
  local out = {}
  for _, id in ipairs(ns.CraftingData:ProfessionRecipes(choice.profession)) do
    local d = ns.CraftingData:Recipe(id)
    local rec = recorded[id]
    local recipe = {
      id = id,
      product = rec and rec.out or d.product,
      made = rec and ((rec.min or 1) + (rec.max or rec.min or 1)) / 2 or d.made,
      reagents = rec and rec.r or d.reagents,
    }
    local c = { recipe = recipe, yellow = d.yellow, grey = d.grey, known = learned[id] or false }
    if d.grey > choice.p.skill and #recipe.reagents > 0 then
      if c.known then
        out[#out + 1] = c
      elseif teachers[id] then
        -- a recipe item: the cheapest one listed lately
        local best
        for _, t in ipairs(teachers[id]) do
          local s = index.items[t.item]
          local fresh = s and (not index.day or not s.day or index.day - s.day <= UI.LEVEL_RECIPE_DAYS)
          if fresh and s.min and (s.qty or 0) > 0 and (not best or s.min < best.price) then
            best = { item = t.item, price = s.min, rank = t.rank }
          end
        end
        if best then
          c.itemPrice, c.learnAt, c.recipeItem = best.price, best.rank, best.item
          out[#out + 1] = c
        end
      else
        -- taught by a trainer (no recipe item); the game data has no training level for most
        c.learnAt = d.yellow <= 50 and 1 or math.max(1, d.yellow - UI.LEVEL_TRAINER_GUESS)
        c.estimated = true
        out[#out + 1] = c
      end
    end
  end
  return out
end

-- plans for the selected profession under every goal (the header compares them)
function UI:LevelingPlans(m)
  local choices = self:LevelingChoices()
  local choice
  for _, c in ipairs(choices) do
    if self.levelChoice and c.key == self.levelChoice.key and c.profession == self.levelChoice.profession then
      choice = c
    end
  end
  choice = choice or choices[1]
  if not choice then
    return nil
  end
  self.levelChoice = { key = choice.key, profession = choice.profession }
  local target = self.levelTarget or TARGETS[#TARGETS]
  local enchanter = false
  for _, c in pairs(m.chars) do
    enchanter = enchanter or (c.professions and c.professions[333]) ~= nil
  end
  local craft = m.craft
  local deValue = enchanter
      and function(id)
        local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        if not getInfo then
          return nil
        end
        local _, _, quality, level, _, _, _, _, _, _, _, classID = getInfo(id)
        return ns.Disenchant.Value(level, quality, classID, function(mat)
          return craft:NetSale(mat)
        end)
      end
    or nil
  local shard = ns.AME:FactionShard()
  local buyCost = function(id, units)
    local book = shard and ns.AME:BookFor(shard, id, 2 * 86400)
    if not book then
      return nil
    end
    local total, _, _, got = ns.Depth.Cost(book, units)
    local p = craft:Price(id)
    if got < units then
      if not p then
        return nil
      end
      total = total + (units - got) * p
    end
    return total
  end
  -- what this character holds, for "my materials"
  local held = {}
  local h = ns.Trading:Holdings()[choice.key] or {}
  for _, place in ipairs({ "bags", "bank" }) do
    for id, n in pairs(h[place] or {}) do
      held[id] = (held[id] or 0) + n
    end
  end
  local list = candidates(m, choice)
  local plans = {}
  for _, g in ipairs(GOALS) do
    plans[g[1]] = ns.Leveling.Plan({
      craft = craft,
      recipes = list,
      from = choice.p.skill or 1,
      to = target,
      cap = choice.p.max,
      goal = g[1],
      held = held,
      deValue = deValue,
      buyCost = buyCost,
    })
  end
  return { choice = choice, target = target, plans = plans, enchanter = enchanter }
end

-- table rows: steps, with a learn row before a step that buys or trains its recipe
function UI:LevelingRows(m)
  local L2 = self:LevelingPlans(m)
  self.leveling = L2
  if not L2 then
    return {}
  end
  local plan = L2.plans[self.levelGoal or "recovery"]
  local rows = {}
  for _, st in ipairs(plan.steps) do
    if st.train then
      rows[#rows + 1] = { note = true, skill = st.from, text = L["Train %s at your trainer"]:format(st.train) }
    else
      local c = st.entry
      if st.learn then
        rows[#rows + 1] = {
          note = true,
          skill = st.from,
          itemID = c.recipeItem,
          text = L["Learn %s: recipe on the AH, %s (needs %d)"]:format(
            itemName(c.recipe.product or 0),
            W.Plain(W.Money(st.learn, true)),
            c.learnAt or 0
          ),
        }
      elseif c.estimated and not c.known then
        rows[#rows + 1] = {
          note = true,
          skill = st.from,
          text = L["Train %s at a trainer (about %d, estimated)"]:format(itemName(c.recipe.product or 0), c.learnAt),
        }
      end
      st.itemID = c.recipe.product
      rows[#rows + 1] = st
    end
  end
  if plan.stuck then
    rows[#rows + 1] = {
      note = true,
      skill = plan.stuck,
      text = W.Color(
        "warn",
        L["No usable recipe from %d with today's data: learn more recipes or scan the AH."]:format(plan.stuck)
      ),
    }
  end
  return rows
end

local function resultsText(st)
  if st.note then
    return ""
  end
  local r, parts = st.results, {}
  local function add(n, label, role)
    if n and n > 0 then
      parts[#parts + 1] = W.Color(role, label:format(n))
    end
  end
  add(r.sell, L["sell %d"], "good")
  add(r.vendor, L["vendor %d"], "vendor")
  add(r.de, L["disenchant %d"], "brand")
  add(r.keep, L["keep %d"], "wait")
  return table.concat(parts, "  ")
end

UI.LEVELING_COLUMNS = {
  {
    key = "skill",
    label = L["Skill"],
    width = 64,
    sortKey = false,
    align = "LEFT",
    text = function(st)
      if st.note then
        return W.Color("brand", tostring(st.skill))
      end
      return ("%d-%d"):format(st.from, st.to)
    end,
  },
  {
    key = "craft",
    label = L["Craft"],
    width = 230,
    sortKey = false,
    align = "LEFT",
    text = function(st)
      if st.note then
        return W.Color("brand", st.text)
      end
      return itemName(st.entry.recipe.product)
    end,
  },
  {
    key = "crafts",
    label = L["Crafts"],
    width = 50,
    sortKey = false,
    text = function(st)
      return st.note and "" or ("~" .. st.crafts)
    end,
  },
  {
    key = "cost",
    label = L["Cost"],
    width = 64,
    sortKey = false,
    text = function(st)
      return st.note and "" or cost(st.cost)
    end,
  },
  {
    key = "back",
    label = L["Gets back"],
    width = 64,
    sortKey = false,
    text = function(st)
      return st.note and "" or gain(st.back)
    end,
  },
  {
    key = "net",
    label = L["Net"],
    width = 64,
    sortKey = false,
    text = function(st)
      return st.note and "" or signed(st.net)
    end,
  },
  {
    key = "results",
    drop = 1,
    label = L["Results"],
    width = 150,
    sortKey = false,
    align = "LEFT",
    text = resultsText,
  },
}

-- toolbar controls, header cards and the color bar, added to the Crafting view
function UI:CreateLevelingControls(v, slots)
  local bar = slots.toolbar
  v.levelProf = W.Dropdown(bar, 170, { { 1, "-" } }, function(i)
    local c = UI.levelChoices and UI.levelChoices[i]
    if c then
      UI.levelChoice = { key = c.key, profession = c.profession }
      UI:RefreshCrafting()
    end
  end, { neutral = true })
  v.levelProf:SetPoint("LEFT", v.modes, "RIGHT", 12, 0)
  local targets = {}
  for _, t in ipairs(TARGETS) do
    targets[#targets + 1] = { t, L["to %d"]:format(t) }
  end
  v.levelTarget = W.Dropdown(bar, 76, targets, function(t)
    UI.levelTarget = t
    UI:RefreshCrafting()
  end, { neutral = true, default = TARGETS[#TARGETS] })
  v.levelTarget:SetPoint("LEFT", v.levelProf, "RIGHT", 6, 0)
  v.levelGoal = W.Segmented(bar, GOALS, {
    minWidth = 56,
    onSelect = function(goal)
      UI.levelGoal = goal
      UI.craftSelected = nil
      UI:RefreshCrafting()
    end,
  })
  v.levelGoal:SetPoint("RIGHT", v.details, "LEFT", -8, 0)
  v.levelGoal:Select("recovery", true)

  v.levelCards = W.CardRow(slots.header, {
    { L["Reagents and recipes cost"] },
    { L["Results get back"] },
    { L["Net to target"] },
    { L["Crafts (expected)"] },
    { L["Other goals, net"] },
  }, { width = UI.WIDTH - 20 })
  v.levelCards:SetPoint("TOPLEFT", 0, 0)
  v.levelCards:SetPoint("RIGHT", 0, 0)

  -- skill colors of the selected step's recipe: orange / yellow / green / grey, with the step marked
  local holder = CreateFrame("Frame", nil, v.colorRow)
  holder:SetAllPoints(v.colorRow)
  v.colorBar = holder
  v.colorParts = {}
  local colors = { { 0.79, 0.46, 0.17, 1 }, { 0.79, 0.69, 0.17, 1 }, { 0.25, 0.61, 0.29, 1 }, { 0.33, 0.35, 0.37, 1 } }
  for i = 1, 4 do
    local t = holder:CreateTexture(nil, "ARTWORK")
    W.Fill(t, colors[i])
    v.colorParts[i] = t
  end
  v.colorMark = holder:CreateTexture(nil, "OVERLAY")
  W.Fill(v.colorMark, { 1, 1, 1, 0.35 })
end

function UI:ShowLevelingControls(v, on)
  v.levelProf:SetShown(on)
  v.levelTarget:SetShown(on)
  v.levelGoal:SetShown(on)
  v.char:SetShown(not on)
  v.slots:ShowBar(v.slots.header, on)
  v.colorBar:SetShown(false)
end

-- toolbar values and header cards for the current plans
function UI:RenderLevelingHeader(v)
  local choices = self:LevelingChoices()
  self.levelChoices = choices
  local options, selected = {}, 1
  for i, c in ipairs(choices) do
    options[#options + 1] = { i, ("%s · %s %d"):format(charName(c.key), c.p.name or "?", c.p.skill or 0) }
    if self.levelChoice and c.key == self.levelChoice.key and c.profession == self.levelChoice.profession then
      selected = i
    end
  end
  if #options == 0 then
    options[1] = { 1, L["No professions recorded"] }
  end
  v.levelProf:SetOptions(options)
  v.levelProf:SetValue(selected)
  v.levelTarget:SetValue(self.levelTarget or TARGETS[#TARGETS])
  v.levelGoal:Select(self.levelGoal or "recovery", true)
  local lv = self.leveling
  local cards = v.levelCards.cards
  if not lv then
    for _, c in ipairs(cards) do
      c.value:SetText(W.Dim("-"))
    end
    return
  end
  local goal = self.levelGoal or "recovery"
  local plan = lv.plans[goal]
  cards[1].value:SetText(cost(plan.cost))
  cards[2].value:SetText(gain(plan.back))
  cards[3].value:SetText(signed(plan.net) .. (plan.complete and "" or W.Dim("  " .. L["(incomplete)"])))
  cards[4].value:SetText("~" .. plan.crafts)
  local others = {}
  for _, g in ipairs(GOALS) do
    if g[1] ~= goal then
      others[#others + 1] = g[2] .. " " .. signed(lv.plans[g[1]].net)
    end
  end
  cards[5].value:SetText(table.concat(others, "  "))
end

-- the selected step in the sidebar; returns the lines for the breakdown
function UI:LevelingDetail(v, st)
  local lines = {}
  local c = st.entry
  v.title:SetText(itemName(c.recipe.product))
  local known = c.known and L["known"]
    or c.itemPrice and L["recipe on the AH"]
    or c.estimated and L["trainer (level estimated)"]
    or ""
  v.subtitle:SetText(L["Skill %d to %d · %s"]:format(st.from, st.to, known))
  -- the color bar: orange from the learn level to yellow, yellow to green, green to grey, then grey
  local lo = math.min(st.from, c.learnAt or st.from, c.yellow)
  local green = math.floor((c.yellow + c.grey) / 2)
  local hi = c.grey + 10
  local width = v.colorBar:GetWidth()
  if not width or width <= 0 then
    width = UI.SIDE_PANEL_W - 20
  end
  local edges = { lo, c.yellow, green, c.grey, hi }
  local scale = width / math.max(1, hi - lo)
  for i, t in ipairs(v.colorParts) do
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", v.colorBar, "TOPLEFT", (edges[i] - lo) * scale, 0)
    t:SetSize(math.max(1, (edges[i + 1] - edges[i]) * scale), 14)
  end
  v.colorMark:ClearAllPoints()
  v.colorMark:SetPoint("TOPLEFT", v.colorBar, "TOPLEFT", (st.from - lo) * scale, 0)
  v.colorMark:SetSize(math.max(2, (st.to - st.from) * scale), 14)
  v.colorBar:SetShown(true)
  lines[#lines + 1] = {
    W.Dim(L["yellow %d · green %d · grey %d"]:format(c.yellow, green, c.grey)),
    "",
  }
  lines[#lines + 1] = {
    L["Skill-up chance"],
    ("%d%% -> %d%%"):format(math.floor(st.chance[1] * 100 + 0.5), math.floor(st.chance[2] * 100 + 0.5)),
  }
  lines[#lines + 1] = { L["Crafts (expected)"], "~" .. st.crafts }
  for _, r in ipairs(c.recipe.reagents) do
    lines[#lines + 1] = { ("%d %s"):format(r[2] * st.crafts, itemName(r[1])), "" }
  end
  lines[#lines + 1] = { L["Cost"], cost(st.cost) }
  local res = st.results
  if res.sell > 0 then
    lines[#lines + 1] = { L["Sell %d (as many as the market takes)"]:format(res.sell), "" }
  end
  if res.vendor > 0 then
    lines[#lines + 1] = { L["Vendor %d"]:format(res.vendor), "" }
  end
  if res.de > 0 then
    lines[#lines + 1] = { L["Disenchant %d"]:format(res.de), "" }
  end
  if res.keep > 0 then
    lines[#lines + 1] = { L["Keep %d for a later step"]:format(res.keep), "" }
  end
  lines[#lines + 1] = { L["Gets back"], gain(st.back) }
  lines[#lines + 1] = { L["Net for this step"], signed(st.net) }
  return lines
end

-- every reagent the path buys, on one shopping list ("<profession> to <target>")
function UI:LevelingShoppingList()
  local lv = self.leveling
  if not lv then
    return
  end
  local plan = lv.plans[self.levelGoal or "recovery"]
  local need, made = {}, {}
  for _, st in ipairs(plan.steps) do
    if st.entry then
      for _, r in ipairs(st.entry.recipe.reagents) do
        local n = r[2] * st.crafts
        local own = math.min(n, made[r[1]] or 0) -- made by an earlier step
        made[r[1]] = (made[r[1]] or 0) - own
        if n - own > 0 then
          need[r[1]] = (need[r[1]] or 0) + n - own
        end
      end
      local p = st.entry.recipe.product
      if p then
        made[p] = (made[p] or 0) + st.results.keep
      end
    end
  end
  local shop = ns.AME.shopping
  local name = L["%s to %d"]:format(lv.choice.p.name or "?", lv.target)
  local index
  for i, l in ipairs(shop:Lists()) do
    if l.name == name then
      index = i
    end
  end
  index = index or shop:AddList(name)
  if not index then
    return
  end
  for id, n in pairs(need) do
    shop:AddItem(index, id, n)
  end
  self:ShoppingChanged(index)
  ns.AME.Say(L["Added the reagents for %s to the shopping list %s."], name, name)
end
