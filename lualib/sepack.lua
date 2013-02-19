local D = require'util'
local O = require'o'
local T = require'thread'
local B = require'binary'
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
  if string.byte(data, 1) == 0 then
    return error(string.sub(data, 2))
  end
  return string.sub(data, 2)
end



-- main class:
local Sepack = O()

Sepack.new = O.constructor(function (self, ext, log)
  self.verbose = 2
  self.log = log
  self.ext = ext
  self.statbox = T.Mailbox:new()
  self.channels = {}

  T.go(self._stat_loop, self)
  T.go(self._in_loop, self)
end)

function Sepack:_enumerate()
  self:_addchn(0, 'control')
  for i, name in ipairs(self.channels.control.channel_names) do
    self:_addchn(i, name)
  end
  if self.verbose > 0 then D.green'÷ ready'() end
  self.statbox:put('ready')
end

function Sepack:_addchn(id, name)
  local old = self.channels[id]
  if old then
    if old.name ~= name then
      error(string.format("channel change after reconnecting: %s -> %s", old.name, name), 0)
    end
    return
  end
  if self.channels[name] and self.channels[name].id ~= id then
    error(string.format("duplicate channel name: %s [no. %d and %d]", name, self.channels[name].id, id), 0)
  end
  local CT = self.channeltypes._default
  for k, v in pairs(self.channeltypes) do
    if string.startswith(name, k) then CT = v break end
  end
  local chn = CT:new(self, id, name)
  self.channels[name] = chn
  self.channels[id] = chn
  chn:init()
end

function Sepack:chn(name)
  local chn = self.channels[name]
  if not chn then return error('unknown channel: '..name, 0) end
  return chn
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
end)

function CT._default:_decode(data)
  return data
end

function CT._default:_push_rx(data, flags, final)
  local b = self.buffer
  if b == false then
    self.inbox:put(self:_decode(data))
  else
    if b == nil then b = {} self.buffer = b end
    table.insert(b, data)
    if final then
      data = table.concat(b)
      for i=1,#b do b[i] = nil end
      self.inbox:put(self:_decode(data))
    end
  end
end

function CT._default:init()
end

function CT._default:write(data, flags)
  flags = flags or NO_REPLY_FLAG
  if type(data) == 'table' then data = B.flat(data) end
  self.sepack:write(self, data, flags)
end

function CT._default:setup(data)
  return self.sepack:setup(self, data)
end

function CT._default:xchg(data)
  self:write(data, 0)
  local r = self:recv()
  return r
end

function CT._default:recv()
  return self.inbox:recv()
end

function CT._default:__tostring()
  return string.format("<%d:%s>", self.id, self.name)
end



CT.control = O(CT._default)

function CT.control:init()
  local names = self.sepack:setup(self)
  names = string.split(names, ' ')
  table.remove(names, 1) -- drop 'control'
  self.channel_names = names
end

CT.control.__tostring = CT._default.__tostring



CT.uart = O(CT._default)

function CT.uart:setup(baud, bits, parity, stopbits)
  bits = bits or 8
  parity = parity or 'N'
  stopbits = stopbits or 1
  return checkerr(self.sepack:setup(self, B.flat{'s', B.enc32BE(baud), bits, parity, stopbits}))
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
    return self.sepack:setup(self, B.flat{t, B.enc16BE(ms * 10)})
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

  function chainer:_getpin(name)
    local pin = self.gpio.pins[name]
    if type(pin) ~= 'number' then error('unknown gpio pin: '..name) end
    return string.char(pin)
  end

  function chainer:setup(name, mode, ...)
    local pin = self:_getpin(name)
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
    return self:setup(name, 'out', 'pull-none')
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
    self:push('r', self:_getpin(name))
    return self
  end

  function chainer:write(name, v)
    local cmd
    if v then cmd = '1' else cmd = '0' end
    self:push(cmd, self:_getpin(name))
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
    if #reply > 0 then
      local t = {}
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
      return t
    end
  end

  CT.gpio._chainer = chainer
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

function CT.gpio:seq()
  return self._chainer:new(self)
end

CT.gpio.__tostring = CT._default.__tostring


CT.notify = O(CT._default)

function CT.notify:init()
  local pins = self.sepack:setup(self):split(' ')
  result = {}
  for i, pin in ipairs(pins) do
    local names, modes = pin:splitv(':')
    names = names:split('/')
    result[i-1] = names[1]
    for _, name in ipairs(names) do result[name] = i-1 end
  end
  self.pins = result
  return result
end

function CT.notify:_getpin(name)
  local pin = self.pins[name]
  if type(pin) ~= 'number' then error('unknown notify pin: '..name) end
  return string.char(pin)
end

function CT.notify:setdebounce(name, ms)
  local pin = self:_getpin(name)
  self.sepack:setup(self, 't'..pin..B.enc16BE(ms))
end

CT.notify.__tostring = CT._default.__tostring

CT.adc = O(CT._default)

function CT.adc:start(fs, samples)
  local reply = checkerr(self.sepack:setup(self, B.enc32BE(fs)..B.enc32BE(samples)))
  return B.dec32BE(reply) / 256
end

function CT.adc:_decode(data)
  local r = {}
  assert(#data % 2, "invalid ADC data length")
  for i=1,#data,2 do
    local v = B.dec16BE(data, i)
    r[#r+1] = v
  end
  return r
end

CT.adc.__tostring = CT._default.__tostring



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
      if self.verbose > 2 then D.cyan(string.format('<<[%d]', #p))(hex_trunc(p, 20)) end
      while #p > 0 do
        local id, data, flags, final, rest = parse_packet(p)
        local channel = self.channels[id]
        if self.verbose > 1 or not channel then D.green(string.format('<%s%s:%x', channel and channel.name or 'ch?', final and "" or "+", flags))(D.hex(data)) end
        if channel then
          channel.bytes_received = (channel.bytes_received or 0) + #data
          channel:_push_rx(data, flags, final)
        end
        p = rest
      end
    end
  end
end

function Sepack:_stat_loop()
  while true do
    local status = self.ext.statbox:recv()
    if status == 'connect' then
      self:_enumerate()
    else
      self.statbox:put(status)
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
    if self.verbose > 1 then D.green(string.format ("%s:%x>", channel.name, flags or 0))(D.hex(data)) end
    while #data > 0 do
      local final = #data <= 62
      local p = format_packet(channel.id, data, flags, final)
      if self.verbose > 2 then D.cyan(string.format('>>[%d]', #p))(hex_trunc(p, 20)) end
      self.ext.outbox:put(p)
      data = data:sub(63)
    end
  end
end

function Sepack:setup (channel, data)
  data = data or ''
  return self:chn'control':xchg(string.char(channel.id)..data)
end

return Sepack
