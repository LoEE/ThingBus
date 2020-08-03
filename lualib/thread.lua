local Object = require'oo'
local socket = require'socket'

local create = coroutine.create
local oldresume = coroutine.resume
local oldcurrent = coroutine.running
local oldyield = coroutine.yield

-- Make sure we only return threads that we created (resumed).
-- This is required for recvs inside a coxpcall to work:
-- we have to resume the coroutine that called pcall and not the inner one.
local current_thread = 'thread:       main'
local function current ()
  return current_thread
end

local pcall = pcall
local xpcall = xpcall
local Thread = {
  now = os.time_monotonic or socket.gettime,
  create = create,
  current = current,
  spcall = pcall,
  sxpcall = xpcall,
  identity = function (...) return ... end,
}
if not rawget(_G, 'jit') then
  local coxpcall = require 'coxpcall'
  Thread.pcall = coxpcall.copcall
  Thread.xpcall = coxpcall.coxpcall
else
  Thread.pcall = pcall
  Thread.xpcall = xpcall
end

_G.pcall = nil
_G.xpcall = nil

local weakmt = { __mode = 'k' }
local thread_names = setmetatable ({}, weakmt)
local thread_handlers = setmetatable ({}, weakmt)
local function default_thread_handler(thd, ...)
  io.stderr:write(string.format("error %s\n%s\nin thread %s",
      (...) or "no message",
      debug.traceback(thd),
      Thread.getname (thd)))
  os.exit(2)
end
local thread_runtimes = setmetatable ({}, weakmt)
local thread_latencies = {}
local thread_mailboxes = setmetatable ({}, weakmt)

local function setname (name, thd)
  checks('string', '?thread')
  if not thd then thd = current() end
  thread_names[thd] = name
end
Thread.setname = setname

local function getname (thd)
  checks('?thread')
  if not thd then thd = current() end
  return thread_names[thd] or ('<'..tostring(thd):sub(9)..'>')
end
Thread.getname = getname

local total_runtime = 0
local function add_runtime (thd, time)
  thd = thread_names[thd]
  if time > (thread_latencies[thd] or 0) then thread_latencies[thd] = time end
  thread_runtimes[thd] = (thread_runtimes[thd] or 0) + time
  total_runtime = total_runtime + time
end

Thread.thread_timing_info = function ()
  local latencies = thread_latencies
  thread_latencies = {}
  return total_runtime, thread_runtimes, latencies
end

