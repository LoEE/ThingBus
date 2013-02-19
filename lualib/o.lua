local O = {}

-- oo
local function __call(_, base)
  local o = {}
  o.__index = o
  if base then setmetatable(o, base) end
  return o
end

function O.constructor(init)
  init = init or function () end
  return function (base, ...)
    local o = setmetatable({}, base)
    init(o, ...)
    return o
  end
end

return setmetatable(O, {__call = __call})
