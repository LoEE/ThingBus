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



local LEVEL_COLORS = {
  dbg = 'norm',
  log = 'blue',
  info = 'cyan',
  warn = 'red',
  err = 'redb',
}
local function stderr_sink(enabled, name, level, msg, ...)
  if not enabled then return end
  -- if LEVEL_COLORS[level] and level ~= 'warn' and level ~= 'err' then return end
  -- print(p:format(enabled, name, level, msg, ...))
  local c = LEVEL_COLORS[level] or level
  local msg = (name and (name..'\t') or '')..msg
  local args
  if select('#', ...) > 0 then
    args = p:format (...)
  else
    args = ""
  end
  io.stderr:write (color(c)..msg..' '..args..color('norm')..'\n')
end



local Logger = O()
Logger.loggers = {}

makelogger = O.constructor(function (self, name)
  self.name = name
  self.enabled = true
  if name then self.loggers[name] = self end
end)
local logger = makelogger(Logger, false)
_G.log = logger

logger.null = makelogger(Logger)
logger.null.stream = T.Publisher:new()
logger.null.stdsink = function () end

Logger.__type = "logger"
Logger.stream = T.Publisher:new()
Logger.stdsink = stderr_sink

function Logger:sub(name)
  checks('logger', 'string')
  if self.name then
    return makelogger(Logger, self.name..'.'..name)
  else
    return makelogger(Logger, name)
  end
end

function Logger:off()
  self.enabled = false
  return self
end

function Logger:_put(name, level, msg, ...)
  self.stdsink(self.enabled, name, level, msg, ...)
  self.stream:publish(self.enabled, name, level, msg, ...)
end

function Logger:__call(level, msg, ...)
  checks('logger', 'string', 'string')
  self.stdsink(self.enabled, self.name, level, msg, ...)
  self.stream:publish(self.enabled, self.name, level, msg, ...)
  return ...
end

function Logger:log(msg, ...)
  return self('log', msg, ...)
end

function Logger:write(msg, ...)
  return self('log', msg, ...)
end

function Logger:dbg(msg, ...)
  return self('dbg', msg, ...)
end

function Logger:info(msg, ...)
  return self('info', msg, ...)
end

function Logger:warn(msg, ...)
  return self('warn', msg, ...)
end

function Logger:error(msg, ...)
  return self('err', msg, ...)
end

local Logger_mt = {}
setmetatable(Logger, Logger_mt)

function Logger_mt.__index(self, name)
  if colors[name] then
    self[name] = function (self, msg, ...)
      return self(name, msg, ...)
    end
    return self[name]
  end
end



M.prepend_thread_names = true

local function D(c)
  return function (msg)
    return function (...)
      local name = M.prepend_thread_names and T.getname()
      logger:_put(name, c, msg, ...)
      return ...
    end
  end
end



local function __index (self, name)
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
