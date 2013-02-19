local D = require'util'
local Object = require'oo'
local T = require'thread'
local B = require'binary'
local bit = require'bit32'

local Sepack = Object:inherit{
  verbose = 0,
}

local loop = require'loop'
local socket = require'socket'
local bio = require'bio'

local function appendToFile(name, data)
  local fd, ok, err
  fd, err = io.open(name, 'a')
  if not fd then return nil, err end
  ok, err = fd:write(data)
  if not ok then return nil, err end
  fd:close()
  return true
end

function Sepack.init (self, infd, sock, port, verbose)
  self.infd = infd
  self.verbose = verbose
  self.sock = sock
  self.serial = port
  self.mboxes = {}
  self.chnames = { [0] = 'uart', uart = 0 }
  self.ibuf = bio.IBuf:new(self.sock)
  T.go(self.run_reader, self, self.ibuf)
end

function Sepack.run_reader (self, ibuf)
  local inbox = self:mbox'uart'
  while true do
    local line = assert(ibuf:readuntil('\n'))
    local args = string.split(line, ' +')
    if args[1] == 'rx' then
      local len = tonumber(args[2])
      local data = assert(ibuf:read(len))
      assert(ibuf:read(1) == '\n')
      if self.verbose >= 2 then
        if self.verbose >= 3 then
          appendToFile(self.serial..'.log', '< '..D.repr(data)..'\n')
        else
          D.green'<uart'(data)
        end
      end
      inbox:put(data)
    else
      error('invalid command: '..D.repr(line))
    end
  end
end

function Sepack.findchannel (self, ...)
  for i=1,select('#', ...) do
    local chname = select(i, ...)
    if self.chnames[chname] ~= nil then
      return chname
    end
  end
end

function Sepack.close (self)
  self.sock:close()
end

-- assumes only one pipe is read simultaneously
function Sepack.mbox (self, chn)
  local chno = chn
  if type(chn) == 'string' then
    chno = self.chnames[chn] or error('unknown channel: '..chn)
  end
  if not chno then
    error ('invalid mailbox: ' .. tostring (chn), 2)
  end
  local mbox = self.mboxes[chno]
  if not mbox then mbox = T.Mailbox:new() self.mboxes[chno] = mbox end
  return mbox
end

function Sepack.write (self, chname, data, flags, cont)
  if type(data) == 'table' then data = B.flat (data) end
  if self.verbose >= 2 then
    if self.verbose >= 3 then
      appendToFile(self.serial..'.log', '> '..D.repr(data)..'\n')
    else
      D.green(chname..'>')(data)
    end
  end
  local t = { "tx ", #data, "\n", data, "\n" }
  loop.write(self.sock, table.concat(t))
end

function Sepack.recv (self, chname)
  return self:mbox(chname):recv()
end

local function open (options)
  local o = options
  if not o.callback then error ("use must provide a callback to Sepack.open", 2) end

  local lsock, err = assert(socket.bind ('127.0.0.1', 0))
  lsock:settimeout (0)
  local addr, port = lsock:getsockname()
  local infd

  local function start(wait)
    if wait then T.sleep(wait) end
    local cmd = table.concat({os.program_path..'/sepack-tty', 'tcp!127.0.0.1!'..port, o.name, o.baud}, ' ')
    infd = assert(io.popen(cmd, "r"))
    local cancel
    local function onread()
      local data, err = io.raw_read(infd)
      if not data then infd:close() end
      if not data and err == 'eof' then
        cancel()
        infd = nil
        return T.go(start, 5)
      end
    end
    cancel = loop.on_readable (infd, onread, true)
  end
  local function handle()
    D.blue'found device'(o.name)
    local sock = lsock:accept()
    sock:settimeout(0)
    local s = Sepack:new(infd, sock, o.name, o.verbose or 0)
    o.callback(s)
  end
  loop.on_acceptable (lsock, handle, true)
  start()
end

return {
  Sepack = Sepack,
  open = open,
}
