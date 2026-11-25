-- The Guide (boards Guide, GuideAH): the article list on the left, the picked article on the right. One screen with
-- an article param (params.article = an article's key, or a glossary term's). The texts are the Guide's own
-- (Core/UI/Help.lua: Help.Articles, Help.TERMS, Help.GLOSSARY); this file orders them as the board does, adds the
-- buttons that open each article's screen and the See also links, and the article the redesign adds (At the
-- auction house). Slash commands in the text are links that put the command in the chat box.
--
--   Guide.Groups() -> { { key, title, articles = { article, ... } }, ... }    the sidebar's groups, in order
--   Guide.Index(groups) -> byKey                    every article and glossary term by key
--   Guide.Entries(groups, current, search) -> sidebar entries (headings, articles; the shown one picked)
--   Guide.Blocks(article, byKey) -> guidearticle blocks (its open buttons first, See also last)
--   Guide.Matches(article, text) -> bool            the search box: title, sidebar name or any paragraph
local _, ns = ...
local L = ns.L

local App = ns.App

local Guide = {}
ns.GuideScreen = Guide

-- At the auction house: the redesign's article (board GuideAH), with the board's words
local function ahArticle()
  local H = function(text)
    return { h = text }
  end
  return {
    key = "ah",
    title = L["At the auction house"],
    body = {
      L["With the auction house open, AME's window is the auction house. The tabs stay the same, and each gains what the auction house allows."],
      H(L["Buying"]),
      L["On Market, the search box searches the auction house itself: the table shows what's on sale now beside the market price, the average and the signal. Click a row to open the item: its listings, cheapest first, with Buy. Buy asks the game for the price, Confirm buys it, and Cancel backs out; the game wants a click for each purchase."],
      L["Pick a shopping list in the sidebar to see what it still needs. Search all prices every item; Confirm then buys down the list, one item after another, and skips what costs more than your top price."],
      H(L["Selling"]),
      L["Portfolio > Sell lists what's in your bags, the most worth first, with a tip for each: Sell, Craft (a recipe of yours makes something worth more), DE or Vendor. Pick Quick, Normal or Patient by how fast you want it sold, or Market for the market price, then Post. Post moves on to the next item, so a bag takes one click or key press an item."],
      H(L["Your auctions"]),
      L["Portfolio > Auctions shows each auction against what's on sale now: lowest, undercut and by how much, or not checked yet. Check prices searches them all. Cancel takes one auction back; it returns by mail and its deposit is lost."],
      H(L["The game's own window"]),
      L["Use the game's AH, at the right end of the Buy, Sell and Auctions tabs, swaps to the game's auction house window, with Auctionator in it when you have that installed. Its Open in AME button swaps back. AME opens the auction house the way you last left it."],
    },
  }
end

-- the order of the board: getting started, then one article per tab in the tab row's order with the topics that cut
-- across them, then the glossary. Keys Help.Articles doesn't have are skipped.
Guide.ORDER = {
  { key = "start", title = L["Getting started"], keys = { "start", "tooltips", "data", "window" } },
  {
    key = "tabs",
    title = L["Tabs"],
    keys = {
      "tabMarket",
      "marketOverview",
      "tabArbitrage",
      "tabItem",
      "ah",
      "crafting",
      "professions",
      "tabSync",
      "tabPortfolio",
      "tabSettings",
      "selling",
      "numbers",
      "watch",
      "shopping",
      "otherAddons",
      "commands",
    },
  },
}

-- sidebar names where the board's differ from the article's own
Guide.LABELS = { selling = L["Posting prices"], tabSync = L["Sharing"], ah = L["At the auction house"] }

-- what each article's buttons open: { label, screen, params? }
Guide.OPEN = {
  tabMarket = { { L["Open Market"], "market" } },
  marketOverview = { { L["Open the Overview"], "market", { mode = "overview" } } },
  tabArbitrage = { { L["Open Arbitrage"], "market", { mode = "arbitrage" } } },
  tabItem = { { L["Open the Item tab"], "item" } },
  ah = { { L["Open Market"], "market" }, { L["Open Portfolio"], "portfolio" } },
  crafting = { { L["Open Crafting"], "crafting" } },
  tabSync = { { L["Open Sharing"], "sharing" } },
  tabPortfolio = { { L["Open Portfolio"], "portfolio" } },
  tabSettings = { { L["Open Settings"], "settings" } },
  watch = { { L["Open your alerts"], "market", { view = "alerts" } }, { L["Open the notifications"], "notifications" } },
  shopping = { { L["Open your lists"], "market", { mode = "lists" } } },
}

