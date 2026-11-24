-- Draws the window's line icons (media/Icons/*.tga) from the design boards' own SVGs (TitleBar.dc.html): white
-- strokes on transparency, tinted in game (the tab colour, white on hover), as the boards' currentColor does.
--   lua5.1 scripts/make-ui-icons.lua
-- 64x64 for the boards' 16-unit viewBox (4 px a unit), 4x4 supersampled edges. Coordinates are the SVG's (y down).
local SIZE, SS, UNIT = 64, 4, 4

-- distance from p to the segment a-b, and where along it p projects (0..1 inside)
local function segment(px, py, ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  local len2 = dx * dx + dy * dy
  local t = len2 > 0 and ((px - ax) * dx + (py - ay) * dy) / len2 or 0
  local ct = math.max(0, math.min(1, t))
  local qx, qy = ax + ct * dx, ay + ct * dy
  return math.sqrt((px - qx) ^ 2 + (py - qy) ^ 2), t
end

-- a stroked line: cap "butt" (the SVG default) stops at the ends, "round" rounds them (and so joins a path's corners)
local function line(ax, ay, bx, by, w, cap)
  return function(x, y)
    local d, t = segment(x, y, ax, ay, bx, by)
    if cap == "butt" and (t < 0 or t > 1) then
      return false
    end
    return d <= w / 2
  end
end

-- a stroked circle, or the part of one between two angles (radians, SVG's y-down sense)
local function ring(cx, cy, r, w, from, to)
  return function(x, y)
    local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
    if math.abs(d - r) > w / 2 then
      return false
    end
    if not from then
      return true
    end
    local a = math.atan2(y - cy, x - cx)
    return a >= from and a <= to
  end
end

local function any(parts)
  return function(x, y)
    for _, p in ipairs(parts) do
      if p(x, y) then
        return true
      end
    end
    return false
  end
end

local ICONS = {}

-- <circle cx="8" cy="8" r="2.4"/> and eight spokes, stroke 1.5
do
  local w, parts = 1.5, { ring(8, 8, 2.4, 1.5) }
  for _, s in ipairs({
    { 8, 1.5, 8, 3.5 },
    { 8, 12.5, 8, 14.5 },
    { 1.5, 8, 3.5, 8 },
    { 12.5, 8, 14.5, 8 },
    { 3.4, 3.4, 4.8, 4.8 },
    { 11.2, 11.2, 12.6, 12.6 },
    { 3.4, 12.6, 4.8, 11.2 },
    { 11.2, 4.8, 12.6, 3.4 },
  }) do
    parts[#parts + 1] = line(s[1], s[2], s[3], s[4], w, "butt")
  end
  ICONS.Cog = any(parts)
end

-- M4 11V7 a4 4 0 0 1 8 0 v4 l1.2 1.5 H2.8 L4 11z  M6.5 14h3, stroke 1.5 (the arc is the top half round 8,7)
do
  local w = 1.5
  ICONS.Bell = any({
    line(4, 11, 4, 7, w, "round"),
    ring(8, 7, 4, w, -math.pi, 0),
    line(12, 7, 12, 11, w, "round"),
    line(12, 11, 13.2, 12.5, w, "round"),
    line(13.2, 12.5, 2.8, 12.5, w, "round"),
    line(2.8, 12.5, 4, 11, w, "round"),
    line(6.5, 14, 9.5, 14, w, "butt"),
  })
end

-- M3 3l10 10M13 3L3 13, stroke 1.6
ICONS.Close = any({ line(3, 3, 13, 13, 1.6, "butt"), line(13, 3, 3, 13, 1.6, "butt") })

local function writeTGA(path, alpha)
  local f = assert(io.open(path, "wb"))
  -- no id, no colour map, uncompressed true colour, 32 bpp, 8 alpha bits, origin top-left (bit 5)
  f:write(string.char(0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, SIZE % 256, math.floor(SIZE / 256), SIZE % 256, math.floor(SIZE / 256), 32, 40))
  for row = 0, SIZE - 1 do
    local out = {}
    for col = 0, SIZE - 1 do
      out[#out + 1] = string.char(255, 255, 255, alpha[row][col]) -- B G R A
    end
    f:write(table.concat(out))
  end
  f:close()
end

local names = {}
for name in pairs(ICONS) do
  names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
  local inside, alpha = ICONS[name], {}
  for row = 0, SIZE - 1 do
    alpha[row] = {}
    for col = 0, SIZE - 1 do
      local hits = 0
      for sy = 0, SS - 1 do
        for sx = 0, SS - 1 do
          if inside((col + (sx + 0.5) / SS) / UNIT, (row + (sy + 0.5) / SS) / UNIT) then
            hits = hits + 1
          end
        end
      end
      alpha[row][col] = math.floor(hits / (SS * SS) * 255 + 0.5)
    end
  end
  writeTGA("media/Icons/" .. name .. ".tga", alpha)
  print("media/Icons/" .. name .. ".tga")
end
