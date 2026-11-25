-- The Crafting tab's model (the redesign: boards CraftingOne, CraftingReady, CraftingMissing, CraftingQueued,
-- CraftingLearn, CraftingLeveling, CraftingProfessions, and the frame beside the game's window, CraftQueue).
-- Pure functions turn gathered facts into rows; CraftingPage.Gather reads them from the rest of AME (CraftModel,
-- CraftQueue, Recipes, Professions, the open profession window).
--
--   CP.Gather() -> facts                          (game state; nil fields where something failed)
--   CP.Rows(facts) -> rows                        every known recipe: ready count, what's missing, profit, queued
--   CP.Filter(rows, filter, opts) -> rows         "all" | "ready" | "missing" (opts: profession, search, skillUp, fav)
--   CP.Sectioned(rows, cats, folds, skillLine)    the game's sections (header rows), folded ones closed
--   CP.Sidebar(facts, selected, live) -> entries  the professions sidebar
--   CP.Detail(facts, row, count) -> {...}         the picked recipe's right column
--   CP.Queue(facts) -> {...}                      the queue page: steps, to do, materials, totals
--   CP.Strip(facts, atAH) -> props                the queue as one line
--   CP.Learn(facts) -> rows                       recipes one of your characters could learn
--   CP.ProfessionRows(chars, rows, now, unrecorded), CP.LevelingChoices(chars), CP.LevelingRows(plan)
-- A row's key says what it is: "r:<recipeID>", "sec:<skillLine>:<categoryID>", "step:<recipeID>",
-- "learn:<item>:<spell>".
local _, ns = ...
local L = ns.L

local CP = { errors = {} }
ns.CraftingPage = CP

CP.FILTERS = {
  { "all", L["All"] },
  { "ready", L["Ready now"] },
  { "queued", L["Queued"] },
  { "missing", L["Missing something"] },
  { "learn", L["To learn"] },
}
CP.GATHERING = { [182] = true, [356] = true, [393] = true } -- no window: nothing to craft (CraftModel.GATHERING)
CP.LISTING_DAYS = 2 -- a recipe item seen on the AH within this many days is for sale
CP.TARGETS = { 75, 150, 225, 300 }
CP.GOALS = {
  { "cheapest", L["Cheapest"] },
  { "recovery", L["Best recovery"] },
  { "fewest", L["Fewest crafts"] },
  { "materials", L["My materials"] },
}

local function money(c)
  return ns.Widgets and ns.Widgets.Money and ns.Widgets.Money(c, true) or tostring(c)
end
local function signed(c)
  return ns.Widgets and ns.Widgets.SignedMoney and ns.Widgets.SignedMoney(c) or tostring(c)
end
local function charName(key)
  return key and (tostring(key):gsub("^[^:]*:", "")) or "?"
end
CP.CharName = charName

-- ------------------------------------------------------------------------------------------------ saved state

-- folds, the filter, search and the game's filter menu, kept as you left them
function CP.State()
  AME_DB = AME_DB or {}
  local s = AME_DB.craftingPage or {}
  AME_DB.craftingPage = s
  s.folds = s.folds or {}
  return s
end

-- ------------------------------------------------------------------------------------------------ pure parts

-- skill-up colour from the shipped data (orange below yellow, yellow to the midpoint, green to grey, none at grey)
function CP.Difficulty(skill, yellow, grey)
  if not (skill and yellow and grey) then
    return nil
  end
  if skill >= grey then
    return nil
  elseif skill < yellow then
    return "orange"
  elseif skill < math.floor((yellow + grey) / 2) then
    return "yellow"
  end
  return "green"
end

-- the open window's own word (Enum.TradeskillRelativeDifficulty: 0 optimal, 1 medium, 2 easy, 3 trivial)
CP.RELATIVE = { [0] = "orange", [1] = "yellow", [2] = "green" }