Guide.SEE = {
  tabItem = { "ah", "selling", "watch", "numbers" },
  ah = { "tabItem", "selling", "shopping", "tabPortfolio" },
  tabMarket = { "marketOverview", "tabArbitrage", "watch", "shopping" },
  selling = { "ah", "tabItem", "numbers" },
  watch = { "tabMarket", "shopping" },
  shopping = { "ah", "watch" },
}

local function glossaryArticle(terms)
  local body = {}
  for _, t in ipairs(terms) do
    body[#body + 1] = { h = t.title }
    for _, b in ipairs(t.body) do
      body[#body + 1] = b
    end
  end
  return { key = "glossary", title = L["Glossary"], label = L["All terms"], body = body, terms = terms }
end

function Guide.Groups()
  local byKey, glossary = {}, {}
  local Help = ns.Help
  for _, g in ipairs(Help and Help.Articles and Help.Articles() or {}) do
    for _, a in ipairs(g[2]) do
      if g[1] == L["Glossary"] then
        a.group = L["Glossary"]
        glossary[#glossary + 1] = a
      else
        byKey[a.key] = a
      end
    end
  end
  byKey.ah = ahArticle()
  local groups = {}
  for _, spec in ipairs(Guide.ORDER) do
    local list = {}
    for _, key in ipairs(spec.keys) do
      local a = byKey[key]
      if a then
        a.group = spec.title
        a.label = Guide.LABELS[key] or a.label
        list[#list + 1] = a
      end
    end
    groups[#groups + 1] = { key = spec.key, title = spec.title, articles = list }
  end
  local all = glossaryArticle(glossary)
  all.group = L["Glossary"]
  groups[#groups + 1] = { key = "glossary", title = L["Glossary"], articles = { all }, terms = glossary }
  return groups
end

function Guide.Index(groups)
  local byKey = {}
  for _, g in ipairs(groups) do
    for _, a in ipairs(g.articles) do
      byKey[a.key] = a
    end
    for _, t in ipairs(g.terms or {}) do
      byKey[t.key] = t
    end
  end
  return byKey
end

local function blockText(b)
  if type(b) == "string" then
    return b
  end
  return b.h or ""
end

function Guide.Matches(a, text)
  if not text or text == "" then
    return true
  end
  text = text:lower()
  if a.title:lower():find(text, 1, true) or (a.label and a.label:lower():find(text, 1, true)) then
    return true
  end
  for _, b in ipairs(a.body or {}) do
    if blockText(b):lower():find(text, 1, true) then
      return true
    end
  end
  return false
end

-- the sidebar: a heading per group with its articles; while searching, only what matches (glossary terms each)
function Guide.Entries(groups, current, search)
  local entries = {}
  local searching = search and search ~= ""
  for _, g in ipairs(groups) do
    local shown = {}
    if g.terms and searching then
      for _, t in ipairs(g.terms) do
        if Guide.Matches(t, search) then
          shown[#shown + 1] = t
        end
      end
    else
      for _, a in ipairs(g.articles) do
        if Guide.Matches(a, search) then
          shown[#shown + 1] = a
        end
      end
    end
    if #shown > 0 then
      local title = g.terms and L["Glossary · %d terms"]:format(#g.terms) or g.title
      entries[#entries + 1] = { heading = true, label = title }
      for _, a in ipairs(shown) do
        -- a term not listed on its own lights the glossary's entry
        local picked = a.key == current or (a.key == "glossary" and g.terms and Guide.IsTerm(g.terms, current))
        entries[#entries + 1] = { key = a.key, label = a.label or a.title, selected = picked and true or false }
      end
    end
  end
  if #entries == 0 then
    entries[1] = { heading = true, label = L["No articles match"] }
  end
  return entries
end

function Guide.IsTerm(terms, key)
  for _, t in ipairs(terms or {}) do
    if t.key == key then
      return true
    end
  end
  return false
end

function Guide.Blocks(a, byKey)
  local blocks = {}
  local open = Guide.OPEN[a.key]
  if open then
    local buttons = {}
    for i, o in ipairs(open) do
      buttons[i] = { label = o[1], action = "openScreen", payload = { screen = o[2], params = o[3] } }
    end
    blocks[#blocks + 1] = { buttons = buttons }
  end
  for _, b in ipairs(a.body or {}) do
    if type(b) == "string" then
      blocks[#blocks + 1] = { p = b }
    elseif b.h then
      blocks[#blocks + 1] = { h = b.h }
    elseif b.example then
      blocks[#blocks + 1] = { example = b.example }
    end
  end
  local see = Guide.SEE[a.key]
  if see then
    local links = {}
    for _, key in ipairs(see) do
      local other = byKey[key]
      if other then
        links[#links + 1] = { key = key, label = Guide.LABELS[key] or other.label or other.title }
      end
    end
    if #links > 0 then
      blocks[#blocks + 1] = { h = L["See also"] }
      blocks[#blocks + 1] = { links = links }
    end
  end
  return blocks
end

-- ------------------------------------------------------------------------------------------------ the screen

local function current(params, byKey)
  local key = params.article
  if not (key and byKey[key]) then
    key = "start"
  end
  return byKey[key] or { key = "start", title = L["Guide"], body = {} }
end

local function build(app, params)
  local groups = Guide.Groups()
  local byKey = Guide.Index(groups)
  local a = current(params, byKey)
  return {
    id = "guide",
    type = "row",
    props = { gap = 10 },
    children = {
      {
        id = "guide.left",
        type = "column",
        props = { gap = 6 },
        meta = { w = app.compact and 170 or 200 },
        children = {
          {
            id = "guide.search",
            type = "input",
            props = { value = params.search or "", hint = L["Search the guide"], action = "guideSearch" },
            meta = { h = 24 },
          },
          {
            id = "guide.navscroll",
            type = "scrollcolumn",
            props = { gap = 0 },
            meta = { grow = 1 },
            children = {
              {
                id = "guide.nav",
                type = "sidebar",
                props = { entries = Guide.Entries(groups, a.key, params.search), action = "article" },
              },
            },
          },
        },
      },
      {
        id = "guide.article",
        type = "guidearticle",
        props = { key = a.key, crumb = a.group, title = a.title, blocks = Guide.Blocks(a, byKey), action = "article" },
        meta = { grow = 1 },
      },
    },
  }
end

App.Screen("guide", {
  tab = "guide",
  Build = build,
  Title = function(_, params)
    local byKey = Guide.Index(Guide.Groups())
    return current(params or {}, byKey).title
  end,
  Status = function(_, params)
    local byKey = Guide.Index(Guide.Groups())
    return L["Guide · %s"]:format(current(params or {}, byKey).title)
  end,
  actions = {
    -- another article is a step in the history, as a link in a browser is
    article = function(app, p)
      if p and p.key then
        local _, params = app:Current()
        app:Go("guide", { article = p.key, search = params.search })
      end
    end,
    guideSearch = function(app, p)
      local text = p and p.text or ""
      local _, params = app:Current()
      if text == (params.search or "") then
        return
      end
      local groups = Guide.Groups()
      local byKey = Guide.Index(groups)
      local shown = current(params, byKey)
      local article = params.article
      -- the article on show no longer matches: the first that does
      if text ~= "" and not Guide.Matches(shown, text) then
        for _, e in ipairs(Guide.Entries(groups, nil, text)) do
          if e.key then
            article = e.key
            break
          end
        end
      end
      app:Set({ search = text, article = article })
    end,
    openScreen = function(app, p)
      if p and p.screen then
        local screen = p.screen
        if screen == "portfolio" and app:AtAH() and App.screens.sell then
          screen = "sell" -- at the auction house, Portfolio opens on Sell
        end
        local params = {}
        for k, v in pairs(p.params or {}) do
          params[k] = v
        end
        app:Go(App.screens[screen] and screen or app:TabScreen(screen), params)
      end
    end,
  },
})
