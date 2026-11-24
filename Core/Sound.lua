-- The notification sound (docs/ux/redesign-review.md, "Notifications outside the window"): one AME sound for what
-- waits on you - a price alert firing, a craft request arriving, and (off by default) an auction selling or being
-- undercut. It is picked from LibSharedMedia's sound list, AME's own first; AME ships no files, so its own are sounds
-- already in the game, registered into LibSharedMedia by file data ID so other addons can pick them too.
--
--   Sound.DEFAULT                      the name of AME's default sound
--   Sound.List() -> { name, ... }      AME's own first, then the rest of LibSharedMedia's (when it is loaded)
--   Sound.Chosen() -> name             the picked one (Settings "notifySound"), AME's default when unset or gone
--   Sound.Enabled(kind) -> bool        kind: "alert" | "craft" | "auction" (the Settings checks under Sound)
--   Sound.Play(kind, now?) -> bool     play the chosen sound for an event, if that kind is on (once per GAP seconds)
--   Sound.Preview(name) -> bool        play one now (picking it in Settings)
--   Sound.Register()                   put AME's own into LibSharedMedia (safe to call again; Sound.Play calls it)
local _, ns = ...
local L = ns.L

local Sound = { GAP = 2 }
ns.Sound = Sound

-- the game's own sounds AME offers: a sound kit to play (reliable on every client) and the file behind it, by file
-- data ID, for LibSharedMedia. To check in game: the file IDs (the kits are the game's own constants).
Sound.OWN = {
  { name = L["AME (default)"], kit = "MAP_PING", kitID = 3175, file = 567416 }, -- Sound\Interface\MapPing.ogg
  { name = L["AME: page"], kit = "IG_QUEST_LOG_OPEN", kitID = 875, file = 567504 }, -- iQuestLogOpenA.ogg
  { name = L["AME: auction house"], kit = "AUCTION_WINDOW_OPEN", kitID = 5274, file = 567482 }, -- AuctionWindowOpen.ogg
}
Sound.DEFAULT = Sound.OWN[1].name

-- which Settings check each event kind follows (alertSound is the existing price-alert switch)
Sound.KEYS = { alert = "alertSound", craft = "soundRequest", auction = "soundAuction" }
Sound.KEY_DEFAULTS = { alertSound = true, soundRequest = true, soundAuction = false }

local function lsm()
  local stub = _G.LibStub
  return stub and stub("LibSharedMedia-3.0", true) or nil
end

local function setting(key)
  local v = ns.Settings and ns.Settings:Get(key)
  if v == nil then
    v = Sound.KEY_DEFAULTS[key]
  end
  return v
end

local function own(name)
  for _, s in ipairs(Sound.OWN) do
    if s.name == name then
      return s
    end
  end
end

function Sound.Register()
  local media = lsm()
  if not media or Sound.registered == media then
    return
  end
  Sound.registered = media
  for _, s in ipairs(Sound.OWN) do
    pcall(media.Register, media, "sound", s.name, s.file)
  end
end

function Sound.List()
  Sound.Register()
  local out, seen = {}, {}
  for _, s in ipairs(Sound.OWN) do
    out[#out + 1] = s.name
    seen[s.name] = true
  end
  local media = lsm()
  local ok, list = false, nil
  if media and media.List then
    ok, list = pcall(media.List, media, "sound")
  end
  for _, name in ipairs(ok and type(list) == "table" and list or {}) do
    if not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end
  return out
end

function Sound.Chosen()
  local name = ns.Settings and ns.Settings:Get("notifySound")
  if type(name) ~= "string" or name == "" then
    return Sound.DEFAULT
  end
  if own(name) then
    return name
  end
  local media = lsm()
  if media and media.IsValid and media:IsValid("sound", name) then
    return name
  end
  return Sound.DEFAULT -- the pack it came from is gone
end

function Sound.Enabled(kind)
  local key = Sound.KEYS[kind]
  return key ~= nil and setting(key) and true or false
end

-- play a sound by name: AME's own by its kit, LibSharedMedia's by its file
local function play(name)
  local s = own(name)
  if s then
    local kit = (_G.SOUNDKIT and _G.SOUNDKIT[s.kit]) or s.kitID
    if _G.PlaySound then
      local ok, willPlay = pcall(_G.PlaySound, kit, "Master")
      if ok and willPlay ~= false then
        return true
      end
    end
    if _G.PlaySoundFile then
      local ok, willPlay = pcall(_G.PlaySoundFile, s.file, "Master")
      return ok and willPlay ~= false
    end
    return false
  end
  local media = lsm()
  local path = media and media.Fetch and media:Fetch("sound", name, true)
  if path and _G.PlaySoundFile then
    local ok, willPlay = pcall(_G.PlaySoundFile, path, "Master")
    if ok and willPlay ~= false then
      return true
    end
  end
  return play(Sound.DEFAULT)
end

function Sound.Preview(name)
  Sound.Register()
  return play(name or Sound.Chosen())
end

function Sound.Play(kind, now)
  if not Sound.Enabled(kind) then
    return false
  end
  now = now or (_G.GetTime and _G.GetTime()) or 0
  if Sound.last and now - Sound.last < Sound.GAP then
    return false -- three alerts from one scan ring once
  end
  Sound.last = now
  Sound.Register()
  return play(Sound.Chosen())
end