-- crafts the reagents you hold make, and what one craft lacks: n, { { item, short }, ... }
function CP.Ready(recipe, held)
  local n, missing = nil, {}
  for _, g in ipairs(recipe and recipe.reagents or {}) do
    local have = held and held[g[1]] or 0
    local each = math.floor(have / math.max(1, g[2]))
    n = n and math.min(n, each) or each
    if have < g[2] then
      missing[#missing + 1] = { item = g[1], short = g[2] - have, have = have }
    end
  end
  return n or 0, missing
end

-- a recipe's requirements: tools (items) and places ("Anvil", "Forge", a deployable) as recorded, with what the open
-- window says (live: { [name] = met }) and whether one of yours holds a tool. -> { { name, kind, id, met, held } }
function CP.Requirements(recipe, live, heldOf, keyByName)
  local out = {}
  local function add(name, kind)
    local id = kind == "tool" and recipe.toolIDs and recipe.toolIDs[name] or (keyByName and keyByName(name)) or nil
    local held = id and heldOf and heldOf(id) or 0
    local met = live and live[name]
    if met == nil and kind == "tool" and id then
      met = held > 0 -- away from the window: a tool one of yours holds counts
    end
    out[#out + 1] = { name = name, kind = kind, id = id, met = met, held = held }
  end
  for _, name in ipairs(recipe and recipe.tools or {}) do
    add(name, "tool")
  end
  for _, name in ipairs(recipe and recipe.at or {}) do
    add(name, "place")
  end
  return out
end

-- the Ready column: { text, color }
function CP.ReadyText(r)
  local unmet
  for _, q in ipairs(r.needs or {}) do
    if q.met == false then
      unmet = unmet or q
    end
  end
  if unmet then
    if unmet.kind == "tool" then
      return { text = L["missing a tool: %s"]:format(unmet.name), color = "warn" }
    elseif unmet.id and (unmet.held or 0) > 0 then
      return { text = L["no %s here · you hold one"]:format(unmet.name), color = "warn" }
    end
    return { text = L["%s not nearby"]:format(unmet.name), color = "warn" }
  end
  -- "missing 2" in amber, the item in its quality colour (a link: its tooltip, Shift-click), as everywhere
  local W = ns.Widgets
  local function amber(text)
    return ns.Kit and ns.Kit.Color("warn", text) or text
  end
  local function shortText(m)
    if not m then
      return nil
    end
    local item = W and W.LinkText and m.item and W.LinkText(m.item) or (r.itemName and r.itemName(m.item)) or "?"
    return amber(L["missing %d"]:format(m.short)) .. " " .. item
  end
  local short = shortText(r.missing and r.missing[1])
  if r.n > 0 then
    local q = r.queuedMissing and r.queuedMissing[1]
    if q then
      return { text = amber(L["%d now · "]:format(r.n)) .. shortText(q) }
    end
    if r.profit and r.profit < 0 then
      return { text = L["ready ×%d · loses money"]:format(r.n), color = "dim" }
    end
    return { text = L["ready ×%d"]:format(r.n), color = "good" }
  end
  if short then
    return { text = short } -- coloured in parts
  end
  return { text = L["missing reagents"], color = "warn" }
end

-- how many things stand in the way of one craft (a reagent short, a requirement not met)
function CP.Short(r)
  local n = #(r.missing or {})
  for _, q in ipairs(r.needs or {}) do
    if q.met == false then
      n = n + 1
    end
  end
  return n
end

-- every known recipe, as rows (facts: CP.Gather's)
function CP.Rows(f)
  local out = {}
  local queued = {}
  for _, q in ipairs(f.queue and f.queue.items or {}) do
    queued[q.recipe] = (queued[q.recipe] or 0) + q.count
  end
  local live = f.live
  for _, e in ipairs(f.entries or {}) do
    local recipe = e.recipe
    local id = recipe.id
    local n, missing = CP.Ready(recipe, f.held)
    local lr = live and live.recipes and live.recipes[id]
    local skill
    for _, key in ipairs(e.crafters or {}) do
      local c = f.chars and f.chars[key]
      local p = c and c.professions and c.professions[e.profession]
      if p and (not skill or (p.skill or 0) > skill) then
        skill = p.skill or 0
      end
    end
    local diff = lr and lr.diff
    if not lr then
      diff = CP.Difficulty(skill, recipe.yellow, recipe.grey)
    end
    local eval = e.eval or {}
    local r = {
      key = "r:" .. id,
      id = id,
      recipe = recipe,
      item = recipe.product,
      name = f.recipeName and f.recipeName(id) or tostring(id),
      profession = e.profession,
      crafters = e.crafters,
      crafter = charName(e.crafters and e.crafters[1]),
      eval = eval,
      profit = eval.profit,
      n = n,
      missing = missing,
      needs = CP.Requirements(recipe, lr and lr.requirements, f.heldOf, f.keyByName),
      queued = queued[id],
      diff = diff,
      cat = (lr and lr.cat) or (f.recipeCat and f.recipeCat(e.profession, id)),
      fav = lr and lr.fav or false,
      itemName = f.itemName,
    }
    if r.queued and r.queued > n then
      -- what the queued crafts lack beyond the ones you can make now
      local q = {}
      for _, g in ipairs(recipe.reagents or {}) do
        local have = f.held and f.held[g[1]] or 0
        if have < g[2] * r.queued then
          q[#q + 1] = { item = g[1], short = g[2] * r.queued - have, have = have }
        end
      end
      r.queuedMissing = #q > 0 and q or nil
    end
    r.short = CP.Short(r)
    r.ready = CP.ReadyText(r)
    out[#out + 1] = r
  end
  table.sort(out, function(a, b)
    local pa, pb = a.profit or -math.huge, b.profit or -math.huge
    if pa ~= pb then
      return pa > pb
    end
    return a.id < b.id
  end)
  return out
end

-- a row's text to search: what it makes, the recipe's name, its reagents
local function matches(r, text, itemName)
  text = text:lower()
  local function has(s)
    return s and tostring(s):lower():find(text, 1, true) ~= nil
  end
  if has(r.name) or (r.item and has(itemName and itemName(r.item))) then
    return true
  end
  for _, g in ipairs(r.recipe and r.recipe.reagents or {}) do
    if has(itemName and itemName(g[1])) then
      return true
    end
  end
  return false
end

-- opts: profession (skill line), search, skillUp, fav, itemName
function CP.Filter(rows, filter, opts)
  opts = opts or {}
  local out = {}
  for _, r in ipairs(rows) do
    local keep = true
    if opts.profession and r.profession ~= opts.profession then
      keep = false
    elseif filter == "ready" then
      keep = r.n > 0 and r.short == 0
    elseif filter == "missing" then
      -- one thing short of a craft (a reagent or a requirement), or of the crafts you queued (one reagent)
      keep = r.short == 1 or (r.short == 0 and r.queuedMissing ~= nil and #r.queuedMissing == 1)
    end
    if keep and opts.skillUp then
      keep = r.diff ~= nil
    end
    if keep and opts.fav then
      keep = r.fav
    end
    if keep and opts.search and opts.search ~= "" then
      keep = matches(r, opts.search, opts.itemName)
    end
    if keep then
      out[#out + 1] = r
    end
  end
  return out
end

-- the game's sections, in the game's order: header rows ({ header, key, label, count, folded }) with their recipes
-- after them, a folded section's left out. cats: { [categoryID] = { name, order, parent } }. Recipes in no section
-- the game named go last, under "Other". No sections recorded: the rows as they are.
function CP.Sectioned(rows, cats, folds, skillLine)
  if not cats or next(cats) == nil then
    return rows, 0
  end
  local groups, order = {}, {}
  for _, r in ipairs(rows) do
    local c = r.cat and cats[r.cat] and r.cat or "other"
    if not groups[c] then
      groups[c] = {}
      order[#order + 1] = c
    end
    table.insert(groups[c], r)
  end
  local function rank(c)
    local cat = cats[c]
    if not cat then
      return math.huge, math.huge
    end
    local parent = cat.parent and cats[cat.parent]
    return parent and (parent.order or 0) or (cat.order or 0), parent and (cat.order or 0) or -1
  end
  table.sort(order, function(a, b)
    local a1, a2 = rank(a)
    local b1, b2 = rank(b)
    if a1 ~= b1 then
      return a1 < b1
    end
    if a2 ~= b2 then
      return a2 < b2
    end
    return tostring(a) < tostring(b)
  end)
  local out = {}
  for _, c in ipairs(order) do
    local key = "sec:" .. tostring(skillLine) .. ":" .. tostring(c)
    local folded = folds and folds[key] or false
    out[#out + 1] = {
      header = true,
      key = key,
      label = cats[c] and cats[c].name or L["Other"],
      count = #groups[c],
      folded = folded,
    }
    if not folded then
      -- inside a section, in the game's order of the list: by profit, as the flat list
      for _, r in ipairs(groups[c]) do
        out[#out + 1] = r
      end
    end
  end
  return out, #order
end

-- the professions sidebar: All professions, then each character's professions under its name (a profession two of
-- yours have shows once, under the one with the higher skill)
function CP.Professions(chars)
  local best = {}
  for key, c in pairs(chars or {}) do
    for skillLine, p in pairs(c.professions or {}) do
      -- a gathering profession with recipes (Forever) counts
      if not CP.GATHERING[skillLine] or next(p.learned or {}) then
        local b = best[skillLine]
        if not b or (p.skill or 0) > (b.skill or 0) or ((p.skill or 0) == (b.skill or 0) and key < b.key) then
          best[skillLine] =
            { key = key, skillLine = skillLine, name = p.name or tostring(skillLine), skill = p.skill, max = p.max }
        end
      end
    end
  end
  local byChar, keys = {}, {}
  for _, b in pairs(best) do
    if not byChar[b.key] then
      byChar[b.key] = {}
      keys[#keys + 1] = b.key
    end
    table.insert(byChar[b.key], b)
  end
  table.sort(keys)
  local out = {}
  for _, key in ipairs(keys) do
    table.sort(byChar[key], function(a, b)
      return a.name < b.name
    end)
    out[#out + 1] = { char = key, list = byChar[key] }
  end
  return out
end

function CP.Sidebar(f, selected)
  local entries = {
    { key = "all", label = L["All professions"], count = #(f.entries or {}), selected = selected == nil },
  }
  for _, g in ipairs(CP.Professions(f.chars)) do
    entries[#entries + 1] = { heading = true, label = charName(g.char) }
    for _, p in ipairs(g.list) do
      entries[#entries + 1] = {
        key = "prof:" .. p.skillLine,
        label = p.name,
        count = p.max and p.max > 0 and ("%d / %d"):format(p.skill or 0, p.max) or p.skill, -- your skill, of its most
        selected = selected == p.skillLine,
      }
    end
  end
  -- always there: the game's profession book (K), where a profession is unlearned
  entries[#entries + 1] = { key = "book", label = L["Your professions in the game"], link = true }
  return entries
end

-- the profession a skill line is, by name, and the character the sidebar shows it under
function CP.ProfessionOf(f, skillLine)
  for _, g in ipairs(CP.Professions(f.chars)) do
    for _, p in ipairs(g.list) do
      if p.skillLine == skillLine then
        return p
      end
    end
  end
end

-- ------------------------------------------------------------------------------------------------ the right column

-- reagents for count crafts: { item, need, have, toBuy }
function CP.Needs(f, recipe, count)
  local out = {}
  for _, g in ipairs(recipe and recipe.reagents or {}) do
    local need = g[2] * count
    local have = f.held and f.held[g[1]] or 0
    local short = math.max(0, need - have)
    local price = short > 0 and f.craft and f.craft:Price(g[1])
    out[#out + 1] =
      { key = "need:" .. g[1], item = g[1], need = need, have = have, toBuy = price and price * short or nil }
  end
  return out
end

-- sold raw, or made into this first: the craft's lines for the reagent you hold most of
function CP.RawOrRefined(f, recipe)
  if not (f.craft and recipe and recipe.product and f.held) then
    return nil
  end
  local best
  for _, g in ipairs(recipe.reagents or {}) do
    local n = f.held[g[1]] or 0
    if n >= g[2] and (not best or n > best.qty) then
      best = { item = g[1], qty = n }
    end
  end
  if not best then
    return nil
  end
  local ok, res = pcall(f.craft.SellOrRefine, f.craft, best.item, best.qty, { recipe })
  local o = ok and res and res.options and res.options[1]
  if not o then
    return nil
  end
  local rate = f.craft.SalesPerDay and f.craft:SalesPerDay(recipe.product)
  return {
    item = best.item,
    qty = best.qty,
    raw = res.raw,
    product = recipe.product,
    sold = o.sold,
    others = o.others,
    left = o.left,
    net = o.net,
    gain = o.gain,
    days = o.days,
    rate = rate,
  }
end

-- the picked recipe's right column: its card, requirements, reagents, Selling it, Raw or refined
function CP.Detail(f, r, count)
  if not r then
    return nil
  end
  count = math.max(1, count or 1)
  local recipe, e = r.recipe, r.eval or {}
  local made = recipe.made or 1
  local sub = {
    f.profName and f.profName(r.profession) or "",
    r.crafter,
    L["makes %s"]:format(made == math.floor(made) and tostring(made) or ("%.1f"):format(made)),
  }
  if r.short == 0 and r.n > 0 then
    sub[#sub + 1] = L["ready ×%d"]:format(r.n)
  end
  for _, q in ipairs(r.needs or {}) do
    if q.met == false then
      sub[#sub + 1] = q.kind == "tool" and L["missing a tool"] or L["needs %s"]:format(q.name)
      break
    end
  end
  if r.queued then
    sub[#sub + 1] = L["queued %d"]:format(r.queued)
  end
  if r.fav then
    sub[#sub + 1] = L["favourite"]
  end
  local sell = {
    { label = L["Reagents, per craft"], copper = e.cost },
    { label = L["Sells for, after the cut"], copper = e.revenue },
    { label = L["Profit per craft"], copper = e.profit, signed = true, total = true },
  }
  if r.diff then
    sell[#sell + 1] = { label = L["Skill"], text = L["a skill-up"], tone = "warn" }
  elseif e.sellRate then
    sell[#sell + 1] = { label = L["Sells"], text = CP.RateWords(e.sellRate), tone = "dim" }
  end
  local tools = {}
  for _, q in ipairs(r.needs or {}) do
    tools[#tools + 1] = CP.ToolLine(f, q)
  end
  return {
    item = recipe.product,
    title = not recipe.product and r.name or nil,
    subtitle = table.concat(sub, " · "),
    needs = CP.Needs(f, recipe, count),
    sell = sell,
    tools = tools,
    raw = CP.RawOrRefined(f, recipe),
  }
end

-- "about 3 a day", "about once in 10 days"
function CP.RateWords(perDay)
  if not perDay or perDay <= 0 then
    return L["hardly sells"]
  elseif perDay >= 1 then
    return L["about %d a day"]:format(math.floor(perDay + 0.5))
  end
  return L["about once in %d days"]:format(math.floor(1 / perDay + 0.5))
end

-- a requirement as the Tools card draws it: an item link (a tool, a deployable) or the game's word for a place,
-- whether you have it, and one short line on where a tool comes from (the rest is in its tooltip)
function CP.ToolLine(f, q)
  local t = { item = q.id, place = not q.id and q.name or nil, name = q.name }
  if q.kind == "place" and not q.id then
    if q.met == true then
      t.have, t.tone = L["nearby"], "good"
    elseif q.met == false then
      t.have, t.tone = L["not nearby"], "warn"
    else
      t.have, t.tone = L["open the profession to check"], "dim"
    end
    return t
  end
  if q.kind == "place" then -- a deployable: one standing here, one of yours holds one, or neither
    if q.met == true then
      t.have, t.tone = L["one stands here"], "good"
    elseif (q.held or 0) > 0 then
      t.have, t.tone = L["none here · you hold one"], "warn"
    else
      t.have, t.tone = L["none of yours has one"], "warn"
    end
  elseif (q.held or 0) > 0 then
    t.have, t.tone = L["you have one"], "good"
  else
    t.have, t.tone = L["none of yours has one"], "warn"
  end
  local ways = f.toolWays and q.id and f.toolWays(q)
  if ways then
    t.line, t.price = ways.line, ways.price
  end
  return t
end

-- UI.CraftTools' ways in one short line: "Made by Engineers (250) · on the auction house", and a price
function CP.WaysLine(tool)
  local parts, price = {}, nil
  for _, w in ipairs(tool and tool.ways or {}) do
    if w.kind == "known" then
      parts[#parts + 1] = L["%s makes it"]:format(w.who)
    elseif w.kind == "make" then
      local what = w.profession and (w.skill and ("%s (%d)"):format(w.profession, w.skill) or w.profession)
      parts[#parts + 1] = L["Made by %s"]:format(what or L["a crafter"])
    elseif w.kind == "vendor" then
      parts[#parts + 1] = L["Sold by %s"]:format(w.npc .. (w.zone and (", " .. w.zone) or ""))
      price = price or w.price
    elseif w.kind == "vendors" then
      parts[#parts + 1] = L["Sold by vendors"]
      price = price or w.price
    elseif w.kind == "ah" then
      parts[#parts + 1] = L["on the auction house"]
      price = w.price or price
    end
  end
  if #parts == 0 then
    return nil
  end
  return { line = table.concat(parts, " · "), price = price }
end

-- ------------------------------------------------------------------------------------------------ the queue

local SOURCE = {
  carried = function()
    return L["in your bags"]
  end,
  bank = function()
    return L["your bank"]
  end,
  mail = function()
    return L["your mailbox"]
  end,
  alt = function(s)
    return L["%s's bags or bank"]:format(s.char or "?")
  end,
  guild = function(s)
    return L["<%s> guild bank"]:format(s.char or "?")
  end,
  vendor = function(s)
    return L["vendor %s"]:format(s.cost and money(s.cost) or "")
  end,
  made = function(s)
    return s.stepIndex and L["made in step %d"]:format(s.stepIndex) or L["made in the queue"]
  end,
  ah = function(s)
    return L["AH %s"]:format(s.cost and money(s.cost) or "")
  end,
}

-- a material's sources as one tag: "8 · Zakzu's bank, 4 · AH 4g"; the kind is the AH's when any comes from it,
-- the queue's when any is made, else other
function CP.SourceTag(m, stepIndex)
  local parts, kind = {}, "other"
  local onlyBags = true
  for _, src in ipairs(m.sources or {}) do
    if src.kind ~= "carried" then
      onlyBags = false
    end
    local s =
      { kind = src.kind, char = src.char, cost = src.cost, stepIndex = src.step and stepIndex and stepIndex[src.step] }
    local where = (SOURCE[src.kind] and SOURCE[src.kind](s) or src.kind):gsub("%s+$", "")
    parts[#parts + 1] = src.kind == "carried" and where or (src.qty .. " · " .. where)
    if src.kind == "ah" then
      kind = "ah"
    elseif src.kind == "made" and kind ~= "ah" then
      kind = "made"
    end
  end
  return { text = table.concat(parts, ", "), kind = kind }, onlyBags
end

-- a to-do line as parts (text and item links): "On Zakzu: craft 2 [Heavy Mithril Gauntlet]"
function CP.TodoParts(t, me)
  local item = { item = t.item }
  local q = tostring(t.qty or 0) .. " "
  local on = t.char and t.char ~= me and t.kind == "craft" and (L["On %s: "]:format(charName(t.char))) or ""
  if t.kind == "buy" then
    return {
      L["Buy "] .. q,
      item,
      { text = " " .. L["on the AH"] .. (t.cost and (" " .. money(t.cost)) or ""), tone = "dim" },
    }
  elseif t.kind == "vendor" then
    return { L["Buy "] .. q, item, { text = " " .. L["from a vendor"], tone = "dim" } }
  elseif t.kind == "bank" then
    return { L["Take "] .. q, item, " " .. L["from the bank"] }
  elseif t.kind == "mail" then
    return { L["Take "] .. q, item, " " .. L["from the mailbox"] }
  elseif t.kind == "alt" then
    return { L["On %s: "]:format(t.char or "?") .. L["mail "] .. q, item, " " .. L["to this character"] }
  elseif t.kind == "guild" then
    return { L["Take "] .. q, item, " " .. L["from the <%s> guild bank"]:format(t.char or "?") }
  elseif t.kind == "craft" then
    return { on .. L["craft "] .. q, item }
  end
  return nil
end

-- the queue page: steps (parts first), to do, materials with their sources, and the totals
function CP.Queue(f)
  local plan = f.plan
  local out = { steps = {}, todo = {}, mats = {}, toBuy = 0, profit = 0, crafts = 0, chars = 0 }
  if not plan then
    return out
  end
  out.toBuy, out.profit = plan.toBuy or 0, plan.profit or 0
  local index, chars = {}, {}
  for i, s in ipairs(plan.steps) do
    index[s] = i
  end
  local recipeOf = f.recipe or function()
    return nil
  end
  for i, s in ipairs(plan.steps) do
    local who = s.crafter and (s.mine and charName(f.me) or charName(s.crafter)) or L["nobody of yours"]
    if s.crafter then
      chars[s.crafter] = true
    end
    local whoText, profit, button, cheaper
    if s.part then
      local forStep
      for j = i + 1, #plan.steps do
        local r = recipeOf(plan.steps[j].recipe)
        for _, g in ipairs(r and r.reagents or {}) do
          if g[1] == s.item and not forStep then
            forStep = j
          end
        end
      end
      whoText = {
        text = forStep and L["%s · a part for step %d"]:format(who, forStep) or L["%s · a part"]:format(who),
        color = "dim",
      }
      -- made, since one of yours can; where buying is cheaper the step says so and Buy is lit: your call
      if s.choice ~= "buy" and s.saved and s.saved < 0 then
        profit = { text = L["buying saves %s"]:format(money(-s.saved)), color = "warn" }
        cheaper = true
      else
        profit = s.saved and s.saved > 0 and { text = L["making saves %s"]:format(money(s.saved)), color = "good" }
          or { text = "", color = "dim" }
      end
      button = L["Buy"]
    else
      whoText = who
      out.crafts = out.crafts + (s.count or 0)
      profit = s.profit and { text = signed(s.profit), color = s.profit >= 0 and "good" or "bad" }
        or { text = "—", color = "dim" }
      button = "✕"
    end
    out.steps[#out.steps + 1] = {
      key = "step:" .. s.recipe,
      n = i,
      item = s.item,
      label = not s.item and (f.recipeName and f.recipeName(s.recipe)) or nil,
      count = s.made or s.count,
      who = whoText,
      profitText = profit,
      act = button,
      actPrimary = cheaper or nil,
      part = s.part or false,
      recipe = s.recipe,
    }
  end
  for _ in pairs(chars) do
    out.chars = out.chars + 1
  end
  for i, t in ipairs(plan.todo or {}) do
    local parts = CP.TodoParts(t, f.me)
    if parts then
      table.insert(parts, 1, { text = (#out.todo + 1) .. ". ", tone = "dim" })
      out.todo[#out.todo + 1] = parts
    end
    local _ = i
  end
  for _, m in ipairs(plan.materials or {}) do
    local tag, bags = CP.SourceTag(m, index)
    out.mats[#out.mats + 1] = {
      key = "mat:" .. m.item,
      item = m.item,
      need = bags and { text = tostring(m.need), color = "good" } or tostring(m.need),
      source = tag,
      -- a part one of yours can make, bought instead: a click on the row makes it again
      bought = m.part and m.choice == "buy" or nil,
    }
  end
  return out
end

-- the queue as one line: what's lined up (item, units), what it still costs, the next thing to do
function CP.Strip(f, atAH)
  local items = {}
  for _, q in ipairs(f.queue and f.queue.items or {}) do
    local r = f.recipe and f.recipe(q.recipe)
    items[#items + 1] = {
      item = r and r.product or nil,
      count = q.count * (r and r.made or 1),
      label = f.recipeName and f.recipeName(q.recipe),
    }
  end
  local toBuy = f.plan and f.plan.toBuy or 0
  -- nothing missing (every reagent held, or made by a step): nothing to buy and no button (board QueueStrip, ready)
  local missing = false
  for _, m in ipairs(f.plan and f.plan.materials or {}) do
    for _, src in ipairs(m.sources or {}) do
      if (src.kind == "ah" or src.kind == "vendor") and (src.qty or 0) > 0 then
        missing = true
      end
    end
  end
  local ready = #items > 0 and f.plan ~= nil and not missing
  return {
    items = items,
    toBuy = toBuy > 0 and toBuy or nil,
    ready = ready or nil,
    button = #items > 0 and not ready and (atAH and L["Buy missing"] or L["Missing to a list"]) or nil,
    buttonAction = "buyMissing",
    action = "openQueue",
    empty = L["Nothing queued. Pick a recipe and click Queue."],
  }
end

-- ------------------------------------------------------------------------------------------------ to learn

-- recipes one of your characters could learn and none knows yet: on the AH lately, or seen at a vendor.
-- f.learnRows: Crafting:RecipesToBuy's rows (each with .via "ah" | "vendor" and .where for a vendor)
function CP.Learn(f, opts)
  opts = opts or {}
  local out = {}
  for _, r in ipairs(f.learnRows or {}) do
    local t = r.teaches or {}
    if not opts.profession or t.profession == opts.profession then
      local who = r.learners and r.learners[1]
      local where
      if r.via == "vendor" then
        where = { text = L["pattern %s, %s"]:format(money(r.price), r.where or L["a vendor"]), color = "vendor" }
      else
        local pays = r.payback
          and (r.payback < 1 and L["pays back in a day"] or L["pays back in %d days"]:format(math.ceil(r.payback)))
        where = { text = L["%s on the AH"]:format(money(r.price)) .. (pays and (" · " .. pays) or ""), color = "link" }
      end
      local row = {
        key = "learn:" .. r.item .. ":" .. tostring(r.spell),
        item = r.recipe and r.recipe.product or nil,
        recipeItem = r.item,
        label = f.recipeName and f.recipeName(r.spell) or nil,
        who = { text = who and charName(who.char) or "?", color = "dim" },
        profit = r.eval and r.eval.profit,
        where = where,
        buy = r.via == "vendor" and L["List"] or L["Buy"],
        faded = not r.ready or nil,
        r = r,
      }
      if
        not opts.search
        or opts.search == ""
        or matches({ name = row.label, item = row.item }, opts.search, f.itemName)
      then
        out[#out + 1] = row
      end
    end
  end
  return out
end

-- the To learn row's right column: { item, subtitle, rows }
function CP.LearnDetail(f, row)
  if not row then
    return nil
  end
  local r = row.r
  local who = r.learners and r.learners[1]
  local usual = f.usual and f.usual(r.item)
  local rows = {
    { label = r.via == "vendor" and L["The recipe, at a vendor"] or L["The recipe, on the AH now"], copper = r.price },
  }
  if usual then
    rows[#rows + 1] = { label = L["Usually"], copper = usual }
  end
  rows[#rows + 1] = { label = L["Profit per craft"], copper = r.eval and r.eval.profit, signed = true }
  rows[#rows + 1] = {
    label = L["Pays back, at best"],
    text = r.payback and (r.payback < 1 and L["under a day"] or L["%d days"]:format(math.ceil(r.payback)))
      or L["not worked out"],
    total = true,
  }
  local guild = f.guildCrafters and f.guildCrafters(r.spell) or 0
  rows[#rows + 1] = {
    label = L["Guild crafters"],
    text = guild > 0 and tostring(guild) or L["nobody"],
    tone = guild == 0 and "warn" or nil,
  }
  local note
  if r.eval and r.eval.sellRate then
    note = L["At best: if you sold all the market takes (about %s a day)."]:format(
      ("%.0f"):format(math.max(1, r.eval.sellRate))
    )
  end
  if guild == 0 then
    note = (note and (note .. " ") or "") .. L["Nobody in your guild makes it: learning it fills a gap."]
  end
  local t = r.teaches or {}
  return {
    item = r.item,
    subtitle = L["Teaches %s · %s %d · for %s"]:format(
      row.label or "?",
      f.profName and f.profName(t.profession) or "?",
      r.rank or 0,
      who and charName(who.char) or "?"
    ),
    rows = rows,
    note = note,
  }
end

-- ------------------------------------------------------------------------------------------------ your professions

-- one row per character and profession: skill, recipes known, cooldowns; what isn't recorded yet, faded.
-- earners: CP.Rows' rows (their crafters and profit). unrecorded: Professions.Unrecorded's list.
function CP.ProfessionRows(chars, earners, now, unrecorded)
  local best = {}
  for _, r in ipairs(earners or {}) do
    for _, key in ipairs(r.crafters or {}) do
      local k = key .. ":" .. tostring(r.profession)
      best[k] = best[k] or {}
      if r.eval and r.eval.perDay and #best[k] < 3 then
        table.insert(best[k], r)
      end
    end
  end
  local rows = {}
  for key, c in pairs(chars or {}) do
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
      rows[#rows + 1] = {
        key = "prof:" .. key .. ":" .. skillLine,
        char = charName(key),
        charKey = key,
        skillLine = skillLine,
        profession = p.name or "?",
        skill = p.skill,
        max = p.max,
        skillText = ("%d / %d"):format(p.skill or 0, p.max or 0),
        known = not CP.GATHERING[skillLine] and known or nil,
        cooldown = ready and { text = L["ready"], color = "good" }
          or wait and { text = L["in %s"]:format(CP.Duration(wait)), color = "dim" }
          or { text = "—", color = "dim" },
        ready = ready,
        earners = best[key .. ":" .. tostring(skillLine)] or {},
      }
    end
  end
  for _, u in ipairs(unrecorded or {}) do
    if not u.noWindow then
      rows[#rows + 1] = {
        key = "prof:" .. u.key .. ":" .. tostring(u.skillLine or "none"),
        char = { text = charName(u.key), color = "dim" },
        charKey = u.key,
        skillLine = u.skillLine,
        profession = { text = u.none and L["nothing recorded"] or (u.name or "?"), color = "dim" },
        skillText = { text = L["not recorded"], color = "dim" },
        cooldown = { text = u.none and L["log in there once"] or L["open it once"], color = "dim" },
        faded = true,
        unrecorded = true,
        earners = {},
      }
    end
  end
  table.sort(rows, function(a, b)
    local ca = type(a.char) == "table" and a.char.text or a.char
    local cb = type(b.char) == "table" and b.char.text or b.char
    if (a.unrecorded or false) ~= (b.unrecorded or false) then
      return not a.unrecorded
    end
    if ca ~= cb then
      return ca < cb
    end
    local pa = type(a.profession) == "table" and a.profession.text or a.profession
    local pb = type(b.profession) == "table" and b.profession.text or b.profession
    return pa < pb
  end)
  return rows
end

function CP.Duration(s)
  if s >= 86400 then
    return L["%d d"]:format(math.floor(s / 86400 + 0.5))
  elseif s >= 3600 then
    return L["%d h"]:format(math.floor(s / 3600 + 0.5))
  end
  return L["%d min"]:format(math.max(1, math.floor(s / 60 + 0.5)))
end

-- ------------------------------------------------------------------------------------------------ leveling

-- every recorded (character, crafting profession): { key, profession, p }
function CP.LevelingChoices(chars)
  local out = {}
  for key, c in pairs(chars or {}) do
    for profession, p in pairs(c.professions or {}) do
      -- a gathering profession with recipes (Forever) counts
      if not CP.GATHERING[profession] or next(p.learned or {}) then
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

-- a Leveling.Plan's steps as table rows, with a learn row before a step whose recipe is bought or trained
function CP.LevelingRows(plan, recipeName)
  local rows, noted = {}, {}
  for i, st in ipairs(plan and plan.steps or {}) do
    if st.train then
      rows[#rows + 1] = {
        key = "lv:train:" .. i,
        skill = { text = tostring(st.from or ""), color = "link" },
        label = ns.Kit and ns.Kit.Color("link", L["Train %s at your trainer"]:format(st.train)) or st.train,
        crafts = "",
      }
    else
      local c = st.entry
      if c and not noted[c] and not c.known and (st.learn or c.estimated) then
        noted[c] = true
        rows[#rows + 1] = {
          key = "lv:learn:" .. i,
          skill = { text = tostring(c.learnAt or st.from), color = "link" },
          item = st.learn and c.recipeItem or c.recipe.product,
          crafts = st.learn and { text = L["learn · AH %s"]:format(money(st.learn)), color = "link" }
            or { text = L["trainer, about %d"]:format(c.learnAt or 0), color = "link" },
        }
      end
      if c then
        -- each result in its own colour: sell green, vendor, disenchant, keep
        local res, parts = st.results or {}, {}
        local function add(n, label, role)
          if (n or 0) > 0 then
            parts[#parts + 1] = ns.Color(role, label:format(n))
          end
        end
        add(res.sell, L["sell %d"], "good")
        add(res.vendor, L["vendor %d"], "vendor")
        add(res.de, L["disenchant %d"], "brand")
        add(res.keep, L["keep %d"], "wait")
        rows[#rows + 1] = {
          key = "lv:" .. i,
          skill = ("%d–%d"):format(st.from, st.to),
          item = c.recipe.product,
          label = not c.recipe.product and recipeName and recipeName(c.recipe.id) or nil,
          crafts = "~" .. tostring(st.crafts),
          -- the whole amount tinted, a dim 0 for nothing (as the ledger)
          net = ns.Widgets.SignedMoney(st.net or 0, { tint = true, zero = "0" }),
          results = table.concat(parts, "  "),
          st = st,
        }
      end
    end
  end
  if plan and plan.stuck then
    rows[#rows + 1] = {
      key = "lv:stuck",
      skill = { text = tostring(plan.stuck), color = "warn" },
      label = ns.Kit and ns.Kit.Color(
        "warn",
        L["No usable recipe from here with today's data: learn more recipes or scan the AH."]
      ) or "",
      crafts = "",
    }
  end
  return rows
end

-- the picked step's right column: card, the colour bar's edges, reagents, the step's net
function CP.LevelingDetail(st)
  if not (st and st.entry) then
    return nil
  end
  local c = st.entry
  local known = c.known and L["known"]
    or c.itemPrice and L["recipe on the AH"]
    or c.estimated and L["trainer, level estimated"]
    or ""
  local yellow, grey = c.yellow or st.from, c.grey or st.to
  local green = math.floor((yellow + grey) / 2)
  local lo = math.min(st.from, c.learnAt or st.from, yellow)
  local mats = {}
  for _, g in ipairs(c.recipe.reagents or {}) do
    mats[#mats + 1] = { key = "lvm:" .. g[1], item = g[1], count = g[2] * st.crafts }
  end
  return {
    item = c.recipe.product,
    subtitle = L["Skill %d to %d · %s · ~%d crafts"]:format(st.from, st.to, known, st.crafts),
    bar = { lo = lo, yellow = yellow, green = green, grey = grey, hi = grey + 10, from = st.from, to = st.to },
    crafts = st.crafts,
    mats = mats,
    net = st.net,
  }
end

-- ------------------------------------------------------------------------------------------------ status lines

function CP.Status(f, filter, profession, counts)
  counts = counts or {}
  local chars = 0
  for _ in pairs(f.chars or {}) do
    chars = chars + 1
  end
  if filter == "queued" then
    local q = CP.Queue(f)
    if #q.steps == 0 then
      return L["Nothing queued · the queue is kept per account"]
    end
    return L["%d crafts queued in %d steps on %d characters · the queue is kept per account"]:format(
      q.crafts,
      #q.steps,
      math.max(1, q.chars)
    )
  elseif filter == "learn" then
    return L["%d recipes your characters could learn · seen in scans of the last %d days, and at vendors"]:format(
      counts.shown or 0,
      CP.LISTING_DAYS
    )
  elseif filter == "ready" then
    return L["%d recipes ready now · counted from bags, bank and mail on %d characters"]:format(
      counts.shown or 0,
      chars
    )
  elseif filter == "missing" then
    return L["%d recipes are one thing short · counted from bags, bank and mail on %d characters"]:format(
      counts.shown or 0,
      chars
    )
  end
  if profession then
    local p = CP.ProfessionOf(f, profession)
    local parts = {
      p and p.name or "?",
      p and charName(p.key) or "?",
      tostring(p and p.skill or 0),
      counts.sections and counts.sections > 0 and L["%d recipes in %d sections"]:format(
        counts.total or 0,
        counts.sections
      ) or L["%d recipes"]:format(counts.total or 0),
      L["%d ready now"]:format(counts.ready or 0),
    }
    if (counts.queued or 0) > 0 then
      parts[#parts + 1] = L["%d queued"]:format(counts.queued)
    end
    return table.concat(parts, " · ")
  end
  local profs = 0
  for _, g in ipairs(CP.Professions(f.chars)) do
    profs = profs + #g.list
  end
  return L["%d recipes across %d professions · %d ready now"]:format(counts.total or 0, profs, counts.ready or 0)
end

-- ------------------------------------------------------------------------------------------------ gathering

local function try(fn, ...)
  return ns.Shield(fn, ...) -- a failing piece is left out; its error goes to the game's handler (BugSack)
end

local function call(api, name, ...)
  local fn = api and api[name]
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b = pcall(fn, ...)
  if ok then
    return a, b
  end
end

-- the open profession window, as the game says: per recipe learned, how many it can make, its skill-up colour,
-- its section, whether it's a favourite and which requirements are met; the sections. nil when none is open (or a
-- linked / guild window).
-- a value the game keeps secret (the modern client's protected values) reads as nil: it can't be compared or be a
-- table key (as Professions does)
local function plain(v)
  local secret = _G.issecretvalue
  if secret and secret(v) then
    return nil
  end
  return v
end

function CP.Live(api)
  if not api or call(api, "IsTradeSkillReady") == false then
    return nil
  end
  if call(api, "IsTradeSkillLinked") or call(api, "IsTradeSkillGuild") or call(api, "IsNPCCrafting") then
    return nil
  end
  local p = call(api, "GetBaseProfessionInfo")
  local skillLine = type(p) == "table" and plain(p.professionID)
  if not skillLine or skillLine == 0 then
    return nil
  end
  local out = { skillLine = skillLine, name = plain(p.professionName), recipes = {}, categories = {} }
  for _, id in ipairs(call(api, "GetAllRecipeIDs") or {}) do
    local info = call(api, "GetRecipeInfo", id)
    if type(info) == "table" and plain(id) then
      local reqs
      for _, req in ipairs(call(api, "GetRecipeRequirements", id) or {}) do
        local rname = type(req) == "table" and plain(req.name)
        if type(rname) == "string" then
          reqs = reqs or {}
          reqs[rname] = plain(req.met) and true or false
        end
      end
      local diff = plain(info.relativeDifficulty)
      out.recipes[id] = {
        learned = plain(info.learned) and true or false,
        available = plain(info.numAvailable) or 0,
        diff = diff ~= nil and CP.RELATIVE[diff] or nil,
        cat = plain(info.categoryID),
        fav = plain(info.favorite) and true or false,
        requirements = reqs,
      }
      local cat = plain(info.categoryID)
      while cat and not out.categories[cat] do
        local c = call(api, "GetCategoryInfo", cat)
        if type(c) ~= "table" then
          break
        end
        local parent = plain(c.parentCategoryID)
        out.categories[cat] = { name = plain(c.name), order = plain(c.uiOrder), parent = parent }
        cat = parent ~= 0 and parent or nil
      end
    end
  end
  return out
end

-- the learn rows: recipe items on the AH lately (as Home's "Worth doing today" finds them) and ones seen at a vendor
local function learnRows(m)
  local data = ns.CraftingData
  if not (data and data.Teaches) then
    return {}
  end
  local listings, via = {}, {}
  for id, s in pairs(m.index.items or {}) do
    if
      data:Teaches(id)
      and s.min
      and (s.qty or 0) > 0
      and (not m.index.day or not s.day or m.index.day - s.day <= CP.LISTING_DAYS)
    then
      listings[#listings + 1] = { item = id, price = s.min }
      via[id] = { via = "ah" }
    end
  end
  for id, list in pairs(AME_DB and AME_DB.recipeSources or {}) do
    if not via[id] and data:Teaches(id) then
      for _, src in ipairs(list) do
        if src.kind == "vendor" and src.price and not via[id] then
          listings[#listings + 1] = { item = id, price = src.price }
          via[id] = { via = "vendor", where = src.zone and (src.npc .. ", " .. src.zone) or src.npc }
        end
      end
    end
  end
  local me = ns.Trading.CharKey()
  local function knows(key, spell)
    return key == me and _G.IsPlayerSpell and _G.IsPlayerSpell(spell) or false
  end
  local rows = m.craft:RecipesToBuy(listings, function(id)
    return data:Teaches(id)
  end, ns.Recipes.Get, m.chars, knows)
  for _, r in ipairs(rows) do
    r.via, r.where = via[r.item].via, via[r.item].where
    r.teaches = data:Teaches(r.item)
  end
  return rows
end

-- The game's sections, kept per profession when a window opens (any character's: the sections are the same):
-- AME_DB.craftingPage.sections[skillLine] = { cats = { [categoryID] = { name, order, parent } }, recipes = { [id] =
-- categoryID } }. Pure: state and live passed in.
function CP.RecordSections(state, live)
  if not (live and live.skillLine and next(live.categories or {})) then
    return false
  end
  state.sections = state.sections or {}
  local s = { cats = live.categories, recipes = {} }
  for id, r in pairs(live.recipes or {}) do
    s.recipes[id] = r.cat
  end
  state.sections[live.skillLine] = s
  return true
end

function CP.RecordLive()
  local live = try(CP.Live, _G.C_TradeSkillUI)
  if live and AME_DB then
    try(CP.RecordSections, CP.State(), live)
  end
end

if CreateFrame then
  local events = CreateFrame("Frame")
  for _, e in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_DATA_SOURCE_CHANGED" }) do
    pcall(events.RegisterEvent, events, e)
  end
  local pending = false
  events:SetScript("OnEvent", function()
    if pending or not (C_Timer and C_Timer.After) then
      return
    end
    pending = true -- the list fires in bursts: once, a moment after
    C_Timer.After(0.5, function()
      pending = false
      CP.RecordLive()
    end)
  end)
end

local function recipeCat(skillLine, id)
  local s = CP.State().sections
  s = s and s[skillLine]
  return s and s.recipes[id]
end

function CP.Categories(f, skillLine)
  if f.live and f.live.skillLine == skillLine and next(f.live.categories) then
    return f.live.categories
  end
  local s = CP.State().sections
  return s and s[skillLine] and s[skillLine].cats
end

local function profName(skillLine)
  local db = AME_DB.crafting
  local c = db and db.catalog and db.catalog[skillLine]
  if c and c.name then
    return c.name
  end
  for _, ch in pairs(ns.Professions:Characters()) do
    local p = ch.professions and ch.professions[skillLine]
    if p and p.name then
      return p.name
    end
  end
  return skillLine and tostring(skillLine) or "?"
end

-- the tool's ways, through the old view's CraftTools with Trading.Held shaped as it reads it ({ [char] = n })
local function toolWays(q)
  local UI = ns.UI
  if not (UI and UI.CraftTools and UI.CraftToolsEnv) then
    return nil
  end
  local env = UI.CraftToolsEnv()
  env.held = function(id)
    local h = ns.Trading.Held(id)
    local chars = {}
    for _, c in ipairs(h.chars or {}) do
      chars[c.name] = (c.bags or 0) + (c.bank or 0) + (c.mail or 0)
    end
    return { total = h.total, chars = chars }
  end
  local ok, t = pcall(UI.CraftTools, { tools = { q.name }, toolIDs = { [q.name] = q.id } }, env)
  return ok and t and CP.WaysLine(t.tools[1]) or nil
end

function CP.Gather()
  CP.errors = {}
  local f = { chars = ns.Professions and ns.Professions:Characters() or {}, entries = {}, held = {} }
  f.me = ns.Trading and ns.Trading.CharKey and ns.Trading.CharKey() or "?"
  f.recipeName = function(id)
    return ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(id) or tostring(id)
  end
  f.itemName = function(id)
    return ns.ItemCache and ns.ItemCache.Name and ns.ItemCache.Name(id) or nil
  end
  f.recipe = function(id)
    return ns.Recipes.Get(id)
  end
  f.profName = profName
  f.recipeCat = recipeCat
  f.keyByName = function(name)
    return ns.ItemCache and ns.ItemCache.KeyByName and ns.ItemCache.KeyByName(name) or nil
  end
  f.heldOf = function(id)
    return f.held[id] or 0
  end
  f.toolWays = toolWays
  f.live = try(CP.Live, _G.C_TradeSkillUI)
  if f.live then
    CP.RecordSections(CP.State(), f.live)
  end
  AME_DB.craftQueue = AME_DB.craftQueue or {}
  f.queue = ns.CraftQueue.New(AME_DB.craftQueue).db
  local m = try(ns.CraftModel.Build)
  if not m then
    f.loading = true
    return f
  end
  f.m, f.craft, f.quote = m, m.craft, m.quote
  f.held = m.held or {}
  f.entries = try(m.craft.TopEarners, m.craft, m.entries, m.heldSet) or m.entries
  if #f.queue.items > 0 and ns.ProfessionBar and ns.ProfessionBar.Plan then
    f.plan = try(ns.ProfessionBar.Plan)
  end
  f.learnRows = nil -- worked out when To learn is shown (CP.LearnRows)
  f.usual = function(id)
    local s = m.index.items[id]
    return s and (s.avg30 or s.avg7)
  end
  f.guildCrafters = function(spell)
    local shared = ns.Crafters and ns.Crafters.Shared and ns.Crafters.Shared()
    local n = 0
    for _, c in ipairs(shared and shared:WhoKnows(spell) or {}) do
      if not c.mine then
        n = n + 1
      end
    end
    return n
  end
  return f
end

function CP.LearnRows(f)
  if f.learnRows == nil and f.m then
    f.learnRows = try(learnRows, f.m) or {}
  end
  return f.learnRows or {}
end

-- plans for a character's profession under every goal (as the old Leveling page worked them out)
function CP.LevelingPlans(f, choice, target)
  local m = f.m
  if not (m and choice and ns.Leveling) then
    return nil
  end
  local craft = m.craft
  local enchanter = false
  for _, c in pairs(m.chars or {}) do
    enchanter = enchanter or (c.professions and c.professions[333]) ~= nil
  end
  local deValue = enchanter
      and function(id)
        local de = ns.ItemCache.Get(id).name and m.quote:Disenchant(id)
        return de and de.value
      end
    or nil
  local shard = ns.AME and ns.AME.FactionShard and ns.AME:FactionShard()
  local buyCost = function(id, units)
    local book = shard and ns.AME.BookFor and ns.AME:BookFor(shard, id, 2 * 86400)
    if not (book and ns.Depth) then
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
  local held = {}
  for id, e in pairs(ns.Holdings.Of("usable", choice.key)) do
    held[id] = e.qty
  end
  local list = ns.Leveling.Candidates(choice.profession, choice.p, m.index.items, m.index.day)
  local plans = {}
  for _, g in ipairs(CP.GOALS) do
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
  return plans
end
