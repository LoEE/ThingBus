local buffer = require'buffer'
local D = require'util'
local B = require'binary'

local VERBOSE = false

local b = buffer.new()

local function asserteq (tv, v) if (tv ~= v) then error (D.p:format(tv) .. " ~= " .. D.p:format(v), 2) end end
local d
if VERBOSE then 
  function d() local dbg = debug.getinfo(2) D(dbg.source .. ":" .. dbg.currentline)(b:_debug()) end
else
  function d() end
end

--[[
d()
b:write ("QWEASDZAZXC")
d()
asserteq (b:read(1), "Q")
asserteq (b:read(2), "WE")
asserteq (b:get(), "ASDZAZXC")
asserteq (b:readuntil("ZX", 2), "ASDZA")
asserteq (b:get(), "C")
asserteq (b:readuntil("C"), "")
d()
b:write ("12345");
d()
asserteq (b:readuntil(""), "")
asserteq (b:readuntil("\n"), nil)
asserteq (b:readuntil("3"), "C12")
asserteq (b:get(), "345")
asserteq (b:readuntil("5", 1), "34")
asserteq (b:get(), "")
d()
b:write ("12345");
d()
asserteq (b:readuntil("\n", 1), nil)
d()
b:write ("678\n123\n");
d()
asserteq (b:readuntil("\n", 1), "12345678")
asserteq (b:readuntil("\n", 1), "123")
asserteq (b:get(), "")
d()
b:write ("123");
d()
asserteq (b:read(4), nil)
asserteq (b:read(), "123")
asserteq (b:read(), nil)
asserteq (b:read(1), nil)
d()
--]]

b:write("1234");
d()
asserteq (b:readstruct('>u4'), 0x31323334)
--asserterr (b:readstruct('>u4'), 'bad argument #1 to 'readstruct' (not enough data)')
d()
b:write(B.hex2bin'ffff fff0 0005' .. 'abcde QWE\0\1\2');
d()
local d1, d2 = b:readstruct'>s2s2'
asserteq (d1, -1)
asserteq (d2, -16)
asserteq (b:readstruct'>u2c0', "abcde")
asserteq (b:readstruct'z', " QWE")
d()
local n, s = b:peekstruct'c2'
asserteq (n, 2)
asserteq (s, "\0\1")
d()
asserteq (b:rseek (4), nil)
asserteq (b:rseek (3), 3)
d()
