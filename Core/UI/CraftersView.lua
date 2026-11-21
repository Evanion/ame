-- "Who can make it": a small window to search what your guildmates', trusted players' and your own characters can
-- craft (Crafters), with a Whisper button per crafter (it opens the chat box to them with the item linked; you send
-- it). Opened with /ame who [text], from an item's right-click menu, and Shift on a craftable item's tooltip says who.
local _, ns = ...
local L = ns.L
local W = ns.Widgets
local UI = ns.UI

local V = {}
ns.CraftersView = V

V.ROWS = 16
V.PER_RECIPE = 4

local function linkFor(recipeID)
  local r = ns.ProfessionBar and ns.ProfessionBar.Recipe(recipeID)
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

-- Pure: the window's lines for search results: a recipe line, then up to PER_RECIPE crafters under it
function V.Lines(results)
  local lines = {}
  for _, r in ipairs(results) do
    lines[#lines + 1] = { kind = "recipe", text = r.name, n = #r.who, recipe = r.recipe }
    for k, c in ipairs(r.who) do
      if k > V.PER_RECIPE then
        lines[#lines + 1] = { kind = "more", text = L["+%d more"]:format(#r.who - V.PER_RECIPE) }
        break
      end
      local where = c.mine and L["your character"]
        or c.online and L["online"]
        or (c.t and W.Ago(c.t, GetServerTime()))
        or ""
      lines[#lines + 1] = {
        kind = "crafter",
        name = c.name,
        recipe = r.recipe,
        mine = c.mine,
        online = c.online,
        text = c.name .. W.Dim("  ·  " .. where .. (c.skill and ("  ·  " .. c.skill) or "")),
      }
    end
  end
  return lines
end

function V:Create()
  local f = CreateFrame("Frame", "AMECraftersFrame", UIParent, "BackdropTemplate")
  W.Skin(f, W.COLORS.bg, W.COLORS.accent)
  f:SetSize(380, 72 + V.ROWS * 18)
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
  title:SetPoint("TOPLEFT", 10, -10)
  title:SetText(W.Color("brand", "AME") .. "  " .. L["Who can make it"])
  W.CloseButton(f, function()
    f:Hide()
  end):SetPoint("TOPRIGHT", -4, -4)
  f.box = W.Input(f, { hint = L["an item or enchant"] })
  f.box:SetPoint("TOPLEFT", 10, -32)
  f.box:SetPoint("RIGHT", -10, 0)
  f.box:SetScript("OnTextChanged", function()
    V:Render()
  end)
  f.box:SetScript("OnEscapePressed", function(box)
    box:ClearFocus()
  end)
  f.rows = {}
  for i = 1, V.ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetHeight(18)
    r:SetPoint("TOPLEFT", 10, -58 - (i - 1) * 18)
    r:SetPoint("RIGHT", -10, 0)
    r.text = W.Text(r, "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 0, 0)
    r.text:SetPoint("RIGHT", -70, 0)
    r.text:SetWordWrap(false)
    r.whisper = W.Button(r, L["Whisper"], 64, 16)
    r.whisper:SetPoint("RIGHT", 0, 0)
    f.rows[i] = r
  end
  f.empty = W.Text(f, "GameFontDisableSmall")
  f.empty:SetPoint("TOPLEFT", 10, -62)
  f.empty:SetPoint("RIGHT", -10, 0)
  f.empty:SetJustifyH("LEFT")
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
  for i, r in ipairs(f.rows) do
    local line = lines[i]
    if line then
      local text = line.text
      if line.kind == "recipe" then
        text = W.Color("gold", text) .. W.Dim("  " .. L["%d can make it"]:format(line.n))
      elseif line.kind == "crafter" then
        text = "   " .. (line.online and W.Color("good", "• ") or W.Dim("• ")) .. text
      else
        text = "   " .. W.Dim(text)
      end
      r.text:SetText(text)
      r.whisper:SetShown(line.kind == "crafter" and not line.mine)
      r.whisper:SetScript("OnClick", function()
        V.Whisper(line.name, line.recipe)
      end)
      r:Show()
    else
      r:Hide()
    end
  end
  local typed = f.box:GetText() ~= ""
  f.empty:SetShown(#lines == 0)
  f.empty:SetText(
    typed and L["Nobody you share with knows a recipe by that name yet."]
      or L["Type part of an item or enchant name. Your guildmates' recipes arrive with sync; open each of your professions once so yours count too."]
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

-- the tooltip's Shift line: who can make this item (yours first, then online)
function V.MadeBy(itemID)
  local crafters = ns.Crafters and ns.Crafters.Shared()
  if not (crafters and itemID) then
    return nil
  end
  local names, n = {}, 0
  local seen = {}
  for _, recipe in ipairs(ns.Crafters.RecipesFor(itemID)) do
    for _, c in ipairs(crafters:WhoKnows(recipe)) do
      if not seen[c.name] then
        seen[c.name] = true
        n = n + 1
        if #names < 3 then
          names[#names + 1] = (c.online and W.Color("good", c.name) or c.name)
            .. (c.mine and W.Dim(" " .. L["(you)"]) or "")
        end
      end
    end
  end
  if n == 0 then
    return nil
  end
  return table.concat(names, ", ") .. (n > #names and W.Dim(" +" .. (n - #names)) or "")
end
