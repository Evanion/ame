-- Guild > Your crafts (board GuildOffers): the other side of Crafters. What your characters make for others, which
-- professions take orders, your tip per craft (what the request form suggests), an advert for chat, and the month's
-- requests and tips. The model is Core/GuildPage.lua.
local _, ns = ...
local L = ns.L

local App, GuildPage, G = ns.App, ns.GuildPage, ns.GuildScreen
local R = ns.CraftRequests

local COLUMNS = {
  { key = "item", label = L["Craft"], width = 220, item = true, fallback = "name" },
  { key = "yours", label = L["Yours who can"], width = 110, align = "LEFT" },
  { key = "asked", label = L["Asked"], width = 50, format = "count" },
  { key = "mats", label = L["Mats, at market"], width = 100, format = "money" },
  { key = "tip", label = L["Your tip"], width = 80 },
}

G.ADVERT_ITEMS = 3

-- what the page shows: { professions, rows, advert = { parts, text }?, month }
function G.OffersData()
  local db = R.DB() or { taking = {}, tips = {} }
  local profs = GuildPage.MyProfessions()
  local crafts = GuildPage.MyCrafts(db.taking)
  local asked = {}
  local list = R.List()
  for _, r in ipairs(list) do
    if r.side == "crafter" then
      asked[r.recipe] = (asked[r.recipe] or 0) + 1
    end
  end
  local price = GuildPage.Price()
  local rows = GuildPage.OfferRows(crafts, {
    asked = function(id)
      return asked[id] or 0
    end,
    tip = function(id)
      return db.tips[id]
    end,
    mats = function(id)
      local rec = ns.Recipes.Get(id)
      if not rec then
        return nil
      end
      local total = 0
      for _, g in ipairs(rec.reagents or {}) do
        local p = price(g[1])
        if not p then
          return nil
        end
        total = total + p * (g[2] or 1)
      end
      return total
    end,
  })
  local d = { professions = profs, rows = rows, month = GuildPage.Month(list, GetServerTime()), taking = db.taking }
  -- the advert: the first profession taking orders (or the first you have), its most asked crafts that make items
  local pick
  for _, p in ipairs(profs) do
    if db.taking[p.key] then
      pick = pick or p
    end
  end
  pick = pick or profs[1]
  if pick then
    local items = {}
    for _, row in ipairs(rows) do
      if row.item and #items < G.ADVERT_ITEMS and row.yours:find(pick.char, 1, true) then
        items[#items + 1] = row.item
      end
    end
    local parts, text = GuildPage.Advert(pick.char, pick.name, pick.skill, items, function(id)
      return ns.ItemCache.Link and ns.ItemCache.Link(id) or ns.ItemCache.Name(id)
    end)
    d.advert = { parts = parts, text = text }
  end
  return d
end

local function build(app, params)
  local d = G.OffersData()
  app:Source("guild.offers", d.rows)
  local checks = { G.Text("offers.taking", L["Taking orders"], { meta = { w = 90, h = 18 } }) }
  for i, p in ipairs(d.professions) do
    checks[#checks + 1] = {
      id = "offers.take" .. i,
      type = "check",
      props = {
        label = ("%s (%s)"):format(p.name, p.char),
        checked = d.taking[p.key] and true or false,
        action = "taking",
        payload = p.key,
      },
      meta = { h = 18 },
    }
  end
  if #d.professions == 0 then
    checks[#checks + 1] = G.Text(
      "offers.noprof",
      L["Open each of your professions once so AME knows what you make."],
      { meta = { grow = 1, h = 18 } }
    )
  end
  local pickedRow
  for _, row in ipairs(d.rows) do
    if row.key == params.recipe then
      pickedRow = row
    end
  end
  local mainKids = {
    G.Heading("offers.h", L["Your crafts"], L["what your characters make for others"]),
    {
      id = "offers.checks",
      type = "row",
      props = { gap = 16, align = "center" },
      meta = { h = 20 },
      children = checks,
    },
    {
      id = "offers.table",
      type = "table",
      props = {
        source = "guild.offers",
        columns = COLUMNS,
        action = "pickCraft",
        selected = pickedRow and pickedRow.key or nil,
        note = L["Asked: requests to you for it. Your tip: what the request form suggests to others; leave it empty for a tenth of what the craft adds."],
        empty = L["Nothing yet: open your professions once, or tick a profession above."],
      },
      meta = { grow = 1 },
    },
  }
  if pickedRow then
    local db = R.DB()
    local tip = db and db.tips[pickedRow.recipe]
    mainKids[#mainKids + 1] = {
      id = "offers.tiprow",
      type = "row",
      props = { gap = 8, align = "center" },
      meta = { h = 24 },
      children = {
        G.Text("offers.tiprow.l", L["Your tip for"], { meta = { h = 18 } }),
        pickedRow.item
            and { id = "offers.tiprow.item", type = "itemlink", props = { item = pickedRow.item }, meta = { h = 18 } }
          or G.Text("offers.tiprow.item", pickedRow.name, { color = "text", meta = { h = 18 } }),
        {
          id = "offers.tiprow.in",
          type = "input",
          props = {
            value = tip and ns.Requests.Typed(tip) or "",
            hint = L["suggested"],
            action = "setTip",
            payload = pickedRow.recipe,
            money = true,
          },
          meta = { w = 70, h = 24 },
        },
      },
    }
  end
  local main = { id = "offers.main", type = "column", props = { gap = 8 }, children = mainKids }

  local tell = {
    G.Text(
      "offers.tell.l",
      L["An advert for chat, with links to what's most asked for. AME puts it in your chat box; you press Enter."],
      { wrap = true, meta = { h = 28 } }
    ),
  }
  if d.advert then
    tell[#tell + 1] =
      { id = "offers.tell.text", type = "linktext", props = { parts = d.advert.parts, wrap = true }, meta = { h = 48 } }
    tell[#tell + 1] = {
      id = "offers.tell.buttons",
      type = "row",
      props = { gap = 6 },
      meta = { h = 24 },
      children = {
        {
          id = "offers.tell.guild",
          type = "button",
          props = { label = L["To guild chat"], variant = "primary", action = "advertGuild" },
        },
        { id = "offers.tell.trade", type = "button", props = { label = L["To trade chat"], action = "advertTrade" } },
      },
    }
  end
  local month = {}
  for i, m in ipairs(d.month) do
    month[i] = { id = "offers.month" .. i, type = "keyvalue", props = m, meta = { h = 18 } }
  end
  local right = {
    id = "offers.right",
    type = "column",
    props = { gap = 8 },
    children = {
      {
        id = "offers.tell",
        type = "card",
        props = { title = L["Tell people"], gap = 6 },
        meta = { h = 32 + 28 + 48 + 24 + 24 },
        children = tell,
      },
      {
        id = "offers.month",
        type = "card",
        props = { title = L["This month"], gap = 2 },
        meta = { h = 32 + 20 * #month },
        children = month,
      },
    },
  }
  return G.Page("offers", main, right, 290)
end

-- open the chat box with the advert in it (you press Enter): /g, or the Trade channel
local function advertise(slash)
  local d = G.OffersData()
  if not d.advert then
    return
  end
  local open = _G.ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
  if open then
    open(slash .. " " .. d.advert.text)
  end
end

local function tradeSlash()
  local list = { _G.GetChannelList and _G.GetChannelList() }
  for i = 1, #list, 3 do
    local id, name = list[i], list[i + 1]
    if type(name) == "string" and name:lower():find("trade", 1, true) then
      return "/" .. tostring(id)
    end
  end
  return "/2"
end

App.Screen("offers", {
  tab = "guild",
  sub = true,
  Build = build,
  Title = function()
    return L["Your crafts"]
  end,
  Status = function()
    local db = R.DB()
    local n = 0
    for _ in pairs(db and db.taking or {}) do
      n = n + 1
    end
    local shared = ns.Settings and ns.Settings:Get("shareRecipes")
    local text = shared and L["Your recipes are shared with the guild"]
      or L["Your recipes are not shared (Sharing prices)"]
    if n > 0 then
      text = text
        .. " · "
        .. (n == 1 and L["taking orders for 1 profession"] or L["taking orders for %d professions"]:format(n))
    end
    return text
  end,
  actions = G.Actions({
    taking = function(app, p)
      local db = R.DB()
      if db and p.payload then
        db.taking[p.payload] = p.checked and true or nil
      end
      app:Render()
    end,
    pickCraft = function(app, p)
      app:Set({ recipe = p.key })
    end,
    setTip = function(app, p)
      local db = R.DB()
      if db and p.payload then
        local copper = ns.ParseMoney(p.text)
        db.tips[p.payload] = copper and copper > 0 and copper or nil
      end
      app:Render()
    end,
    advertGuild = function()
      advertise("/g")
    end,
    advertTrade = function()
      advertise(tradeSlash())
    end,
  }),
})
