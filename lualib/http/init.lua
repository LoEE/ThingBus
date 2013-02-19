local M = {}

for i,k in ipairs{'server', 'routers'} do
  M[k] = require('http.'..k)
end

for _,mod in ipairs{'handlers', 'websockets'} do
  local mod = require('http.'..mod)
  for k,v in pairs(mod) do
    M[k] = v
  end
end

M.serve = M.server.start

return M
