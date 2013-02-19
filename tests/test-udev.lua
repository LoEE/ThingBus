local udev = require'udev'
local D = require'util'

D'udev:'(udev)
ctx = udev.context()
D'ctx:'(ctx)
D'sys_path:'(ctx:get_sys_path())
D'dev_path:'(ctx:get_dev_path())
D'run_path:'(ctx:get_run_path())
monitor = ctx:monitor("kernel")
D'monitor:'(monitor)
D'monitor ctx:'(monitor:get_context())
D'monitor filter:'(monitor:filter_add_match_subsystem_devtype("usb", "usb_device"))
D'monitor enable:'(monitor:enable_receiving())
--[[
local enum = ctx:enumerate()
D'enumerate:'(enum)
D'enum filter subsystem:'(enum:add_match_subsystem ("usb"))
D'enum filter devtype:'(enum:add_match_property ("DEVTYPE", "usb_device"))
D'enum filter idVendor:'(enum:add_match_sysattr ("idVendor", "16d0"))
D'enum filter idProduct:'(enum:add_match_sysattr ("idProduct", "0450"))
D'enum scan devices:'(enum:scan_devices())
local devs = enum:get_list()
D'enum result:'(devs)
for i,d in ipairs(devs) do
  d = ctx:device_from_syspath (d)
  D'dev:'(i, d:get_sysattr_value'idVendor', d:get_sysattr_value'idProduct', d:get_sysattr_value'serial')
end
--]]
--require 'repl'.start(0)
--require 'loop'.run()
local loop = require'loop'
loop.on_readable(monitor, function ()
  local dev = monitor:receive_device()
  if dev then
    D'monitor receive:'(dev)
    local attrs = {}
    attrkeys = {
      "devpath", "subsystem", "devtype", "syspath", "sysname", "sysnum", "devnode", 
      "driver", "devnum", "action", "is_initialized", "seqnum", "usec_since_initialized"
    }
    for _,attr in ipairs(attrkeys) do
      attrs[attr] = dev['get_' .. attr](dev)
    end
    D'dev attrs:'(attrs)
    D'dev serial:'(dev:get_sysattr_value'serial')
  end
end, true)
loop.run()
