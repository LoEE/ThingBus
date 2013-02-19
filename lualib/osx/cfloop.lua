local D = require'util'
local T = require'thread'

local loop = require'_loop'
loop.type = 'CFRunLoop'

function loop.read (file)
  local thd = T.current()
  local cancel
  local function handler ()
    local data, err
    if type(file) ~= 'number' and file.getsockname then
      local partial
      data, err, partial = file:receive('*a')
      if err == 'timeout' and partial then
        data = partial
        err = nil
      end
    else
      data, err = io.raw_read(file)
    end
    if err ~= "timeout" then
      cancel()
      return T.resume (thd, true, data, err)
    end
  end
  cancel = loop.on_readable (file, handler, true)
  local ok, data, err = T.yield()
  if not ok then error(data, err) end
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
      if err == 'timeout' and partial then
        i = partial
        err = nil
      end
    else
      i, err = io.raw_write (file, data, start)
    end
    if not i then
      return i, err
    elseif i < len then
      start = i + 1
      loop.on_writeable (file, function () return T.resume (thd, true) end)
      local ok, err, arg = T.yield()
      if not ok then error(err, arg) end
    else
      return true
    end
  end
end 

--[[
do
  local pr, pw = os.pipe()
  os.set_interrupt_pipe(pw)
  loop.on_readable(pr,function () io.raw_read(pr) end, true)
end
--]]

T.install_loop (loop)

package.loaded['loop'] = loop
return loop
