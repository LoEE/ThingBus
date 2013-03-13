local socket = require'socket'
local loop = require'loop'
local bio = require'bio'
local T = require'thread'
local B = require'binary'
local D = require'util'
local Object = require'oo'

local ExtProc = Object:inherit{
  respawn_period = 5,
  portno_token = newproxy()
}

if os.platform == 'linux' or os.platform == 'osx' then
  ExtProc.usb_exe = os.executable_path..' :raw-usb'
elseif os.platform == 'win32' then
  ExtProc.usb_exe = os.executable_dir..'/sepack-hid-win32.exe'
end

function ExtProc:init (args, log)
  self.log = log

  local lsock, err = assert(socket.bind ('127.0.0.1', 0))
  lsock:settimeout (0)
  local addr, port = lsock:getsockname()
  self.lsock = lsock
  self.port = port

  self.args = {}
  for i,v in ipairs(args) do
    if v == self.portno_token then
      self.args[i] = port
    else
      self.args[i] = args[i]
    end
  end

  self.inbox = T.Mailbox:new()
  self.outbox = T.Mailbox:new()
  self.statbox = T.Mailbox:new()
  T.go(self._out_loop, self)

  self.accept_watcher = loop.on_acceptable (lsock, function () T.go(self._handle_connect, self) end, true)
  T.go(self._start_loop, self)
end

function ExtProc.newUsb (class, product, serial, log)
  local args = {ExtProc.usb_exe, ExtProc.portno_token}
  if product then args[#args+1] = '.p'..product end
  if serial then args[#args+1] = '.s'..serial end
  return class:new(args, log)
end

function ExtProc:_start_loop()
  local cmd = table.concat(self.args, ' ')
  while true do
    local timeout = T.Timeout:new(self.respawn_period)
    if self.log then self.log:write("executing: "..cmd.."\n") end
    self.exitbox = T.Mailbox:new()
    self.procin, err = io.popen(cmd, "w")
    if not self.procin then self.log:write('E', ' ', err, '\n') end
    self.exitbox:recv()
    self.exitbox = nil
    timeout:recv()
  end
end

function ExtProc:restart()
  if self.exitbox then
    self.exitbox:put(true)
  end
end

function ExtProc:_handle_connect()
  local sock = self.lsock:accept()
  sock:settimeout(0)
  self.outfd = sock
  self.statbox:put(true)
  return self:_in_loop(sock)
end

function ExtProc.read_message(b)
  local line, err = b:readuntil('\n')
  if not line then
    if err == 'closed' then err = 'eof' end
    return nil, nil, err
  end
  if string.sub(line, -1) == '\r' then line = string.sub(line, 1, -2) end
  local len = tonumber(line)
  if not len then
    if #line == 0 then
      return ExtProc.read_message(b)
    else
      return nil, line
    end
  else
    local data, err = b:read(len)
    if not data then return nil, nil, err end
    local ending, err = b:read(1)
    if not ending then return nil, nil, err end
    if ending ~= '\n' then return nil, nil, 'framing error: '..D.repr(ending) end
    return data, nil
  end
end

function ExtProc:_in_loop(infd)
  local inb = bio.IBuf:new(infd)
  while true do
    local data, cmd, err = self.read_message(inb)
    if data then
      if self.log then self.log:write('<', string.format(' %s : %s', B.bin2hex(data), D.repr(data)), '\n') end
      self.inbox:put(data)
    elseif cmd then
      if self.log then self.log:write('?', ' ', cmd, '\n') end
      self.statbox:put(cmd)
    else
      if err == 'eof' then
        if self.log then self.log:write('?', ' exit\n') end
        self.statbox:put(false)
        break
      else
        if self.log then self.log:write('E', ' ', err, '\n') end
        break
      end
    end
  end
  infd:close()
  self.exitbox:put(true)
end

function ExtProc:_out_loop()
  while true do
    local data = self.outbox:recv()
    assert(type(data) == 'string', 'data is not a string')
    if self.log then self.log:write('>', string.format(' %s : %s', B.bin2hex(data), D.repr(data)), '\n') end
    if self.outfd then loop.write(self.outfd, table.concat{ "tx ", #data, "\n", data, "\n" }) end
  end
end

return ExtProc
