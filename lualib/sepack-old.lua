local usb = require'usb'
local D = require'util'
local Object = require'oo'
local T = require'thread'
local B = require'binary'
local bit = require'bit32'

local Sepack = Object:inherit{
  vendorID = '16d0',
  productID = '0450',
  version = '0100',

  verbose = false,
}

function Sepack.init (self, dev, verbose)
  self.dev = dev
  self.serial = dev.serial
  self.verbose = verbose
end

function Sepack.error_handler (msg, fatal, errno)
  if fatal then
    D.red(string.format('fatal usb error: %s', msg))()
    os.exit(5)
  end
end

function Sepack.open (self, errorh)
  self.errorh = errorh or self.error_handler
  self.buffers = {}
  self.mboxes = {}
  self.chnames = { [0] = 'control', control = 0 }
  --self.chtypes = {}
  local d = self.dev
  d:open ()
  assert(d:set_configuration(2))
  local intf = assert(d:find_interfaces{ bInterfaceClass = 'ff' }[1], 'vendor interface not found')
  assert(intf:open())
  self.pin  = assert(intf:get_endpoint('83'))
  self.pout = assert(intf:get_endpoint('03'))
  self:_start_reading ()
  local channels = string.split (self:setup ('control'), ' ')
  for i,name in ipairs (channels) do
    self.chnames[i - 1] = name self.chnames[name] = i - 1
    self:addbuffer (i - 1)
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
  return self.dev:close()
end

-- assumes only one pipe is read simultaneously
function Sepack._start_reading (self)
  local stop = false
  local callback, schedule_read
  function callback (data, msg, fatal, errno)
    if data then
      schedule_read ()
      self:_handle_usb_data (data)
    else
      if not fatal then
        if self.verbose > 1 then D.magenta("read error: " .. msg)(errno) end
        schedule_read ()
      else
        if self.verbose > 1 then D.red("fatal read error: " .. msg)(errno) end
        if self.errorh then self.errorh (msg, fatal, errno) end
      end
    end
  end
  function schedule_read ()
    if not stop then
      self.pin:read (4096, callback)
    end
  end
  schedule_read ()
  schedule_read ()
  self.cancel_reading = function ()
    stop = true
  end
end

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

function Sepack.addbuffer (self, chn)
  if type(chn) == 'string' then
    chn = self.chnames[chn] or error('unknwon channel: '..chn)
  end
  self.buffers[chn] = self.buffers[chn] or {}
end

