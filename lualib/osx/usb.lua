  local loop = require'cfloop'
local D = require'util'
local T = require'thread'
local Object = require'oo'
local _usb = require'_usb'

local usb = {
  _usb = _usb,
}


-- oo
local function O(attrs)
  local o = {}
  o.__index = o
  return o
end

local function constructor(init)
  init = init or function () end
  return function (base, ...)
    local o = setmetatable({}, base)
    init(o, ...)
    return o
  end
end

local function rebind(sub, method)
  return function(self, ...)
    local sub = self[sub]
    return sub[method](sub, ...)
  end
end


-- helpers
local function fromhex(n)
  return n and tonumber(n, 16)
end

function usb.fmt_errno(errno)
  return string.format("0x%08x", errno)
end

local device = O()
usb.device = device
local interface = O()
usb.interface = interface
local endpoint = O()
usb.endpoint = endpoint

--
-- USB device
--
device._attrs = {
  'idVendor',
  'idProduct',
  'bcdDevice',
  'manufacturer',
  'product',
  'serial',
}

device.new = constructor(function (self, dev)
  self.dev = dev
  for _,k in ipairs(device._attrs) do
    self[k] = dev[k]
  end
end)

device.open = rebind('dev', 'open')
device.reset = rebind('dev', 'reset')
device.reenumerate = rebind('dev', 'reenumerate')

function device:set_configuration (cfgv)
  return T.spcall(self.dev.set_configuration, self.dev, cfgv)
end

function device:find_interfaces(filter)
  if filter then
    filter.bInterfaceClass = fromhex(filter.bInterfaceClass)
    filter.bInterfaceSubClass = fromhex(filter.bInterfaceSubClass)
    filter.bInterfaceProtocol = fromhex(filter.bInterfaceProtocol)
    filter.bAlternateSetting = fromhex(filter.bAlternateSetting)
  end
  local intfs = self.dev:list_interfaces(filter)
  for i=1,#intfs do
    intfs[i] = interface:new(intfs[i])
  end
  return intfs
end

device.close = rebind('dev', 'close')
device.__tostring = rebind('dev', '__tostring')
--function device:__tostring ()
--  return tostring(self.dev)
--end

--
-- USB interface
--
interface = O()
usb.interface = interface

interface.new = constructor(function (self, intf)
  self.intf = intf
end)

interface.open = rebind('intf', 'open')

function interface:find_endpoints (filter)
  local pipes = self.intf:find_pipes(filter)
  for i=1,#pipes do
    pipes[i] = endpoint:new(pipes[i])
  end
  return pipes
end

function interface:get_endpoint(bEndpointNumber)
  local ep = self.intf:get_pipe(fromhex(bEndpointNumber))
  if not ep then return nil, 'endpoint not found' end
  return endpoint:new(ep)
end

interface.close = rebind('intf', 'close')
interface.__tostring = rebind('intf', '__tostring')

--
-- USB endpoint
--
endpoint = O()
usb.endpoint = endpoint

endpoint.new = constructor(function (self, ep)
  self.ep = ep
  ep:reset()
end)

function endpoint:write (data, callback)
  local ok, err, fatal, errno
  for i=1,5 do
    ok, err, fatal, errno = self.ep:write(data)
    if not ok then
      local ok, err2 = T.spcall(self.ep.reset, self.ep)
      if not ok then
        return callback(nil, err, true, errno)
      end
    else
      return callback(true)
    end
  end
  return callback(nil, err, true, errno)
end

function endpoint:read (n, callback)
  local ok, err, fatal, errno = self.ep:read(n, callback)
  if not ok then
    local ok, err2 = T.spcall(self.ep.reset, self.ep)
    if not ok then
      return callback(nil, err, fatal, errno)
    else
      return callback(nil, err, true, errno)
    end
  end
end

--
-- USB API
--
function usb.watch(o)
  assert(o.connect, "connect callback required")
  local cbagent = T.agent()
  local devs = {}
  _usb.watch_usb{
    idVendor = fromhex(o.idVendor),
    idProduct = fromhex(o.idProduct),
    bcdDevice = fromhex(o.bcdDevice),

    connect = function (d)
      local newd = usb.device:new (d)
      devs[d] = newd
      cbagent(o.connect, newd)
    end,
    disconnect = function (d)
      local newd = devs[d]
      if not newd then return end
      if o.disconnect then cbagent(o.disconnect, newd) end
      devs[d] = nil
    end,
    coldplug_end = function ()
      if o.coldplug_end then cbagent(o.coldplug_end) end
    end,
  }
end

return usb
