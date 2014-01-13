local loop = require'loop'
local T = require'thread'
local D = require'util'
local B = require'binary'
local Object = require'oo'

local M = {}

local interactions = T.Publisher:new()
M.interactions = interactions

local agent = T.agent()
M.agent = agent

local stdout = io.stdout
local stderr = io.stderr

local function handleReturn (src, ok, ...)
  if not ok then
    local err = ...
    interactions:publish{'error', src, tostring(err)}
  else
    interactions:publish{'reply', src, D.p:format(...)}
  end
end

local ns = {
  T = T,
  D = D,
  B = B,
}
setmetatable(ns, {__index = _G})
M.ns = ns

local function wrap (data, src, chunk)
  setfenv(chunk, ns)
  return function ()
    interactions:publish{'cmd', src, data}
    handleReturn (src, T.xpcall (chunk, function (...) return ... end))
  end
end

function M.compile (data, src)
  local chunk, err = loadstring ("return " .. data, "stdin")
  if err then chunk, err = loadstring ("return (function () " .. data .. " end)()", "stdin") end
  if chunk then chunk = wrap(data, src, chunk) end
  return chunk, err
end

function M.execute (chunk, ...)
  return agent (chunk, ...)
end

function M.default_err_handler (cancel, err)
  if err == 'eof' then
    os.exit(0)
  else
    print ("repl read error:", err)
    os.exit(3)
  end
end

local console_in
do
  local source
  function console_in()
    if source then return source end
    local sink
    source, sink = os.pipe()
    io.setinherit(source, false)
    io.setinherit(sink, false)
    os.forward_console(sink)
    return source
  end
end

M.repls = {}

function M.start (file, err_handler)
  if file == 0 and os.platform == "win32" then
    file = console_in()
  end
  err_handler = err_handler or M.default_err_handler
  local sub = interactions:subscribe ()
  local ui = T.go(function ()
    while true do
      local ev = sub:recv()
      if #ev > 2 then
        if ev[1] ~= 'stdout' and ev[1] ~= 'stderr' then
          if ev[2] == 'stdin' then
            if ev[1] ~= 'cmd' and #ev[3] > 0 then stderr:write (ev[3] .. '\n') end
          else
            local prefix = '  '
            if ev[1] == 'cmd' then prefix = '> ' end
            D.green(prefix .. ev[3])()
          end
        end
      end
    end
  end)
  local reader
  local done = false
  local function cancel()
    done = true
  end
  reader = T.go(function ()
    while not done do
      local data, err = loop.read(file)
      if not data then return err_handler (cancel, err) end
      local chunk, err = M.compile (string.strip (data), "stdin")
      if chunk then
        M.execute(chunk)
      else
        print(err)
      end
    end
  end)
  M.repls[file] = reader
  return M
end

return M
