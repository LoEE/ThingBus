local Pretty = require'interactive'
local B = require'binary'
local T = require'thread'
local O = require'o'
local M = {}

--: ANSI terminal colors and other goodies
local colors = {
  red = "31m", green = "32m", yellow = "33m", blue = "34m", magenta = "35m", cyan = "36m", white = "37m",
  redb = "1;31m", greenb = "1;32m", yellowb = "1;33m", blueb = "1;34m", magentab = "1;35m", cyanb = "1;36m", whiteb = "1;37m",
  norm = "m"
}

local p = Pretty:new{}
M.p = p

local unq = {
  __tostring = function (self) return table.concat(self, ' ') end
}

function M.unq(...)
  return setmetatable({...}, unq)
end

function M.hex(s)
  if type(s) == 'string' then
    return M.unq(B.bin2hex(s))
  else
    local s = string.format('%x', s)
    if #s % 2 == 1 then
      return '0'..s
    else
      return s
    end
  end
end

function M.repr(...)
  return p:format(...)
end

function M.gc()
  local before = collectgarbage'count'
  collectgarbage'collect'
  M.cyan(string.format('GC: %.2f -> %.2f', before, collectgarbage'count'))()
end

function M.abort(code, message)
  M.red(message)()
  os.exit(code)
end

local color
if os.platform == 'win32' then
  function color(c)
    return ''
  end
else
  function color(c)
    if colors[c] then
      return "\27[" .. colors[c]
    else
      error ("unknown color: " .. p:format (c))
    end
  end
end



local logger = O()

makelogger = O.constructor(function (self, name)
  self.name = name
end)

function logger:sub(name)
  assert(name, 'subloggers need a name')
  if self.name then
    makelogger(logger, self.name..'.'..name)
  else
    makelogger(logger, name)
  end
end

-- function logger:__call(color, ...)
--   return function (...)
--     local args = ""
--     if select('#', ...) > 0 then
--       args = (msg and " " or "") .. p:format (...)
--     end
--     local t = color (c) .. (msg or '') .. args .. color'norm' .. (nonl and '' or '\n')
--     file:write (t)
--     return ...
--   end
--   D(self.name)(...)
--   return ...
-- end

function logger:log(...)
  return self(...)
end

function logger:clog(color, ...)
  D(color)(self.name)(...)
  return ...
end

function logger:info(...)
  D'cyan'(self.name)(...)
  return ...
end

function logger:warning(...)
  D'red'(self.name)(...)
  return ...
end

function logger:error(...)
  D'redb'(self.name)(...)
  return ...
end

local mainlogger = makelogger(logger)
local loggers = {}

local function getlogger()
  -- return loggers[T.current()] or mainlogger
  return io.stderr
end



local function D(c)
  return function (msg, nonl, file)
    file = file or getlogger()
    return function (...)
      local args = ""
      if select('#', ...) > 0 then
        args = (msg and " " or "") .. p:format (...)
      end
      local t = color (c) .. (msg or '') .. args .. color'norm' .. (nonl and '' or '\n')
      file:write (t)
      return ...
    end
  end
end

-- local old_print = print
-- function print(...)
--   D'norm'()(...)
-- end



local function __index (self, name)
  if name == 'log' then
    return getlogger()
  end
  if colors[name] then
    self[name] = D(name)
    return self[name]
  end
end

local function __call (self, ...)
  return self.blue(...)
end

do
  --pcall (function () require 'luarocks.loader' end)
  local socket = require'socket'
  local names = {}
  local times = {}
  function M.rtime (name)
    names[#names + 1] = name
    times[#times + 1] = socket.gettime()
  end
  function M.rtimedump ()
    local maxl = 0
    for i,name in ipairs(names) do maxl = math.max (maxl, #name) end
    local tab = string.rep (' ', maxl + 2)
    for i = 2,#times do
      local t = times[i] - times[i-1]
      if t > 1 then
        t = string.format("%6.2f s", t)
      else
        t = string.format("%4.2f ms", t * 1000)
      end
      print (tab .. t .. '\r' .. names[i - 1])
    end
  end
end

return setmetatable(M, {__call = __call, __index = __index})

--[=[ interactive registry dumper
function repl.ns.REG(table,index)
  local ans = ""
  local dash = "--------------"
  local function dumpreg(table,index)
    local x,y
    print(dash)
    for x,y in pairs(table) do
      if type(y) == "table" then
        print(string.format("%-30s%-20s",index,tostring(x)),tostring(y),"     Enter table y or q")
        ans = io.read()
        if ans == 'y' then
          dumpreg(y,tostring(x))
        end
        if ans == 'q' then
          return
        end
      else
        print(string.format("%-30s%-20s",index,tostring(x)),tostring(y))
      end
    end
    print(dash)
  end

  print(string.format("%-30s%-25s%s","Table","Index","Type"))
  dumpreg(table or debug.getregistry(),index or "Registry")
  print("\nend of program")
end
--]=]
