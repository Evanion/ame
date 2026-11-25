-- The craft request frames (boards RequestForm, RequestAnswer, RequestReview): one frame of their own beside the
-- window, drawn by its own Layout.Renderer. Ask (Guild > Crafters) opens the form; Answer and Review (Guild >
-- Requests) open the answer, from the crafter's side or the asker's. The model is Core/CraftRequests.lua.
--
--   Requests.Ask(recipeID, crafter, note)   write a request to a crafter (note: "online · Enchanting 300")
--   Requests.Change(id)                     the asker changes their request (the form, filled in from it)
--   Requests.Answer(id)                     answer or review a request
--   Requests.FormTree(d, s) / AnswerTree(r, a)   the trees (pure: the specs validate them)
local _, ns = ...
local L = ns.L

local Layout = ns.Layout
local R = ns.CraftRequests

local Q = { W = 500, FORM_H = 480, ANSWER_H = 520 }
ns.Requests = Q

-- money as you'd type it: "46g", "45s", "1g 20s", "15c"
local function typed(copper)
  copper = math.floor(copper or 0)
  local gold, silver, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if gold > 0 then
    out[#out + 1] = gold .. "g"
  end
  if silver > 0 then
    out[#out + 1] = silver .. "s"
  end
  if c > 0 or #out == 0 then
    out[#out + 1] = c .. "c"
  end
  return table.concat(out, " ")
end
Q.Typed = typed

local function itemName(id)
  return id and ns.ItemCache and ns.ItemCache.Name(id) or nil
end

local function g(copper)
  return ns.Widgets.Money(copper or 0, true)
end

-- what's being made: the product's link, or (an enchant) the recipe's name
local function whatItem(id, item, recipe, size)
  if item then
    return {
      id = id,
      type = "itemlink",
      props = { item = item, size = size or 13, bold = true },
      meta = { grow = 1, h = 18 },
    }
  end
  local name = ns.Crafters and ns.Crafters.RecipeName and ns.Crafters.RecipeName(recipe) or tostring(recipe)
  return {
    id = id,
    type = "text",
    props = { text = name or "?", color = "white", size = size or 13 },
    meta = { grow = 1, h = 18 },
  }
end

local function text(id, s, opts)
  opts = opts or {}
  return {
    id = id,
    type = "text",
    props = { text = s or "", color = opts.color, size = opts.size or 11, justify = opts.justify, wrap = opts.wrap },
    meta = opts.meta,
  }
end

-- ------------------------------------------------------------------------------------------------ the form

-- d: a draft (CraftRequests.Draft); s = { crafter, note, change (true: changing your request) }
function Q.FormTree(d, s)
  local crafter = s.crafter or "?"
  local rows = {
    {
      id = "rf.head",
      type = "grid",
      props = { widths = { 18, 0, 40, 60 }, gap = 10 },
      meta = { h = 18 },
      children = {
        { id = "rf.head.0", type = "spacer" },
        text("rf.head.1", L["Reagent · tick what you bring"], { color = "heading" }),
        text("rf.head.2", L["Need"], { color = "heading", justify = "RIGHT" }),
        text("rf.head.3", L["You bring"], { color = "heading", justify = "RIGHT" }),
      },
    },
    { id = "rf.headrule", type = "divider", meta = { h = 1 } },
  }
  local supplies = {}
  for i, row in ipairs(d.rows) do
    local p = "rf.r" .. i
    local sub, tone
    if row.soulbound then
      sub, tone = L["soulbound: %s supplies it"]:format(crafter), "warn"
    else
      sub = L["you hold %d"]:format(row.hold or 0)
      if (row.supply or 0) > 0 then
        sub, tone = sub .. " · " .. L["%s supplies %d"]:format(crafter, row.supply), "warn"
      end
    end
    if (row.supply or 0) > 0 then
      supplies[#supplies + 1] = row
    end
    rows[#rows + 1] = {
      id = p,
      type = "grid",
      props = { widths = { 18, 0, 40, 60 }, gap = 10, rowH = 36 },
      meta = { h = 36 },
      children = {
        row.soulbound and { id = p .. ".tick", type = "spacer" }
          or { id = p .. ".tick", type = "check", props = { checked = row.checked, action = "tick", payload = i } },
        {
          id = p .. ".name",
          type = "column",
          props = { gap = 1 },
          children = {
            { id = p .. ".item", type = "itemlink", props = { item = row.item, size = 12 }, meta = { h = 17 } },
            text(p .. ".sub", sub, { color = tone or "dim", meta = { h = 14 } }),
          },
        },
        text(p .. ".need", tostring(row.need), { justify = "RIGHT", size = 12 }),
        row.soulbound and text(p .. ".bring", "—", { justify = "RIGHT", color = "dim" }) or {
          id = p .. ".bring",
          type = "input",
          props = {
            value = tostring(row.bring or 0),
            hint = L["How many you bring"],
            numeric = true,
            action = "bring",
            payload = i,
          },
          meta = { h = 24 },
        },
      },
    }
  end
  local supplyParts = { { text = L["%s supplies"]:format(crafter) .. " ", tone = "text" } }
  if #supplies == 0 then
    supplyParts[#supplyParts + 1] = L["nothing: you bring it all"]
  else
    for i, row in ipairs(supplies) do
      supplyParts[#supplyParts + 1] = (i > 1 and ", " or "") .. row.supply .. " "
      supplyParts[#supplyParts + 1] = { item = row.item }
    end
    supplyParts[#supplyParts + 1] = " · " .. L["%s at market"]:format(g(d.market))
  end
  rows[#rows + 1] =
    { id = "rf.supply", type = "linktext", props = { parts = supplyParts, wrap = true }, meta = { h = 16 } }

  local offerNote = L["the market price; %s can change it"]:format(crafter)
  if d.offerSet and d.offer ~= R.Round(d.market or 0) then
    offerNote = L["market is %s; %s can change it"]:format(g(d.market), crafter)
  end
  if not d.priced then
    offerNote = L["no market price for some of it yet"]
  end
  local tree = {
    id = "rf",
    type = "requestform",
    props = { gap = 10 },
    children = {
      {
        id = "rf.title",
        type = "frametitle",
        props = { title = L["Ask %s"]:format(crafter), note = s.note, close = true },
        meta = { h = 20 },
      },
      {
        id = "rf.what",
        type = "row",
        props = { gap = 8, align = "center" },
        meta = { h = 24 },
        children = {
          text("rf.make", L["Make"], { color = "dim" }),
          {
            id = "rf.count",
            type = "input",
            props = { value = tostring(d.count), hint = L["How many"], numeric = true, action = "count" },
            meta = { w = 40, h = 24 },
          },
          text("rf.x", "×", { color = "dim" }),
          whatItem("rf.item", d.item, d.recipe),
        },
      },
      {
        id = "rf.mats",
        type = "card",
        props = { gap = 4 },
        meta = { h = 18 + 1 + 36 * #d.rows + 16 + 4 * (#d.rows + 3) + 20 },
        children = rows,
      },
      {
        id = "rf.money",
        type = "grid",
        props = { widths = { 110, 64, 0 }, gap = 10, rowH = 24 },
        meta = { h = 24 * 3 + 20 },
        children = {
          text("rf.offer.l", L["For %s's mats"]:format(crafter), { color = "dim" }),
          {
            id = "rf.offer",
            type = "input",
            props = { value = typed(d.offer), hint = L["For the mats"], action = "offer", money = true },
          },
          text("rf.offer.n", offerNote, { color = "dim" }),
          text("rf.tip.l", L["Tip"], { color = "dim" }),
          {
            id = "rf.tip",
            type = "input",
            props = { value = typed(d.tip), hint = L["Tip"], action = "tip", money = true },
          },
          {
            id = "rf.tip.n",
            type = "row",
            props = { gap = 4, align = "center" },
            children = {
              text("rf.tip.s", L["suggested"], { color = "dim" }),
              {
                id = "rf.tip.use",
                type = "keyvalue",
                props = { text = typed(d.suggested), action = "useSuggested" },
                meta = { w = 60, h = 18 },
              },
            },
          },
          text("rf.pay.l", L["You pay"], { color = "text", size = 12 }),
          { id = "rf.pay", type = "money", props = { copper = d.total, size = 14, bold = true, justify = "LEFT" } },
          { id = "rf.pay.n", type = "spacer" },
        },
      },
      {
        id = "rf.msg.head",
        type = "row",
        props = { gap = 8 },
        meta = { h = 16 },
        children = {
          text("rf.msg.l", L["Message · AME puts the item link in front"], { color = "dim", meta = { grow = 1 } }),
          {
            id = "rf.msg.reset",
            type = "keyvalue",
            props = { text = L["Reset"], action = "reset" },
            meta = { w = 60, h = 16 },
          },
        },
      },
      {
        id = "rf.msg",
        type = "textarea",
        props = { value = d.message, hint = L["Your message"], action = "message" },
        meta = { h = 52 },
      },
      { id = "rf.gap", type = "spacer", meta = { grow = 1 } },
      {
        id = "rf.buttons",
        type = "row",
        props = { gap = 6 },
        meta = { h = 24 },
        children = {
          {
            id = "rf.send",
            type = "button",
            props = {
              label = s.change and L["Send it back"] or L["Send request"],
              variant = "primary",
              action = "send",
            },
          },
          { id = "rf.cancel", type = "button", props = { label = L["Cancel"], action = "close" } },
          { id = "rf.fill", type = "spacer", meta = { grow = 1 } },
          { id = "rf.lack", type = "button", props = { label = L["What I lack, to a list"], action = "lack" } },
        },
      },
    },
  }
  return tree
end

-- ------------------------------------------------------------------------------------------------ the answer

-- r: the request; a: the answer being written (the crafter's side): { offer, tip, message };
-- s = { held = fn(item) -> n, now }
function Q.AnswerTree(r, a, s)
  s = s or {}
  local crafter = r.side == "crafter"
  local them = crafter and r.asker or r.crafter
  local now = s.now or GetServerTime()
  local when = ns.Widgets.Ago(r.changed or r.at, now)
  local title, note
  if crafter then
    title = L["%s asks"]:format(r.asker)
    note = L["%s · for %s"]:format(when, r.crafter)
    if s.online then
      note = L["online"] .. " · " .. note
    end
  else
    title = L["%s answered"]:format(r.crafter)
    note = L["your request · %s"]:format(when)
  end
  local colBring = crafter and L["%s brings"]:format(r.asker) or L["You bring"]
  local colSupply = crafter and L["You supply"] or L["%s supplies"]:format(r.crafter)
  local rows = {
    {
      id = "ra.head",
      type = "grid",
      props = { widths = { 0, 40, 76, 86 }, gap = 10 },
      meta = { h = 18 },
      children = {
        text("ra.head.1", L["Reagent"], { color = "heading" }),
        text("ra.head.2", L["Need"], { color = "heading", justify = "RIGHT" }),
        text("ra.head.3", colBring, { color = "heading", justify = "RIGHT" }),
        text("ra.head.4", colSupply, { color = "heading", justify = "RIGHT" }),
      },
    },
    { id = "ra.headrule", type = "divider", meta = { h = 1 } },
  }
  local changed = R.Changed(r)
  for i, m in ipairs(r.reagents or {}) do
    local p = "ra.r" .. i
    local supply = (m.need or 0) - (m.soulbound and 0 or (m.bring or 0))
    local sub, tone
    if crafter and supply > 0 and s.held then
      local hold = s.held(m.item) or 0
      sub = L["you hold %d"]:format(hold)
      if hold < supply then
        sub, tone = sub .. " · " .. L["%d short"]:format(supply - hold), "warn"
      else
        tone = "good"
      end
    elseif not crafter and changed.bring[i] then
      sub, tone = L["changed"], "warn"
    end
    local nameKids =
      { { id = p .. ".item", type = "itemlink", props = { item = m.item, size = 12 }, meta = { h = 17 } } }
    if sub then
      nameKids[2] = text(p .. ".sub", sub, { color = tone or "dim", meta = { h = 14 } })
    end
    rows[#rows + 1] = {
      id = p,
      type = "grid",
      props = { widths = { 0, 40, 76, 86 }, gap = 10, rowH = 34 },
      meta = { h = 34 },
      children = {
        { id = p .. ".name", type = "column", props = { gap = 1 }, children = nameKids },
        text(p .. ".need", tostring(m.need), { justify = "RIGHT", size = 12 }),
        text(p .. ".bring", (m.bring or 0) > 0 and tostring(m.bring) or "—", { justify = "RIGHT", size = 12 }),
        text(p .. ".supply", supply > 0 and tostring(supply) or "—", { justify = "RIGHT", size = 12 }),
      },
    }
  end

  -- the money: what was offered beside the answer, a change lit
  local lines = {}
  local offered, answer
  if crafter then
    offered = { offer = r.offer or 0, tip = r.tip or 0 }
    answer = { offer = a.offer or r.offer or 0, tip = a.tip or r.tip or 0 }
  else
    local p = r.prev or R.Terms(r)
    offered = { offer = p.offer or 0, tip = p.tip or 0 }
    answer = { offer = r.offer or 0, tip = r.tip or 0 }
  end
  local money = {
    { key = "offer", label = crafter and L["For your mats"] or L["For %s's mats"]:format(r.crafter) },
    { key = "tip", label = L["Tip"] },
  }
  local grid = {
    { id = "ra.m.h0", type = "spacer" },
    text("ra.m.h1", crafter and L["Offered"] or L["You offered"], { color = "dim", justify = "RIGHT" }),
    text(
      "ra.m.h2",
      crafter and L["Your answer"] or L["%s asks"]:format(r.crafter),
      { color = "dim", justify = "RIGHT" }
    ),
    { id = "ra.m.h3", type = "spacer" },
  }
  for _, m in ipairs(money) do
    local o, v = offered[m.key], answer[m.key]
    local diff = v - o
    local noteText, tone = L["as offered"], "dim"
    if diff ~= 0 then
      tone = "warn"
      noteText = crafter and L["changed"] or L["changed, %s"]:format((diff > 0 and "+" or "-") .. typed(math.abs(diff)))
      if crafter and m.key == "offer" and s.market then
        noteText = L["changed · market is %s"]:format(typed(s.market))
      end
    end
    grid[#grid + 1] = text("ra.m." .. m.key .. ".l", m.label, { color = "dim" })
    grid[#grid + 1] = { id = "ra.m." .. m.key .. ".o", type = "money", props = { copper = o } }
    if crafter then
      grid[#grid + 1] = {
        id = "ra.m." .. m.key .. ".a",
        type = "input",
        props = { value = typed(v), hint = m.label, action = m.key, money = true },
      }
    else
      grid[#grid + 1] = { id = "ra.m." .. m.key .. ".a", type = "money", props = { copper = v, bold = diff ~= 0 } }
    end
    grid[#grid + 1] = text("ra.m." .. m.key .. ".n", noteText, { color = tone })
    lines[#lines + 1] = diff ~= 0
  end
  local anyChange = lines[1] or lines[2]
  grid[#grid + 1] = text("ra.m.t.l", crafter and L["You receive"] or L["You pay"], { color = "text", size = 12 })
  grid[#grid + 1] = { id = "ra.m.t.o", type = "money", props = { copper = offered.offer + offered.tip } }
  grid[#grid + 1] =
    { id = "ra.m.t.a", type = "money", props = { copper = answer.offer + answer.tip, size = 14, bold = true } }
  grid[#grid + 1] = { id = "ra.m.t.n", type = "spacer" }

  local theirs = crafter and r.message or r.note
  local kids = {
    {
      id = "ra.title",
      type = "frametitle",
      props = { title = title, note = note, close = true },
      meta = { h = 20 },
    },
    {
      id = "ra.what",
      type = "row",
      props = { gap = 8, align = "center" },
      meta = { h = 20 },
      children = {
        text("ra.make", L["Make"], { color = "dim" }),
        text("ra.count", tostring(r.count), { size = 12 }),
        text("ra.x", "×", { color = "dim" }),
        whatItem("ra.item", r.item, r.recipe),
      },
    },
    {
      id = "ra.mats",
      type = "card",
      props = { gap = 4 },
      meta = { h = 18 + 1 + 34 * #(r.reagents or {}) + 4 * (#(r.reagents or {}) + 2) + 20 },
      children = rows,
    },
    {
      id = "ra.money",
      type = "grid",
      props = { widths = { 104, 74, 74, 0 }, gap = 10, rowH = 24 },
      meta = { h = 24 * 4 + 30 },
      children = grid,
    },
  }
  if theirs and theirs ~= "" then
    kids[#kids + 1] =
      text("ra.theirs", ('%s: "%s"'):format(them, theirs), { color = "soft", wrap = true, meta = { h = 30 } })
  end
  if crafter then
    kids[#kids + 1] = text("ra.yours.l", L["Your message · optional"], { color = "dim", meta = { h = 14 } })
    kids[#kids + 1] = {
      id = "ra.yours",
      type = "textarea",
      props = { value = a.message or "", hint = L["Your message"], action = "message" },
      meta = { h = 34 },
    }
  end
  local rule, buttons
  if crafter then
    rule = anyChange
        and L["You changed a figure, so this goes back to %s to approve. Nothing is queued until you both agree."]:format(
          r.asker
        )
      or L["As asked: accepting puts it on your queue."]
    buttons = {}
    if anyChange then
      buttons[#buttons + 1] = {
        id = "ra.b.send",
        type = "button",
        props = { label = L["Send your answer"], variant = "primary", action = "sendAnswer" },
      }
      buttons[#buttons + 1] =
        { id = "ra.b.accept", type = "button", props = { label = L["Accept as asked"], action = "accept" } }
    else
      buttons[#buttons + 1] = {
        id = "ra.b.accept",
        type = "button",
        props = { label = L["Accept as asked"], variant = "primary", action = "accept" },
      }
    end
    buttons[#buttons + 1] =
      { id = "ra.b.decline", type = "button", props = { label = L["Decline"], action = "decline" } }
  else
    rule =
      L["Accept agrees to %s's terms and %s can start. Change it opens your request with these figures, to answer back."]:format(
        r.crafter,
        r.crafter
      )
    buttons = {
      { id = "ra.b.accept", type = "button", props = { label = L["Accept"], variant = "primary", action = "accept" } },
      { id = "ra.b.change", type = "button", props = { label = L["Change it"], action = "change" } },
      { id = "ra.b.decline", type = "button", props = { label = L["Withdraw"], action = "decline" } },
    }
  end
  if not R.Mine(r, r.side) or not (r.state == "new" or r.state == "answered") then
    -- not yours to answer now: only what's left to do
    rule = L["Waiting for %s."]:format(them)
    buttons = {}
  end
  buttons[#buttons + 1] = { id = "ra.b.fill", type = "spacer", meta = { grow = 1 } }
  buttons[#buttons + 1] = { id = "ra.b.whisper", type = "button", props = { label = L["Whisper"], action = "whisper" } }
  kids[#kids + 1] = { id = "ra.gap", type = "spacer", meta = { grow = 1 } }
  kids[#kids + 1] = text("ra.rule", rule, { color = "dim", wrap = true, meta = { h = 28 } })
  kids[#kids + 1] = { id = "ra.buttons", type = "row", props = { gap = 6 }, meta = { h = 24 }, children = buttons }
  return { id = "ra", type = "requestanswer", props = { gap = 8 }, children = kids }
end

-- ------------------------------------------------------------------------------------------------ the frame

function Q.Tree()
  local s = Q.state
  if not s then
    return nil
  end
  if s.mode == "form" then
    return Q.FormTree(s.draft, s)
  end
  local r = R.Get(s.id)
  if not r then
    return nil
  end
  local price = ns.GuildPage.Price()
  local market = 0
  for _, m in ipairs(R.Supply(r)) do
    market = market + (price(m.item) or 0) * m.n
  end
  return Q.AnswerTree(r, s.answer, { held = ns.GuildPage.Held(), market = market, online = R.Online(r.asker) })
end

local function draftOpts(crafter)
  local price = ns.GuildPage.Price()
  return {
    price = price,
    sells = price,
    held = ns.GuildPage.Held(),
    soulbound = ns.GuildPage.Soulbound,
    crafter = crafter,
  }
end

Q.actions = {}
local A = Q.actions

local function refresh()
  local s = Q.state
  if s and s.mode == "form" then
    R.Refresh(s.draft, draftOpts(s.crafter))
  end
  Q.Render()
end

function A.close()
  Q.Close()
end

function A.count(p)
  local n = tonumber(p.text)
  if n and n >= 1 then
    Q.state.draft.count = math.min(200, math.floor(n))
  end
  refresh()
end

function A.tick(p)
  local row = Q.state.draft.rows[p.payload]
  if row then
    row.checked = p.checked and true or false
    if not row.checked then
      row.bringSet = nil
    end
  end
  refresh()
end

function A.bring(p)
  local row = Q.state.draft.rows[p.payload]
  local n = tonumber(p.text)
  if row and n then
    row.bringSet = math.max(0, math.floor(n))
    row.checked = row.bringSet > 0
  end
  refresh()
end

local function moneyField(field)
  return function(p)
    local s = Q.state
    local copper = ns.ParseMoney(p.text)
    if s.mode == "form" then
      s.draft[field] = copper or s.draft[field]
      s.draft[field .. "Set"] = copper ~= nil or nil
    else
      s.answer[field] = copper
    end
    refresh()
  end
end
A.offer = moneyField("offer")
A.tip = moneyField("tip")

function A.useSuggested()
  Q.state.draft.tipSet = nil
  refresh()
end

function A.message(p)
  local s = Q.state
  if s.mode == "form" then
    s.draft.message, s.draft.messageSet = p.text, true
  else
    s.answer.message = p.text
  end
end

function A.reset()
  Q.state.draft.messageSet = nil
  refresh()
end

local function openRequests(id)
  local app = ns.App
  if app and app.frame and app.frame:IsShown() then
    app:Go("requests", { request = id })
  end
end

function A.send()
  local s = Q.state
  local d = s.draft
  local id
  if s.change then
    local bring = {}
    for i, row in ipairs(d.rows) do
      bring[i] = row.bring
    end
    R.DoAnswer(s.change, { offer = d.offer, tip = d.tip, bring = bring }, d.message)
    id = s.change
  else
    local r = R.Create(d, s.crafter)
    id = r and r.id
    if r and ns.AME and ns.AME.Say then
      ns.AME.Say(L["Request sent to %s"], s.crafter)
    end
  end
  Q.Close()
  openRequests(id)
end

-- what you lack of what you bring: a shopping list
function A.lack()
  local d = Q.state.draft
  local shopping = ns.AME and ns.AME.shopping
  if not shopping then
    return
  end
  local name = L["For %s"]:format(itemName(d.item) or (ns.Crafters.RecipeName(d.recipe) or "?"))
  local i = shopping:AddList(name)
  if not i then
    for k, l in ipairs(shopping:Lists()) do
      if l.name == name then
        i = k
      end
    end
  end
  if not i then
    return
  end
  local any = false
  for _, row in ipairs(d.rows) do
    local short = (row.bring or 0) - (row.hold or 0)
    if short > 0 then
      shopping:SetItem(i, row.item, short)
      any = true
    end
  end
  if ns.AME.Say then
    ns.AME.Say(any and L["Added to the shopping list %s"] or L["You hold all you bring: %s is empty"], name)
  end
end

function A.sendAnswer()
  local s = Q.state
  R.DoAnswer(s.id, { offer = s.answer.offer, tip = s.answer.tip }, s.answer.message)
  Q.Close()
  openRequests(s.id)
end

function A.accept()
  local s = Q.state
  R.DoAccept(s.id)
  Q.Close()
  openRequests(s.id)
end

function A.decline()
  local s = Q.state
  R.DoDecline(s.id)
  Q.Close()
  openRequests(s.id)
end

function A.change()
  Q.Change(Q.state.id)
end

function A.whisper()
  local r = R.Get(Q.state.id)
  if r and ns.CraftersView and ns.CraftersView.Whisper then
    ns.CraftersView.Whisper(r.side == "crafter" and r.asker or r.crafter, r.recipe)
  end
end

function Q.Create()
  if Q.frame then
    return Q.frame
  end
  local f = CreateFrame("Frame", "AMERequestFrame", UIParent)
  f:SetSize(Q.W, Q.FORM_H)
  f:SetPoint("CENTER", 0, 40)
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  table.insert(_G.UISpecialFrames or {}, "AMERequestFrame")
  f:Hide()
  local handlers = setmetatable({}, {
    __index = function(_, name)
      local fn = A[name]
      return fn
        and function(payload)
          local ok, err = pcall(fn, payload or {})
          if not ok and ns.Dev and ns.Dev.Warn then
            ns.Dev.Warn("requests: " .. tostring(err))
          end
        end
    end,
  })
  Q.ctx = Layout.Context(handlers, { sources = {} })
  Q.renderer = Layout.Renderer(f, Q.ctx)
  Q.frame = f
  return f
end

function Q.Render()
  if not (Q.frame and Q.frame:IsShown()) then
    return
  end
  local tree = Q.Tree()
  if not tree then
    return Q.Close()
  end
  Q.frame:SetHeight(Q.state.mode == "form" and Q.FORM_H or Q.ANSWER_H)
  Q.renderer:Render(tree)
end

function Q.Open(state)
  Q.Create()
  Q.state = state
  Q.frame:Show()
  Q.Render()
end

function Q.Close()
  Q.state = nil
  if Q.frame then
    Q.frame:Hide()
  end
end

function Q.Ask(recipeID, crafter, note)
  local recipe = ns.Recipes and ns.Recipes.Get(recipeID)
  if not recipe then
    if ns.AME and ns.AME.Say then
      ns.AME.Say(L["AME doesn't know that recipe's reagents yet"])
    end
    return
  end
  local db = R.DB()
  local opts = draftOpts(crafter)
  opts.recipe, opts.count = recipe, 1
  opts.tip = db and db.tips[recipeID] -- your own tip for it, when you make it too
  local d = R.Draft(opts)
  Q.Open({ mode = "form", draft = d, crafter = crafter, note = note })
end

-- the asker changes their request: the form, filled in from the request as it stands
function Q.Change(id)
  local r = R.Get(id)
  local recipe = r and ns.Recipes and ns.Recipes.Get(r.recipe)
  if not recipe then
    return
  end
  local opts = draftOpts(r.crafter)
  opts.recipe, opts.count = recipe, r.count
  local d = R.Draft(opts)
  for i, row in ipairs(d.rows) do
    local m = r.reagents[i]
    if m and not row.soulbound then
      row.bringSet, row.checked = m.bring, (m.bring or 0) > 0
    end
  end
  d.offer, d.offerSet, d.tip, d.tipSet = r.offer, true, r.tip, true
  d.message, d.messageSet = r.message, true
  R.Refresh(d, opts)
  Q.Open({ mode = "form", draft = d, crafter = r.crafter, change = id, note = L["your request"] })
end

function Q.Answer(id)
  local r = R.Get(id)
  if not r then
    return
  end
  Q.Open({ mode = "answer", id = id, answer = { offer = r.offer, tip = r.tip, message = "" } })
end
