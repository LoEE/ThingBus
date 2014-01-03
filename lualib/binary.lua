local M = require'_binary'
local bit32 = require'bit32'

function M.packbits(obj, fmt)
  local result = 0
  local parts = string.split(fmt)
  for _,part in ipairs(parts) do
    local name, len = string.match(part, '([^:]+):([0-9]+)')
    if not name then
      result = bit32.lshift(result, 1)
      if part ~= '_' then
        result = result + (obj[part] and 1 or 0)
      end
    else
      result = bit32.lshift(result, len)
      if name ~= '_' then
        result = result + obj[name]
      end
    end
  end
  return result
end

local sub = string.sub

function M.allslices (s, e, size)
  return function ()
    if s <= e then
      local ss = s
      local se = s + size - 1
      if se > e then se = e end
      s = s + size
      return ss, se
    end
  end
end

function M.flat (t)
  for i,v in ipairs(t) do
    if v == true then
      v = 1
    elseif v == false then
      v = 0
    end
    -- not elseif!
    if type(v) == 'number' then
      t[i] = string.char (v)
    elseif type(v) == 'table' then
      t[i] = M.flat (v)
    end
  end
  return table.concat (t)
end

function M.bin2hex (data, n, spacer, mode)
  n = n or 2
  if n == 0 then n = #data end
  spacer = spacer or " "
  local swap = mode == 'swap'
  local out = {}
  for i=1,#data,n do
    local bs = sub (data, i, i+n - 1)
    if swap then bs = string.reverse(bs) end
    out[#out+1] = bs:gsub(".", function (b) return string.format ("%02x", b:byte()) end)
  end
  return table.concat (out, spacer)
end

function M.hex2bin (data)
  return (data:gsub ("[^0-9a-fA-F]+", ""):gsub ("..", function (str) return string.char(tonumber(str, 16)) end))
end

function M.hex (n, prefix)
  prefix = prefix or '0x'
  local s = string.format ("%x", n)
  local p
  if #s % 2 == 0 then
    p = prefix
  else
    p = prefix .. "0"
  end
  return p .. s
end

function M.binary_decoder (n, le)
  return function (bs, s)
    local s = s or 1
    local e = s + (n - 1)
    local step = 1
    if le then
      s, e = e, s
      step = -step
    end
    local n = 0
    for i=s,e,step do
      n = n * 256 + bs:byte(i)
    end
    return n
  end
end

function M.binary_encoder (n, le)
  return function (x)
    local s = n
    local e = 1
    local step = -1
    if le then
      s, e = e, s
      step = -step
    end
    local bs = {}
    local old_x = x
    for i=s,e,step do
      bs[i] = string.char (math.floor (x % 256))
      x = math.floor (x / 256)
    end
    return table.concat (bs)
  end
end

M.dec16BE = M.binary_decoder(2, false)
M.dec32BE = M.binary_decoder(4, false)
M.dec64BE = M.binary_decoder(8, false)
M.dec16LE = M.binary_decoder(2, true)
M.dec32LE = M.binary_decoder(4, true)
M.dec64LE = M.binary_decoder(8, true)

M.enc16BE = M.binary_encoder(2, false)
M.enc32BE = M.binary_encoder(4, false)
M.enc64BE = M.binary_encoder(8, false)
M.enc16LE = M.binary_encoder(2, true)
M.enc32LE = M.binary_encoder(4, true)
M.enc64LE = M.binary_encoder(8, true)

--[[
function M.encSTR (n, str, fill)
  fill = fill or " "
  local l = #str
  if l > n then
    error (string.format ("string too long to encode (%d > %d): %s", l, n, str), 2)
  elseif l < n then
    return str .. string.rep (fill, n - l)
  else
    return str
  end
end
--]]

--[[
function M.N (name, ...)
  return lpeg.Cg(lpeg.P(string.char (...)) * lpeg.Cc (name), "type")
end

function M.BYTE (name)
  return lpeg.Cg(lpeg.P(1) / string.byte, name)
end

function M.STR (name, len)
  return lpeg.Cg(lpeg.P(len), name)
end

function M.HEXSTR (name, len)
  return lpeg.Cg(lpeg.P(len) / M.bin2hex, name)
end

function make_bin_match (n, le)
  return function (name)
    return lpeg.Cg(lpeg.P(n) / M.binary_decoder (n, le), name)
  end
end

M.n16BE = make_bin_match (2, false)
--]]

return M
