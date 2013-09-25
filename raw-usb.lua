local usb = require'usb'
local T = require'thread'
local D = require'util'
local loop = require'loop'
local bio = require'bio'
local O = require'o'
local E = require'errno'

local verbose = false
local ssub = string.sub


local function usage(err)
  print(string.format([[Usage:
	%s <port-no>|stdio <options>

Supported options:
  .p<product-name>
  .s<serial-number>
]], arg[0]))
  if err then
    print(err)
  end
  os.exit(1)
end

local function eprintf(...)
  io.stderr:write(string.format(...))
end

local config = {
  transform = function (...) return ... end,
}

if #arg < 1 then
  usage()
end

local port = table.remove(arg, 1)
if port == 'stdio' then
  config.port = port
else
  config.port = tonumber(port)
end
if not config.port then
  usage()
end

for i,arg in ipairs(arg) do
  local prefix = ssub(arg, 1, 2)
  if prefix == '.p' then
    config.product = ssub(arg, 3)
  elseif prefix == '.s' then
    config.serial = ssub(arg, 3)
  else
    usage('unknown option: '..arg)
  end
end

local LeakyBucket = O()

LeakyBucket.new = O.constructor(function (self, T)
  self.T = T
  self.t = 0
  self.T0 = {}
  self.T1 = {}
end)

function LeakyBucket:put(v)
  local t = math.floor(T.now() / self.T)
  local dt = t - self.t
  if dt > 0 then
    self.t = t
    if dt > 1 then
      self.T1 = {}
    else
      self.T1 = self.T0
    end
    self.T0 = {}
  end
  self.T0[#self.T0 + 1] = v
  return v
end

function LeakyBucket:count()
  return #self.T0 + #self.T1
end

function LeakyBucket:get()
  local T = {}
  for i=#self.T1,1,-1 do T[#T+1] = self.T1[i] end
  for i=#self.T0,1,-1 do T[#T+1] = self.T0[i] end
  return T
end

local errors = LeakyBucket:new(1)

local function handle_error (msg, err, fatal, errc, errno)
  if errc == "ENODEV" or errc == "ESHUTDOWN" or errc == "iokit/NoDevice" then
    eprintf("device diconnected\n")
    os.exit(2)
  end
  if verbose then D.red'ERROR:'(msg, err, errc, usb.fmt_errno(errno)) end
  local str = errors:put(string.format("error: %s: %s [%s %s]\n", msg, err, errc, usb.fmt_errno(errno)))
  if errors:count() > 15 then
    io.stderr:write("giving up after too many errors:\n")
    for i,v in ipairs(errors:get()) do
      io.stderr:write("  "..v)
    end
    os.exit(2)
  else
    io.stderr:write()
  end
end

local pin, pout

local function read_usb (fdout)
  local read_cb, read
  local function read_cb(data, err, fatal, errno)
    local errc = E[errno]
    if data then
      loop.write(fdout, #data..'\n'..data..'\n')
      read()
    else
      if errc ~= "iokit/Aborted" then
        handle_error("usb read", err, fatal, errc, errno)
      end
      loop.run_after(.1, read)
    end
  end
  function read()
    pin:read(2048, read_cb)
  end
  read()
  read()
  read()
  read()
end

local function write_usb(fdin)
  local ibuf = bio.IBuf:new(fdin)
  while true do
    local line = ibuf:readuntil('\n')
    if not line then os.exit(0) end
    if #line > 0 then
      local len = string.match(line, '^tx ([0-9]+)$')
      if len then
        local data = ibuf:read(len)
        if not data then
          eprintf("error: invalid data framing\n")
          os.exit(3)
        end
        if pout then
          pout:write(data, function (ok, err, fatal, errno)
            if not ok then handle_error("usb write", err, fatal, E[errno], errno) end
          end)
        end
        if ibuf:read(1) ~= '\n' then
          eprintf("error: invalid data framing\n")
          os.exit(3)
        end
      else
        eprintf("error: invalid command: %s\n", line)
        os.exit(3)
      end
    end
  end
end

local fdin, fdout

if config.port == 'stdio' then
  fdin = 0 fdout = 1
else
  local socket = require'socket'
  local sock, err = socket.connect('127.0.0.1', config.port)
  if not sock then
    eprintf("error connecting to port %d: %s", config.port, err)
    os.exit(3)
  end
  sock:settimeout(0)
  fdin = sock
  fdout = sock
end
T.go(write_usb, fdin)

local function open_device(d)
  local ok, err = T.spcall(d.open, d)
  if not ok and err:endswith("USBDeviceOpen: (iokit/common) exclusive access and device already open (0xe00002c5)") then -- FIXME
    eprintf("device busy: %s [%s]\n", d.product, d.serial)
    return false
  end
  local errc = E[errno]
  local ok, err = d:set_configuration(2)
  if not ok then
    if d.reset then
      eprintf("error: set_configuration: %s\n", err)
      eprintf("performing device reset\n")
      assert(d:reset())
      assert(d:set_configuration(2))
    else
      eprintf("error: set_configuration: %s\n", err)
      os.exit(2)
    end
  end
  local intf = assert(d:find_interfaces{ bInterfaceClass = 'ff' }[1], 'vendor interface not found')
  assert(intf:open())
  pin  = assert(intf:find_endpoints{'bulk', 'in'}[1])
  pout = assert(intf:find_endpoints{'bulk', 'out'}[1])
  loop.write(fdout, "connect\n")
  T.go(read_usb, fdout)
  return true
end

local found
usb.watch{
  idVendor = '16d0',
  idProduct = '0450',
  bcdDevice = '0100',

  connect = function (d)
    --eprintf("+ %s\n", tostring(d))
    if config.product and d.product ~= config.product then return end
    if config.serial and d.serial ~= config.serial then return end
    local ok, status = T.spcall(open_device, d)
    if not ok then
      eprintf("error: open_device: %s\n", status)
      os.exit(2)
    end
    if status then found = true end
  end,
  disconnect = function (d)
    --eprintf("- %s\n", tostring(d))
  end,
  coldplug_end = function (d)
    if not found then
      loop.write(fdout, "coldplug-end\n")
      --eprintf("coldplug end\n")
    end
  end,
}

loop.run()
