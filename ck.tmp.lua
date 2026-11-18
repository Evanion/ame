local p = "Core/UI/Widgets.lua"
local f = io.open(p, "rb"); local s = f:read("*a"); f:close()
local function rep(a, b) local i, j = s:find(a, 1, true); assert(i, a:sub(1, 60)); s = s:sub(1, i-1) .. b .. s:sub(j+1) end
rep([==[  -- selected buttons take the new accent
  for b in pairs(W.buttons) do
    if b.selected then
      b:SetSelected(true)
    end
  end
end

W.buttons = setmetatable({}, { __mode = "k" }) -- every W.Button, for re-tinting on a theme change
]==], [==[  -- selected buttons and ticked checkboxes take the new accent
  for b in pairs(W.buttons) do
    if b.selected then
      b:SetSelected(true)
    end
  end
  for c in pairs(W.checks) do
    c:SetChecked(c.checked)
  end
end

W.buttons = setmetatable({}, { __mode = "k" }) -- every W.Button, for re-tinting on a theme change
W.checks = setmetatable({}, { __mode = "k" }) -- every W.Check, likewise
]==])
rep([==[  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetTexture("Interface\Buttons\UI-CheckBox-Check")
  b.mark:SetPoint("CENTER")
  b.mark:SetSize(16, 16)
]==], [==[  -- ticked: an accent-coloured square inside the box (the game's check texture doesn't show on every client)
  b.mark = b:CreateTexture(nil, "OVERLAY")
  b.mark:SetPoint("TOPLEFT", 4, -4)
  b.mark:SetPoint("BOTTOMRIGHT", -4, 4)
]==])
rep([==[    self.mark:SetShown(self.checked)
    local a = self.checked and W.COLORS.accent or W.COLORS.border
]==], [==[    self.mark:SetShown(self.checked)
    local accent = W.COLORS.accent
    self.mark:SetColorTexture(accent[1], accent[2], accent[3], 1)
    local a = self.checked and accent or W.COLORS.border
]==])
rep([==[  b:SetChecked(false)
  return b
end]==], [==[  b:SetChecked(false)
  W.checks[b] = true
  return b
end]==])
f = io.open(p, "wb"); f:write(s); f:close()
