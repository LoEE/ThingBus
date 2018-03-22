// Generated file, see luatoc.lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
static char code[] = "\n\n\n\n\n"
  "package.preload[\"extensions\"] = function (...)\n"
  "  if not newproxy then\n"
  "    function newproxy(mt)\n"
  "      if mt then\n"
  "        return setmetatable({}, {})\n"
  "      else\n"
  "        return {}\n"
  "      end\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  -- os\n"
  "  function os.dirname(path)\n"
  "    return string.match(path, \"(.*)[\\\\/]\") or '.'\n"
  "  end\n"
  "  \n"
  "  function os.basename(path)\n"
  "    return string.match(path, \"([^\\\\/]*)$\") or ''\n"
  "  end\n"
  "  \n"
  "  if os.platform == 'win32' then\n"
  "    local socket = require'socket'\n"
  "    function os.pipe()\n"
  "      local p1, p2, lsock\n"
  "      lsock = assert(socket.bind(\"localhost\", 0, 1))\n"
  "      local laddr, lport = lsock:getsockname()\n"
  "      p1 = assert(socket.connect(laddr, lport))\n"
  "      p2 = assert(lsock:accept())\n"
  "      local addr1, port1 = p1:getsockname()\n"
  "      local paddr2, pport2 = p2:getpeername()\n"
  "      assert(addr1 == paddr2 and port1 == pport2)\n"
  "      lsock:close()\n"
  "      p1:settimeout(0)\n"
  "      p2:settimeout(0)\n"
  "      return p1, p2\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  -- table\n"
  "  function table.index (t, v)\n"
  "    for i,x in ipairs (t) do\n"
  "      if x == v then\n"
  "        return i\n"
  "      end\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  -- string\n"
  "  do\n"
  "    local matches =\n"
  "    {\n"
  "      [\"^\"] = \"%^\";\n"
  "      [\"$\"] = \"%$\";\n"
  "      [\"(\"] = \"%(\";\n"
  "      [\")\"] = \"%)\";\n"
  "      [\"%\"] = \"%%\";\n"
  "      [\".\"] = \"%.\";\n"
  "      [\"[\"] = \"%[\";\n"
  "      [\"]\"] = \"%]\";\n"
  "      [\"*\"] = \"%*\";\n"
  "      [\"+\"] = \"%+\";\n"
  "      [\"-\"] = \"%-\";\n"
  "      [\"?\"] = \"%?\";\n"
  "      [\"\\0\"]= \"%z\";\n"
  "    }\n"
  "    function string.quote_patterns (s)\n"
  "      return (s:gsub(\".\", matches))\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  function string.strip (str, chars)\n"
  "    if not str then return nil end\n"
  "    if chars then\n"
  "      chars = \"[\"..string.quote_patterns(chars)..\"]\"\n"
  "    else\n"
  "      chars = \"[ \\t\\r\\n]\"\n"
  "    end\n"
  "    return string.match(str, \"^\"..chars..\"*(.-)\"..chars..\"*$\")\n"
  "  end\n"
  "  \n"
  "  local ssub = string.sub\n"
  "  local sfind = string.find\n"
  "  \n"
  "  function string.startswith(s, prefix)\n"
  "    return ssub(s, 1, #prefix) == prefix\n"
  "  end\n"
  "  \n"
  "  function string.endswith(s, suffix)\n"
  "    return ssub(s, -#suffix) == suffix\n"
  "  end\n"
  "  \n"
  "  function string.split (str, pat, n)\n"
  "    -- FIXME: transform into a closure based iterator?\n"
  "    pat = pat or \"[ \\t\\r\\n]+\"\n"
  "    n = n or #str\n"
  "    local r = {}\n"
  "    local s, e = sfind (str, pat, 1)\n"
  "    if not s then return {str} end\n"
  "    if s ~= 1 then r[#r+1] = ssub(str, 1, s - 1) end\n"
  "    while true do\n"
  "      if e == #str then return r end\n"
  "      local ne\n"
  "      s, ne = sfind (str, pat, e + 1)\n"
  "      if not s or #r >= n then r[#r+1] = ssub(str, e + 1, #str) return r end\n"
  "      r[#r+1] = ssub(str, e + 1, s - 1)\n"
  "      e = ne\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  function string.splitv (str, pat, n)\n"
  "    return unpack(string.split (str, pat, n))\n"
  "  end\n"
  "  \n"
  "  --[[ tests\n"
  "  do\n"
  "    local split = function (str, pat, n) return yd('split', string.split (str, pat, n)) end\n"
  "    split('foo/bar/baz/test','/')\n"
  "    --> {'foo','bar','baz','test'}\n"
  "    split('/foo/bar/baz/test','/')\n"
  "    --> {'foo','bar','baz','test'}\n"
  "    split('/foo/bar/baz/test/','/')\n"
  "    --> {'foo','bar','baz','test'}\n"
  "    split('/foo/bar//baz/test///','/')\n"
  "    --> {'foo','bar','','baz','test','',''}\n"
  "    split('//foo////bar/baz///test///','/+')\n"
  "    --> {'foo','bar','baz','test'}\n"
  "    split('foo','/+')\n"
  "    --> {'foo'}\n"
  "    split('','/+')\n"
  "    --> {}\n"
  "    split('foo','')  -- splits a zero-sized string 3 (#str) times\n"
  "    --> {'','','',''}\n"
  "    split('a|b|c|d','|',2)\n"
  "    --> {'a','b','c|d'}\n"
  "    split('|a|b|c|d|','|',2)\n"
  "    --> {'a','b','c|d|')\n"
  "  end\n"
  "  --]]\n"
  "  \n"
  "  function string.splitall (str, pat, n)\n"
  "    -- FIXME: transform into a closure based iterator?\n"
  "    pat = pat or \"[ \\t\\r\\n]+\"\n"
  "    n = n or #str\n"
  "    local r = {}\n"
  "    local s = 0\n"
  "    local e = 0\n"
  "    while true do\n"
  "      local ne\n"
  "      s, ne = sfind (str, pat, e + 1)\n"
  "      if not s or #r >= n then r[#r+1] = ssub(str, e + 1, #str) return r end\n"
  "      r[#r+1] = ssub(str, e + 1, s - 1)\n"
  "      e = ne\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  function string.splitallv (str, pat, n)\n"
  "    return unpack(string.splitall (str, pat, n))\n"
  "  end\n"
  "  \n"
  "  --[[ tests\n"
  "  do\n"
  "    local split = function (str, pat, n) local t = string.splitall (str, pat, n) yd('splitall', pat, str == table.concat (t, pat), t) return t end\n"
  "    split('foo/bar/baz/test','/')\n"
  "    --> {'foo','bar','baz','test'}\n"
  "    split('/foo/bar/baz/test','/')\n"
  "    --> {'','foo','bar','baz','test'}\n"
  "    split('/foo/bar/baz/test/','/')\n"
  "    --> {'','foo','bar','baz','test',''}\n"
  "    split('/foo/bar//baz/test///','/')\n"
  "    --> {'','foo','bar','','baz','test','','',''}\n"
  "    split('//foo////bar/baz///test///','/+')\n"
  "    --> {'','foo','bar','baz','test',''}\n"
  "    split('foo','/+')\n"
  "    --> {'foo'}\n"
  "    split('','/+')\n"
  "    --> {}\n"
  "    split('foo','')  -- splits a zero-sized string 3 (#str) times\n"
  "    --> {'','','',''}\n"
  "    split('a|b|c|d','|',2)\n"
  "    --> {'a','b','c|d'}\n"
  "  end\n"
  "  --]]\n"
  "  \n"
  "  \n"
  "  \n"
  "  \n"
  "  --[[\n"
  "    START\n"
  "    The getopt function by Attractive Chaos <attractor@live.co.uk>\n"
  "  --]]\n"
  "  \n"
  "  --[[\n"
  "    The MIT License\n"
  "  \n"
  "    Copyright (c) 2011, Attractive Chaos <attractor@live.co.uk>\n"
  "  \n"
  "    Permission is hereby granted, free of charge, to any person obtaining a copy\n"
  "    of this software and associated documentation files (the \"Software\"), to deal\n"
  "    in the Software without restriction, including without limitation the rights\n"
  "    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell\n"
  "    copies of the Software, and to permit persons to whom the Software is\n"
  "    furnished to do so, subject to the following conditions:\n"
  "  \n"
  "    The above copyright notice and this permission notice shall be included in\n"
  "    all copies or substantial portions of the Software.\n"
  "  \n"
  "    THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR\n"
  "    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,\n"
  "    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE\n"
  "    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER\n"
  "    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,\n"
  "    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE\n"
  "    SOFTWARE.\n"
  "  ]]--\n"
  "  \n"
  "  -- Description: getopt() translated from the BSD getopt(); compatible with the default Unix getopt()\n"
  "  --[[ Example:\n"
  "    for o, a in os.getopt(arg, 'a:b') do\n"
  "      print(o, a)\n"
  "    end\n"
  "  ]]--\n"
  "  function os.getopt(args, ostr)\n"
  "    local arg, place = nil, 0;\n"
  "    return function ()\n"
  "      if place == 0 then -- update scanning pointer\n"
  "        place = 1\n"
  "        if #args == 0 or args[1]:sub(1, 1) ~= '-' then place = 0; return nil end\n"
  "        if #args[1] >= 2 then\n"
  "          place = place + 1\n"
  "          if args[1]:sub(2, 2) == '-' then -- found \"--\"\n"
  "            place = 0\n"
  "            table.remove(args, 1);\n"
  "            return nil;\n"
  "          end\n"
  "        end\n"
  "      end\n"
  "      local optopt = args[1]:sub(place, place);\n"
  "      place = place + 1;\n"
  "      local oli = ostr:find(optopt);\n"
  "      if optopt == ':' or oli == nil then -- unknown option\n"
  "        if optopt == '-' then return nil end\n"
  "        if place > #args[1] then\n"
  "          table.remove(args, 1);\n"
  "          place = 0;\n"
  "        end\n"
  "        return '?';\n"
  "      end\n"
  "      oli = oli + 1;\n"
  "      if ostr:sub(oli, oli) ~= ':' then -- do not need argument\n"
  "        arg = nil;\n"
  "        if place > #args[1] then\n"
  "          table.remove(args, 1);\n"
  "          place = 0;\n"
  "        end\n"
  "      else -- need an argument\n"
  "        if place <= #args[1] then  -- no white space\n"
  "          arg = args[1]:sub(place);\n"
  "        else\n"
  "          table.remove(args, 1);\n"
  "          if #args == 0 then -- an option requiring argument is the last one\n"
  "            place = 0;\n"
  "            if ostr:sub(1, 1) == ':' then return ':' end\n"
  "            return '?';\n"
  "          else arg = args[1] end\n"
  "        end\n"
  "        table.remove(args, 1);\n"
  "        place = 0;\n"
  "      end\n"
  "      return optopt, arg;\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  --[[\n"
  "    The getopt function by Attractive Chaos <attractor@live.co.uk>\n"
  "    END\n"
  "  --]]\n"
  "end\n"
  "package.preload[\"coxpcall\"] = function (...)\n"
  "  -------------------------------------------------------------------------------\n"
  "  -- Coroutine safe xpcall and pcall versions\n"
  "  --\n"
  "  -- Encapsulates the protected calls with a coroutine based loop, so errors can\n"
  "  -- be dealed without the usual Lua 5.x pcall/xpcall issues with coroutines\n"
  "  -- yielding inside the call to pcall or xpcall.\n"
  "  --\n"
  "  -- Authors: Roberto Ierusalimschy and Andre Carregal \n"
  "  -- Contributors: Thomas Harning Jr., Ignacio Burgueño, Fábio Mascarenhas\n"
  "  --\n"
  "  -- Copyright 2005 - Kepler Project (www.keplerproject.org)\n"
  "  --\n"
  "  -- $Id: coxpcall.lua,v 1.13 2008/05/19 19:20:02 mascarenhas Exp $\n"
  "  -------------------------------------------------------------------------------\n"
  "  \n"
  "  -------------------------------------------------------------------------------\n"
  "  -- Implements xpcall with coroutines\n"
  "  -------------------------------------------------------------------------------\n"
  "  local performResume, handleReturnValue\n"
  "  local oldpcall, oldxpcall = pcall, xpcall\n"
  "  \n"
  "  function handleReturnValue(err, co, status, ...)\n"
  "      if not status then\n"
  "          return false, err(debug.traceback(co, (...)), ...)\n"
  "      end\n"
  "      if coroutine.status(co) == 'suspended' then\n"
  "          return performResume(err, co, coroutine.yield(...))\n"
  "      else\n"
  "          return true, ...\n"
  "      end\n"
  "  end\n"
  "  \n"
  "  function performResume(err, co, ...)\n"
  "      return handleReturnValue(err, co, coroutine.resume(co, ...))\n"
  "  end    \n"
  "  \n"
  "  function coxpcall(f, err, ...)\n"
  "      local res, co = oldpcall(coroutine.create, f)\n"
  "      if not res then\n"
  "          local params = {...}\n"
  "          local newf = function() return f(unpack(params)) end\n"
  "          co = coroutine.create(newf)\n"
  "      end\n"
  "      return performResume(err, co, ...)\n"
  "  end\n"
  "  \n"
  "  -------------------------------------------------------------------------------\n"
  "  -- Implements pcall with coroutines\n"
  "  -------------------------------------------------------------------------------\n"
  "  \n"
  "  local function id(trace, ...)\n"
  "    return ...\n"
  "  end\n"
  "  \n"
  "  function copcall(f, ...)\n"
  "      return coxpcall(f, id, ...)\n"
  "  end\n"
  "end\n"
  "package.preload[\"md5\"] = function (...)\n"
  "  ----------------------------------------------------------------------------\n"
  "  -- $Id: md5.lua,v 1.4 2006/08/21 19:24:21 carregal Exp $\n"
  "  ----------------------------------------------------------------------------\n"
  "  \n"
  "  local core\n"
  "  local string = string or require\"string\"\n"
  "  if string.find(_VERSION, \"Lua 5.0\") then\n"
  "  	local cpath = os.getenv\"LUA_CPATH\" or \"/usr/local/lib/lua/5.0/\"\n"
  "  	core = loadlib(cpath..\"md5/core.so\", \"luaopen_md5_core\")()\n"
  "  else\n"
  "  	core = require\"md5.core\"\n"
  "  end\n"
  "  \n"
  "  \n"
  "  ----------------------------------------------------------------------------\n"
  "  -- @param k String with original message.\n"
  "  -- @return String with the md5 hash value converted to hexadecimal digits\n"
  "  \n"
  "  function core.sumhexa (k)\n"
  "    k = core.sum(k)\n"
  "    return (string.gsub(k, \".\", function (c)\n"
  "             return string.format(\"%02x\", string.byte(c))\n"
  "           end))\n"
  "  end\n"
  "  \n"
  "  return core\n"
  "end\n"
  "package.preload[\"socket\"] = function (...)\n"
  "  -----------------------------------------------------------------------------\n"
  "  -- LuaSocket helper module\n"
  "  -- Author: Diego Nehab\n"
  "  -----------------------------------------------------------------------------\n"
  "  \n"
  "  -----------------------------------------------------------------------------\n"
  "  -- Declare module and import dependencies\n"
  "  -----------------------------------------------------------------------------\n"
  "  local base = _G\n"
  "  local string = require(\"string\")\n"
  "  local math = require(\"math\")\n"
  "  local socket = require(\"socket.core\")\n"
  "  \n"
  "  local _M = socket\n"
  "  \n"
  "  -----------------------------------------------------------------------------\n"
  "  -- Exported auxiliar functions\n"
  "  -----------------------------------------------------------------------------\n"
  "  function _M.connect4(address, port, laddress, lport)\n"
  "      return socket.connect(address, port, laddress, lport, \"inet\")\n"
  "  end\n"
  "  \n"
  "  function _M.connect6(address, port, laddress, lport)\n"
  "      return socket.connect(address, port, laddress, lport, \"inet6\")\n"
  "  end\n"
  "  \n"
  "  function _M.bind(host, port, backlog)\n"
  "      if host == \"*\" then host = \"0.0.0.0\" end\n"
  "      local addrinfo, err = socket.dns.getaddrinfo(host);\n"
  "      if not addrinfo then return nil, err end\n"
  "      local sock, res\n"
  "      err = \"no info on address\"\n"
  "      for i, alt in base.ipairs(addrinfo) do\n"
  "          if alt.family == \"inet\" then\n"
  "              sock, err = socket.tcp4()\n"
  "          else\n"
  "              sock, err = socket.tcp6()\n"
  "          end\n"
  "          if not sock then return nil, err end\n"
  "          sock:setoption(\"reuseaddr\", true)\n"
  "          res, err = sock:bind(alt.addr, port)\n"
  "          if not res then\n"
  "              sock:close()\n"
  "          else\n"
  "              res, err = sock:listen(backlog)\n"
  "              if not res then\n"
  "                  sock:close()\n"
  "              else\n"
  "                  return sock\n"
  "              end\n"
  "          end\n"
  "      end\n"
  "      return nil, err\n"
  "  end\n"
  "  \n"
  "  _M.try = _M.newtry()\n"
  "  \n"
  "  function _M.choose(table)\n"
  "      return function(name, opt1, opt2)\n"
  "          if base.type(name) ~= \"string\" then\n"
  "              name, opt1, opt2 = \"default\", name, opt1\n"
  "          end\n"
  "          local f = table[name or \"nil\"]\n"
  "          if not f then base.error(\"unknown key (\".. base.tostring(name) ..\")\", 3)\n"
  "          else return f(opt1, opt2) end\n"
  "      end\n"
  "  end\n"
  "  \n"
  "  -----------------------------------------------------------------------------\n"
  "  -- Socket sources and sinks, conforming to LTN12\n"
  "  -----------------------------------------------------------------------------\n"
  "  -- create namespaces inside LuaSocket namespace\n"
  "  local sourcet, sinkt = {}, {}\n"
  "  _M.sourcet = sourcet\n"
  "  _M.sinkt = sinkt\n"
  "  \n"
  "  _M.BLOCKSIZE = 2048\n"
  "  \n"
  "  sinkt[\"close-when-done\"] = function(sock)\n"
  "      return base.setmetatable({\n"
  "          getfd = function() return sock:getfd() end,\n"
  "          dirty = function() return sock:dirty() end\n"
  "      }, {\n"
  "          __call = function(self, chunk, err)\n"
  "              if not chunk then\n"
  "                  sock:close()\n"
  "                  return 1\n"
  "              else return sock:send(chunk) end\n"
  "          end\n"
  "      })\n"
  "  end\n"
  "  \n"
  "  sinkt[\"keep-open\"] = function(sock)\n"
  "      return base.setmetatable({\n"
  "          getfd = function() return sock:getfd() end,\n"
  "          dirty = function() return sock:dirty() end\n"
  "      }, {\n"
  "          __call = function(self, chunk, err)\n"
  "              if chunk then return sock:send(chunk)\n"
  "              else return 1 end\n"
  "          end\n"
  "      })\n"
  "  end\n"
  "  \n"
  "  sinkt[\"default\"] = sinkt[\"keep-open\"]\n"
  "  \n"
  "  _M.sink = _M.choose(sinkt)\n"
  "  \n"
  "  sourcet[\"by-length\"] = function(sock, length)\n"
  "      return base.setmetatable({\n"
  "          getfd = function() return sock:getfd() end,\n"
  "          dirty = function() return sock:dirty() end\n"
  "      }, {\n"
  "          __call = function()\n"
  "              if length <= 0 then return nil end\n"
  "              local size = math.min(socket.BLOCKSIZE, length)\n"
  "              local chunk, err = sock:receive(size)\n"
  "              if err then return nil, err end\n"
  "              length = length - string.len(chunk)\n"
  "              return chunk\n"
  "          end\n"
  "      })\n"
  "  end\n"
  "  \n"
  "  sourcet[\"until-closed\"] = function(sock)\n"
  "      local done\n"
  "      return base.setmetatable({\n"
  "          getfd = function() return sock:getfd() end,\n"
  "          dirty = function() return sock:dirty() end\n"
  "      }, {\n"
  "          __call = function()\n"
  "              if done then return nil end\n"
  "              local chunk, err, partial = sock:receive(socket.BLOCKSIZE)\n"
  "              if not err then return chunk\n"
  "              elseif err == \"closed\" then\n"
  "                  sock:close()\n"
  "                  done = 1\n"
  "                  return partial\n"
  "              else return nil, err end\n"
  "          end\n"
  "      })\n"
  "  end\n"
  "  \n"
  "  \n"
  "  sourcet[\"default\"] = sourcet[\"until-closed\"]\n"
  "  \n"
  "  _M.source = _M.choose(sourcet)\n"
  "  \n"
  "  return _M\n"
  "end\n"
  "do\n"
  "  -- os.platform needs to be set immediately (IDEA: do it from C)\n"
  "  os.executable_path, os.platform = ...\n"
  "  \n"
  "  package.path = ''\n"
  "  package.cpath = ''\n"
  "  \n"
  "  require'extensions'\n"
  "  \n"
  "  local function addtoPATH(p)\n"
  "    package.path = p..'/?.luac;'..p..'/?/init.luac;'..p..'/?.lua;'..p..'/?/init.lua;'..package.path\n"
  "    package.cpath = p..'/?.so;'..package.cpath\n"
  "  end\n"
  "  \n"
  "  os.executable_dir = os.dirname(os.executable_path)\n"
  "  addtoPATH(os.executable_dir..'/lualib')\n"
  "  addtoPATH(os.executable_dir..'/lualib/'..os.platform)\n"
  "  \n"
  "  local main\n"
  "  \n"
  "  local function drop_arguments(n)\n"
  "    for i=0,#arg do\n"
  "      arg[i] = arg[i+n]\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  if not os.basename(arg[0]):startswith\"thb\" then\n"
  "    -- FIXME: realpath does not work for executables in PATH\n"
  "    os.program_path = os.dirname(os.realpath(arg[0]))\n"
  "    addtoPATH(os.program_path)\n"
  "    function main()\n"
  "      local name = arg[0]\n"
  "      if name:endswith\".exe\" then\n"
  "        name = name:sub(1, -5)\n"
  "      end\n"
  "      dofile(name..'.lua')\n"
  "    end\n"
  "  elseif arg[1] then\n"
  "    if string.sub(arg[1], 1, 1) == ':' then\n"
  "      arg[1] = os.executable_dir..'/'..string.sub(arg[1], 2)..'.lua'\n"
  "    else\n"
  "      local rpath = os.realpath(arg[1])\n"
  "      if not rpath then io.stderr:write('error: file not found: '..arg[1]..'\\n') os.exit(2) end\n"
  "      os.program_path = os.dirname(os.realpath(arg[1]))\n"
  "      addtoPATH(os.program_path)\n"
  "    end\n"
  "    function main()\n"
  "      drop_arguments(1)\n"
  "      dofile(arg[0])\n"
  "    end\n"
  "  else\n"
  "    function main()\n"
  "      addtoPATH('.')\n"
  "      local repl = require'repl'\n"
  "      local loop = require'loop'\n"
  "      repl.start(0)\n"
  "      loop.run()\n"
  "    end\n"
  "  end\n"
  "  \n"
  "  main()\n"
  "end\n"
  ;

int l_init (lua_State *L)
{
  int n = lua_gettop(L);
  if (luaL_loadbuffer(L, code, sizeof(code) - 1, "l_init.c")) return lua_error(L);
  lua_insert(L, 1);
  lua_call(L, n, 0);
  return 0;
}
