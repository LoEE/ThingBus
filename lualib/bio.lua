local Object = require'oo'
local T = require'thread'
local buffer = require'buffer'
local loop = require'loop'
local D = require'util'

local IBuf = Object:inherit()

function IBuf.init (self, file)
  self.file = file
  self.buffer = buffer.new()
end

function IBuf._read (self, reader)
  local data = reader ()
  if data ~= nil then return data end
  while true do
    local data, err = loop.read (self.file)
    if err and err ~= "eof" then
      return nil, err
    else
      if data and data ~= "" then
        self.buffer:write (data)
        local ret = reader ()
        if ret then return ret end
      end
      if err == "eof" then
        return nil, "eof"
      end
    end
  end
end

function IBuf.read (self, len)
  return self:_read (function () return self.buffer:read(len) end)
end

function IBuf.readuntil (self, ending)
  ending = ending or '\n'
  return self:_read (function () return self.buffer:readuntil(ending, #ending) end)
end

function IBuf.readstruct (self, fmt)
  return self:_read (function () return self.buffer:readstruct(fmt) end)
end

return {
  IBuf = IBuf
}
