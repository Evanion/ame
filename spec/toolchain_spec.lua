-- Guards the test environment itself: WoW runs Lua 5.1, so the pure-logic modules must be tested on 5.1.
describe("toolchain", function()
  it("runs on Lua 5.1 like the WoW client", function()
    assert.are.equal("Lua 5.1", _VERSION)
  end)

  it("has 5.1 integer/float semantics (no integer subtype)", function()
    assert.are.equal("number", type(1))
    assert.are.equal(0.5, 1 / 2)
  end)

  it("keeps the backslashes in texture paths (a lost one silently breaks the texture)", function()
    local bad = {}
    for line in io.lines("AzerothMercantileExchange.toc") do
      line = line:gsub("\r", "")
      if line:match("%.lua$") then
        local path = line:gsub("\\", "/")
        local n = 0
        for code in io.lines(path) do
          n = n + 1
          if code:find('"Interface[%a]') then
            bad[#bad + 1] = path .. ":" .. n
          end
        end
      end
    end
    assert.are.same({}, bad)
  end)

  it("ships the addon icon the TOC points at", function()
    local icon
    for line in io.lines("AzerothMercantileExchange.toc") do
      icon = icon or line:match("^## IconTexture: Interface.AddOns.AzerothMercantileExchange.(.+)$")
    end
    assert.is_not_nil(icon, "IconTexture should point inside the addon")
    local file = io.open(icon:gsub("\r", ""):gsub("\\", "/") .. ".tga", "rb")
    assert.is_not_nil(file, "missing " .. icon .. ".tga")
    file:close()
  end)
end)

-- Guards the UI's shared pieces (docs/plans/ui-components.md): views draw item names, main actions, chat lines and
-- side menus with the widgets, not by hand. Each rule lists the offending file:line.
describe("Data core rules", function()
  -- file:line of every line (not a comment) in the Core/UI files the TOC loads that has the text
  local function offenders(pattern)
    local bad = {}
    for line in io.lines("AzerothMercantileExchange.toc") do
      line = line:gsub("\r", "")
      local path = line:match("^Core\\UI\\.+%.lua$") and line:gsub("\\", "/")
      if path then
        local n = 0
        for code in io.lines(path) do
          n = n + 1
          if not code:match("^%s*%-%-") and code:find(pattern, 1, true) then
            bad[#bad + 1] = path .. ":" .. n
          end
        end
      end
    end
    return bad
  end

  -- the numbers every view shows come from the core (docs/plans/data-core.md): a view that works out a cut, a
  -- deposit or an item's facts itself is how two screens came to disagree
  it("reads the UI files", function()
    assert.is_true(#offenders("ns.Quote.") > 5) -- the views do ask the core
  end)

  it("works out no auction house cut in a view (Quote.Cut, q.cut, Quote:ListingNet / BestSale / PostNet)", function()
    assert.are.same({}, offenders("Settings:AuctionCut"))
  end)

  it("works out no listing deposit in a view (Quote:Deposit, Arbitrage.Find's net)", function()
    assert.are.same({}, offenders("Arbitrage.Deposit"))
  end)

  it("reads no item facts from the client in a view (ItemCache.Get / Info)", function()
    assert.are.same({}, offenders("C_Item.GetItemInfo("))
    assert.are.same({}, offenders("C_Item and C_Item.GetItemInfo"))
  end)
end)

describe("UI rules", function()
  -- every Lua file under Core/UI the TOC loads, as { path, lines }
  local function uiFiles()
    local out = {}
    for line in io.lines("AzerothMercantileExchange.toc") do
      line = line:gsub("\r", "")
      local path = line:match("^Core\\UI\\.+%.lua$") and line:gsub("\\", "/")
      if path then
        local lines = {}
        for code in io.lines(path) do
          lines[#lines + 1] = code
        end
        out[#out + 1] = { path = path, name = path:match("([^/]+)%.lua$"), lines = lines }
      end
    end
    return out
  end
  -- file:line for every line (outside the files allowed) that the test matches
  local function offenders(test, allowed)
    local bad = {}
    for _, f in ipairs(uiFiles()) do
      if not (allowed and allowed[f.name]) then
        for n, code in ipairs(f.lines) do
          if not code:match("^%s*%-%-") and test(code) then
            bad[#bad + 1] = f.path .. ":" .. n
          end
        end
      end
    end
    return bad
  end

  it("finds the UI files", function()
    assert.is_true(#uiFiles() > 20)
  end)

  it(
    "draws no item name as plain coloured text in a view (W.ItemLink, W.LinkText or a DataTable item column)",
    function()
      -- Widgets builds the links themselves; a tooltip can't be clicked, so its names are only quality-coloured
      local bad = offenders(function(code)
        return code:find("W.QualityText(", 1, true)
            and (code:find("W.ItemLabel(", 1, true) or code:find("ItemCache.Name(", 1, true))
            and true
          or false
      end, { Widgets = true, Tooltip = true })
      assert.are.same({}, bad)
    end
  )

  it("marks main actions with W.Primary, not a selected button standing in for one", function()
    assert.are.same(
      {},
      offenders(function(code)
        return code:find("SetSelected(true)", 1, true) ~= nil
      end, { Widgets = true })
    )
  end)

  it("prints chat lines with AME's own prefix (ns.AME.Say), not a hand-coloured one", function()
    assert.are.same(
      {},
      offenders(function(code)
        return code:find("|cff33ccffAME", 1, true) ~= nil
      end)
    )
  end)

  it("draws side menus with UI.SideList: no hand-made selected lines outside the shared pieces", function()
    assert.are.same(
      {},
      offenders(function(code)
        return code:find("rowSelected", 1, true) ~= nil
      end, { Shell = true, DataTable = true, Widgets = true })
    )
  end)
end)
