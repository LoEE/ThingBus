local D = require'util'
local O = require'o'
local T = require'thread'
local B = require'binary'
local o = require'kvo'
local bit = require'bit32'


-- all flags are >> 1 compared to sepack-lpc1342 C code
local NO_REPLY_FLAG = 0x01


-- misc:
local function hex_trunc (data, maxlen)
  if #data > maxlen then
    return D.unq(B.bin2hex(data:sub(1,maxlen))..'…')
  else
    return D.unq(B.bin2hex(data))
  end
end

local function checkerr(data)
  if #data == 0 then return nil, "timeout" end
  if string.byte(data, 1) == 0 then
    error(string.sub(data, 2))
  end
  return string.sub(data, 2)
end


-- main class:
local Sepack = O()

Sepack.new = O.constructor(function (self, ext, _log)
  self.verbose = 2
  self.log = _log or log.null
  self.ext = ext
  self.connected = o()
  self.channels = {}

  self.ext.status:watch(function (...) self:_ext_status(...) end)
  T.go(self._in_loop, self)
end)

function Sepack:mixinChannelTypes(channeltypes)
  local class = O(Sepack)
  class.channeltypes = channeltypes
  return class
end

function Sepack:_ext_status(status)
  if status == 'connect' then
    T.go(self._enumerate, self)
  elseif status == true then
  elseif status == 'coldplug end' then
    self.connected(false)
  else
    if self.verbose > 2 then self.log:green('÷ status:', status, self.connected()) end
    if status == false and self.connected() then self:on_disconnect() end
    self.connected(false)
  end
end

function Sepack:_enumerate()
  self:_addchn(0, 'control', 'force-init')
  for i, name in ipairs(self.channels.control.channel_names) do
    self:_addchn(i, name)
  end
  if self.verbose > 0 then self.log:green'÷ ready' end
  self.connected(true)
end

function Sepack:on_disconnect()
  local chns = self.channels
  for i=0,#chns do
    chns[i]:on_disconnect()
  end
end

function Sepack:_parsechnname(str)
  local type, name = string.match(str, "([^:]*):(.*)")
  if not type then return str, str end
  return type, name
end

function Sepack:_addchn(id, name, forceinit)
  local type, name = self:_parsechnname(name)
  local chn = self.channels[id]
  if chn then
    if chn.name ~= name then
      error(string.format("channel change after reconnecting: %s -> %s", chn.name, name), 0)
    end
    chn:on_connect()
  else
    if self.channels[name] and self.channels[name].id ~= id then
      error(string.format("duplicate channel name: %s [no. %d and %d]", name, self.channels[name].id, id), 0)
    end
    local CT = self.channeltypes._default
    for k, v in pairs(self.channeltypes) do
      if string.startswith(type, k) then CT = v break end
    end
    chn = CT:new(self, id, name)
    self.channels[name] = chn
    self.channels[id] = chn
    forceinit = true
  end
  chn:on_connect()
  if forceinit then
    chn:init()
  end
end

function Sepack:chn(name)
  local chn = self.channels[name]
  if not chn then return error('unknown channel: '..name, 0) end
  return chn
end