function Sepack._bufferput (self, chn, data)
  local b = self.buffers[chn]
  b[#b+1] = data
end

function Sepack._bufferget (self, chn, data)
  local b = self.buffers[chn]
  if b and #b then
    b[#b+1] = data
    data = table.concat(b)
    self.buffers[chn] = {}
  end
  return data
end

function Sepack._handle_usb_data (self, p)
  if self.verbose > 2 then
    local repr
    if false and #p > 20 then
      repr = B.bin2hex(p:sub(1,20)) .. ' …'
    else
      repr = B.bin2hex(p)
    end
    D.cyan(string.format('<<[%d] %s', #p, repr))()
  end
  while true do
    local head = p:byte(1)
    local chno = bit.extract (head, 0, 4)
    local cont = bit.extract (head, 4) == 1
    local flags = bit.extract (head, 5, 3)
    local len = p:byte(2)
    local data = p:sub(3,3+len-1)
    if self.verbose > 1 then
      local chname = self.chnames[chno]
      D.green(string.format ('<%s:%s%x', chname or 'ch?', cont and "c" or "", flags))(D.hex(data))
    end
    local buffer = self.buffers[chno]
    if cont and buffer then
      self:_bufferput (chno, data)
    else
      local mbox = self:mbox (chno)
      local data = self:_bufferget (chno, data)
      mbox:put (data)
    end
    if (#p > 3+len) then
      -- handles several serial packets sent in one USB transaction
      p = p:sub (3+len)
    else
      return
    end
  end
end

function Sepack.write (self, chname, data, flags, cont)
  if type(data) == 'table' then data = B.flat (data) end
  if #data > 62 then
    self:write (chname, data:sub (1,62), flags, true)
    return self:write (chname, data:sub (63), flags)
  else
    flags = (flags or 0) * 2 + (cont and 1 or 0)
    if self.verbose > 1 then
      D.green(string.format ("%s:%s%x>", chname, cont and "c" or "", flags))(D.hex(data))
    end
    local chno = self.chnames[chname] or error('unknown channel: '..chname)
    local packet = string.char (chno + (flags * 16), #data) .. data
    if self.verbose > 2 then D.cyan(string.format('>>[%d]', #packet))(D.hex(packet)) end
    self.pout:write (packet, function (ok, err, fatal, errno) if not ok and fatal then D.red'usb write error:'(err, errno) end end)
  end
end

function Sepack.recv (self, chname)
  return self:mbox(chname):recv()
end

function Sepack.setup (self, chname, data)
  data = data or ''
  local chno = self.chnames[chname] or error('unknown channel: '..chname)
  return self:xchg ('control', string.char (chno) .. data)
end

function Sepack.xchg (self, chname, data, flags)
  self:write(chname, data, flags)
  return self:recv(chname)
end

function Sepack.setup_uart (self, chname, baud, bits, parity, stopbits)
  local chno = self.chnames[chname]
  bits = bits or 8
  parity = parity or 'N'
  stopbits = stopbits or 1
  self:xchg('control', {chno,B.enc32BE(baud),bits,parity,stopbits})
end

local function register (options)
  local o = options
  local p = o.prefix or ''
  local c = o.class or Sepack
  o.verbose = o.verbose or 0
  return usb.watch{
    idVendor = o.vendorID or c.vendorID,
    idProduct = o.productID or c.productID,
    bcdDevice = o.version or c.version,

    connect = function (d)
      local ch = '+'
      if o.product and d.product ~= o.product then ch = ':' end
      if o.serial  and d.serial  ~= o.serial  then ch = ':' end
      if o.verbose > 3 or (ch == '+' and o.verbose > 0) then D.blue(p..ch)(d) end
      if ch == '+' and o.connect then o.connect(c:new(d, o.verbose)) end
    end,
    disconnect = function (d)
      local ch = '-'
      if o.product and d.product ~= o.product then ch = ':' end
      if o.serial  and d.serial  ~= o.serial  then ch = ':' end
      if ch == '-' and o.disconnect then o.disconnect(d) end
      if o.verbose > 3 or (ch == '-' and o.verbose > 0) then D.blue(p..ch)(d) end
    end,
    coldplug_end = function ()
      if o.verbose > 1 then D.blue(p..'= coldplug ended')() end
      if o.coldplug_end then o.coldplug_end() end
    end,
  }
end

local function open (options)
  local o = options
  if not o.callback then error ("use must provide a callback to Sepack.open", 2) end
  local sepack
  local enumerator = register{
    class = o.class,
    verbose = o.verbose,
    serial = o.serial,
    product = o.product,
    prefix = o.prefix,
    connect = function (s)
      s:open (o.error_handler)
      sepack = s
      o.callback (s)
    end,
    disconnect = function (s)
      if s == sepack then
        os.exit(2)
      end
    end,
    coldplug_end = function ()
      local p
      if options.prefix then p = o.prefix .. ' ' else p = '' end
      local msg = "waiting for any device"
      if o.serial then msg = "waiting for device matching: " .. o.serial end
      if not sepack then D.blue(p..msg)() end
      if o.coldplug_end then o.coldplug_end () end
    end,
  }
  if not o.async then require'loop'.run() end
  return enumerator
end

return {
  Sepack = Sepack,
  register = register,
  open = open,
}
