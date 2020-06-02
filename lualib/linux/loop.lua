local T = require'thread'
local ev = require'ev'
local loop = {
  default = ev.Loop.default,
  type = 'libev',
}

local function oneshot (handler)
  return function (loop, watcher, ev)
    watcher:stop (loop)
    handler()
  end
end

local D = require'util'
local convert_file
if os.platform == 'windows' then
  local cache = setmetatable({}, { __mode = 'k' })
  function convert_file(file)
    if not cache[file] then
      local handle = assert(io.open_osfhandle(file))
      cache[file] = handle
    end
    return cache[file]
  end
else
  convert_file = io.getfd
end
function loop.on_readable (file, handler, rearm)
  if not rearm then handler = oneshot (handler) end
  local watcher = ev.IO.new(handler, convert_file(file), ev.READ)
  watcher:start (loop.default)
  return function (restart)
    if restart then
      watcher:start(loop.default)
    else
      watcher:stop(loop.default)
    end
  end
end
loop.on_acceptable = loop.on_readable

function loop.on_writeable (file, handler, rearm)
  if not rearm then handler = oneshot (handler) end
  local watcher = ev.IO.new(handler, convert_file(file), ev.WRITE)
  watcher:start (loop.default)
  return function () watcher:stop(loop.default) end
end

function loop.run_after (seconds, handler)
  local timer = ev.Timer.new (handler, seconds)
  timer:start (loop.default)
  return function (newseconds)
    if newseconds then
      return timer:again(loop.default, newseconds)
    else
      timer:stop(loop.default)
    end
  end
end

function loop.run ()
  loop.default:loop()
end

function loop.read (file, len)
  local thd = T.current()
  local cancel
  local function handler ()
    local data, err
    if type(file) ~= 'number' and file.getsockname then
      local partial
      if file.receivefrom then
        data, err = file:receive()
      else
        data, err, partial = file:receive(len or '*a')
      end
      if err == 'timeout' and partial then
        data = partial
        err = nil
      end
    else
      data, err = io.raw_read(file, len)
    end
    if err == 'closed' then err = 'eof' end
    if err ~= "timeout" then
      cancel()
      return T.resume (thd, true, data, err)
    end
  end
  cancel = loop.on_readable (file, handler, true)
  local ok, data, err = T.yield()
  if not ok then cancel() return T.yield() end
  return data, err
end

function loop.write (file, data)
  local thd = T.current()
  local len = #data
  local start = 1
  while start <= len do
    local i, err
    if type(file) ~= 'number' and file.send then
      local partial
      i, err, partial = file:send (data, start)
      if (err == 'timeout' or err == "Socket is not connected") and partial then
        i = partial
        err = nil
      end
    else
      i, err = io.raw_write (file, data, start)
    end
    if not i then
      return i, err
    elseif i == 0 then
      return false, 'zero bytes written'
    elseif i < len then
      start = i + 1
      local cancel = loop.on_writeable (file, function () return T.resume (thd, true) end)
      local ok, err, arg = T.yield()
      if not ok then cancel() return T.yield() end
    else
      return true
    end
  end
end

--[[
do
  local pr, pw = os.pipe()
  os.set_interrupt_pipe(pw)
  loop.interrupt_watcher = loop.on_readable(pr,function () io.raw_read(pr) end, true)
end
--]]

T.install_loop (loop)

return loop
