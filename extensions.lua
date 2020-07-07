-- os

function os.dirname(path)
  return string.match(path, "(.*)[\\/]") or '.'
end

function os.basename(path)
  return string.match(path, "([^\\/]*)$") or ''
end

if os.platform == 'windows' then
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

do
  -- Copyright (c) 2012 Rob Hoelz <rob@hoelz.ro>, 2020 LoEE – Jakub Piotr Cłapa <jpc@loee.pl>
  --
  -- Permission is hereby granted, free of charge, to any person obtaining a copy of
  -- this software and associated documentation files (the "Software"), to deal in
  -- the Software without restriction, including without limitation the rights to
  -- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
  -- the Software, and to permit persons to whom the Software is furnished to do so,
  -- subject to the following conditions:
  --
  -- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
  --
  -- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  -- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
  -- FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
  -- COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
  -- IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  -- CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

  local sformat      = string.format
  local sgmatch      = string.gmatch
  local sgsub        = string.gsub
  local smatch       = string.match
  local tconcat      = table.concat
  local tinsert      = table.insert
  local setmetatable = setmetatable
  local ploadlib     = package.loadlib

  local meta = {}
  local _M   = setmetatable({}, meta)

  _M.VERSION = '0.01'

  -- XXX assert(type(package.preload[name]) == 'function')?
  local function preload_loader(name)
    if package.preload[name] then
      return package.preload[name]
    else
      return sformat("no field package.preload['%s']\n", name)
    end
  end

  local function path_loader(name, paths, loader_func)
    local errors = {}
    local loader

    name = sgsub(name, '%.', '/')

    for path in sgmatch(paths, '[^;]+') do
      path = sgsub(path, '%?', name)

      local errmsg

      loader, errmsg = loader_func(path)

      if loader then
        break
      else
        -- XXX error for when file isn't readable?
        -- XXX error for when file isn't valid Lua (or loadable?)
        tinsert(errors, sformat("no file '%s'", path))
      end
    end

    if loader then
      return loader
    else
      return tconcat(errors, '\n') .. '\n'
    end
  end

  local function lua_loader(name)
    return path_loader(name, package.path, function (path)
      local fd = io.open(path, 'r')
      if not fd then return nil end
      local code = fd:read'*a'
      fd:close()
      local header = string.format(
        "local __SRC_DIR = %q; local function rrequire(name) return require(%q..name) end;",
        os.dirname(path), name
      )
      -- print(name, path, header)
      return loadstring(header .. code, path)
    end)
  end

  local function get_init_function_name(name)
    name = sgsub(name, '^.*%-', '', 1)
    name = sgsub(name, '%.', '_')

    return 'luaopen_' .. name
  end

  local function c_loader(name)
    local init_func_name = get_init_function_name(name)

    return path_loader(name, package.cpath, function(path)
      return ploadlib(path, init_func_name)
    end)
  end

  local function all_in_one_loader(name)
    local init_func_name = get_init_function_name(name)
    local base_name      = smatch(name, '^[^.]+')

    return path_loader(base_name, package.cpath, function(path)
      return ploadlib(path, init_func_name)
    end)
  end

  local function findchunk(name)
    local errors = { string.format("module '%s' not found\n", name) }
    local found

    for _, loader in ipairs(_M.loaders) do
      local chunk = loader(name)

      if type(chunk) == 'function' then
        return chunk
      elseif type(chunk) == 'string' then
        errors[#errors + 1] = chunk
      end
    end

    return nil, table.concat(errors, '')
  end

  local function require(name)
    if package.loaded[name] == nil then
      local chunk, errors = findchunk(name)

      if not chunk then
        error(errors, 2)
      end

      local result = chunk(name)

      if result ~= nil then
        package.loaded[name] = result
      elseif package.loaded[name] == nil then
        package.loaded[name] = true
      end
    end

    return package.loaded[name]
  end

  local loadermeta = {}

  function loadermeta:__call(...)
    return self.impl(...)
  end

  local function makeloader(loader_func, name)
    return setmetatable({ impl = loader_func, name = name }, loadermeta)
  end

  -- XXX make sure that any added loaders are preserved (esp. luarocks)
  _M.loaders = {
    makeloader(preload_loader, 'preload'),
    makeloader(lua_loader, 'lua'),
    makeloader(c_loader, 'c'),
    makeloader(all_in_one_loader, 'all_in_one'),
  }

  if package.loaded['luarocks.require'] then
    local luarocks_loader = require('luarocks.require').luarocks_loader

    table.insert(_M.loaders, 1, makeloader(luarocks_loader, 'luarocks')) 
  end

  -- XXX sugar for adding/removing loaders

  _G.require = require

  _M.findchunk = findchunk
end
