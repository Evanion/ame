-- Guild > Requests (board GuildRequests): craft requests asked of your characters and the ones you asked, and the
-- picked one beside them: what, the message, where it stands, the mats, what it's worth, and what to do next.
-- Answer and Review open the request frame (Core/UI/Requests.lua). The model is Core/CraftRequests.lua.
local _, ns = ...
local L = ns.L

local App, GuildPage, G = ns.App, ns.GuildPage, ns.GuildScreen
local R = ns.CraftRequests

local IN_COLUMNS = {
  { key = "item", label = L["Craft"], width = 190, item = true, fallback = "name" },
  { key = "qty", label = L["Qty"], width = 36, format = "count" },
  { key = "who", label = L["From"], width = 96, align = "LEFT" },
  { key = "mats", label = L["Mats"], width = 90, align = "LEFT" },
  { key = "tip", label = L["Tip"], width = 64, format = "money" },
  { key = "yours", label = L["Yours who can"], width = 90, align = "LEFT" },
  { key = "state", label = L["State"], width = 170, align = "LEFT" },
  { key = "ago", label = "", width = 50 },
}

local OUT_COLUMNS = {
  { key = "item", label = L["Craft"], width = 190, item = true, fallback = "name" },
  { key = "qty", label = L["Qty"], width = 36, format = "count" },
  { key = "who", label = L["To"], width = 96, align = "LEFT" },
  { key = "mats", label = L["Mats"], width = 110, align = "LEFT" },
  { key = "tip", label = L["Tip"], width = 64, format = "money" },
  { key = "state", label = L["State"], width = 180, align = "LEFT" },
  { key = "ago", label = L["Asked"], width = 50 },
}

local MAT_COLUMNS = {
  { key = "item", label = L["Mats"], width = 150, item = true },
  { key = "need", label = L["Need"], width = 40, format = "count" },
  { key = "copper", label = L["At market"], width = 70, format = "money" },
}

local function env()
  return { online = R.Online, name = GuildPage.RequestName }
end

local function picked(params, list)
  local id = params.request
  local first
  for _, r in ipairs(list) do
    if r.id == id then
      return r
    end
    if not first and not R.ENDED[r.state] and R.Mine(r, r.side) then
      first = r
    end
  end
  return first or list[1]
end

