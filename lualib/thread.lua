require 'coxpcall'
local Object = require'oo'
local D = require'util'
local socket = require'socket'

local create = coroutine.create
local yield = coroutine.yield
local oldresume = coroutine.resume
local oldcurrent = coroutine.running

-- Make sure we only return threads that we created (resumed).
-- This is required for recvs inside a coxpcall to work:
-- we have to resume the coroutine that called pcall and not the inner one.
local current_thread = nil
local function current ()
  return current_thread
end

local Thread = {
  now = socket.gettime,
  create = create,
  current = current,
  spcall = _G.pcall,
  sxpcall = _G.xpcall,
  pcall = _G.copcall,
  xpcall = _G.coxpcall,
  identity = function (...) return ... end,
}
_G.pcall = nil
_G.xpcall = nil

local weakmt = { __mode = 'k' }
local thread_names = setmetatable ({}, weakmt)
local thread_handlers = setmetatable ({}, weakmt)
local thread_runtimes = setmetatable ({}, weakmt)
local thread_mailboxes = setmetatable ({}, weakmt)

local function add_runtime (thd, time)
  thread_runtimes[thd] = (thread_runtimes[thd] or 0) + time
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
local handle_resume, resume
function handle_resume (thd, tstart, ok, ...)
  local tend = Thread.now()
  add_runtime (thd, tend - tstart)
  if not ok then
    local h = thread_handlers[thd]
    if h then
      h(thd, ...)
    else
      print(string.format("error in %s: %s", Thread.getname (thd), select(1, ...) or "no message"))
      print(debug.traceback(thd))
    end
  else
    if select(1, ...) then
      return resume(...) -- trampoline
    else
      local thd = next(busy_list)
      if thd then
        busy_list[thd] = nil
        return resume(thd)
      end
      if #callback_list > 0 then
        local l = callback_list
        callback_list = {}
        for i=1,#l do
          l[i]()
        end
      end
      while true do
        local v = next(nice_list)
        if type(v) == 'thread' then
          return resume (v, Idle)
        elseif type(v) == 'function' then
          nice_list[v] = nil
          v()
        else
          break
        end
      end
      current_thread = nil
    end
  end
end
function resume (thd, ...)
  local cthd = oldcurrent()
  if not cthd then
    current_thread = thd
    return handle_resume (thd, Thread.now(), oldresume (thd, ...))
  else
    if cthd == thd then error('a thread cannot resume itself', 2) end
    busy_list[current()] = true
    return yield (thd, ...) -- return to trampoline
  end
end

Thread.yield = yield
Thread.resume = resume

function Thread.queuecall (fun)
  assert(type(fun) == 'function', 'function expected')
  callback_list[#callback_list+1] = fun
end

function Thread.kill (thd)
  if coroutine.status(thd) == 'dead' then return end
  local cthd = oldcurrent()
  if cthd == thd then error('a thread cannot kill itself', 2) end
  return resume(thd, false)
end

function Thread.go (fun, ...)
  local thd
  if not oldcurrent() then
    thd = create(fun)
    resume(thd, ...)
  else
    if select('#', ...) > 0 then
      local ofun = fun
      local args = {...}
      fun = function () return ofun(unpack(args)) end
    end
    thd = create (fun)
    busy_list[thd] = true
  end
  return thd
end

local function setname (name, thd)
  if not thd then thd = current() end
  thread_names[thd] = name
end
Thread.setname = setname

local function getname (thd)
  if not thd then thd = current() end
  return thread_names[thd] or tostring(thd)
end
Thread.getname = getname

function Thread.sethandler (thd, fun)
  assert(type(thd) == 'thread')
  assert(type(fun) == 'function')
  thread_handlers[thd] = fun
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
  for s,f in pairs(srcs) do
    s:register_thread (thd)
  end
  local function handle (src, ...)
    for s,f in pairs(srcs) do
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

function ThreadMailbox.poll (self)
  local thd = current()
  local mbox = thread_mailboxes[thd]
  if mbox and #mbox > 0 then
    return true, table.remove(mbox, 1)
  end
  return false
end

function ThreadMailbox.register_thread (self, thd)
  get_mailbox(thd).waiting = true
end

function ThreadMailbox.unregister_thread (self, thd)
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

function Idle.poll (self)
  return nil
end

function Idle.register_thread (self, thd)
  nice_list[thd] = true
end

function Idle.unregister_thread (self, thd)
  nice_list[thd] = nil
end

function Idle.recv (self)
  return recvone (self)
end

local Source = Object:inherit()
Thread.Source = Source

function Source.poll (self)
  return nil
end

function Source.register_thread (self, thd)
  local i = #self + 1
  self[i] = thd
end

local function find(t, v)
  for i,c in ipairs(t) do
    if c == v then
      return i
    end
  end
end

function Source.unregister_thread (self, thd)
  local i = find(self, thd)
  table.remove (self, i)
end

function Source.recv (self)
  return recvone (self)
end

function Thread.install_loop (loop)
  function Thread.sleep (seconds, id)
    local c = current()
    local cancel = loop.run_after (seconds, function ()
      resume(c, true)
    end)
    local ok, err, arg = yield()
    if not ok then cancel() return yield() end
  end

  local Timeout = Source:inherit()
  Thread.Timeout = Timeout

  function Timeout.init (self, seconds)
    if type(seconds) ~= 'number' then error('timeout is not a number: '..tostring(seconds), 3) end
    self.timer = loop.run_after (seconds, function ()
      self.fired = true
      for i, thd in ipairs(self) do
        resume (thd, self)
      end
    end)
  end

  function Timeout.poll (self)
    return self.fired
  end

  function Timeout.cancel (self)
    return self.timer:cancel ()
  end
end

local Mailbox = Source:inherit()
Thread.Mailbox = Mailbox

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
    if not ok then D.red'cast error:'(D.unq(err)) end
  end
end

function Thread.agent ()
  local mbox = Mailbox:new()
  local agent = {
    [ThreadMailbox] = apply
  }
  local thd = Thread.go (function ()
    while true do Thread.recv(agent) end
  end)
  local function cast (self, thunk, ...)
    return Thread.send(thd, nil, thunk, ...)
  end
  local function pcall (self, thunk, ...)
    Thread.send(thd, mbox, thunk, ...)
    return mbox:recv()
  end
  local function handle_return(ok, ...)
    assert(ok, ...)
    return ...
  end
  local function call (self, thunk, ...)
    Thread.send(thd, mbox, thunk, ...)
    return handle_return(mbox:recv())
  end
  local function handle (self, evsrc, func)
    agent[evsrc] = func
    self(function () end)
  end
  local mt = {__call = cast, pcall = pcall, call = call, handle = handle}
  mt.__index = mt
  return setmetatable(agent, mt)
end



local Broadcast = Source:inherit()
Thread.Broadcast = Broadcast

function Broadcast:send(...)
  local n = #self
  for i=n,1,-1 do
    resume (self[i], self, ...)
  end
end



local Publisher = Object:inherit()
Thread.Publisher = Publisher

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
    D.cyan'send cur to new sub'(unpack(self.current))
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
