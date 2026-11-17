-- Guards the translations: enUS must match the L["..."] keys in the code, every translation must translate a real
-- key, and a translated format string must take the same arguments (a missing or extra %d errors in game).
local LOCALES = { "deDE", "frFR", "esES", "ruRU", "ptBR", "itIT", "koKR", "zhCN", "zhTW" }

-- Load a locale file with a stub AceLocale that records what it assigns.
local function load(code)
  local recorded = {}
  local stub = {
    NewLocale = function()
      return recorded
    end,
  }
  local saved = _G.LibStub
  _G.LibStub = function()
    return stub
  end
  local chunk = assert(loadfile("Locales/" .. code .. ".lua"))
  local ok, err = pcall(chunk, "AzerothMercantileExchange", {})
  _G.LibStub = saved
  assert(ok, err)
  return recorded
end

-- format specifiers in order ("%d", "%.1f", "%+d"); a plain "%" in prose ("5% at") is not one
local function specifiers(s)
  local out = {}
  for spec in s:gsub("%%%%", ""):gmatch("%%[-+#0]*%d*%.?%d*[%a]") do
    out[#out + 1] = spec
  end
  return table.concat(out, " ")
end

describe("locales", function()
  local english = load("enUS")

  it("enUS lists exactly the keys the code uses (run lua5.1 scripts/locale-keys.lua)", function()
    local ok = os.execute("lua5.1 scripts/locale-keys.lua --check >/dev/null")
    assert.is_true(ok == 0 or ok == true)
  end)

  it("enUS is not empty", function()
    assert.is_truthy(next(english))
  end)

  for _, code in ipairs(LOCALES) do
    describe(code, function()
      local strings = load(code)

      it("only translates keys the code uses", function()
        local unknown = {}
        for key in pairs(strings) do
          if not english[key] then
            unknown[#unknown + 1] = key
          end
        end
        table.sort(unknown)
        assert.are.same({}, unknown)
      end)

      it("keeps the format specifiers of every key", function()
        local bad = {}
        for key, text in pairs(strings) do
          assert.are.equal("string", type(text), key)
          if specifiers(key) ~= specifiers(text) then
            bad[#bad + 1] = key .. " -> " .. text
          end
        end
        table.sort(bad)
        assert.are.same({}, bad)
      end)

      it("keeps WoW escape codes balanced (|c needs |r)", function()
        local bad = {}
        for key, text in pairs(strings) do
          local _, kc = key:gsub("|c", "")
          local _, tc = text:gsub("|c", "")
          local _, kr = key:gsub("|r", "")
          local _, tr = text:gsub("|r", "")
          if kc ~= tc or kr ~= tr then
            bad[#bad + 1] = key
          end
        end
        assert.are.same({}, bad)
      end)
    end)
  end
end)
