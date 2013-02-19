local b = require'_binary'
local D = require'util'
local B = require'binary'

local VERBOSE = true --false

local function asserteq (tv, v) if (tv ~= v) then error (D.p:format(tv) .. " ~= " .. D.p:format(v), 2) end end
local function tab_diff (t1, t2)
  for k,v in pairs(t1) do
    if t2[k] ~= v then return true end
  end
  for k,v in pairs(t2) do
    if t1[k] ~= v then return true end
  end
  return false
end
local function asserteqtab (tv, v) if tab_diff (tv, v) then error (D.p:format(tv) .. " ~= " .. D.p:format(v), 2) end
end
local d
if VERBOSE then 
  function d() local dbg = debug.getinfo(2) D(dbg.source .. ":" .. dbg.currentline)(b:_debug()) end
else
  function d() end
end

asserteqtab ({b.unpack('1234', '>u4')}, {4, 0x31323334})
--asserterr (b.unpack('', '>u4'), 'bad argument #2 to 'unpack' (not enough data)') 
local data = B.hex2bin'ffff fff0 0005' .. 'abcde QWE\0\1\2'
local l, d1, d2, d3, d4 = b.unpack(data, '>s2s2u2c0z')
asserteq (l, #data - 3)
asserteq (d1, -1)
asserteq (d2, -16)
asserteq (d3, "abcde")
asserteq (d4, " QWE")
local l, d3, d4 = b.unpack(data, '>u2c0z', 5)
asserteq (l, 11)
asserteq (d3, "abcde")
asserteq (d4, " QWE")

asserteqtab (b.unpackbits(0x123e, 'a:4 b:4 c1:1 c2:1 c3:1 c4:1 d:4'), { a = 1, b = 2, c1 = false, c2 = false, c3 = true, c4 = true, d = 0xe })
asserteqtab (b.unpackbits(0x123e, 'a:4 _:4 c1:1 _ c3:1 c4:1 d:4'), { a = 1, c1 = false, c3 = true, c4 = true, d = 0xe })

asserteq (b.b64_decode'YW55IGNhcm5hbCBwbGVhc3VyZS4=', 'any carnal pleasure.')
asserteq (b.b64_decode'YW55IGNhcm5hbCBwbGVhc3VyZQ==', 'any carnal pleasure')
asserteq (b.b64_decode'YW55IGNhcm5hbCBwbGVhc3Vy', 'any carnal pleasur')
asserteq (b.b64_decode'YW55IGNhcm5hbCBwbGVhc3U=', 'any carnal pleasu')
asserteq (b.b64_encode'pleasure.', 'cGxlYXN1cmUu')
asserteq (b.b64_encode'easure.', 'ZWFzdXJlLg==')
asserteq (b.b64_encode'pleasure.', 'cGxlYXN1cmUu')
asserteq (b.b64_encode'sure.', 'c3VyZS4=')
