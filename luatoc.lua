local out = {[[// Generated file, see luatoc.lua
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
static char code[] = 
]]}
local dep = {}
local lfs = require'lfs'

local function mod_from_fname(fname)
  return string.gsub(string.sub(fname, 1, -5), "/", ".")
end

local function add_module(fname, modname)
  local run = false
  if string.sub(fname, 1, 1) == '+' then
    run = true
    fname = string.sub(fname, 2)
  end
  dep[#dep+1] = fname
  if run then
    out[#out+1] = '  "do\\n"\n'
  else
    modname = modname or mod_from_fname(fname)
    out[#out+1] = '  "package.preload[\\"'..modname..'\\"] = function (...)\\n"\n'
  end
  for line in io.lines(fname) do
    out[#out+1] = '  "  '
    out[#out+1] = string.gsub(line, "[\\\"]", { ['\\'] = '\\\\', ['"'] = '\\"' })
    out[#out+1] = '\\n"\n'
  end
  out[#out+1] = '  "end\\n"\n'
end

local function add_moddir(name)
  for fname in lfs.dir(name) do
    if fname:sub(-4, -1) == '.lua' then
      add_module(name..fname, mod_from_fname(fname))
    end
  end
end

local func_name = table.remove(arg, 1)

dep[#dep+1] = string.format("%s.c:", func_name)

for i,name in ipairs(arg) do
  if name:sub(-1,-1) == '/' then
    add_moddir(name)
  else
    add_module(name)
  end
end

out[#out+1] = [[  ;

int ]]..func_name..[[ (lua_State *L)
{
  int n = lua_gettop(L);
  if (luaL_loadbuffer(L, code, sizeof(code) - 1, "]]..func_name..[[")) return lua_error(L);
  lua_insert(L, 1);
  lua_call(L, n, 0);
  return 0;
}
]]

local f = assert(io.open(func_name .. '.c', 'w'))
assert(f:write(table.concat(out)))
assert(f:close())
local f = assert(io.open('.' .. func_name .. '.d', 'w'))
assert(f:write(table.concat(dep, ' ')..'\n'))
table.remove(dep, 1)
dep[#dep+1] = ''
assert(f:write(table.concat(dep, ':\n')))
assert(f:close())
