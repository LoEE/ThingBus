local D = require'util'
local M = {}

local SeqMT = {}
function SeqMT.__call (self, req, prefix, url)
  for i,handler in ipairs(self) do
    handler(req, prefix, url)
    if req.done then return end
  end
end

function M.Seq (routes)
  -- FIXME: flatten nested Seqs
  return setmetatable(routes, SeqMT)
end

local function MethodNotAllowed(req)
  return req:reply'Method Not Allowed':write(req.method .. ' method is not allowed for the resource: ' .. req.url):sendAs'text'
end

function M.P (pattern, get_handler, handlers)
  pattern = '^' .. pattern .. '$'
  return function (req, url, prefix)
    --D.yellow'trying'(pattern, get_handler, handlers, url, prefix)
    local function handle(...)
      if not select(1, ...) then return nil end
      --D.yellow'matched'(pattern, ...)
      local meth = req.method
      if req.websocket then
        local h = handlers and handlers['websocket']
        if not h then return MethodNotAllowed(req) end
        return h(req, ...)
      elseif get_handler and (meth == 'GET' or meth == 'HEAD') then
        return get_handler (req, ...)
      else
        local h
        if handlers then
          h = handlers[meth]
          if not h and meth == 'HEAD' then h = handlers['GET'] end
        end
        if not h then return MethodNotAllowed(req) end
        return h(req, ...)
      end
    end
    return handle(string.match (url, pattern))
  end
end

function M.Always (handler)
  return function (req, url, prefix)
    handler(req)
  end
end

-- TODO: implement M.Include(path_prefix, sub_router)

return M
