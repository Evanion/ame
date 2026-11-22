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

local function charName(key)
  return (key or ""):gsub("^[^:]*:", "")
end

-- an item's name as a link in a card's text (the right column's cards switch links on)
local function link(id)
  return W.LinkText(id, nil, function()
    UI.RedrawCrafting()
  end)
end

-- the ledger: spending in red, getting back in green, the whole amount tinted; nothing: a dim dash (signed: 0)
local function cost(v)
  return v and v > 0 and W.SignedMoney(-v, { tint = true }) or W.Dim("-")
end
local function gain(v)
  return v and v > 0 and W.SignedMoney(v, { tint = true }) or W.Dim("-")
end
local function signed(v)
  return W.SignedMoney(v or 0, { tint = true, zero = "0" })
end

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

-- the candidate recipes for a character's profession: Leveling.Candidates
local function candidates(m, choice)
  return ns.Leveling.Candidates(choice.profession, choice.p, m.index.items, m.index.day)
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
        local info = ns.ItemCache.Get(id)
        if not info.name then
          return nil
        end
        return ns.Disenchant.Value(info.level, info.quality, info.classID, function(mat)
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
  for id, e in pairs(ns.Holdings.Of("usable", choice.key)) do
    held[id] = e.qty
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
  local noted = {} -- a recipe's learn / train note only before its first step
  for _, st in ipairs(plan.steps) do
    if st.train then
      rows[#rows + 1] = { note = true, skill = st.from, text = L["Train %s at your trainer"]:format(st.train) }
    else
      local c = st.entry
      if not noted[c] and not c.known then
        noted[c] = true
        -- the text is made when drawn, so an item name that loads later shows up
        if st.learn then
          local price = W.Plain(W.Money(st.learn, true))
          rows[#rows + 1] = {
            note = true,
            skill = st.from,
            itemID = c.recipeItem, -- the table shows the recipe item as a link, with what it costs after it
            learn = L["learn · AH %s · needs %d"]:format(price, c.learnAt or 0),
            text = function()
              return L["Learn %s · AH %s · needs %d"]:format(link(c.recipe.product or 0), price, c.learnAt or 0)
            end,
          }
        elseif c.estimated then
          rows[#rows + 1] = {
            note = true,
            skill = st.from,
            text = function()
              return L["Train %s · trainer, about %d"]:format(link(c.recipe.product or 0), c.learnAt)
            end,
          }
        end
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
        return W.Color("link", tostring(st.skill))
      end
      return ("%d-%d"):format(st.from, st.to)
    end,
  },
  -- what to craft, as an item link; a learn row: the recipe item, then where to get it, in the learn tone; a train
  -- or "stuck" row: its words
  {
    key = "craft",
    label = L["Craft"],
    width = 260,
    sortKey = false,
    item = true,
    fallback = function(st)
      if st.note then
        return W.Color("link", type(st.text) == "function" and st.text() or st.text)
      end
      return ""
    end,
    suffix = function(st)
      return st.learn and ("  " .. W.Color("link", st.learn)) or ""
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
    width = 130,
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
  -- the pickers come after the toolbar's own controls (UI.CraftingToolbar places them)
  v.toolbar:SetExtra("leveling", function(place)
    place(v.levelProf, 12)
    place(v.levelTarget)
  end)
  local targets = {}
  for _, t in ipairs(TARGETS) do
    targets[#targets + 1] = { t, L["to %d"]:format(t) }
  end
  v.levelTarget = W.Dropdown(bar, 76, targets, function(t)
    UI.levelTarget = t
    UI:RefreshCrafting()
  end, { neutral = true, default = TARGETS[#TARGETS] })
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
  -- the other goals card: one line, kept inside the card; every goal's net on hover
  local others = v.levelCards.cards[5]
  others.value:SetPoint("RIGHT", -8, 0)
  others.value:SetWordWrap(false)
  W.Tooltip(others, function(tip)
    local lv = UI.leveling
    if not lv then
      return false
    end
    W.TipText(tip, L["Other goals, net"], L["What the path nets under each goal (the one in use is marked)."])
    for _, g in ipairs(GOALS) do
      local label = g[1] == (UI.levelGoal or "recovery") and (g[2] .. " " .. W.Dim(L["(in use)"])) or g[2]
      W.TipPair(tip, label, signed(lv.plans[g[1]].net))
    end
  end, "ANCHOR_BOTTOM")

  -- skill colors of the selected step's recipe: orange / yellow / green / grey, with the step marked
  local holder = CreateFrame("Frame", nil, v.colorRow)
  holder:SetAllPoints(v.colorRow)
  v.colorBar = holder
  v.colorParts = {}
  local sk = W.COLORS.skill
  local colors = { sk.orange, sk.yellow, sk.green, sk.grey }
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
      c:Set({ value = W.Dim("-") })
    end
    return
  end
  local goal = self.levelGoal or "recovery"
  local plan = lv.plans[goal]
  -- signed amounts: what the path spends in red, what it gets back in green; nothing: a dim dash
  local function money(c, amount)
    if amount and amount ~= 0 then
      c:Set({ copper = amount, signed = true })
    else
      c:Set({ value = W.Dim("-") })
    end
  end
  money(cards[1], plan.cost and -plan.cost)
  money(cards[2], plan.back)
  cards[3]:Set({
    copper = plan.net or 0,
    signed = true,
    delta = not plan.complete and L["(incomplete)"] or nil,
    deltaKind = "mute",
  })
  cards[4]:Set({ value = "~" .. plan.crafts })
  -- the best of the other goals on the card; all of them on hover
  local best
  for _, g in ipairs(GOALS) do
    local p = lv.plans[g[1]]
    if g[1] ~= goal and (not best or p.net > lv.plans[best[1]].net) then
      best = g
    end
  end
  cards[5]:Set({ value = best and (best[2] .. " " .. signed(lv.plans[best[1]].net)) or W.Dim("-") })
end

-- the selected step in the right column: its title card, the skill colours, its reagents, then a card ending on the
-- step's net
function UI:LevelingDetail(v, st)
  local lines = {}
  local c = st.entry
  local known = c.known and L["known"]
    or c.itemPrice and L["recipe on the AH"]
    or c.estimated and L["trainer (level estimated)"]
    or ""
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
  local function line(label, text, extra)
    local row = extra or {}
    row.label, row.text = label, text
    lines[#lines + 1] = row
  end
  line(W.Dim(L["yellow %d · green %d · grey %d"]:format(c.yellow, green, c.grey)), "")
  line(
    L["Skill-up chance"],
    ("%d%% -> %d%%"):format(math.floor(st.chance[1] * 100 + 0.5), math.floor(st.chance[2] * 100 + 0.5))
  )
  line(L["Cost"], cost(st.cost))
  local res = st.results
  if res.sell > 0 then
    line(L["Sell %d (as many as the market takes)"]:format(res.sell), "")
  end
  if res.vendor > 0 then
    line(L["Vendor %d"]:format(res.vendor), "")
  end
  if res.de > 0 then
    line(L["Disenchant %d"]:format(res.de), "")
  end
  if res.keep > 0 then
    line(L["Keep %d for a later step"]:format(res.keep), "")
  end
  line(L["Gets back"], gain(st.back))
  line(L["Net for this step"], signed(st.net), { total = true })
  -- the reagents for the step's crafts, as item links
  local reagents = {}
  for _, r in ipairs(c.recipe.reagents) do
    reagents[#reagents + 1] = { itemID = r[1], countText = W.Thousands(r[2] * st.crafts) }
  end
  UI.CRAFT_DETAIL_TABLES.levelReagents = UI.CRAFT_DETAIL_TABLES.levelReagents
    or {
      rows = 6,
      itemID = function(d)
        return d.itemID
      end,
      itemMenu = {},
      columns = {
        { key = "name", label = L["Item"], width = 150, item = true, sortKey = false },
        { key = "countText", label = L["Need"], width = 50, sortKey = false },
      },
    }
  return {
    blocks = {
      {
        card = {
          item = c.recipe.product,
          subtitle = L["Skill %d to %d · %s · ~%d crafts"]:format(st.from, st.to, known, st.crafts),
        },
      },
      { colors = true },
      { heading = L["Reagents for ~%d"]:format(st.crafts) },
      { table = "levelReagents", rows = reagents },
      { card = { rows = lines } },
    },
  }
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
