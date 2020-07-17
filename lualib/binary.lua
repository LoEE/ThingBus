local M = require'_binary'
local bit32 = require'bit32'

--# Binary data manipulation
--. Converting Lua strings with binary data (which may contain embedded zeros) to hex
--. strings, base64, little-endian and big-endian integers, floats (and back).
--. Unpacking and packing of structs to Lua strings and bitfields to Lua
--. numbers. Also bytewise XORing of two strings, recursively concatenating tables, .

--$ binary = require'binary'

--## Encoding and decoding 16- and 32-bit unsigned integers
--. Function names follow this grammar: `(enc|dec)(16|32|64)(LE|BE)` and
--. encode or decode unsigned integers of standard sizes and with respective
--. endianesses.

--$ binary.enc16LE(0x0102)
--  "\002\001"
--$ binary.dec16BE('\1\0')
--  256
--$ data = binary.enc16LE(0x0102)..'\0\0'..binary.enc16LE(0x8001)
--$ data
--  "\002\001\000\000\001\128"

function M.binary_decoder (n, le)
  return function (bs, s)
    checks('string', '?number')
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
    checks('number')
    local s = n
    local e = 1
    local step = -1
    if le then
      s, e = e, s
      step = -step
    end
    local bs = {}
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

--## Structure unpacking (packing is not implemented yet)
--. `binary.unpack(data, spec, off = 1, size = #data)` unpacks the structure
--. of max length `size` in string `data` starting from `off` and according to
--. `spec` and returns the actual "consumed" length + the values of all unpacked
--. fields. The field specifications should match the following pattern:
--. `[usfcz_][0-9]*`. The letter specifies the format (`u`nsigned, `s`igned,
--. `f`loat, `c`har[], `z`ero-terminated string, `_` - throw away) and the
--. number specifies the length in bytes. `c0` means the length in bytes should
--. be taken from the previous decoded integer (this can be used to decode
--. length-value encodings in one pass).

--$ binary.unpack(data, '< u2 _2 s2')
--  6 258 -32767
--$ binary.unpack(data, '> u2 _2 s2')
--  6 513 384
--$ binary.unpack('\1\2\3\4\1\2\3\4\5\6\7\8', '< f4 f8')
--  12 1.5399896144396e-36 5.4476037220116e-270
--$ binary.unpack('\4abcd', '< u c0')
--  5 "abcd"
--$ binary.unpack('\4\1abcd  ', '< u2 c6')
--  8 260 "abcd  "
--$ binary.unpack('\4\1abcd\0 ', '< u2 z')
--  6 260 "abcd"
--@ ../common/l_binary.c:unpack


--## Bitfield unpacking and packing
--. `binary.unpackbits(number, spec, table = {})` unpacks bitfields of `number`
--. according to `spec`, puts the results in `table` and returns it. Each
--. element of `spec` consists of a name optionally followed by a `:` and a bit
--. length (which defaults to 1 if omitted). Single-bit fields are treated as
--. booleans and multi-bit ones as unsigned integers. All fields named `_` are
--. ignored.

--$ binary.unpackbits(0x1234, 'a:4 b:4 c:4 d:4')
--  { a = 1, b = 2, c = 3, d = 4 }
--$ binary.unpackbits(0x80, 'msb _:6 lsb')
--  { lsb = false, msb = true }
--$ p = { data = 'stuff' }
--$ binary.unpackbits(0x80, 'msb:1 _:6 lsb:1', p)
--  { data = "stuff", lsb = false, msb = true }
--@ ../common/l_binary.c:unpackbits

--. `binary.packbits(table, spec)` performs the inverse operation with ignored
--. fields filled with zeros.

--$ binary.packbits({ lsb = false, msb = true }, 'msb _:6 lsb')
--  128

function M.packbits(obj, fmt)
  checks('table', 'string')
  local result = 0
  local parts = string.split(fmt)
  for _,part in ipairs(parts) do
    local name, len = string.match(part, '([^:]+):([0-9]+)')
    if not name then name = part len = 1 end
    len = tonumber(len)
    if len == 1 then
      result = bit32.lshift(result, 1)
      if name ~= '_' then
        result = result + (obj[name] and 1 or 0)
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

--## Hex strings
--$ binary.bin2hex('abcde')
--  "6162 6364 65"
--$ binary.bin2hex('abc', 0) -- no spaces between bytes
--  "616263"
--$ binary.bin2hex('abc', 1) -- space every 1 byte
--  "61 62 63"
--$ binary.hex2bin'01  0203  2c' -- spaces, \t, \r and \n are ignored
--  "\001\002\003,"
--. Assigning hex2bin to a local variable `H` provides some nice syntactic sugar
--. for files with lots of hex literals.
--$ H = binary.hex2bin
--$ H'01  0203  15'
--  "\001\002\003\021"

function M.bin2hex (data, n, spacer, mode)
  checks('string', '?number', '?string', '?string')
  local sub = string.sub
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
  checks('string')
  return (data:gsub ("[^0-9a-fA-F]+", ""):gsub ("..", function (str) return string.char(tonumber(str, 16)) end))
end

--. `binary.hex(n, prefix = '0x')` a quick convenience function which converts
--. numbers to hexadecimal.
--$ binary.hex(15)
--  "0x0f"
--$ binary.hex(70000, '')
--  "011170"

function M.hex (n, prefix)
  checks('number|string', '?string')
  prefix = prefix or '0x'
  local s = string.format ("%x", n)
  if #s % 2 ~= 0 then
    prefix = prefix .. "0"
  end
  return prefix .. s
end

--## Base64
--. `binary.b64_encode` and `binary.b64_decode` convert between binary and base64 encodings of data.

--$ binary.b64_encode('\0\1\2')
--  "AAEC"
--$ binary.b64_decode('CAG9hXvLXd8=')
--  "\008\001\189\133{\203]\223"
--@ ../common/l_binary.c:base64

--## Misc utilities
--. `binary.flat(table)` recursively concatenates all elements of `table` (converting
--. all numbers to bytes) and returns the resulting string.
--$ binary.flat{'a', 3, { 'b', '\0\1' }}
--  "a\003b\000\001"

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

--. `binary.strxor(src, key)` returns a new string whos XORs each byte of the `src` string with a
--. corresponding byte of string `key`. The `key` is repeated if `#src > #key`.
--$ binary.strxor('\1\2\3\4', '\127\0')
--  "~\002|\004"
--$ binary.strxor("~\002|\004", '\127\0')
--  "\001\002\003\004"
--@ ../common/l_binary.c:strxor


--. `binary.allslices(start, end, blocksize)` returns byte offsets (to be passed
--. to `string.sub`) which split the whole range into blocks no longer than
--. blocksize.
--$ for startoff, endoff in binary.allslices(0, 320-1, 100) do
--$   print(startoff, endoff)
--$  end
--  0	99
--  100	199
--  200	299
--  300	319
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

--//

return M
