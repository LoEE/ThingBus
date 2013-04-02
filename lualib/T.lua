require 'coxpcall'
local O = require'o'

local ccreate = coroutine.create
local cyield = coroutine.yield
local cresume = coroutine.resume
local crunning = coroutine.running
local cstatus = coroutine.status

local spcall = pcall
local sxpcall = xpcall

local now = os.time_unix

pcall = nil
xpcall = nil

local T = {
  now = now,
  pcall = copcall,
  xpcall = coxpcall,
}

function T.identity (...)
  return ...
end

-- thread attributes
local weakkeymt = { __mode = 'k' }
local names = setmetatable ({}, weakkeymt)

local function getname (obj)
  return names[obj] or tostring(obj)
end
T.getname = getname

local function setname (obj, name)
  checks('?', 'string')
  names[obj] = name
end
T.setname = setname

local function fmtname (name)
  local pname = getname(current_thd)
  if not pname then return name end
  return pname..'.'..name
end

local thd_runtimes = setmetatable ({}, weakkeymt)

local function thd_runtime_add (thd, time)
  thd_runtimes[thd] = (thd_runtimes[thd] or 0) + time
end

local tboxes = setmetatable ({}, weakkeymt)

local function gettbox (thd)
  local mbox = tboxes[thd]
  if not mbox then mbox = {} tboxes[thd] = mbox end
  return mbox
end

local thd_recvs = setmetatable ({}, weakkeymt)

local function fmtrecvs (thd)
  return 'RECVS: '..thd_recvs[thd]
end

-- scheduler
local current_thd = nil
local busylist = {}
local nicelist = {}

function T.thread_error_handler(thd, msg)
  print(string.format("error in %s: %s", getname(thd), msg))
  print(debug.traceback(thd))
end

local handle_resume, resume
function handle_resume (thd, tstart, ok, ...)
  local tend = now()
  thd_runtime_add(thd, tend - tstart)
  if not ok then T.thread_error_handler(thd, select(1, ...) or "no error message") end
  if ok and ... then
    return resume(...) -- trampoline
  else
    local thd = next(busylist)
    if thd then
      busylist[thd] = nil
      return resume(thd)
    end
    while true do
      local v = next(nicelist)
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

function resume (thd, ...)
  local cthd = crunning()
  if cthd == thd then error('a thread cannot resume itself', 2) end
  if not cthd then
    -- we are in the main thread so lets just resume the target thread
    current_thread = thd
    return handle_resume (thd, now(), cresume (thd, ...))
  else
    -- we are in some other thread so we have to trampoline back to
    -- the main thread to avoid stack overflows
    busylist[current_thd] = true
    return yield (thd, ...)
  end
end

function T.current ()
  return current_thd
end

local function go (name, fun, ...)
  checks('string', 'function')
  name = fmtname(name)
  local thd
  if not crunning() then
    -- we are in the main thread
    thd = ccreate(fun)
    setname(thd, name)
    resume(thd, ...)
  else
    if select('#', ...) > 0 then
      local ofun = fun
      local args = {...}
      fun = function () return ofun(unpack(args)) end
    end
    thd = ccreate (fun)
    setname(thd, name)
    busy_list[thd] = true
  end
  return thd
end

function T.go (namefun, ...)
  if type(namefun) == 'function' then return go('unknown', namefun, ...) end
  return go(namefun, ...)
end

function T.kill (thd)
  if cstatus(thd) == 'dead' then return end
  local cthd = crunning()
  if cthd == thd then error('a thread cannot kill itself', 2) end
  return resume(thd, false)
end

local function recvone (src, poll)
  if not crunning() then error ('you cannot use recv on the main thread', 2) end
  local ok, v = src:poll ()
  if ok then
    if v then
      return unpack(v)
    else
      return nil
    end
  end
  if poll then return nil end
  local thd = current_thd
  src:register_thread (thd)
  local function handle (rsrc, ...)
    src:unregister_thread (thd)
    if rsrc == false then return yield() end
    return ...
  end
  return handle (yield())
end

function T.recv (srcs, poll)
  if not crunning() then error ('you cannot use T.recv on the main thread', 2) end
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
  local thd = current_thd
  for s,f in pairs(srcs) do
    s:register_thread (thd)
  end
  local function handle (src, ...)
    for s,f in pairs(srcs) do
      s:unregister_thread (thd)
    end
    if src == false then return yield() end -- T.kill
    local handler = srcs[src]
    return handler(...)
  end
  return handle (yield())
end



--
-- Basic event sources
--
local Tbox = {}
T.Tbox = Tbox
local Mailbox = O()
T.Mailbox = Mailbox



function T.send (thd, ...)
  checks('thread')
  local mbox = gettbox(thd)
  if mbox.waiting then
    return resume (thd, Tbox, ...)
  else
    mbox[#mbox + 1] = {...}
  end
end



function Tbox:poll ()
  local tbox = gettbox(current_thd)
  if tbox and #tbox > 0 then
    return true, table.remove(tbox, 1)
  end
end

function Tbox:register_thread (thd)
  gettbox(thd).waiting = true
end

function Tbox:unregister_thread (thd)
  gettbox(thd).waiting = false
end

Tbox.recv = recvone




