-- "Who can make it": a small window to search what your guildmates', trusted players' and your own characters can
-- craft (Crafters): one table of recipes (the product as an item link) with their crafters under them, and a Whisper
-- button per crafter (it opens the chat box to them with the item linked; you send it). Opened with /ame who [text],
-- from an item's right-click menu, and Shift on a craftable item's tooltip says who (V.MadeBy, a tooltip section).
local _, ns = ...
local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local V = {}
ns.CraftersView = V

V.ROWS = 16
V.PER_RECIPE = 4

local function linkFor(recipeID)
  local r = ns.Recipes.Get(recipeID)
  if r and r.product then
    local link = ns.ItemCache.Link and ns.ItemCache.Link(r.product)
    if link then
      return link
    end
  end
  local spellLink = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(recipeID))
    or (_G.GetSpellLink and _G.GetSpellLink(recipeID))
  return spellLink or ns.Crafters.RecipeName(recipeID)
end

-- open the chat box to a crafter with the item linked (you press Enter)
function V.Whisper(name, recipeID)
  local open = _G.ChatFrame_OpenChat or (ChatFrameUtil and ChatFrameUtil.OpenChat)
  if not open then
    return
  end
  open("/w " .. name .. " ")
  local insert = _G.ChatEdit_InsertLink or (ChatFrameUtil and ChatFrameUtil.InsertLink)
  local link = linkFor(recipeID)
  if insert and link then
    insert(link)
  end
end

-- what a recipe makes (an enchant makes nothing: nil)
local function productOf(recipeID)
  local r = ns.Recipes.Get(recipeID)
  local d = not r and ns.CraftingData and ns.CraftingData.Recipe and ns.CraftingData:Recipe(recipeID)
  return (r and r.product) or (d and d.product) or nil
end

