local Object = {}

function Object.inherit (self, o)
  if self == nil then error ("Object:inherit must be called on a prototype (got nil)", 2) end
  local o = o or {}
  setmetatable (o, self)
  self.__index = self
  return o
end

function Object.new (self, ...)
  if self == nil then error ("Object:new must be called on a prototype (got nil)", 2) end
  local o = self:inherit ()
  return o:init(...) or o
end

function Object.init (self)
  return self
end

function Object.isinstance (self, class)
  local c = getmetatable(self)
  if c == nil then
    return false
  elseif c == class then
    return true
  else
    return c:isinstance (class)
  end
end

return Object
