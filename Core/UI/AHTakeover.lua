-- At the auction house with the new window on (Settings: At the auction house). "ame": AME's window is the auction
-- house: the game's window is put out of sight (not closed: closing it ends the visit) and AME's opens. "game": the
-- game's window, with AME's beside it when "open AME beside it" is on. "Use the game's AH" in AME's title bar and
-- "Open in AME" on the game's window swap between them, and the last one used is remembered (ahMode).
--
--   AHTakeover.OnShow()     AUCTION_HOUSE_SHOW
--   AHTakeover.OnClosed()   AUCTION_HOUSE_CLOSED
--   AHTakeover.UseGame()    swap to the game's window
--   AHTakeover.UseAME()     swap to AME's
local _, ns = ...
local L = ns.L

local T = {}
ns.AHTakeover = T

local function game()
  return _G.AuctionHouseFrame
end

local function app()
  return ns.App
end

local function on()
  local a = app()
  return a and a.Enabled and a.Enabled() or false
end

-- out of sight: invisible, a speck, and off the screen (its buttons can't catch a click); the visit stays open
local function tuck(f)
  if not f or f.ameTucked then
    return
  end
  f.ameTucked = { alpha = f:GetAlpha(), scale = f:GetScale() }
  f:SetAlpha(0)
  f:SetScale(0.001)
  if f.EnableMouse then
    f:EnableMouse(false)
  end
end

local function untuck(f)
  local saved = f and f.ameTucked
  if not saved then
    return
  end
  f.ameTucked = nil
  f:SetScale(saved.scale or 1)
  f:SetAlpha(saved.alpha or 1)
  if f.EnableMouse then
    f:EnableMouse(true)
  end
  if _G.UpdateUIPanelPositions then
    pcall(_G.UpdateUIPanelPositions, f) -- back in its place among the game's windows
  end
end

-- "Open in AME" on the game's window, left of its close button
local function swapButton(f)
  if not f or f.ameOpen then
    return
  end
  local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  b:SetSize(110, 22)
  local close = f.CloseButton or _G.AuctionHouseFrameCloseButton
  if close then
    b:SetPoint("RIGHT", close, "LEFT", -4, 0)
  else
    b:SetPoint("TOPRIGHT", -30, -1)
  end
  b:SetText(L["Open in AME"])
  b:SetScript("OnClick", function()
    T.UseAME()
  end)
  f.ameOpen = b
end

function T.UseGame()
  local f, a = game(), app()
  ns.Settings:Set("ahMode", "game")
  T.swapping = true
  untuck(f)
  if a then
    a:Hide()
  end
  T.swapping = false
  swapButton(f)
end

function T.UseAME()
  local f, a = game(), app()
  ns.Settings:Set("ahMode", "ame")
  tuck(f)
  if a then
    a:Show()
  end
end

function T.OnShow()
  if not on() then
    return false
  end
  local a = app()
  T.openBefore = a.frame and a.frame:IsShown() or false
  -- the game's window may build itself after the event: once it's there (next frame), place both
  C_Timer.After(0, function()
    local f = game()
    swapButton(f)
    if ns.Settings:Get("ahMode") == "game" then
      untuck(f)
      if ns.Settings:Get("openWithAH") then
        a:Show()
      end
    else
      tuck(f)
      a:Show()
    end
    a:Redraw()
  end)
  return true
end

function T.OnClosed()
  if not on() then
    return false
  end
  local a = app()
  untuck(game()) -- the game's window as the game left it, for the next visit
  if not T.openBefore and a.frame and a.frame:IsShown() then
    a:Hide()
  else
    a:Redraw()
  end
  T.openBefore = nil
  return true
end

-- AME's window closed while it is the auction house (its close button, Escape): the visit ends too, as closing the
-- game's window would end it
function T.WindowHidden()
  if T.swapping or not (on() and ns.AME and ns.AME.ahOpen) then
    return
  end
  local f = game()
  if f and f.ameTucked and C_AuctionHouse and C_AuctionHouse.CloseAuctionHouse then
    C_AuctionHouse.CloseAuctionHouse()
  end
end