-- Pure: the window's lines for search results: a recipe line, then up to PER_RECIPE crafters under it.
-- A crafter line: name, note (your own character), seen (online, when last heard from), skill, and whether Whisper
-- shows (your own characters: log in there instead).
function V.Lines(results)
  local lines = {}
  for _, r in ipairs(results) do
    lines[#lines + 1] = { kind = "recipe", text = r.name, n = #r.who, recipe = r.recipe, product = productOf(r.recipe) }
    for k, c in ipairs(r.who) do
      if k > V.PER_RECIPE then
        lines[#lines + 1] = { kind = "more", text = L["+%d more"]:format(#r.who - V.PER_RECIPE) }
        break
      end
      local seen = c.mine and L["log in there"]
        or c.online and L["online"]
        or (c.t and L["seen %s"]:format(W.Ago(c.t, GetServerTime())))
        or ""
      lines[#lines + 1] = {
        kind = "crafter",
        name = c.name,
        recipe = r.recipe,
        mine = c.mine,
        online = c.online,
        note = c.mine and L["(your character)"] or nil,
        seen = seen,
        skill = c.skill,
        text = c.name,
      }
    end
  end
  return lines
end

-- a crafter's dot: green online (your own characters count as online), dim otherwise
local function dot(online)
  return W.Swatch(W.RGB(online and "good" or "dim"))
end

local COLUMNS = {
  -- the recipe's product as an item link (an enchant: its name in gold), or a crafter under it
  {
    key = "name",
    label = L["Recipe or crafter"],
    width = 180,
    item = true,
    sortKey = false,
    fallback = function(l)
      if l.kind == "recipe" then
        return W.Color("gold", l.text)
      elseif l.kind == "crafter" then
        return dot(l.online) .. " " .. l.name .. (l.note and W.Dim("  " .. l.note) or "")
      end
      return W.Dim(l.text)
    end,
  },
  {
    key = "seen",
    label = "",
    width = 96,
    align = "LEFT",
    sortKey = false,
    text = function(l)
      if l.kind == "recipe" then
        return W.Dim(L["%d can make it"]:format(l.n))
      end
      return W.Dim(l.seen or "")
    end,
  },
  {
    key = "skill",
    label = L["Skill"],
    width = 34,
    sortKey = false,
    text = function(l)
      return l.skill and W.Dim(tostring(l.skill)) or ""
    end,
  },
  {
    key = "whisper",
    label = "",
    width = 64,
    button = {
      label = L["Whisper"],
      shown = function(l)
        return l.kind == "crafter" and not l.mine
      end,
      onClick = function(l)
        V.Whisper(l.name, l.recipe)
      end,
    },
  },
}

V.WIDTH, V.HEIGHT = 460, 440

function V:Create()
  local f = CreateFrame("Frame", "AMECraftersFrame", UIParent, "BackdropTemplate")
  W.Skin(f, W.COLORS.bg)
  f:SetSize(V.WIDTH, V.HEIGHT)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if UISpecialFrames then
    table.insert(UISpecialFrames, "AMECraftersFrame") -- Escape closes it
  end
  local title = W.Text(f, "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText(L["Who can make it"])
  W.CloseButton(f, function()
    f:Hide()
  end):SetPoint("TOPRIGHT", -4, -4)
  local label = W.Text(f, "GameFontDisableSmall")
  label:SetPoint("TOPLEFT", 12, -32)
  label:SetText(L["Item or enchant"])
  f.box = W.Input(f, { hint = L["an item or enchant"] })
  f.box:SetPoint("TOPLEFT", 12, -46)
  f.box:SetPoint("RIGHT", -12, 0)
  f.box:SetScript("OnTextChanged", function()
    V:Render()
  end)
  f.box:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
  end)
  -- the results: one table, recipes with their crafters under them, as many rows as the window holds
  local body = CreateFrame("Frame", nil, f)
  body:SetPoint("TOPLEFT", 12, -76)
  body:SetPoint("BOTTOMRIGHT", -12, 12)
  f.table = ns.DataTable.New(body, {
    columns = COLUMNS,
    bare = true,
    fill = true,
    rows = 14,
    rowHeight = 20,
    note = L["Whisper opens the chat box to them with the item linked; you press Enter. Online first, then by when they were last heard from."],
    itemID = function(l)
      return l.kind == "recipe" and l.product or nil
    end,
    itemMenu = {},
    onClick = function(l)
      if l.kind == "recipe" and l.product then
        UI:ShowItem(l.product)
      end
    end,
  })
  f.rows = f.table.rows
  f:Hide()
  self.frame = f
  return f
end

function V:Render()
  local f = self.frame
  if not (f and f:IsShown()) then
    return
  end
  local crafters = ns.Crafters.Shared()
  local results = crafters and crafters:Search(f.box:GetText()) or {}
  local lines = V.Lines(results)
  f.lines = lines
  f.table:SetData(lines)
  f.table:Render()
  local typed = f.box:GetText() ~= ""
  f.table:SetMessage(
    #lines == 0
        and (typed and L["Nobody you share with knows a recipe by that name yet."] or L["Type part of an item or enchant name. Your guildmates' recipes arrive with sync; open each of your professions once so yours count too."])
      or nil
  )
end

function V:Open(text)
  local f = self.frame or self:Create()
  f:Show()
  f.box:SetText(text or "")
  if not text or text == "" then
    f.box:SetFocus()
  end
  self:Render()
end

function UI:WhoCanMake(itemID)
  local name = itemID and ns.ItemCache.Name(itemID)
  V:Open(name or "")
end

V.MADE_BY_NAMES = 3 -- names the tooltip lists; the rest are counted

-- The tooltip's Shift section: who can make this item, a line each (yours first, then online), with a dot for
-- online. -> a tooltip section (Tooltip.SectionRows), or nil when nobody you know can
function V.MadeBy(itemID)
  local crafters = ns.Crafters and ns.Crafters.Shared()
  if not (crafters and itemID) then
    return nil
  end
  local lines, n = {}, 0
  local seen = {}
  for _, recipe in ipairs(ns.Crafters.RecipesFor(itemID)) do
    for _, c in ipairs(crafters:WhoKnows(recipe)) do
      if not seen[c.name] then
        seen[c.name] = true
        n = n + 1
        if #lines < V.MADE_BY_NAMES then
          lines[#lines + 1] = dot(c.online) .. " " .. c.name .. (c.mine and W.Dim(" " .. L["(you)"]) or "")
        end
      end
    end
  end
  if n == 0 then
    return nil
  end
  if n > #lines then
    lines[#lines + 1] = W.Dim(L["+%d more"]:format(n - #lines))
  end
  return { heading = L["Made by"], note = L["with Shift"], lines = lines }
end
