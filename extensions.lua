-- os

function os.dirname(path)
  return string.match(path, "(.*)[\\/]") or '.'
end

function os.basename(path)
  return string.match(path, "([^\\/]*)$") or ''
end

if os.platform == 'win32' then
  local socket = require'socket'
  function os.pipe()
    local p1, p2, lsock
    lsock = assert(socket.bind("localhost", 0, 1))
    local laddr, lport = lsock:getsockname()
    p1 = assert(socket.connect(laddr, lport))
    p2 = assert(lsock:accept())
    local addr1, port1 = p1:getsockname()
    local paddr2, pport2 = p2:getpeername()
    assert(addr1 == paddr2 and tonumber(port1) == pport2, "address mismatch")
    lsock:close()
    p1:settimeout(0)
    p2:settimeout(0)
    return p1, p2
  end
end

-- table
function table.index (t, v)
  for i,x in ipairs (t) do
    if x == v then
      return i
    end
  end
end

-- string
do
  local matches =
  {
    ["^"] = "%^";
    ["$"] = "%$";
    ["("] = "%(";
    [")"] = "%)";
    ["%"] = "%%";
    ["."] = "%.";
    ["["] = "%[";
    ["]"] = "%]";
    ["*"] = "%*";
    ["+"] = "%+";
    ["-"] = "%-";
    ["?"] = "%?";
    ["\0"]= "%z";
  }
  function string.quote_patterns (s)
    return (s:gsub(".", matches))
  end
end

function string.strip (str, chars)
  if not str then return nil end
  if chars then
    chars = "["..string.quote_patterns(chars).."]"
  else
    chars = "[ \t\r\n]"
  end
  return string.match(str, "^"..chars.."*(.-)"..chars.."*$")
end

local ssub = string.sub
local sfind = string.find

function string.startswith(s, prefix)
  return ssub(s, 1, #prefix) == prefix
end

function string.endswith(s, suffix)
  return ssub(s, -#suffix) == suffix
end

function string.split (str, pat, n)
  -- FIXME: transform into a closure based iterator?
  pat = pat or "[ \t\r\n]+"
  n = n or #str
  local r = {}
  local s, e = sfind (str, pat, 1)
  if not s then return {str} end
  if s ~= 1 then r[#r+1] = ssub(str, 1, s - 1) end
  while true do
    if e == #str then return r end
    local ne
    s, ne = sfind (str, pat, e + 1)
    if not s or #r >= n then r[#r+1] = ssub(str, e + 1, #str) return r end
    r[#r+1] = ssub(str, e + 1, s - 1)
    e = ne
  end
end

function string.splitv (str, pat, n)
  return unpack(string.split (str, pat, n))
end

--[[ tests
do
  local split = function (str, pat, n) return yd('split', string.split (str, pat, n)) end
  split('foo/bar/baz/test','/')
  --> {'foo','bar','baz','test'}
  split('/foo/bar/baz/test','/')
  --> {'foo','bar','baz','test'}
  split('/foo/bar/baz/test/','/')
  --> {'foo','bar','baz','test'}
  split('/foo/bar//baz/test///','/')
  --> {'foo','bar','','baz','test','',''}
  split('//foo////bar/baz///test///','/+')
  --> {'foo','bar','baz','test'}
  split('foo','/+')
  --> {'foo'}
  split('','/+')
  --> {}
  split('foo','')  -- splits a zero-sized string 3 (#str) times
  --> {'','','',''}
  split('a|b|c|d','|',2)
  --> {'a','b','c|d'}
  split('|a|b|c|d|','|',2)
  --> {'a','b','c|d|')
end
--]]

function string.splitall (str, pat, n)
  -- FIXME: transform into a closure based iterator?
  pat = pat or "[ \t\r\n]+"
  n = n or #str
  local r = {}
  local s = 0
  local e = 0
  while true do
    local ne
    s, ne = sfind (str, pat, e + 1)
    if not s or #r >= n then r[#r+1] = ssub(str, e + 1, #str) return r end
    r[#r+1] = ssub(str, e + 1, s - 1)
    e = ne
  end
end

function string.splitallv (str, pat, n)
  return unpack(string.splitall (str, pat, n))
end

--[[ tests
do
  local split = function (str, pat, n) local t = string.splitall (str, pat, n) yd('splitall', pat, str == table.concat (t, pat), t) return t end
  split('foo/bar/baz/test','/')
  --> {'foo','bar','baz','test'}
  split('/foo/bar/baz/test','/')
  --> {'','foo','bar','baz','test'}
  split('/foo/bar/baz/test/','/')
  --> {'','foo','bar','baz','test',''}
  split('/foo/bar//baz/test///','/')
  --> {'','foo','bar','','baz','test','','',''}
  split('//foo////bar/baz///test///','/+')
  --> {'','foo','bar','baz','test',''}
  split('foo','/+')
  --> {'foo'}
  split('','/+')
  --> {}
  split('foo','')  -- splits a zero-sized string 3 (#str) times
  --> {'','','',''}
  split('a|b|c|d','|',2)
  --> {'a','b','c|d'}
end
--]]




--[[
  START
  The getopt function by Attractive Chaos <attractor@live.co.uk>
--]]

--[[
  The MIT License

  Copyright (c) 2011, Attractive Chaos <attractor@live.co.uk>

  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in
  all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.
]]--

-- Description: getopt() translated from the BSD getopt(); compatible with the default Unix getopt()
--[[ Example:
  for o, a in os.getopt(arg, 'a:b') do
    print(o, a)
  end
]]--
function os.getopt(args, ostr)
  local arg, place = nil, 0;
  return function ()
    if place == 0 then -- update scanning pointer
      place = 1
      if #args == 0 or args[1]:sub(1, 1) ~= '-' then place = 0; return nil end
      if #args[1] >= 2 then
        place = place + 1
        if args[1]:sub(2, 2) == '-' then -- found "--"
          place = 0
          table.remove(args, 1);
          return nil;
        end
      end
    end
    local optopt = args[1]:sub(place, place);
    place = place + 1;
    local oli = ostr:find(optopt);
    if optopt == ':' or oli == nil then -- unknown option
      if optopt == '-' then return nil end
      if place > #args[1] then
        table.remove(args, 1);
        place = 0;
      end
      return '?';
    end
    oli = oli + 1;
    if ostr:sub(oli, oli) ~= ':' then -- do not need argument
      arg = nil;
      if place > #args[1] then
        table.remove(args, 1);
        place = 0;
      end
    else -- need an argument
      if place <= #args[1] then  -- no white space
        arg = args[1]:sub(place);
      else
        table.remove(args, 1);
        if #args == 0 then -- an option requiring argument is the last one
          place = 0;
          if ostr:sub(1, 1) == ':' then return ':' end
          return '?';
        else arg = args[1] end
      end
      table.remove(args, 1);
      place = 0;
    end
    return optopt, arg;
  end
end

--[[
  The getopt function by Attractive Chaos <attractor@live.co.uk>
  END
--]]
