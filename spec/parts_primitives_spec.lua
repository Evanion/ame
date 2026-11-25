-- Core/UI/Parts/Primitives.lua: the small widgets every screen is made of, drawn by the layout engine on the stubbed
-- client: they validate, draw their props, size themselves and report clicks as named actions.
local wow = require("spec.helpers.wow")
local addon = require("spec.helpers.addon")

describe("primitive widgets", function()
  local env, ns, Layout, r, got

  before_each(function()
    env = wow.install()
    ns = addon.load({
      "Core/Init.lua",
      "Core/Settings.lua",
      "Core/ItemCache.lua",
      "Core/UI/Tokens.lua",
      "Core/UI/Kit.lua",
      "Core/UI/Layout.lua",
      "Core/UI/Widgets.lua",
      "Core/UI/Parts/Primitives.lua",
    })
    _G.AME_DB = { settings = {} }
    Layout = ns.Layout
    got = {}
    local ctx = Layout.Context(setmetatable({}, {
      __index = function(_, name)
        return function(payload)
          got[#got + 1] = { name, payload }
        end
      end,
    }))
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetSize(600, 400)
    r = Layout.Renderer(root, ctx)
  end)

  after_each(function()
    env:restore()
  end)

  local tree = {
    id = "top",
    type = "column",
    props = { gap = 4 },
    children = {
      { id = "t", type = "text", props = { text = "Hello", font = "display" } },
      { id = "b", type = "button", props = { label = "Queue", action = "queue", payload = 7, variant = "primary" } },
      { id = "off", type = "button", props = { label = "At the AH", action = "post", variant = "disabled" } },
      { id = "i", type = "input", props = { value = "lotus", hint = "Search", action = "search" } },
      { id = "f", type = "field", props = { label = "Tip", value = "5g", action = "tip" } },
      { id = "c", type = "check", props = { label = "I bring them", checked = true, action = "bring", payload = 2 } },
      {
        id = "s",
        type = "segmented",
        props = { options = { { "all", "All" }, { "ready", "Ready now" } }, selected = "all", action = "filter" },
      },
      { id = "m", type = "money", props = { copper = 12345 } },
      { id = "kv", type = "keyvalue", props = { label = "You pay", copper = 510000, total = true } },
      { id = "tag", type = "tag", props = { text = "AH", kind = "ah" } },
      {
        id = "card",
        type = "card",
        props = { title = "Selling it", gap = 2 },
        meta = { h = 100 },
        children = {
          { id = "card.a", type = "keyvalue", props = { label = "Reagents", copper = 9838 } },
        },
      },
    },
  }

  it("the whole tree validates", function()
    assert.same({}, Layout.Validate(tree))
  end)

  it("draws each widget from its props", function()
    r:Render(tree)
    assert.equals("Hello", r:Frame("t").fs:GetText())
    assert.equals("Queue", r:Frame("b").label:GetText())
    assert.equals("lotus", r:Frame("i"):GetText())
    assert.equals("Tip", r:Frame("f").label:GetText())
    assert.is_true(r:Frame("c").checked)
    assert.equals(2, #r:Frame("s").buttons)
    assert.equals("selected", r:Frame("s").buttons[1].variant)
    assert.matches("1g", r:Frame("m").fs:GetText())
    assert.equals("You pay", r:Frame("kv").label:GetText())
  end)

  it("reports clicks as named actions with their payloads", function()
    r:Render(tree)
    r:Frame("b").scripts.OnClick(r:Frame("b"))
    r:Frame("off").scripts.OnClick(r:Frame("off"))
    r:Frame("c").scripts.OnClick(r:Frame("c"))
    r:Frame("s").buttons[2].scripts.OnClick(r:Frame("s").buttons[2])
    local box = r:Frame("i")
    box:SetText("dreamfoil")
    box.scripts.OnEnterPressed(box)
    assert.same({ "queue", 7 }, got[1])
    assert.same({ "bring", { payload = 2, checked = false } }, got[2]) -- the disabled button sent nothing
    assert.same({ "filter", { key = "ready" } }, got[3])
    assert.same({ "search", { text = "dreamfoil" } }, got[4])
  end)

  it("an item search box suggests matching items in a dropdown, 150 ms after the typing pauses", function()
    local index = { items = { [2452] = {}, [2459] = {} } }
    ns.AME = {
      CachedIndex = function()
        return index
      end,
    }
    ns.App = {
      Shard = function()
        return "R|Horde"
      end,
    }
    ns.MarketFilter = {
      FindByName = function(_, text)
        return text == "swift" and { { itemID = 2452 }, { itemID = 2459 } } or {}
      end,
    }
    local menus = {}
    ns.Widgets.Menu = function(anchor, entries, opts)
      menus[#menus + 1] = { anchor = anchor, entries = entries, opts = opts }
    end
    ns.Widgets.HideMenu = function() end
    r:Render({ id = "q", type = "input", props = { action = "find", suggest = true } })
    local box = r:Frame("q")
    box.HasFocus = function()
      return true
    end
    box:SetText("swi")
    box.scripts.OnTextChanged(box, true)
    box:SetText("swift")
    box.scripts.OnTextChanged(box, true)
    env:advance(0.1)
    assert.equals(0, #menus) -- still typing
    env:advance(0.1)
    assert.equals(1, #menus) -- once, for the last key only
    assert.equals(box, menus[1].anchor) -- under the box
    assert.equals(2452, menus[1].entries[1].item)
    menus[1].entries[1].func()
    assert.same({ "find", { item = 2452 } }, got[#got])
  end)

  it("a card puts its children under its title, inside its padding", function()
    r:Render(tree)
    local kid = r:Frame("card.a")
    assert.equals(r:Frame("card").content, kid:GetParent())
    assert.equals(600 - 20, kid:GetWidth())
  end)

  it("a button and a segmented row size themselves to their labels", function()
    r:Render(tree)
    local w = Layout.Natural({ frame = r:Frame("b"), item = Layout.Find(tree, "b") }, "w")
    assert.is_true(w >= 24)
    assert.equals(24, Layout.Natural({ frame = r:Frame("s"), item = Layout.Find(tree, "s") }, "h"))
  end)
end)
