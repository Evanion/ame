-- The Guild tab's model (boards GuildNav, CraftingCrafters, GuildRequests, GuildOffers, GuildLists, Sync): pure
-- functions that turn what AME knows into the rows and lines the screens draw, and a few readers of the game's
-- state (GuildPage.Price, GuildPage.Professions, ...) kept defensive, as Core/Home.lua does.
--
--   GuildPage.Nav(active, counts) -> sidebar entries      the Guild pages, with the requests waiting on you
--   GuildPage.RecipeRows(results, info) / CrafterRows(who, opts)     Crafters: who can make it
--   GuildPage.RequestRow(r, now, env) / Strip(r) / MatRows(r, price) / WorthRows(r, w) / Actions(r)   Requests
--   GuildPage.OfferRows(crafts, env) / Month(list, now) / Advert(char, profession, skill, items)   Your crafts
--   GuildPage.ListRows(lists, now, me) / ListItems(items, price)                    Guild lists
-- Rows are table rows (Core/UI/Parts/Table.lua): { key, item?, [column] = value }.
local _, ns = ...
local L = ns.L

local GuildPage = {}
ns.GuildPage = GuildPage

local R = ns.CraftRequests

local function ago(t, now)
  if not t then
    return ""
  end
  return ns.Widgets and ns.Widgets.Age and ns.Widgets.Age(t, now) or tostring(now - t)
end

local function g(copper)
  return ns.Widgets and ns.Widgets.Money and ns.Widgets.Money(copper, true) or tostring(copper)
end

local function dot(name, online)
  return { text = "● " .. tostring(name), color = online and "good" or "dim" }
end
GuildPage.Dot = dot

-- ------------------------------------------------------------------------------------------------ the nav

GuildPage.PAGES = { "guild", "requests", "offers", "guildlists", "sharing" }

function GuildPage.Nav(active, counts)
  counts = counts or {}
  local function page(key, label, count)
    return { key = key, label = label, count = count and count > 0 and count or nil, selected = active == key }
  end
  return {
    { heading = true, label = L["Crafting together"] },
    page("guild", L["Crafters"]),
    page("requests", L["Requests"], counts.requests),
    page("offers", L["Your crafts"]),
    { heading = true, label = L["Shared"] },
    page("guildlists", L["Guild lists"], counts.lists),
    page("sharing", L["Sharing prices"]),
  }
end

-- ------------------------------------------------------------------------------------------------ professions

GuildPage.PROFESSIONS = {
  [171] = L["Alchemy"],
  [164] = L["Blacksmithing"],
  [185] = L["Cooking"],
  [333] = L["Enchanting"],
  [202] = L["Engineering"],
  [129] = L["First Aid"],
  [755] = L["Jewelcrafting"],
  [773] = L["Inscription"],
  [165] = L["Leatherworking"],
  [186] = L["Mining"],
  [197] = L["Tailoring"],
}

-- a skill line's name: as your characters' windows recorded it, else the classic names
function GuildPage.ProfessionName(skillLine)
  for _, c in pairs(AME_DB and AME_DB.crafting and AME_DB.crafting.chars or {}) do
    local p = c.professions and c.professions[skillLine]
    if p and p.name then
      return p.name
    end
  end
  return GuildPage.PROFESSIONS[skillLine] or ""
end

-- ------------------------------------------------------------------------------------------------ crafters

-- results: Crafters:Search(); info(recipe) -> { item?, profession? } -> rows { key, item?, name, prof, n }
function GuildPage.RecipeRows(results, info)
  local rows = {}
  for _, r in ipairs(results or {}) do
    local i = info and info(r.recipe) or {}
    rows[#rows + 1] = {
      key = tostring(r.recipe),
      recipe = r.recipe,
      item = i.item,
      name = r.name,
      prof = { text = i.profession or "", color = "dim" },
      n = #(r.who or {}),
    }
  end
  return rows
end

-- the crafters of one recipe: yours first, then online; Ask on everyone but your own characters.
-- opts = { trusted = fn(owner) -> bool } -> rows { key, crafter, skill, ask }
function GuildPage.CrafterRows(who, opts)
  opts = opts or {}
  local rows = {}
  for _, c in ipairs(who or {}) do
    local name = c.name
    if c.mine then
      name = L["%s (yours)"]:format(c.name)
    elseif opts.trusted and c.owner and opts.trusted(c.owner) then
      name = L["%s (trusted)"]:format(c.name)
    end
    rows[#rows + 1] = {
      key = c.name,
      crafter = dot(name, c.online),
      skill = c.skill and tostring(c.skill) or "",
      ask = not c.mine and L["Ask"] or false,
      mine = c.mine,
    }
  end
  return rows
