local udev = require'udev'
local usb = require'usb'
local Object = require'oo'
local D = require'util'

local endpoint = Object:inherit{
}

function endpoint.init (self, ctx, udevh, intf)
  self.ctx = ctx
  self.intf = intf
  self.f = intf.f
  self.udevh = udevh
  self.bEndpointAddress = udevh:get_sysattr_value'bEndpointAddress'
end

local interface = Object:inherit{
}

function interface.init (self, ctx, udevh, dev)
  self.ctx = ctx
  self.dev = dev
  self.f = dev.f
  self.udevh = udevh
  self.bInterfaceNumber = udevh:get_sysattr_value'bInterfaceNumber'
end

function interface.open (self)
  usb.claim_interface (self.f, self.bInterfaceNumber)
  local eps = {}
  local enum = self.ctx:enumerate()
  assert(enum:add_match_parent (self.udevh))
  assert(enum:scan_devices())
  for i,path in ipairs(enum:get_list()) do
    local d = self.ctx:device_from_syspath (path)
    if d:get_sysattr_value ('bEndpointNumber') then
      eps[#eps+1] = endpoint:new(self.ctx, d, self)
    end
  end
  self.endpoints = eps
end

function interface.close (self)
  usb.release_interface (self.f, self.bInterfaceNumber)
end

function interface.get_pipe (self, epnum, dir)
  -- FIXME
end

function interface.__tostring (self)
  local d = self.udevh
  local state
  if self.isopen then state = 'open' else state = 'closed' end
  local function a(key) return d:get_sysattr_value(key) or ('unknown-' .. key) end
  return string.format ("usb_interface<%s / %s / %s:%s:%s / %s EPs @ %s %s>",
    a'interface', a'bInterfaceNumber', a'bInterfaceClass', a'bInterfaceSubClass',
    a'bInterfaceProtocol', a'bNumEndpoints', d:get_sysname(), state)
end

local device = Object:inherit{
  isopen = false,
}

function device.init (self, ctx, udevh)
  self.ctx = ctx
  self.udevh = udevh
end

function device.open (self)
  local fname = self.udevh:get_devnode()
  self.f = assert(io.open (fname, "r+"))
  self.isopen = true
end

function device.list_interfaces (self, filter)
  assert(self.isopen, "usb device not open")
  local intfs = {}
  local enum = self.ctx:enumerate()
  assert(enum:add_match_subsystem ("usb"))
  assert(enum:add_match_property ("DEVTYPE", "usb_interface"))
  local function fhex(key, sysattr)
    local v = filter[key]
    if v then assert(enum:add_match_sysattr (sysattr, string.format ('%02x', v))) end
  end
  fhex ('class', 'bInterfaceClass')
  fhex ('subclass', 'bInterfaceSubClass')
  fhex ('protocol', 'bInterfaceProtocol')
  fhex ('number', 'bInterfaceNumber')
  assert(enum:scan_devices())
  for i,path in ipairs(enum:get_list()) do
    intfs[#intfs+1] = interface:new(self.ctx, self.ctx:device_from_syspath (path), self)
  end
  return intfs
end

function device.__tostring (self)
  local d = self.udevh
  local state
  if self.isopen then state = 'open' else state = 'closed' end
  local function a(key) return d:get_sysattr_value(key) or ('unknown-' .. key) end
  return string.format ("usb_device<%s / %s / %s @ %s %s>",
    a'manufacturer', a'product', a'serial', d:get_sysname(), state)
end

function usb.watch_usb(o)
  local devs = {}
  local ctx = udev.context()
  local monitor = ctx:monitor("kernel")
  assert(monitor:filter_add_match_subsystem_devtype("usb", "usb_device"))
  assert(monitor:enable_receiving())
  local enum = ctx:enumerate()
  assert(enum:add_match_subsystem ("usb"))
  assert(enum:add_match_property ("DEVTYPE", "usb_device"))
  assert(enum:add_match_sysattr ("idVendor", string.format("%04x", o.vendorID)))
  assert(enum:add_match_sysattr ("idProduct", string.format("%04x", o.productID)))
  assert(enum:add_match_sysattr ("bcdDevice", string.format("%04x", o.version)))
  assert(enum:scan_devices())
  local list = enum:get_list()
  for i,path in ipairs (list) do
    local d = device:new(ctx, ctx:device_from_syspath (path))
    devs[path] = d
    --o.connect (d)
  end
  --o.coldplug_end ()
  D.cyan'devs:' (devs)
end

usb.watch_usb{
  vendorID = 0x16d0,
  productID = 0x0450,
  version = 0x0100,
}

require 'loop'.run()
