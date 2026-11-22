-- DataTable (Core/UI/DataTable.lua) on the stubbed client's frames: sorting, how many rows a filling table shows,
-- the note under the rows, share bars, item links in rows and button cells.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("DataTable", function()
  local env, ns, W, DT, shown

  before_each(function()
    env = wow.install()
    ns = addon.load({ "Core/Init.lua", "Core/ItemCache.lua", "Core/UI/Widgets.lua", "Core/UI/DataTable.lua" })
    W, DT = ns.Widgets, ns.DataTable
    W.SetTheme("Horde")
    shown = {}
    ns.AME = {}
    ns.UI = {
      ShowItem = function(_, key)
        shown[#shown + 1] = key
      end,
    }
  end)

  after_each(function()
    env:restore()
  end)

  local function new(opts)
    opts.columns = opts.columns
      or {
        { key = "name", label = "Item", width = 150, item = true },
        { key = "price", label = "Price", width = 70, format = "money" },
      }
    opts.itemID = opts.itemID or function(d)
      return d.id
    end
    local parent = CreateFrame("Frame", nil, UIParent)
    parent:SetSize(500, 400)
    local t = DT.New(parent, opts)
    if opts.fill then
      t.frame:SetSize(500, opts.height or 400)
    else
      t.frame:SetWidth(500) -- a fixed table keeps its own height
    end
    return t
  end

  local function texts(t, c)
    local out = {}
    for r = 1, t.visible do
      local row = t.rows[r]
      if row:IsShown() then
        out[#out + 1] = row.cells[c]:GetText()
      end
    end
    return out
  end

  it("sorts by a column on a header click, and back the other way on the next", function()
    local t = new({ rows = 5 })
    t:SetData({ { id = 1, price = 300 }, { id = 2, price = 100 }, { id = 3, price = 200 } })
    t:Render()
    local price = t.headers[2]
    price.scripts.OnClick(price)
    assert.are.same({ 300, 200, 100 }, { t.data[1].price, t.data[2].price, t.data[3].price }) -- most first
    price.scripts.OnClick(price)
    assert.are.same({ 100, 200, 300 }, { t.data[1].price, t.data[2].price, t.data[3].price })
  end)

  it("fills its height with rows: as many as fit under the header", function()
    local t = new({ rows = 3, fill = true, height = 20 + 10 * 22 })
    t:SetData({})
    t:Render()
    assert.are.equal(10, t.visible)
    t.frame:SetHeight(20 + 4 * 22 + 10) -- part of a row left over: not shown
    t:Render()
    assert.are.equal(4, t.visible)
  end)

  it("a bare table has no header row: its rows start at the top", function()
    local t = new({ rows = 3, fill = true, bare = true, height = 10 * 22 })
    t:SetData({})
    t:Render()
    assert.are.equal(10, t.visible)
    assert.is_false(t.headers[1]:IsShown())
    assert.are.equal(0, t.rows[1].points[1][3])
  end)

  it("makes room for a note under the rows", function()
    local t = new({ rows = 3, fill = true, height = 20 + 10 * 22 })
    t:SetData({})
    t:SetNote("Faded rows are more than a week old.")
    t:Render()
    -- the note (one 12 px line and its margins) takes the last row's room
    assert.are.equal(9, t.visible)
    assert.is_true(t.note:IsShown())
    t:SetNote(nil)
    t:Render()
    assert.are.equal(10, t.visible)
    -- a fixed table grows by its note instead
    local fixed = new({ rows = 3, note = "A note." })
    assert.are.equal(20 + 3 * 22 + fixed:NoteSpace(), fixed.frame:GetHeight())
  end)

  it("draws share bars full at the column's max, with the percent beside them", function()
    local t = new({
      rows = 3,
      columns = {
        {
          key = "name",
          label = "Category",
          width = 150,
          text = function(d)
            return d.name
          end,
        },
        { key = "share", label = "Share", width = 110, format = "share", max = 0.4 },
      },
    })
    t:SetData({ { name = "Herbs", share = 0.2 }, { name = "Ore", share = 0.5 }, { name = "None", share = 0 } })
    t:Render()
    local s1, s2, s3 = t.rows[1].shares[2], t.rows[2].shares[2], t.rows[3].shares[2]
    assert.are.equal(32, s1.width) -- half of the 64 px track at half the max
    assert.are.equal(64, s2.width) -- past the max: full, not wider
    assert.are.equal(0, s3.width)
    assert.is_false(s3.bar:IsShown())
    assert.are.same({ "20%", "50%", "0%" }, texts(t, 2))
  end)

  it("signs money in signedMoney columns", function()
    local t = new({
      rows = 2,
      columns = {
        { key = "name", label = "Item", width = 150, item = true },
        { key = "net", label = "Net", width = 70, format = "signedMoney" },
      },
    })
    t:SetData({ { id = 1, net = 12000 }, { id = 2, net = -3500 } })
    t.sort = {}
    t:Resort()
    t:Render()
    assert.are.same({ W.SignedMoney(12000), W.SignedMoney(-3500) }, texts(t, 2))
  end)

  describe("item rows", function()
    local picked
    local function table_(extra)
      picked = {}
      local opts = {
        rows = 3,
        onClick = function(d)
          picked[#picked + 1] = d.id
        end,
      }
      for k, v in pairs(extra or {}) do
        opts[k] = v
      end
      local t = new(opts)
      t:SetData({ { id = 2589, price = 5 } })
      t:Render()
      return t, t.rows[1]
    end

    it("a modified click links the item (HandleModifiedItemClick), before the owner's click", function()
      local _, row = table_()
      env.modified = "CHATLINK"
      row.scripts.OnClick(row, "LeftButton")
      assert.are.same({ "|Hitem:2589|h" }, env.modifiedLinks)
      assert.are.same({}, picked)
      env.modified = nil
      row.scripts.OnClick(row, "LeftButton")
      assert.are.same({ 2589 }, picked)
    end)

    it("with shiftClick, Shift is the owner's while no chat box is open, a link when one is", function()
      local _, row = table_({ shiftClick = true })
      env.modified = "CHATLINK"
      row.scripts.OnClick(row, "LeftButton")
      assert.are.same({ 2589 }, picked) -- the owner's (search the AH)
      assert.is_nil(env.modifiedLinks)
      _G.ChatEdit_GetActiveWindow = function()
        return {}
      end
      row.scripts.OnClick(row, "LeftButton")
      _G.ChatEdit_GetActiveWindow = nil
      assert.are.same({ "|Hitem:2589|h" }, env.modifiedLinks)
      assert.are.same({ 2589 }, picked)
    end)

    it("another item column has its own icon and link; a plain click on it is the row's", function()
      local t = new({
        rows = 2,
        onClick = function(d)
          shown[#shown + 1] = "row " .. d.id
        end,
        columns = {
          { key = "name", label = "Item", width = 150, item = true },
          {
            key = "made",
            label = "Craft",
            width = 150,
            item = function(d)
              return d.made
            end,
          },
        },
      })
      t:SetData({ { id = 2589, made = 2996 } })
      t:Render()
      local row = t.rows[1]
      local link = row.links[2]
      assert.are.equal(2996, link.key)
      assert.are.equal("|cffffffffItem 2996|r", row.cells[2]:GetText())
      assert.is_true(link:IsShown())
      env.modified = "CHATLINK"
      link.scripts.OnClick(link, "LeftButton")
      assert.are.same({ "|Hitem:2996|h" }, env.modifiedLinks)
      env.modified = nil
      link.scripts.OnClick(link, "LeftButton")
      assert.are.same({ "row 2589" }, shown)
      -- it sorts by its item's name, and exports it
      t.headers[2].scripts.OnClick(t.headers[2])
      assert.are.equal("__name:made", t.sort.key)
      assert.are.equal("item 2996", t:SortValue(t.data[1], "__name:made"))
      assert.truthy(t:ExportText():find("Item 2996", 1, true))
    end)
  end)

  it("draws a button per row with its own label and look", function()
    local clicked
    local t = new({
      rows = 2,
      columns = {
        { key = "name", label = "Item", width = 150, item = true },
        {
          key = "act",
          label = "",
          width = 50,
          button = {
            label = function(d)
              return d.buy and "Buy" or "x"
            end,
            variant = function(d)
              return d.buy and "primary" or nil
            end,
            onClick = function(d)
              clicked = d.id
            end,
          },
        },
      },
    })
    t:SetData({ { id = 1, buy = true }, { id = 2 } })
    t.sort = {}
    t:Resort()
    t:Render()
    local b1, b2 = t.rows[1].buttons[2], t.rows[2].buttons[2]
    assert.are.equal("Buy", b1:GetText())
    assert.is_true(b1.primary)
    assert.are.equal("x", b2:GetText())
    assert.is_false(b2.primary)
    b2.scripts.OnClick(b2)
    assert.are.equal(2, clicked)
    assert.is_falsy(t:ExportText():find("Buy", 1, true)) -- buttons aren't exported
  end)
end)