local function timing_sort(tab)
  local r = {}
  for k, v in pairs(tab) do
    r[#r+1] = { k, v }
  end
  table.sort(r, function (a, b) return a[2] > b[2] end)
  return r
end

Thread.thread_timing_report = function ()
  local start = Thread.now()
  local total, run, latency = Thread.thread_timing_info()
  run = timing_sort(run) latency = timing_sort(latency)
  io.stderr:write("Highest runtimes:\n")
  for i=1,10 do
    if not run[i] then break end
    io.stderr:write(string.format("%6.2f ms %4.1f %s\n", run[i][2] * 1000, run[i][2] / total * 100, run[i][1]))
  end
  io.stderr:write(string.format("Total runtime: %.2f ms\n", total * 1000))
  io.stderr:write('\n')
  io.stderr:write("Highest latencies:\n")
  for i=1,10 do
    if not latency[i] then break end
    io.stderr:write(string.format("%6.2f ms %s\n", latency[i][2] * 1000, latency[i][1]))
  end
  io.stderr:write('\n')
  io.stderr:write(string.format("Timing report time: %.2f ms\n", (Thread.now() - start) * 1000))
end

local function get_mailbox (thd)
  local mbox = thread_mailboxes[thd]
  if not mbox then mbox = {} thread_mailboxes[thd] = mbox end
  return mbox
end

local busy_list = {}
local callback_list = {}
local nice_list = {}
local Idle = { list = nice_list, call = function (f) assert(type(f) == 'function', 'function expected') nice_list[f] = true end }
local handle_resume_result, resume
function handle_resume_result (thd, tstart, resume_ok, ...)
  local tend = Thread.now()
  add_runtime (thd, tend - tstart)
  if not resume_ok then
    local handler = thread_handlers[thd] or default_thread_handler
    local ok, err = Thread.spcall(handler, thd, ...)
    if not ok then
      io.stderr:write(string.format("error in thread error handler for %s: %s\n",
        Thread.getname (thd), err))
      os.exit(2)
    end
  elseif ... then
    return resume(...) -- trampoline
  end
  local idle = false
  while not idle do
    idle = true
    local busy_thd = next(busy_list)
    if busy_thd then
      busy_list[busy_thd] = nil
      return resume(busy_thd)
    end
    if #callback_list > 0 then
      idle = false
      current_thread = 'thread:   callback'
      local l = callback_list
      callback_list = {}
      for i=1,#l do
        local ok, err = xpcall(l[i], debug.traceback)
        if not ok then local here = #debug.traceback() - 16 + 27
          -- FIXME: use default_thread_handler
          print("error in queued callback: "..err:sub(1,#err - here))
          os.exit(2)
        end
      end
    end
    while true do
      local v = next(nice_list)
      if type(v) == 'thread' then
        return resume (v, Idle)
      elseif type(v) == 'function' then
        idle = false
        current_thread = 'thread:       nice'
        nice_list[v] = nil
        local ok, err = xpcall(v, debug.traceback)
        if not ok then
          -- FIXME: use default_thread_handler
          print("error in idle callback: "..err)
          os.exit(2)
        end
      else
        break
      end
    end
    current_thread = 'thread:       main'
  end
end
local main_thread_resume_arguments
function resume (thd, ...)
  local cthd = oldcurrent()
  -- print("resume", cthd, thd, (...))
  if not cthd then
    current_thread = thd
    if thd == 'thread:       main' then
      -- io.stderr:write('Thread.loop_stop() not cthd\n')
      main_thread_resume_arguments = {...}
      return Thread.loop_stop()
    else
      return handle_resume_result (thd, Thread.now(), oldresume (thd, ...))
    end
  else
    if cthd == thd then error('a thread cannot resume itself', 2) end
    busy_list[current()] = true
    if thd == 'thread:       main' then
      -- print('Thread.loop_stop() cthd', current())
      main_thread_resume_arguments = {...}
      Thread.loop_stop()
      return oldyield ()
    else
      return oldyield (thd, ...) -- return to trampoline
    end
  end
end
local function yield (...)
  if not oldcurrent() then
    -- io.stderr:write('Thread.loop_run()\n')
    Thread.loop_run()
    local resume_args = main_thread_resume_arguments
    if not resume_args then
      -- Ctrl-C ??
      error("Keyboard interrupt", 0)
    end
    main_thread_resume_arguments = nil
    return unpack(resume_args)
  else
    return oldyield(...)
  end
end

Thread.yield = yield
Thread.resume = resume

function Thread.queuecall (fun)
  assert(type(fun) == 'function', 'function expected')
  if not oldcurrent() then
    local ok, err = xpcall(fun, debug.traceback)
    if not ok then local here = #debug.traceback() - 16 + 27
      -- FIXME: use default_thread_handler
      print("error in (non)queued callback: "..err:sub(1,#err - here))
      os.exit(2)
    end
  else
    callback_list[#callback_list+1] = fun
  end
end

function Thread.kill (thd)
  if coroutine.status(thd) == 'dead' then return end
  local cthd = oldcurrent()
  if cthd == thd then error('a thread cannot kill itself', 2) end
  return resume(thd, false)
end

function Thread.go (fun, ...)
  local thd
  local src = debug.getinfo(2, "Sl")
  src = '<'..string.sub(src.source, 2)..':'..src.currentline..'>'
  if not oldcurrent() then
    thd = create(fun)
    setname(src, thd)
    resume(thd, ...)
  else
    if select('#', ...) > 0 then
      local ofun = fun
      local args = {...}
      fun = function () return ofun(unpack(args)) end
    end
    thd = create (fun)
    setname(src, thd)
    busy_list[thd] = true
  end
  return thd
end

function Thread.sethandler (thd, fun)
  checks('thread|string', 'function')
  local old_handler = default_thread_handler
  if type(thd) == 'thread' then
    thread_handlers[thd] = fun
  elseif thd == 'default' then
    default_thread_handler = fun
  else
    error("sethandler: invalid argument #1 expected thread or 'default' got: "..tostring(thd))
  end
  return old_handler
end

function Thread.recv (srcs, poll)
  srcs[false] = nil -- remove 'never' events
  for s,f in pairs(srcs) do
    local ok, v = s:poll ()
    if ok then
      if v then
        return f(unpack(v))
      else
        return f()
      end
    end
  end
  if poll then return nil end
  local thd = current()
  if not thd then error ('you cannot use Thread.recv on the main thread', 2) end
  for s,_ in pairs(srcs) do
    s:register_thread (thd)
  end
  local function handle (src, ...)
    for s,_ in pairs(srcs) do
      s:unregister_thread (thd)
    end
    if src ~= false then
      local handler = srcs[src]
      return handler(...)
    else
      return yield()
    end
  end
  return handle (yield())
end

local function recvone (src, poll)
  local ok, v = src:poll ()
  if ok then
    if v then
      return unpack(v)
    else
      return nil
    end
  end
  if poll then return nil end
  local thd = current()
  if not thd then error ('you cannot use Thread.recvone on the main thread', 2) end
  src:register_thread (thd)
  local function handle (rsrc, ...)
    src:unregister_thread (thd)
    if rsrc ~= false then
      return ...
    else
      return yield()
    end
  end
  return handle (yield())
end
Thread.recvone = recvone

local ThreadMailbox = {}
Thread.ThreadMailbox = ThreadMailbox
ThreadMailbox.__type = "ThreadMailbox"

function ThreadMailbox.poll (_)
  local thd = current()
  local mbox = thread_mailboxes[thd]
  if mbox and #mbox > 0 then
    return true, table.remove(mbox, 1)
  end
  return false
end

function ThreadMailbox.register_thread (_, thd)
  get_mailbox(thd).waiting = true
end

function ThreadMailbox.unregister_thread (_, thd)
  get_mailbox(thd).waiting = false
end

function ThreadMailbox.recv (self)
  return recvone (self)
end

function Thread.send (thd, ...)
  if type(thd) ~= 'thread' then error ('can only send to threads, not: ' .. tostring (thd), 2) end
  local mbox = get_mailbox (thd)
  if mbox.waiting then
    return resume (thd, ThreadMailbox, ...)
  else
    mbox[#mbox + 1] = {...}
  end
end

Thread.Idle = Idle

function Idle.poll (_)
  return nil
end

function Idle.register_thread (_, thd)
  nice_list[thd] = true
end

function Idle.unregister_thread (_, thd)
  nice_list[thd] = nil
end

function Idle.recv (self)
  return recvone (self)
end

local Source = Object:inherit()
Thread.Source = Source

function Source.poll (_)
  return nil
end

function Source.register_thread (self, thd)
  local i = #self + 1
  self[i] = thd
  self[thd] = i
end

function Source.unregister_thread (self, thd)
  local i = self[thd]
  table.remove (self, i)
  self[thd] = nil
end

function Source.recv (self)
  return recvone (self)
end

function Thread.install_loop (loop)
  function Thread.sleep (seconds)
    local c = current()
    local cancel = loop.run_after (seconds, function ()
      return resume(c, true)
    end)
    local ok = yield()
    if not ok then cancel() return yield() end
  end

  local ev = require'ev'
  Thread.loop_run = loop.run
  Thread.loop_stop = function () loop.default:unloop(ev.UNLOOP_ONE) end

  local Timeout = Source:inherit()
  Timeout.__type = 'Timeout'
  Thread.Timeout = Timeout

  function Timeout:init(seconds)
    if type(seconds) ~= 'number' then error('timeout is not a number: '..tostring(seconds), 3) end
    self.time = seconds
    if seconds <= 0 then
      self:fire()
    else
      if self.timer then
        self.timer(seconds)
      else
        self.timer = loop.run_after (seconds, function ()
          self:fire()
        end)
      end
    end
  end

  function Timeout:fire()
    self.fired = true
    for _, thd in ipairs(self) do
      resume (thd, self)
    end
  end

  function Timeout:poll()
    return self.fired
  end

  function Timeout:cancel()
    self.fired = nil
    self.timer()
  end

  function Timeout:restart(time)
    checks('Timeout', '?number')
    self:cancel()
    self:init(time or self.time)
  end

  function Timeout:tick(time)
    checks('Timeout', '?number')
    if self:poll() then
      self:restart(time)
      return true
    end
  end
end

local Mailbox = Source:inherit()
Thread.Mailbox = Mailbox
Mailbox.__type = 'Mailbox'

function Mailbox.init (self)
  self.buffer = {}
  return self
end

function Mailbox.put (self, ...)
  local n = #self
  if n == 0 then
    local buf = self.buffer
    buf[#buf + 1] = {...}
  else
    if n > 1 then
      n = math.random (#self)
    end
    return resume (self[n], self, ...)
  end
end

function Mailbox.putback (self, ...)
  local n = #self
  if n == 0 then
    table.insert (self.buffer, 1, {...})
  else
    if n > 1 then
      n = math.random (#self)
    end
    return resume (self[n], self, ...)
  end
end

function Mailbox.poll (self)
  local buf = self.buffer
  if #buf > 0 then
    return true, table.remove (buf, 1)
  end
  return false
end

local function apply (mbox, fun, ...)
  if mbox then
    return mbox:put(Thread.pcall(fun, ...))
  else
    local ok, err = Thread.xpcall(fun, debug.traceback, ...)
    if not ok then print('cast error:', err) end
  end
end

function Thread.agent ()
  local agent = {
    [ThreadMailbox] = apply
  }
  local mt = {
    __type = "agent"
  }
  mt.__index = mt
  local src = debug.getinfo(2, "Sl")
  src = '<'..string.sub(src.source, 2)..':'..src.currentline..'>'
  local thd = Thread.go (function ()
    setname(src)
    while true do Thread.recv(agent) end
  end)
  function mt:__call (thunk, ...)
    return Thread.send(thd, nil, thunk, ...)
  end
  function mt:pcall (thunk, ...)
    local mbox = Mailbox:new()
    Thread.send(thd, mbox, thunk, ...)
    return mbox:recv()
  end
  local function handle_return(ok, ...)
    assert(ok, ...)
    return ...
  end
  function mt:call (thunk, ...)
    return handle_return(self:pcall(thunk, ...))
  end
  function mt:handle (evsrc, func)
    agent[evsrc] = func
    self(function () end)
  end
  return setmetatable(agent, mt)
end



local Broadcast = Source:inherit()
Thread.Broadcast = Broadcast
Broadcast.__type = "Broadcast"

function Broadcast:send(...)
  local n = #self
  for i=n,1,-1 do
    resume (self[i], self, ...)
  end
end



local Publisher = Object:inherit()
Thread.Publisher = Publisher
Publisher.__type = "Publisher"

function Publisher.publish (self, ...)
  self.current = {...}
  for _,mbox in ipairs(self) do
    mbox:put (...)
  end
end

function Publisher.subscribe (self)
  local m = Mailbox:new()
  self[#self+1] = m
  if self.current ~= nil then
    m:put(unpack(self.current))
  end
  return m
end

function Publisher.unsubscribe (self, mbox)
  for i,m in ipairs(self) do
    if m == mbox then
      return table.remove(self, i)
    end
  end
end

return Thread
