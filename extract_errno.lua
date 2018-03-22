local errnomap = {}
local errnos = {}

for ln in io.lines() do
  local name, value = string.match(ln, "^#define (E.-) (.-)$")
  if name and value then
    errnomap[name] = value
    if tonumber(value) then
      errnos[#errnos+1] = {name, value}
    end
  end
end

table.sort(errnos, function (a, b) return tonumber(a[2]) < tonumber(b[2]) end)

local fd = io.open(arg[1], "w")

fd:write[[
return setmetatable({
]]
for _,p in ipairs(errnos) do
  local k,v = table.unpack(p)
  if not tonumber(v) then v = errnomap[v] end
  fd:write(string.format('  % 20s = '..v..',\n', '["'..k..'"]'))
end
for _,p in ipairs(errnos) do
  local k,v = table.unpack(p)
  if tonumber(v) then
    fd:write(string.format('  % 20s = "'..k..'",\n', '['..v..']'))
  end
end
fd:write[[
}, { __index = function(key) return tostring(key) end })
]]
