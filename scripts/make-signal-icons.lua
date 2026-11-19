-- Draws the signal icons (media/Signals/*.tga): white shapes on transparency, tinted in game per signal.
--   lua5.1 scripts/make-signal-icons.lua
-- 32x32, 4x4 supersampled edges. Up / Down triangles (BUY / SELL), Dot (HOLD), Pause (WAIT), Coin (VENDOR),
-- Shard (DE: a cut gem, a diamond with its girdle line).
local SIZE, SS = 32, 4

local function inTriangle(px, py, ax, ay, bx, by, cx, cy)
  local function sign(x1, y1, x2, y2, x3, y3)
    return (x1 - x3) * (y2 - y3) - (x2 - x3) * (y1 - y3)
  end
  local d1, d2, d3 = sign(px, py, ax, ay, bx, by), sign(px, py, bx, by, cx, cy), sign(px, py, cx, cy, ax, ay)
  local neg = d1 < 0 or d2 < 0 or d3 < 0
  local pos = d1 > 0 or d2 > 0 or d3 > 0
  return not (neg and pos)
end

-- shapes in a 0..1 square, y up
local SHAPES = {
  Up = function(x, y)
    return inTriangle(x, y, 0.5, 0.86, 0.1, 0.18, 0.9, 0.18)
  end,
  Down = function(x, y)
    return inTriangle(x, y, 0.5, 0.14, 0.1, 0.82, 0.9, 0.82)
  end,
  Dot = function(x, y)
    return (x - 0.5) ^ 2 + (y - 0.5) ^ 2 <= 0.3 ^ 2
  end,
  Pause = function(x, y)
    return y >= 0.18 and y <= 0.82 and ((x >= 0.22 and x <= 0.42) or (x >= 0.58 and x <= 0.78))
  end,
  Shard = function(x, y)
    local d = math.abs(x - 0.5) / 0.32 + math.abs(y - 0.5) / 0.42
    return d <= 1 and not (math.abs(y - 0.62) < 0.035 and d <= 0.9) -- the girdle line across the top half
  end,
  Coin = function(x, y)
    local r2 = (x - 0.5) ^ 2 + (y - 0.5) ^ 2
    return r2 <= 0.4 ^ 2 and r2 >= 0.22 ^ 2 or r2 <= 0.1 ^ 2
  end,
}

local function writeTGA(path, alpha)
  local f = assert(io.open(path, "wb"))
  -- header: no id, no colour map, uncompressed true colour, 32 bpp, 8 alpha bits, origin bottom-left
  f:write(
    string.char(
      0,
      0,
      2,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      SIZE % 256,
      math.floor(SIZE / 256),
      SIZE % 256,
      math.floor(SIZE / 256),
      32,
      8
    )
  )
  for row = 0, SIZE - 1 do -- bottom row first
    local out = {}
    for col = 0, SIZE - 1 do
      local a = alpha[row][col]
      out[#out + 1] = string.char(255, 255, 255, a) -- B G R A
    end
    f:write(table.concat(out))
  end
  f:close()
end

for name, inside in pairs(SHAPES) do
  local alpha = {}
  for row = 0, SIZE - 1 do
    alpha[row] = {}
    for col = 0, SIZE - 1 do
      local hits = 0
      for sy = 0, SS - 1 do
        for sx = 0, SS - 1 do
          local x = (col + (sx + 0.5) / SS) / SIZE
          local y = (row + (sy + 0.5) / SS) / SIZE
          if inside(x, y) then
            hits = hits + 1
          end
        end
      end
      alpha[row][col] = math.floor(hits / (SS * SS) * 255 + 0.5)
    end
  end
  writeTGA("media/Signals/" .. name .. ".tga", alpha)
  print("media/Signals/" .. name .. ".tga")
end