local function detail(r, now)
  local price = GuildPage.Price()
  local each = r.item and price(r.item) or nil
  local acts = GuildPage.Actions(r)
  local buttons = {}
  for i, b in ipairs(acts.buttons) do
    buttons[i] = { id = "req.b" .. i, type = "button", props = { label = b.label, action = "req_" .. b.action, variant = b.variant } }
  end
  buttons[#buttons + 1] = { id = "req.b.fill", type = "spacer", meta = { grow = 1 } }
  buttons[#buttons + 1] = { id = "req.b.whisper", type = "button", props = { label = L["Whisper"], action = "req_whisper" } }
  local what = r.item and { id = "req.what.item", type = "itemlink", props = { item = r.item, size = 13, bold = true }, meta = { h = 18 } }
    or G.Text("req.what.item", GuildPage.RequestName(r), { color = "white", size = 13, meta = { h = 18 } })
  local quote = {
    { text = '"' .. L["%d ×"]:format(r.count) .. " ", tone = "soft" },
    r.item and { item = r.item } or GuildPage.RequestName(r),
    { text = ": " .. (r.message or "") .. '"', tone = "soft" },
  }
  local worth = {}
  for i, row in ipairs(GuildPage.WorthRows(r, each, price)) do
    worth[i] = { id = "req.worth" .. i, type = "keyvalue", props = row, meta = { h = row.total and 20 or 18 } }
  end
  worth[#worth + 1] = G.Text("req.worth.note", L["A fair tip: about a tenth of what the craft adds."], { meta = { h = 14 } })
  local kids = {
    {
      id = "req.what",
      type = "card",
      props = { gap = 2 },
      meta = { h = 54 },
      children = { what, G.Text("req.what.sub", GuildPage.RequestSub(r, now), { meta = { h = 14 } }) },
    },
    {
      id = "req.msg",
      type = "card",
      meta = { h = 58 },
      children = { { id = "req.msg.text", type = "linktext", props = { parts = quote, wrap = true }, meta = { h = 36 } } },
    },
    { id = "req.strip", type = "statestrip", props = GuildPage.Strip(r), meta = { h = 16 } },
  }
  if r.note and r.note ~= "" then
    kids[#kids + 1] = G.Text("req.note", ('%s: "%s"'):format(r.crafter, r.note), { color = "soft", wrap = true, meta = { h = 28 } })
  end
  kids[#kids + 1] = {
    id = "req.mats",
    type = "table",
    props = { source = "guild.mats", columns = MAT_COLUMNS, bare = true },
    meta = { h = math.min(120, 24 + 20 * #(r.reagents or {})) },
  }
  kids[#kids + 1] = {
    id = "req.worth",
    type = "card",
    props = { title = L["What it's worth"], gap = 2 },
    meta = { h = 32 + 20 * #worth },
    children = worth,
  }
  kids[#kids + 1] = { id = "req.gap", type = "spacer", meta = { grow = 1 } }
  if acts.rule then
    kids[#kids + 1] = G.Text("req.rule", acts.rule, { wrap = true, meta = { h = 56 } })
  end
  kids[#kids + 1] = { id = "req.buttons", type = "row", props = { gap = 6 }, meta = { h = 24 }, children = buttons }
  return { id = "req.right", type = "column", props = { gap = 8 }, children = kids }
end

local function build(app, params)
  local now = GetServerTime()
  local list = R.List()
  local into, out = GuildPage.Split(list, now, env())
  app:Source("guild.in", into)
  app:Source("guild.out", out)
  local r = picked(params, list)
  app:Source("guild.mats", r and GuildPage.MatRows(r, GuildPage.Price()) or {})
  local main = {
    id = "req.main",
    type = "column",
    props = { gap = 8 },
    children = {
      G.Heading("req.h.in", L["Asked of you"], L["crafts your characters can make"]),
      {
        id = "req.in",
        type = "table",
        props = {
          source = "guild.in",
          columns = IN_COLUMNS,
          action = "pickRequest",
          selected = r and r.id or nil,
          empty = L["Nobody has asked your characters for a craft yet. Your crafts says what you make for others."],
        },
        meta = { grow = 1 },
      },
      G.Heading("req.h.out", L["You asked"], L["and where each stands"]),
      {
        id = "req.out",
        type = "table",
        props = {
          source = "guild.out",
          columns = OUT_COLUMNS,
          action = "pickRequest",
          selected = r and r.id or nil,
          note = L["A request also goes out as a whisper, so a crafter without AME still sees it. Handed over and declined ones clear after a week."],
          empty = L["Ask a crafter from Crafters: what they make, the mats you bring, and a tip."],
        },
        meta = { grow = 1 },
      },
    },
  }
  local right = r and detail(r, now)
    or {
      id = "req.right",
      type = "column",
      children = { G.Text("req.none", L["Pick a request to see its terms."], { wrap = true, meta = { h = 30 } }) },
    }
  return G.Page("requests", main, right, 280)
end

local function current(app)
  local _, params = app:Current()
  local r = picked(params, R.List())
  return r
end

local function act(fn)
  return function(app)
    local r = current(app)
    if r then
      fn(app, r)
      app:Render()
    end
  end
end

App.Screen("requests", {
  tab = "guild",
  sub = true,
  Build = build,
  Title = function()
    return L["Requests"]
  end,
  Status = function()
    local n = R.Waiting()
    local text = L["Requests travel with guild sharing"]
    if n > 0 then
      text = text .. " · " .. (n == 1 and L["1 waits on you"] or L["%d wait on you"]:format(n))
    end
    return text
  end,
  actions = G.Actions({
    pickRequest = function(app, p)
      app:Set({ request = p.key })
    end,
    req_answer = act(function(_, r)
      ns.Requests.Answer(r.id)
    end),
    req_accept = act(function(_, r)
      R.DoAccept(r.id)
    end),
    req_decline = act(function(_, r)
      R.DoDecline(r.id)
    end),
    req_change = act(function(_, r)
      ns.Requests.Change(r.id)
    end),
    req_crafted = act(function(_, r)
      R.DoCrafted(r.id)
    end),
    req_handed = act(function(_, r)
      R.DoHanded(r.id)
    end),
    req_remove = act(function(app, r)
      R.Remove(r.id)
      app.state.params.request = nil
    end),
    req_whisper = act(function(_, r)
      if ns.CraftersView and ns.CraftersView.Whisper then
        ns.CraftersView.Whisper(r.side == "crafter" and r.asker or r.crafter, r.recipe)
      end
    end),
  }),
})
