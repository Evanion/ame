-- The price check prompt: someone typed "!pc <item>" and AME has the answer ready. The game (12.x) only lets addons
-- send chat from a click, so the answer waits here for you to click Send. It goes away when someone else answers, or
-- after PriceCheck.ANSWER_TIMEOUT (the next AME player in line is offered it then).
local _, ns = ...
local L = ns.L
local W = ns.Widgets
local PC = ns.PriceCheck

local CHANNEL = {
  GUILD = L["guild chat"],
  PARTY = L["party chat"],
  RAID = L["raid chat"],
  WHISPER = L["a whisper"],
}

local frame

local function build()
  local f = CreateFrame("Frame", "AME_PriceCheckPrompt", UIParent, "BackdropTemplate")
  f:SetSize(360, 112)
  -- where you last dragged it (AME_DB.priceCheckPrompt), else near the top of the screen
  local pos = AME_DB and AME_DB.priceCheckPrompt
  if pos then
    f:SetPoint(pos[1], UIParent, pos[1], pos[2], pos[3])
  else
    f:SetPoint("TOP", UIParent, "TOP", 0, -160)
  end
  f:SetFrameStrata("DIALOG")
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    if point and AME_DB then
      AME_DB.priceCheckPrompt = { point, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
  end)
  W.Skin(f, W.COLORS.bg, W.COLORS.accent)

  f.title = W.Text(f, "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText(L["Price check"])

  f.close = W.CloseButton(f, function()
    PC:DropOffer()
  end)
  f.close:SetPoint("TOPRIGHT", -4, -4)

  f.who = W.Text(f, "GameFontHighlightSmall")
  f.who:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -6)
  f.who:SetPoint("RIGHT", -12, 0)

  f.answer = W.Text(f, "GameFontDisableSmall")
  f.answer:SetPoint("TOPLEFT", f.who, "BOTTOMLEFT", 0, -4)
  f.answer:SetPoint("RIGHT", -12, 0)
  f.answer:SetWordWrap(true)

  f.send = W.Button(f, L["Send answer"], 120, 22, function()
    PC:SendOffer()
  end)
  f.send:SetPoint("BOTTOMRIGHT", -12, 10)

  f.hint = W.Text(f, "GameFontDisableSmall")
  f.hint:SetPoint("LEFT", 12, 0)
  f.hint:SetPoint("BOTTOM", f.send, "BOTTOM", 0, 5)
  f.hint:SetPoint("RIGHT", f.send, "LEFT", -8, 0)
  f.hint:SetText(L["The game only lets addons send chat when you click. Drag to move."])
  f.hint:SetWordWrap(true)

  f:Hide()
  return f
end

-- PriceCheck calls this with the offer to show, or nil when it goes away
function PC.onOffer(offer)
  if not offer then
    if frame then
      frame:Hide()
    end
    return
  end
  frame = frame or build()
  PC.prompt = frame
  local asker = PC.CharName(offer.asker) or offer.asker or "?"
  frame.who:SetText(L["%s asked in %s:"]:format(asker, CHANNEL[offer.channel] or offer.channel))
  frame.answer:SetText(offer.text)
  frame:SetHeight(math.max(112, 84 + frame.answer:GetStringHeight()))
  frame:Show()
  -- lapses with the offer
  C_Timer.After(PC.ANSWER_TIMEOUT, function()
    if PC.offer == offer then
      PC:DropOffer()
    end
  end)
end
