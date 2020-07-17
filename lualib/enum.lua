local __name = newproxy()

local function createenum(self, t)
  local o = {}
  for k,v in pairs(t) do
    if t[v] then error('ambiguous enum: '..require'util'.repr(t)) end
    o[v] = k
    o[k] = v
  end
  o[__name] = t.__name
  return setmetatable(o, self)
end

local enum = setmetatable({}, { __call = createenum })

enum.__index = enum
enum.__type = 'enum'

function enum:msg(arg, msg)
  return string.format(msg or 'invalid '..self.__name..': %s', tostring(arg))
end

function enum:dec(n)
  checks('enum', 'number')
  local r = self[n]
  if not r then
    return '<unknown '..self[__name]..': '..tostring(n)..'>'
  end
  return r
end

function enum:enc(s)
  if type(s) == 'number' then return s end
  checks('enum', 'string')
  local r = self[s]
  if not r then error('invalid '..self.__name..': '..tostring(s)) end
  return r
end

return enum