do
  local function parse_packet(p)
    local head = p:byte(1)
    local id = bit.extract (head, 0, 4)
    local final = bit.extract (head, 4) == 0
    local flags = bit.extract (head, 5, 3)
    local len = p:byte(2)
    local data = p:sub(3, 3+len-1)
    return id, data, flags, final, p:sub(3+len)
  end

  function Sepack:_in_loop ()
    while true do
      local p = self.ext.inbox:recv()
      if self.verbose > 2 then self.log:cyan(string.format('<<[%d]', #p), hex_trunc(p, 20)) end
      while #p > 0 do
        local id, data, flags, final, rest = parse_packet(p)
        local channel = self.channels[id]
        if self.verbose > 1 or not channel then self.log:green(string.format('<%s%s:%x', channel and channel.name or 'ch?', final and "" or "+", flags), D.hex(data)) end
        if channel then
          channel.bytes_received = (channel.bytes_received or 0) + #data
          channel:_handle_rx(data, flags, final)
        end
        p = rest
      end
    end
  end
end

do
  local function format_packet(id, data, flags, final)
    flags = (flags or 0) * 2
    if not final then flags = flags + 1 end
    return string.char(id + (flags * 16), #data)..data
  end

  function Sepack:write (channel, data, flags)
    if self.verbose > 1 then self.log:green(string.format ("%s:%x>", channel.name, flags or 0), D.hex(data)) end
    local pkgs = {}
    while #data > 0 do
      local final = #data <= 62
      local p = format_packet(channel.id, data:sub(1,62), flags, final)
      pkgs[#pkgs+1] = p
      data = data:sub(63)
    end
    local out = table.concat(pkgs)
    if self.verbose > 2 then self.log:cyan(string.format('>>[%d]', #out), hex_trunc(out, 20)) end
    self.ext.outbox:put(out)
  end
end

function Sepack:setup (channel, data)
  data = data or ''
  return self:chn'control':xchg(string.char(channel.id)..data)
end



local CT = {}
Sepack.channeltypes = CT



CT._default = O()

CT._default.new = O.constructor(function (self, sepack, id, name)
  self.sepack = sepack
  self.id = id
  self.name = name
  self.inbox = T.Mailbox:new()
  self.buffer = {}
  self.busy = false
  self.connected = o(false)
end)

function CT._default:_decode(data)
  return data
end

function CT._default:_inbox_put(data)
  self.inbox:put(data)
end

function CT._default:_handle_rx(data, flags, final)
  local b = self.buffer
  local r
  if b == false then
    r = data
  else
    if b == nil then b = {} self.buffer = b end
    table.insert(b, data)
    if final then
      data = table.concat(b)
      for i=1,#b do b[i] = nil end
      r = data
    end
  end
  if r then self:_inbox_put(self:_decode(r)) end
end

function CT._default:init()
end

function CT._default:write(data, flags)
  flags = flags or NO_REPLY_FLAG
  if type(data) == 'table' then data = B.flat(data) end
  self.sepack:write(self, data, flags)
end

function CT._default:setup(data)
  return checkerr(self.sepack:setup(self, data))
end

function CT._default:on_connect()
  self.connected(true)
end

function CT._default:on_disconnect()
  self.connected(false)
  if self.busy then self.inbox:put("") end
end

function CT._default:xchg(data)
  if not self.connected() then return "" end
  self:write(data, 0)
  local r = self:recv()
  return r
end

function CT._default:recv()
  if self.busy then error("multiple recvs detected on channel: "..self.name, 1) end
  self.busy = true
  return (function (...)
    self.busy = false
    return ...
  end)(self.inbox:recv())
end

function CT._default:__tostring()
  return string.format("<%d:%s>", self.id, self.name)
end



CT.control = O(CT._default)

function CT.control:init()
  self.inbox = nil -- only xchg should be used
  local names = self.sepack:setup(self)
  names = string.split(names, ' ')
  table.remove(names, 1) -- drop 'control'
  self.channel_names = names
end

function CT.control:_inbox_put(data)
  local chn = table.remove(self.reply_chns, 1)
  chn:put(data)
end

function CT.control:on_connect()
  self.reply_chns = {}
end

function CT.control:on_disconnect()
  local rc = self.reply_chns
  self.reply_chns = nil
  for i=1,#rc do rc[i]:put("") end
end

function CT.control:recv()
  error("only use xchg on the control channel")
end

function CT.control:xchg(data)
  local chn = T.Mailbox:new()
  local rc = self.reply_chns
  if not rc then return "" end
  rc[#rc+1] = chn
  self:write(data, 0)
  return chn:recv()
end

CT.control.__tostring = CT._default.__tostring



CT.uart = O(CT._default)

function CT.uart:init()
  self.last_timeouts = {}
  self.last_flags = {}
end

function CT.uart:setup(baud, bits, parity, stopbits)
  self.baud = baud
  self.bits = bits or 8
  self.parity = parity or 'N'
  self.stopbits = stopbits or 1
  self.last_setup = B.flat{'s', B.enc32BE(self.baud), self.bits, self.parity, self.stopbits}
  checkerr(self.sepack:setup(self, self.last_setup))
end

function CT.uart:on_connect()
  CT._default.on_connect(self)
  if self.last_setup then checkerr(self.sepack:setup(self, self.last_setup)) end
  if self.last_timeouts then
    for type,ms in pairs(self.last_timeouts) do
      self:settimeout(type, ms)
    end
  end
  if self.last_flags then
    for type,on in pairs(self.last_flags) do
      self:setflag(type, on)
    end
  end
end

do
  local timeouts = {
    rx = 'i',
    tx = 'o',
    reply = 'r',
  }
  function CT.uart:settimeout(type, ms)
    local t = timeouts[type]
    if not t then error('invalid timeout type: '..type) end
    self.last_timeouts[type] = ms
    checkerr(self.sepack:setup(self, B.flat{t, B.enc16BE(ms * 10)}))
  end
end

do
  local flags = {
    ext = 'x',
    cts = 'c',
  }
  function CT.uart:setflag(type, on)
    local t = flags[type]
    if not t then error('invalid flag: '..type) end
    self.last_flags[type] = on
    checkerr(self.sepack:setup(self, B.flat{t, on}))
  end
end

CT.uart.__tostring = CT._default.__tostring



CT.gpio = O(CT._default)

do
  local chainer = O()

  chainer.new = O.constructor(function (self, gpio)
    self.gpio = gpio
    self._pull = 'up'
    self._hyst = true
    self.cmds = {}
    self.rets = {}
  end)

  function chainer:push(...)
    for i=1,select('#', ...) do
      local v = select(i, ...)
      assert(type(v) == 'string')
      self.cmds[#self.cmds+1] = v
    end
  end

  local _pullmap = { up = 'u', down = 'd', repeater = 'r', none = 'z' }
  function chainer:_setpull(pull)
    if pull ~= self._pull then
      local v = _pullmap[pull]
      if not v then error('invalid PULL option: '..pull) end
      self:push('S', v)
      self._pull = pull
    end
  end

  function chainer:_sethyst(hyst)
    if hyst ~= self._hyst then
      local v
      if hyst then v = 'h' else v = 'l' end
      self:push('S', v)
      self._hyst = hyst
    end
  end

  function chainer:setup(name, mode, ...)
    local pin = self.gpio:_getpin(name)
    local pull = 'up'
    local hyst = true
    for i=1,select('#', ...) do
      local v = select(i, ...)
      assert(type(v) == 'string', 'gpio setup option is not a string')
      if v:startswith('pull-') then
        pull = v:sub(6)
      elseif v == 'no-hystheresis' then
        hyst = false
      else
        error('unknown gpio setup option: '..v)
      end
    end
    self:_setpull(pull) self:_sethyst(hyst)
    local cmd
    if mode == 'in' then
      cmd = 'I'
    elseif mode == 'out' then
      cmd = 'O'
    elseif mode == 'peripheral' then
      cmd = 'P'
    else
      error('invalid gpio mode: '..mode)
    end
    self:push(cmd, pin)
    return self
  end

  function chainer:output(name)
    return self:setup(name, 'out', 'pull-none', 'no-hystheresis')
  end

  function chainer:input(name, ...)
    return self:setup(name, 'in', ...)
  end

  function chainer:peripheral(name, ...)
    return self:setup(name, 'peripheral', ...)
  end

  function chainer:float(name)
    return self:setup(name, 'in', 'pull-none')
  end

  function chainer:delay(ms)
    self:push('d', B.enc16BE(ms - 1))
    return self
  end

  function chainer:read(name, key)
    if not key then key = name end
    self.rets[#self.rets+1] = key
    self:push('r', self.gpio:_getpin(name))
    return self
  end

  function chainer:write(name, v)
    local cmd
    if v then cmd = '1' else cmd = '0' end
    self:push(cmd, self.gpio:_getpin(name))
    return self
  end

  function chainer:hi(name)
    return self:write(name, true)
  end

  function chainer:lo(name)
    return self:write(name, false)
  end

  function chainer:run()
    local reply = self.gpio:xchg(self.cmds)
    local t = {}
    if #reply > 0 then
      local i = 1
      local o = 1
      while i < #reply do
        if reply:sub(i,i) == 'r' then
          if not self.rets[o] then error('unexpected reply byte @ '..i) end
          t[self.rets[o]] = reply:byte(i+1,i+1)
          i = i + 2
          o = o + 1
        else
          error('invalid reply byte @ '..i)
        end
      end
    end
    return t
  end

  CT.gpio._chainer = chainer
end

do
  local pin = O()

  pin.new = O.constructor(function (self, gpio, name)
    self.gpio = gpio
    self.name = name
  end)

  function pin:read()
    return self.gpio:seq():read(self.name):run()[self.name]
  end

  for _,method in ipairs{'setup', 'output', 'input', 'float', 'peripheral',
                         'write', 'hi', 'lo', } do
    pin[method] = function (self, ...)
      local seq = self.gpio:seq()
      seq[method](seq, self.name, ...)
      return seq:run()
    end
  end
  CT.gpio._pin = pin
end

function CT.gpio:init()
  local pins = self.sepack:setup(self):split(' ')
  result = {}
  for i, pin in ipairs(pins) do
    local names, modes = pin:splitv(':')
    names = names:split('/')
    local name
    if not modes:find('p') then name = names[1] else name = names[2] end
    result[i-1] = { name = name, modes = modes, }
    for _, name in ipairs(names) do result[name] = i-1 end
  end
  self.pins = result
  return result
end

function CT.gpio:alias(old, new)
  self:_getpin(old)
  assert(not self.pins[new], "gpio pin name in use")
  self.pins[new] = self.pins[old]
end

function CT.gpio:_getpin(name)
  local pin = self.pins[name]
  if type(pin) ~= 'number' then error('unknown gpio pin: '..name) end
  return string.char(pin)
end

function CT.gpio:seq()
  return self._chainer:new(self)
end

function CT.gpio:pin(name)
  self:_getpin(name)
  return self._pin:new(self, name)
end

CT.gpio.__tostring = CT._default.__tostring



CT.notify = O(CT._default)

function CT.notify:init()
  self.pins = {}
  local pins = self.sepack:setup(self):split(' ')
  result = {}
  for i, pin in ipairs(pins) do
    local names, modes = pin:splitv(':')
    names = names:split('/')
    local name = names[1]
    result[i-1] = name
    self.pins[name] = o()
    self.pins['n'..name] = o()
    for _, alias in ipairs(names) do result[alias] = i-1 end
  end
  self._pins = result
  self.debouncetimes = {}
  self:write'r'
end

function CT.notify:_decode(data)
  if data:startswith('n') or data:startswith('r') then
    local changes = {}
    for i=2,#data,2 do
      local i, v = string.byte(data, i, i+1)
      local name = self._pins[i]
      v = v == 1
      changes[name] = v
    end
    return changes
  else
    return data
  end
end

function CT.notify:_inbox_put(changes)
  if type(changes) ~= 'table' then error('malformed packet: '..D.repr(changes)) end
  for name, v in pairs(changes) do
    self.pins[name](v)
    self.pins['n'..name](not v)
  end
end

function CT.notify:on_connect()
  CT._default.on_connect(self)
  if self.debouncetimes then
    for name, ms in pairs(self.debouncetimes) do
      self:setdebounce(name, ms)
    end
    self:write'r'
  end
end

function CT.notify:_getpin(name)
  local pin = self._pins[name]
  if type(pin) ~= 'number' then error('unknown notify pin: '..name) end
  return string.char(pin)
end

function CT.notify:setdebounce(name, ms)
  local pin = self:_getpin(name)
  checkerr(self.sepack:setup(self, 't'..pin..B.enc16BE(ms)))
  self.debouncetimes[name] = ms
end

CT.notify.__tostring = CT._default.__tostring



CT.adc = O(CT._default)

function CT.adc:start(fs)
  local reply = checkerr(self.sepack:setup(self, B.enc32BE(fs)))
  if reply then
    return B.dec32BE(reply) / 256
  else
    return nil, "timeout"
  end
end

function CT.adc:stop()
  checkerr(self.sepack:setup(self, B.enc32BE(0)))
end

function CT.adc:_decode(data)
  local r = {}
  assert(#data % 2, "invalid ADC data length")
  for i=1,#data,2 do
    local v = B.dec16BE(data, i)
    if v > 32767 then v = v - 65536 end
    r[#r+1] = v
  end
  return r
end

CT.adc.__tostring = CT._default.__tostring


CT.spi = O(CT._default)

function CT.spi:setup_master(clk, bits, cpol, cpha)
  self.clk = clk
  self.bits = bits or 8
  self.cpol = cpol or 1
  self.cpha = cpha or 1
  local new = B.flat{'M', self.bits, self.cpol, self.cpha, B.enc32BE(self.clk)}
  if new ~= self.last_setup then
    self.last_setup = new
    local reply = checkerr(self.sepack:setup(self, self.last_setup))
    if reply then
      return B.dec32BE(reply)
    else
      return nil, "timeout"
    end
  end
end

function CT.spi:setup_slave(bits, cpol, cpha)
  self.bits = bits or 8
  self.cpol = cpol or 1
  self.cpha = cpha or 1
  local new = B.flat{'S', self.bits, self.cpol, self.cpha}
  if new ~= self.last_setup then
    self.last_setup = new
    return checkerr(self.sepack:setup(self, self.last_setup))
  end
end

function CT.spi:on_connect()
  CT._default.on_connect(self)
  if self.last_setup then checkerr(self.sepack:setup(self, self.last_setup)) end
end


CT.spi.__tostring = CT._default.__tostring



CT.watchdog = O(CT._default)

function CT.watchdog:query()
  local reply = self:setup('?')
  if not reply then return nil, "timeout" end
  local _, time_left = B.unpack(reply, ">s4")
  local mode
  if time_left < 0 then
    mode = "reset"
    time_left = -time_left
  else
    mode = "countdown"
  end
  return mode, time_left
end

function CT.watchdog:reset_status()
  local reply = self:setup('R')
  if not reply then return nil, "timeout" end
  local _, status = B.unpack(reply, ">s4")
  local b = B.unpackbits(status, 'soft bod wdt ext por')
  for k,v in pairs(b) do if not v then b[k] = nil end end
  return b
end

function CT.watchdog:settimer(val)
  return self:setup('='..B.enc32BE(val))
end

function CT.watchdog:feed()
  self:write('0')
end

CT.watchdog.__tostring = CT._default.__tostring



CT.phy = O(CT._default)

CT.phy.PHYS = { [0] = "none", "rs485ch1", "rs485ch2", "rs232ch1", "rs232ch2", "mdb" }
for k,v in pairs(CT.phy.PHYS) do CT.phy.PHYS[v] = k end

function CT.phy:init()
  self.assignments = {}
end

function CT.phy:setup(uart, phy)
  checks('table', 'number', 'string')
  if uart < 0 or uart > 2 then error('invalid UART id: '..tostring(uart)) end
  local phyid = self.PHYS[phy]
  if not phyid then error('invalid PHY: '..phy) end
  self.assignments[uart] = phy
  self:write(string.char(uart, phyid))
end

function CT.phy:on_connect()
  CT._default.on_connect(self)
  if self.assignments then
    for k,v in pairs(self.assignments) do
      self:setup(k, v)
    end
  end
end

CT.phy.__tostring = CT._default.__tostring



return Sepack
