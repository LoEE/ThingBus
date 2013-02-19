local D = require'util'
local T = require'thread'
local D = require'util'
local usb = require'usb'

i = 1
dmap = {}

usb.watch{
  --vendorID = vendorID,
  --productID = productID,
  --version = version,

  connect = function (d) dmap[i] = d; D.blue"+"(i, d) i = i+1 end,
  disconnect = function (d) D.blue"-"(d) end,
  coldplug_end = function (d) D.blue"coldplug ended"() end,
}

local repl = require'repl'

repl.start(0)
require'loop'.run()