end

-- "Enchanting · 8 can make it · online first"
function GuildPage.RecipeSub(profession, n)
  local parts = {}
  if profession and profession ~= "" then
    parts[#parts + 1] = profession
  end
  parts[#parts + 1] = n == 1 and L["1 can make it"] or L["%d can make it"]:format(n or 0)
  parts[#parts + 1] = L["online first"]
  return table.concat(parts, " · ")
end

-- ------------------------------------------------------------------------------------------------ requests

-- where a request stands, in words for the side that reads it: text, tone
function GuildPage.StateText(r)
  local side, s = r.side, r.state
  local them = side == "crafter" and r.asker or r.crafter
  if s == "new" then
    if side == "crafter" then
      return L["new"], "warn"
    end
    return L["sent · waiting for %s"]:format(them), "dim"
  elseif s == "answered" then
    if R.ToAct(r) == side then
      return L["answered · yours to approve"], "warn"
    end
    return L["answered · waiting for %s"]:format(them), "dim"
  elseif s == "accepted" then
    return side == "crafter" and L["accepted · queued"] or L["accepted · being made"], "good"
  elseif s == "crafted" then
    return side == "crafter" and L["crafted · hand them over"] or L["crafted · collect them"], "link"
  elseif s == "handed" then
    return L["handed over · tip paid"], "dim"
  elseif s == "declined" then
    return L["declined"], "bad"
  elseif s == "withdrawn" then
    return L["withdrawn"], "dim"
  end
  return tostring(s), "dim"
end

-- who brings the mats, for the side that reads it
function GuildPage.MatsText(r)
  local b = R.Brings(r)
  local past = r.state == "crafted" or r.state == "handed"
  if r.side == "crafter" then
    if b == "all" then
      return past and L["brought"] or L["brings them"]
    elseif b == "none" then
      return L["you provide"]
    end
    return b == "most" and L["brings most"] or L["brings some"]
  end
  if b == "all" then
    return past and L["you brought them"] or L["you bring them"]
  elseif b == "none" then
    return L["%s provides"]:format(r.crafter)
  end
  return b == "most" and L["you bring most"] or L["you bring some"]
end

-- one request as a table row. env = { online = fn(name) -> bool, name = fn(r) -> text (an enchant: the recipe) }
function GuildPage.RequestRow(r, now, env)
  env = env or {}
  local them = r.side == "crafter" and r.asker or r.crafter
  local text, tone = GuildPage.StateText(r)
  return {
    key = r.id,
    item = r.item,
    name = env.name and env.name(r) or nil,
    qty = r.count,
    who = dot(them, env.online and env.online(them)),
    mats = GuildPage.MatsText(r),
    tip = r.tip or 0,
    yours = r.crafter,
    state = { text = text, color = tone },
    ago = ago(r.at, now),
    faded = R.ENDED[r.state] or nil,
  }
end

-- the two tables: asked of you (your characters craft), you asked; newest change first, ended ones last
function GuildPage.Split(list, now, env)
  local into, out = {}, {}
  local sorted = {}
  for _, r in ipairs(list or {}) do
    sorted[#sorted + 1] = r
  end
  table.sort(sorted, function(a, b)
    local ea, eb = R.ENDED[a.state] and 1 or 0, R.ENDED[b.state] and 1 or 0
    if ea ~= eb then
      return ea < eb
    end
    return (a.changed or 0) > (b.changed or 0)
  end)
  for _, r in ipairs(sorted) do
    local row = GuildPage.RequestRow(r, now, env)
    if r.side == "crafter" then
      into[#into + 1] = row
    else
      out[#out + 1] = row
    end
  end
  return into, out
end

-- the state strip: new > answered > accepted > crafted > handed over, the current one lit
function GuildPage.Strip(r)
  local labels = { L["new"], L["answered"], L["accepted"], L["crafted"], L["handed over"] }
  local current = 0
  for i, s in ipairs(R.ORDER) do
    if s == r.state then
      current = i
    end
  end
  local ended
  if r.state == "declined" then
    ended = L["declined"]
  elseif r.state == "withdrawn" then
    ended = L["withdrawn"]
  end
  return { steps = labels, current = current, ended = ended }
end

-- the mats: { key, item, need, copper (all of it at market) }
function GuildPage.MatRows(r, price)
  local rows = {}
  for i, m in ipairs(r.reagents or {}) do
    local p = price and price(m.item)
    rows[i] = { key = tostring(i), item = m.item, need = m.need, copper = p and p * (m.need or 0) or nil }
  end
  return rows
end

-- What it's worth: what they sell for, the mats, what the craft adds, the tip. each: one product's price (nil: an
-- enchant), price(item) -> copper -> keyvalue props
function GuildPage.WorthRows(r, each, price)
  local mats, priced = 0, true
  for _, m in ipairs(r.reagents or {}) do
    local p = price and price(m.item)
    if p then
      mats = mats + p * (m.need or 0)
    else
      priced = false
    end
  end
  local rows = {}
  if each then
    rows[#rows + 1] = { label = L["%d sell for"]:format(r.count or 1), copper = each * (r.count or 1) }
  end
  rows[#rows + 1] =
    { label = L["The mats, at market"], copper = priced and mats or nil, text = not priced and "—" or nil }
  if each and priced then
    rows[#rows + 1] = { label = L["The craft adds"], copper = each * (r.count or 1) - mats, signed = true }
  end
  rows[#rows + 1] =
    { label = r.side == "crafter" and L["Offered tip"] or L["Your tip"], copper = r.tip or 0, total = true }
  return rows
end

-- the picked request's buttons and the line over them: { buttons = { { label, action, variant? } }, rule }
function GuildPage.Actions(r)
  local side, s = r.side, r.state
  local them = side == "crafter" and r.asker or r.crafter
  local b, rule = {}, nil
  local mine = R.ToAct(r) == side
  if side == "crafter" then
    if (s == "new" or s == "answered") and mine then
      b = {
        { L["Answer"], "answer", "primary" },
        { L["Accept as asked"], "accept" },
        { L["Decline"], "decline" },
      }
      rule =
        L["Answer opens the request: accept it as asked, or change your price for the mats or the tip and send it back for %s to approve. Once agreed it goes on %s's queue; trading it over marks it handed over."]:format(
          them,
          r.crafter
        )
    elseif s == "answered" then
      b = { { L["Decline"], "decline" } }
      rule = L["You changed the terms: %s approves them, changes them, or withdraws."]:format(them)
    elseif s == "accepted" then
      b = { { L["Made it"], "crafted", "primary" }, { L["Handed over"], "handed" }, { L["Decline"], "decline" } }
      rule = L["Agreed: it is on %s's queue. Made it tells %s it is ready."]:format(r.crafter, them)
    elseif s == "crafted" then
      b = { { L["Handed over"], "handed", "primary" } }
      rule = L["Trade it to %s; Handed over closes the request."]:format(them)
    end
  else
    if s == "answered" and mine then
      b = {
        { L["Review"], "answer", "primary" },
        { L["Accept"], "accept" },
        { L["Withdraw"], "decline" },
      }
      rule =
        L["%s changed the terms. Review shows what changed: accept them, change them back, or withdraw."]:format(them)
    elseif s == "new" or s == "answered" then
      b = { { L["Change it"], "change" }, { L["Withdraw"], "decline" } }
      rule =
        L["Waiting for %s to answer. A request also goes out as a whisper, so a crafter without AME still sees it."]:format(
          them
        )
    elseif s == "accepted" then
      b = { { L["Withdraw"], "decline" } }
      rule = L["Agreed: %s makes it and tells you when it is ready."]:format(them)
    elseif s == "crafted" then
      b = { { L["Handed over"], "handed", "primary" } }
      rule = L["Ready: trade with %s to collect it, with the tip."]:format(them)
    end
  end
  if R.ENDED[s] then
    b = { { L["Remove"], "remove" } }
    rule = L["Handed over and declined requests clear after a week."]
  end
  local out = {}
  for i, v in ipairs(b) do
    out[i] = { label = v[1], action = v[2], variant = v[3] }
  end
  return { buttons = out, rule = rule }
end

-- the card over the picked request: "5 for Zakzu · asked 12 min ago"
function GuildPage.RequestSub(r, now)
  local for_ = r.side == "crafter" and L["%d for %s"]:format(r.count, r.asker)
    or L["%d from %s"]:format(r.count, r.crafter)
  local when = ns.Widgets and ns.Widgets.Ago and ns.Widgets.Ago(r.at, now) or ""
  return for_ .. " · " .. L["asked %s"]:format(when)
end

-- ------------------------------------------------------------------------------------------------ your crafts

-- crafts: { { recipe, item?, name, who = { charName, ... } } }; env = { asked = fn(recipe) -> n, mats = fn(recipe)
-- -> copper?, tip = fn(recipe) -> copper? } -> rows, most asked first, then the dearest mats
function GuildPage.OfferRows(crafts, env)
  env = env or {}
  local rows = {}
  for _, c in ipairs(crafts or {}) do
    local tip = env.tip and env.tip(c.recipe)
    rows[#rows + 1] = {
      key = tostring(c.recipe),
      recipe = c.recipe,
      item = c.item,
      name = c.name,
      yours = table.concat(c.who or {}, ", "),
      asked = env.asked and env.asked(c.recipe) or 0,
      mats = env.mats and env.mats(c.recipe) or nil,
      tip = tip and g(tip) or { text = L["suggested"], color = "dim" },
    }
  end
  table.sort(rows, function(a, b)
    if a.asked ~= b.asked then
      return a.asked > b.asked
    end
    if (a.mats or 0) ~= (b.mats or 0) then
      return (a.mats or 0) > (b.mats or 0)
    end
    return tostring(a.name) < tostring(b.name)
  end)
  return rows
end

-- This month: requests to your characters, how many were done, the tips they brought
function GuildPage.Month(list, now)
  local asked, done, tips = 0, 0, 0
  for _, r in ipairs(list or {}) do
    if r.side == "crafter" and now - (r.at or 0) < 30 * 86400 then
      asked = asked + 1
      if r.state == "handed" then
        done, tips = done + 1, tips + (r.tip or 0)
      end
    end
  end
  return {
    { label = L["Requests to you"], text = tostring(asked) },
    { label = L["Done"], text = tostring(done) },
    { label = L["Tips"], copper = tips },
  }
end

-- the advert: shown as parts (item links), and sent as text with the game's links. link(item) -> the item's link
function GuildPage.Advert(char, profession, skill, items, link)
  local head = L["%s (%s %s) is taking orders:"]:format(char, profession, tostring(skill or ""))
  local parts, text = { head }, { head }
  for _, id in ipairs(items or {}) do
    parts[#parts + 1] = " "
    parts[#parts + 1] = { item = id }
    text[#text + 1] = link and link(id) or ("item:" .. id)
  end
  local tail = L["Whisper me, or ask through AME."]
  parts[#parts + 1] = " " .. tail
  text[#text + 1] = tail
  return parts, table.concat(text, " ")
end

-- ------------------------------------------------------------------------------------------------ guild lists

-- lists = { watch = Watch:GuildLists(), shopping = Shopping:GuildLists(), mineWatch = { { i, name, n, t } },
-- mineShopping = (the same) }; online(name) -> bool -> rows { key, list, kind, by, items, changed, act }
function GuildPage.ListRows(lists, now, online)
  local rows = {}
  local function count(items)
    local n = 0
    for _ in pairs(items or {}) do
      n = n + 1
    end
    return n
  end
  for _, l in ipairs(lists.shopping or {}) do
    rows[#rows + 1] = {
      key = "s:" .. l.key,
      list = l.name,
      kind = { text = L["Shopping list"], color = "dim" },
      by = dot(l.owner, online and online(l.owner)),
      items = count(l.items),
      changed = L["%s ago"]:format(ago(l.t, now)),
      act = L["Copy"],
      t = l.t,
    }
  end
  for _, l in ipairs(lists.watch or {}) do
    rows[#rows + 1] = {
      key = "w:" .. l.key,
      list = l.name,
      kind = { text = L["Watchlist"], color = "dim" },
      by = dot(l.owner, online and online(l.owner)),
      items = count(l.items),
      changed = L["%s ago"]:format(ago(l.t, now)),
      act = L["Copy"],
      t = l.t,
    }
  end
  table.sort(rows, function(a, b)
    return (a.t or 0) > (b.t or 0)
  end)
  for _, l in ipairs(lists.mineShopping or {}) do
    rows[#rows + 1] = {
      key = "ms:" .. l.i,
      list = l.name,
      kind = { text = L["Shopping list"], color = "dim" },
      by = { text = L["you"], color = "gold" },
      items = l.n or 0,
      changed = "",
      act = L["Stop sharing"],
    }
  end
  for _, l in ipairs(lists.mineWatch or {}) do
    rows[#rows + 1] = {
      key = "mw:" .. l.i,
      list = l.name,
      kind = { text = L["Watchlist"], color = "dim" },
      by = { text = L["you"], color = "gold" },
      items = l.n or 0,
      changed = "",
      act = L["Stop sharing"],
    }
  end
  return rows
end

-- a list's items: { [key] = true } (a watchlist) or { [key] = { need, max } } (a shopping list)
function GuildPage.ListItems(items, price)
  local rows = {}
  for key, e in pairs(items or {}) do
    rows[#rows + 1] = {
      key = tostring(key),
      item = key,
      need = type(e) == "table" and e.need or nil,
      market = price and price(key) or nil,
    }
  end
  table.sort(rows, function(a, b)
    if (a.need or 0) ~= (b.need or 0) then
      return (a.need or 0) > (b.need or 0)
    end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows
end

-- ------------------------------------------------------------------------------------------------ the game

-- an item's price on your faction's auction house, or nil before there's an index
function GuildPage.Price()
  local AME = ns.AME
  local index = AME and AME.FactionIndex and AME:FactionIndex()
  if not index then
    return function()
      return nil
    end
  end
  local ok, q = pcall(ns.Quote.For, AME:FactionShard(), index)
  if not ok or not q then
    return function()
      return nil
    end
  end
  return function(id)
    local okp, p = pcall(q.Price, q, id)
    return okp and p or nil
  end
end

-- what your characters on this market hold to craft with
function GuildPage.Held()
  local ok, map = pcall(ns.Holdings.Of, "usable", "market")
  map = ok and map or {}
  return function(id)
    local e = map[id]
    return e and e.qty or 0
  end
end

function GuildPage.Soulbound(id)
  local e = ns.ItemCache and ns.ItemCache.Get and ns.ItemCache.Get(id)
  return e and e.bind == 1 or false
end

-- what a recipe makes and its profession
function GuildPage.RecipeInfo(recipeID)
  local r = ns.Recipes and ns.Recipes.Get(recipeID)
  local d = not r and ns.CraftingData and ns.CraftingData.Recipe and ns.CraftingData:Recipe(recipeID)
  local prof = (r and r.profession) or (d and d.profession)
  return {
    item = (r and r.product) or (d and d.product) or nil,
    profession = prof and GuildPage.ProfessionName(prof) or "",
  }
end

-- the name to show for a request with no product (an enchant)
function GuildPage.RequestName(r)
  return ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(r.recipe) or tostring(r.recipe)
end

-- your characters' crafts on this market: { { recipe, item?, name, who = { charName } } }; taking orders limits it
-- to the professions ticked (none ticked: all of them)
function GuildPage.MyCrafts(taking)
  local byRecipe, out = {}, {}
  local any = taking and next(taking) ~= nil
  local gathering = ns.CraftModel and ns.CraftModel.GATHERING or {}
  for name, c in pairs(ns.Crafters and ns.Crafters.Mine() or {}) do
    for skillLine, p in pairs(c.profs or {}) do
      if not gathering[skillLine] and (not any or taking[name .. ":" .. skillLine]) then
        for id in pairs(p.ids or {}) do
          local e = byRecipe[id]
          if not e then
            local info = GuildPage.RecipeInfo(id)
            e = { recipe = id, item = info.item, name = ns.Crafters.RecipeName(id) or tostring(id), who = {} }
            byRecipe[id] = e
            out[#out + 1] = e
          end
          e.who[#e.who + 1] = name
        end
      end
    end
  end
  return out
end

-- your characters' professions: { { key = "<char>:<skillLine>", char, skillLine, name, skill } }
function GuildPage.MyProfessions()
  local out = {}
  local gathering = ns.CraftModel and ns.CraftModel.GATHERING or {}
  for name, c in pairs(ns.Crafters and ns.Crafters.Mine() or {}) do
    for skillLine, p in pairs(c.profs or {}) do
      if not gathering[skillLine] and next(p.ids or {}) then
        out[#out + 1] = {
          key = name .. ":" .. skillLine,
          char = name,
          skillLine = skillLine,
          name = GuildPage.ProfessionName(skillLine),
          skill = p.skill,
        }
      end
    end
  end
  table.sort(out, function(a, b)
    return a.key < b.key
  end)
  return out
end
