local socket = require'socket'
local loop = require'loop'
local bio = require'bio'
local T = require'thread'
local B = require'binary'
local D = require'util'
local Object = require'oo'
local o = require'kvo'
local subproc = require'subproc'

local ExtProc = Object:inherit{
  respawn_period = 1,
  portno_token = newproxy()
}

if os.platform == 'linux' or os.platform == 'osx' then
  ExtProc.usb_exe = {os.executable_path, ':raw-usb'}
elseif os.platform == 'win32' then
  ExtProc.usb_exe = {os.executable_dir..'/sepack-hid-win32.exe'}
end

function ExtProc:init (args, _log)
  self.log = _log or log.null

  local lsock, err = assert(socket.bind ('127.0.0.1', 0))
  io.setinherit(lsock, false)
  lsock:settimeout (0)
  local addr, port = lsock:getsockname()
  self.lsock = lsock
  self.port = port

  self.args = {}
  for i,v in ipairs(args) do
    if v == self.portno_token then
      self.args[i] = 'stdio'
    else
      self.args[i] = args[i]
    end
  end

  self.in_pckts = 0
  self.out_pckts = 0

  self.inbox = T.Mailbox:new()
  self.outbox = T.Mailbox:new()
  self.status = o(false)
  T.go(self._out_loop, self)

  -- self.accept_watcher = loop.on_acceptable (lsock, function () T.go(self._handle_connect, self) end, true)
  T.go(self._start_loop, self)
end

function ExtProc.newUsb (class, product, serial, log)
  local args = {unpack(ExtProc.usb_exe)}
  args[#args+1] = ExtProc.portno_token
  if product then args[#args+1] = '.p'..product end
  if serial then args[#args+1] = '.s'..serial end
  return class:new(args, log)
end

function ExtProc:_start_loop()
  -- local cmd = table.concat(self.args, ' ')
  while true do
    local timeout = T.Timeout:new(self.respawn_period)
    self.log:info("exec", cmd)
    self.exitbox = T.Mailbox:new()
    -- self.procin, err = io.popen(cmd, "w")
    -- if not self.procin then self.log:error("exec failed", D.unq(err)) end
    local sub = subproc:new(unpack(self.args)):stdin'pipe':stdout'pipe':start()
    self.outfd = sub._stdin.w
    self.status(true)
    T.go(self._in_loop, self, sub._stdout.r)
    sub:wait()
    -- self.exitbox:recv()
    -- self.exitbox = nil
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
  sock:setoption('tcp-nodelay', true)
  self.outfd = sock
  self.status(true)
  return self:_in_loop(sock)
end

function ExtProc.read_message(b)
  local line, err = b:readuntil('\n')
  if not line then
    if err == 'closed' then err = 'eof' end
    return nil, nil, err
  end
  -- local len = string.match(line, "^[rx ]*(.*)\r?")
  -- D'line:'(len, line)
  -- if string.sub(line, -1) == '\r' then line = string.sub(line, 1, -2) end
  -- if string.startswith(line, "rx ") then line = string.sub(line, 4) end
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
    if ending ~= '\n' then return nil, nil, 'framing error: '..D.repr(data, ending) end
    return data, nil
  end
end

function ExtProc:_in_loop(infd)
  local inb = bio.IBuf:new(infd)
  while true do
    local data, cmd, err = self.read_message(inb)
    if data then
      if self.log.enabled == true or type(self.log.enabled) == 'string' and string.find(self.log.enabled, 'dbg', 1, true) then self.log:dbg('< '..string.format('%s : %s', B.bin2hex(data), D.repr(data))) end
      self.in_pckts = self.in_pckts + 1
      self.inbox:put(data)
    elseif cmd then
      self.log:dbg('? '..cmd)
      self.status(cmd)
    else
      if err == 'eof' then
        self.log:dbg('< eof')
        self.status(false)
        break
      else
        self.log:error('input error', err)
        break
      end
    end
  end
  io.raw_close(infd) --:close()
  -- self.exitbox:put(true)
end

function ExtProc:_out_loop()
  -- self.outbox.put = function (_, data)
  --   if self.outfd then
  --     self.out_pckts = self.out_pckts + 1
  --     if type(data) == 'string' then
  --       if self.log.enabled and string.find(self.log.enabled, 'dbg', 1, true) then self.log:dbg('> '..string.format('%s : %s', B.bin2hex(data), D.repr(data))) end
  --       loop.write(self.outfd, "tx "..#data.."\n"..data.."\n")
  --     elseif type(data) == 'table' then
  --       D'out-table:'(data)
  --       if self.log.enabled and string.find(self.log.enabled, 'dbg', 1, true) then self.log:dbg('> '..D.repr(data)) end
  --       local out = table.concat(data, " ")
  --       loop.write(self.outfd, out.."\n")
  --     else
  --       D'out-error:'(data)
  --       self.log:err('error: unknown data format: '..D.repr(data))
  --     end
  --   end
  -- end
  while true do
    local data = self.outbox:recv()
    if self.outfd then
      self.out_pckts = self.out_pckts + 1
      if type(data) == 'string' then
        if self.log.enabled == true or type(self.log.enabled) == 'string' and string.find(self.log.enabled, 'dbg', 1, true) then self.log:dbg('> '..string.format('%s : %s', B.bin2hex(data), D.repr(data))) end
        loop.write(self.outfd, "tx "..#data.."\n"..data.."\n")
      elseif type(data) == 'table' then
        D'out-table:'(data)
        if self.log.enabled == true or type(self.log.enabled) == 'string' and string.find(self.log.enabled, 'dbg', 1, true) then self.log:dbg('> '..D.repr(data)) end
        local out = table.concat(data, " ")
        loop.write(self.outfd, out.."\n")
      else
        D'out-error:'(data)
        self.log:err('error: unknown data format: '..D.repr(data))
      end
    end
  end
end

return ExtProc
