local loop = require'loop'
local T = require'thread'
local udev = require'udev'
local _usb = require'_usb'
local D = require'util'

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

-- sets
local function set()
  local s = {}
  local n = 0
  return {
    add = function(_, v)
      if not s[v] then
        n = n + 1
        s[v] = true
      end
      return v
    end,
    remove = function(_, v)
      if s[v] then
        n = n - 1
        s[v] = nil
        return v
      end
    end,
    random = function(_, v)
      local i = math.random(n)
      local k
      for a=1,i do
        k = next(s, k)
      end
      return k
    end,
    list = function ()
      local c = {}
      for k,v in pairs(s) do c[#c+1] = k end
      return c
    end,
  }
end

-- helpers
local function fromhex(n)
  return n and tonumber(n, 16)
end

function usb.fmt_errno(errno)
  return string.format("%d", errno)
end


local ENODEV = 19
local EBUSY = 16

local function udev_id(udevh)
  return udevh:get_subsystem()..":"..udevh:get_sysname()
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

device.new = constructor(function (self, ctx, udevh)
  self.ctx = ctx
  self.udevh = udevh
  self.cont_errors = 0
  for i,k in ipairs(device._attrs) do
    self[k] = udevh:get_sysattr_value(k)
  end
  self.callbacks = {}
end)

function device:open()
  local fname = self.udevh:get_devnode()
  self.f = assert(io.open (fname, "r+"))
  self.wrwatch_stop = loop.on_writeable(self.f, function (loop, io, ev) self:_do_reap() end, true)
  return self
end

function device:set_configuration(cfgv)
  assert(self.f, "usb device not open")
  local ok, err, errno = _usb.set_configuration(self.f, cfgv)
  if errno == EBUSY then
    for _,intf in ipairs(self:find_interfaces()) do
      if intf:get_driver() then assert(intf:disconnect_kernel()) end
    end
  else
    return ok, err, errno
  end
  return _usb.set_configuration(self.f, cfgv)
end

function device:find_interfaces(filter)
  assert(self.f, "usb device not open")
  local intfs = {}
  local enum = self.ctx:enumerate()
  assert(enum:add_match_property("DEVTYPE", "usb_interface"))
  assert(enum:add_match_parent(self.udevh))
  if filter then
    for i,k in ipairs(interface._attrs) do
      if filter[k] then assert(enum:add_match_sysattr(k, filter[k])) end
    end
  end
  assert(enum:scan_devices())
  for i,path in ipairs(enum:get_list()) do
    intfs[#intfs+1] = interface:new(self.ctx, assert(self.ctx:device_from_syspath(path)), self)
  end
  return intfs
end

function device:close ()
  self.f:close()
  self.f = nil
end

function device.__tostring (s)
  return string.format("usb_device<%s / %s / %s @ %s %s>",
    s.manufacturer or '(null)', s.product or '(null)', s.serial or '(null)',
    udev_id(s.udevh), s.f and 'open' or 'closed')
end

function device:_handle_reap(token, ...)
  -- if not token or not (...) then D.red'reap err:'(token, ...) end
  if token then
    local cb = self.callbacks[token]
    self.callbacks[token] = nil
    local result, msg, fatal, errno = ...
    if not result then
      self.cont_errors = self.cont_errors + 1
      if self.cont_errors > 7 then
        fatal = true
      end
    else
      self.cont_errors = 0
    end
    return cb(result, msg, fatal, errno)
  else
    -- device disconnected?
    local msg, fatal, errno = ...
    if not errno then errno = fatal fatal = true end
    if errno ~= ENODEV then
      D.red'unexpected reap error:'(msg, fatal, errno)
    end
    self.wrwatch_stop()
    self.f:close()
    for token,cb in pairs(self.callbacks) do
      cb(nil, msg, fatal, errno)
    end
  end
end

function device:_do_reap ()
  return self:_handle_reap(_usb.reap_urb(self.f))
end

--
-- USB interface
--
interface._attrs = {
  'bInterfaceNumber',
  'bInterfaceClass',
  'bInterfaceSubClass', 
  'bInterfaceProtocol',
}

interface.new = constructor(function (self, ctx, udevh, dev)
  self.ctx = ctx
  self.dev = dev
  self.f = dev.f
  self.udevh = udevh
  for i, name in ipairs(interface._attrs) do
    self[name] = udevh:get_sysattr_value(name)
  end
  self.bNumEndpoints = tonumber(udevh:get_sysattr_value'bNumEndpoints')
  self.description = udevh:get_sysattr_value'interface'
end)

function interface:open()
  local ok, err, errno = _usb.claim_interface(self.f, self.bInterfaceNumber)
  if ok then self.isopen = true end
  return ok, err, errno
end

local function filter_endpoint(ep, filter)
  if not ep:get_sysattr_value'bEndpointAddress' then return end
  for i,v in ipairs(filter) do
    if type(v) == 'number' then
      if tonumber(ep:get_sysattr_value'bEndpointAddress', 16) ~= v then return end
    elseif v == 'in' or v == 'out' then
      if ep:get_sysattr_value'direction' ~= v then return end
    elseif v == "control" or v == 'isoc' or v == 'bulk' or v == 'interrupt' then
      if string.lower(ep:get_sysattr_value'type' or '') ~= v then return end
    else
      error("invalid pipe search term type: "..tostring(v))
    end
  end
  return true
end

function interface:find_endpoints (filter)
  local enum = assert(self.ctx:enumerate())
  assert(enum:add_match_parent(self.udevh))
  assert(enum:scan_devices())
  local r = {}
  for i,path in ipairs(enum:get_list()) do
    local d = assert(self.ctx:device_from_syspath(path))
    if filter_endpoint(d, filter) then
      r[#r+1] = endpoint:new(self.ctx, d, self)
    end
  end
  return r
end

function interface:get_endpoint (bEndpointNumber)
  local enum = assert(self.ctx:enumerate())
  assert(enum:add_match_parent(self.udevh))
  assert(enum:scan_devices())
  for i,path in ipairs(enum:get_list()) do
    local d = assert(self.ctx:device_from_syspath(path))
    if d:get_sysattr_value('bEndpointAddress') == bEndpointNumber then
      return endpoint:new(self.ctx, d, self)
    end
  end
  return nil, 'endpoint not found'
end

function interface:close()
  self.isopen = nil
  return _usb.release_interface(self.f, self.bInterfaceNumber)
end

function interface:get_driver()
  return _usb.get_driver(self.f, self.bInterfaceNumber)
end

function interface:connect_kernel()
  return _usb.connect_kernel(self.f, self.bInterfaceNumber)
end

function interface:disconnect_kernel()
  return _usb.disconnect_kernel(self.f, self.bInterfaceNumber)
end

function interface.__tostring(s)
  return string.format("usb_interface<%s / %s / %s:%s:%s / %s EPs @ %s %s>",
    s.description or '(no description)',
    s.bInterfaceNumber, s.bInterfaceClass, s.bInterfaceSubClass, s.bInterfaceProtocol,
    s.bNumEndpoints, udev_id(s.udevh), s.isopen and 'open' or 'closed')
end

--
-- USB endpoint
--
endpoint.new = constructor(function (self, ctx, udevh, intf)
  self.ctx = ctx
  self.intf = intf
  self.dev = intf.dev
  self.f = intf.f
  self.udevh = udevh
  self.bEndpointAddress = udevh:get_sysattr_value'bEndpointAddress'
  self.type = udevh:get_sysattr_value'type'
  self.direction = udevh:get_sysattr_value'direction'
  assert(_usb.clear_halt(self.f, fromhex(self.bEndpointAddress)))
  assert(_usb.reset_ep(self.f, fromhex(self.bEndpointAddress)))
end)

function endpoint:write(data, callback)
  local token, err, errno = _usb.bulk_write(self.f, fromhex(self.bEndpointAddress), data) -- 0x03
  if not token then
    return callback(nil, err, true, errno)
  end
  self.dev.callbacks[token] = callback
end

function endpoint:read(n, callback)
  local token, err, errno = _usb.bulk_read(self.f, fromhex(self.bEndpointAddress), n) -- 0x83
  if not token then
    return callback(nil, err, true, errno)
  end
  self.dev.callbacks[token] = callback
end

function endpoint.__tostring(s)
  return string.format("usb_ep<%s %s 0x%s>",
    s.type or 'type?', s.direction or 'direction?', s.bEndpointAddress or '??')
end

--
-- USB API
--
local all_watchers = set()
usb.all_watchers = all_watchers

local dev_filters = { 'idVendor', 'idProduct', 'bcdDevice' }

local monitor = O()

monitor.new = constructor(function (self, ctx)
  self.inner = ctx:monitor("kernel")
  assert(self.inner:filter_add_match_subsystem_devtype("usb", "usb_device"))
  assert(self.inner:enable_receiving())
end)

function monitor:enable(add, remove)
  local function read_dev(loop, watcher, ev)
    local d = self.inner:receive_device()
    if not d then return end
    local action = d:get_action()
    local path = d:get_syspath()
    if action == 'add' then
      add(d, path)
    elseif action == 'remove' then
      remove(d, path)
    else
      error(string.format('unknown udev action: %s for device: %s', action, udev_id(d)))
    end
  end
  self.cancel_watcher = loop.on_readable(self.inner, read_dev, true)
end

function monitor:disable()
  if self.cancel_watcher then
    self.cancel_watcher()
    self.cancel_watcher = nil
  end
end

local function enumerate(ctx, o, callback)
  local enum = ctx:enumerate()
  assert(enum:add_match_subsystem("usb"))
  assert(enum:add_match_property("DEVTYPE", "usb_device"))
  for i,k in ipairs(dev_filters) do
    if o[k] then
      assert(enum:add_match_sysattr(k, o[k]))
    end
  end
  assert(enum:scan_devices())
  local list = enum:get_list()
  for i,path in ipairs (list) do
    local d = ctx:device_from_syspath(path)
    callback(d, path)
  end
end

function usb.watch(o)
  assert(o.connect, "connect callback required")
  local agent = T.agent()
  local ctx = udev.context()
  local devices = {}
  
  local watcher = all_watchers:add({
    agent = agent,
    udevctx = ctx,
    devices = devices,
  })

  local monitor = monitor:new(ctx)
  enumerate(ctx, o, function(ud, path)
    local d = device:new(ctx, ud)
    devices[path] = d
    agent(o.connect, d)
  end)
  if o.coldplug_end then agent(o.coldplug_end) end
  local function adddev(ud, path)
    if devices[path] then return end
    for i,k in ipairs(dev_filters) do
      if o[k] and ud:get_sysattr_value(k) ~= o[k] then return end
    end
    local d = device:new(ctx, ud)
    devices[path] = d
    agent(function ()
      -- workaround a possible race with kernel drivers
      -- otherwise we may succeed with set_configuration and even claim_interface
      -- but the device may still be snatched away from us and reconfigured by the kernel driver
      T.sleep(.5)
      o.connect(d)
    end)
  end
  local function remdev(ud, path)
    local d = devices[path]
    if not d then return end
    if o.disconnect then agent(o.disconnect, d) end
    devices[path] = nil
  end
  monitor:enable(adddev, remdev)
  return { disable = function () monitor:disable() all_watchers:remove(watcher) end }
end

return usb
