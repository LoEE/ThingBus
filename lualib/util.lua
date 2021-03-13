local Pretty = require'interactive'
local B = require'binary'
local T = require'thread'
local O = require'o'
local json = require'cjson'
local socket = require'socket'
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
if os.platform == 'windows' then
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
M.color = color



local start = T.now()
local LEVEL_COLORS = {
  dbg = 'norm',
  log = 'blue',
  info = 'cyan',
  warn = 'red',
  err = 'redb',
}
local function stderr_sink(enabled, name, level, msg, ...)
  if not enabled then return end
  if type(enabled) == 'string' and not string.find(enabled, level, 1, true) then return end
  -- if LEVEL_COLORS[level] and level ~= 'warn' and level ~= 'err' then return end
  -- print(p:format(enabled, name, level, msg, ...))
  local c = LEVEL_COLORS[level] or level
  if name then
    msg = string.format("%12s %s", name, msg)
  end
  local args
  if select('#', ...) > 0 then
    args = p:format (...)
  else
    args = ""
  end
  local tstamp = ''
  if M.prepend_timestamps then
    tstamp = string.format("% 5.3f ", T.now()-start)
  end
  io.stderr:write (tstamp..color(c)..msg..' '..args..color('norm')..'\n')
end

local print_struct
if io.isatty(io.stderr) then
  function print_struct(msg)
    io.stderr:write('\27[1m'..msg..'\27[m')
  end
else
  function print_struct(msg)
    io.stderr:write(msg)
  end
end

local function struct_sink(enabled, name, id, object, ctx)
  if not enabled then return end
  if name then
    id = name .. "-" .. id
  end
  if ctx then
    ctx = ', '..ctx
  else
    ctx = ''
  end
  local ok, object_json = T.sxpcall(function () return json.encode(object) end, debug.traceback)
  if not ok then
    local err = object_json
    M.red('cannot serialize:')(err, object)
    error(err)
  end
  print_struct(string.format("~ %.3f [", socket.gettime())..json.encode(id)..", "..object_json..ctx..']\n')
end



local Logger = O()
Logger.loggers = {}

local makelogger = O.constructor(function (self, name)
  self.name = name
  self.enabled = true
  if name then self.loggers[name] = self end
end)
local logger = makelogger(Logger, false)
rawset(_G, 'log', logger)

logger.null = makelogger(Logger)
logger.null.stream = T.Publisher:new()
logger.null.stdsink = function () end

Logger.__type = "logger"
Logger.stream = T.Publisher:new()
Logger.stdsink = stderr_sink

function Logger:sub(name)
  checks('logger', 'string')
  local l
  if self.name then
    l = makelogger(Logger, self.name..'.'..name)
  else
    l = makelogger(Logger, name)
  end
  l.parent = self
  return l
end

function Logger:ctx()
  local ctx = self.context
  local l = self
  while true do
    l = l.parent
    if not l then break end
    if l.context then ctx = l.context end
  end
  return ctx and ctx()
end

function Logger:off()
  self.enabled = false
  return self
end

function Logger:flt(levels)
  self.enabled = levels
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

function Logger:struct(id, object)
  local ctx = self:ctx()
  struct_sink(self.enabled, self.name, id, object, ctx)
end

function Logger.format_traceback_struct(err, thd)
  local loc, file, msg, traceback = string.match(err, "^(([^:]+):[0-9]+): *([^\n]*)\n?(.*)$")
  if not loc then
    msg, traceback = string.match(err, "^([^\n]*)\n?(.*)$")
  end
  local name
  if type(thd) == 'thread' then
    name = T.getname(thd)
  end
  return {
    name = name,
    error = msg or err,
    location = loc,
    file = file,
    traceback = string.gsub(thd and debug.traceback(thd) or traceback, "^stack traceback:\n[\t ]+", ""),
  }
end

local function test_format_traceback_struct()
  local p1 = log.format_traceback_struct([[test_exception_logging.lua:10: qwe
stack traceback:
  [C]: in function 'error'
  test_exception_logging.lua:10: in function <test_exception_logging.lua:9>
  [C]: in function 'xpcall'
  /Users/jpc/Projects/vending-app/stm.lua:32: in function </Users/jpc/Projects/vending-app/stm.lua:24>]])
  assert(p1.error == "qwe")
  assert(p1.location == "test_exception_logging.lua:10")
  assert(p1.file == "test_exception_logging.lua")
  assert(p1.traceback == [[[C]: in function 'error'
  test_exception_logging.lua:10: in function <test_exception_logging.lua:9>
  [C]: in function 'xpcall'
  /Users/jpc/Projects/vending-app/stm.lua:32: in function </Users/jpc/Projects/vending-app/stm.lua:24>]])
  local c = coroutine.create(function () error("asd") end)
  local ok, err = coroutine.resume(c)
  assert(not ok)
  local p2 = log.format_traceback_struct(err, c)
  assert(p2.error == "asd")
  assert(p2.file == "lualib/util.lua")
  assert(string.match(p2.location, "lualib/util.lua:[0-9]+"))
  assert(string.match(p2.traceback,
      "%[C%]: in function 'error'\n\009lualib/util.lua:[0-9]+: in function <lualib/util.lua:[0-9]+>"))
  local p3 = log.format_traceback_struct([[attempt to yield across metamethod/C-call boundary
stack traceback:
  [C]: in function 'oldyield'
  .../jpc/Projects/ThingBus/install/osx/lualib/thread.lua:187: in function <.../jpc/Projects/ThingBus/install/osx/lualib/thread.lua:166>
  (tail call): ?
  .../jpc/Projects/ThingBus/install/osx/lualib/sepack.lua:234: in function 'on_disconnect'
  .../jpc/Projects/ThingBus/install/osx/lualib/sepack.lua:88: in function 'on_disconnect'
  .../jpc/Projects/ThingBus/install/osx/lualib/sepack.lua:71: in function '_ext_status'
  .../jpc/Projects/ThingBus/install/osx/lualib/sepack.lua:49: in function 'fun'
  ...ers/jpc/Projects/ThingBus/install/osx/lualib/kvo.lua:209: in function <...ers/jpc/Projects/ThingBus/install/osx/lualib/kvo.lua:209>
  [C]: in function 'sxpcall'
  ...ers/jpc/Projects/ThingBus/install/osx/lualib/kvo.lua:209: in function 'notify'
  ...ers/jpc/Projects/ThingBus/install/osx/lualib/kvo.lua:168: in function <...ers/jpc/Projects/ThingBus/install/osx/lualib/kvo.lua:163>
  (tail call): ?
  ...jpc/Projects/ThingBus/install/osx/lualib/extproc.lua:126: in function <...jpc/Projects/ThingBus/install/osx/lualib/extproc.lua:111>
  (tail call): ?  nil nil]])
  assert(not p3.loc and not p3.file)
  assert(p3.error == "attempt to yield across metamethod/C-call boundary")
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



-- log tracebacks
local thread_error_log = log:sub('thread')
local old_thread_error_handler
old_thread_error_handler = T.sethandler('default', function (thd, err)
  thread_error_log:struct('error', thread_error_log.format_traceback_struct(err, thd))
  if io.isatty(2) then old_thread_error_handler(thd, err) end
  os.exit(2)
end)



M.prepend_timestamps = true
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
    times[#times + 1] = T.now()
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
