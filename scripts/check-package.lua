-- Verify a packaged addon: every file listed in the TOCs, and every <Script file>/<Include file> in the XML they
-- pull in, exists (paths are relative to the referencing file, with Windows separators).
--   lua5.1 scripts/check-package.lua path/to/A.toc [path/to/B.toc ...]
local missing, checked = {}, 0

local function exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function dirOf(path)
  return path:match("^(.*)/[^/]*$") or "."
end

local check

local function checkXml(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  text = text:gsub("<!%-%-.-%-%->", "") -- ignore comments
  for file in text:gmatch('<%a+%s+file%s*=%s*"([^"]+)"') do
    check(dirOf(path) .. "/" .. file:gsub("\\", "/"), path)
  end
end

function check(path, from)
  checked = checked + 1
  if not exists(path) then
    missing[#missing + 1] = path .. "  (from " .. from .. ")"
  elseif path:lower():match("%.xml$") then
    checkXml(path)
  end
end

for _, toc in ipairs(arg) do
  for line in io.lines(toc) do
    line = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:match("^#") then
      check(dirOf(toc) .. "/" .. line:gsub("\\", "/"), toc)
    end
  end
end

if #missing > 0 then
  io.stderr:write("missing files:\n  " .. table.concat(missing, "\n  ") .. "\n")
  os.exit(1)
end
print(("package check: %d referenced files present"):format(checked))
