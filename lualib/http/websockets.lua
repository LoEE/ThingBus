local T = require'thread'
local Object = require'oo'
local B = require'binary'
local loop = require'loop'
local json = require'json'

local M = {}

local function bihash(forward)
  local reverse = {}
  for k,v in pairs(forward) do reverse[v] = k end
  return function (val)
    return forward[val] or reverse[val] or val
  end
end

local OPCODES = bihash{
  [0x0] = 'Continuation',
  [0x1] = 'Text',
  [0x2] = 'Binary',
  [0x8] = 'Close',
  [0x9] = 'Ping',
  [0xA] = 'Pong',
}

local WebSocket = Object:inherit()
M.WebSocket = WebSocket

function WebSocket:init(req)
  self.req = req
  self.inbox = T.Mailbox:new()
  self.outbox = T.Mailbox:new()
  self.inthd = T.go(self.readLoop, self)
  self.outthd = T.go(self.writeLoop, self)
end

function WebSocket:readPacket(ibuf)
  local head, err = ibuf:readstruct'>u2'
  if not head then
    if err == 'eof' then return false end
    error(err)
  end
  local p = B.unpackbits(head, 'FIN RSV1 RSV2 RSV3 opcode:4 MASK len:7')
  p.opcode = OPCODES(p.opcode)
  if p.len == 126 then
    p.len = assert(ibuf:readstruct'>u2')
  elseif p.len == 127 then
    p.len = assert(ibuf:readstruct'>u8')
  end
  local maskkey
  if p.MASK then
    maskkey = assert(ibuf:read(4))
  end
  p.MASK = nil
  local data = assert(ibuf:read(p.len))
  if maskkey then
    p.data = B.strxor(data, maskkey)
  end
  return p
end

function WebSocket:formatLength(len, mask)
  local b0 = 0
  if mask then b0 = 0x80 end
  if len < 126 then
    return b0 + len
  elseif len < 65536 then
    return { b0 + 126, B.enc16BE(len) }
  elseif len < 0x7fffffff then
    return { b0 + 127, B.enc64BE(len) }
  else
    error('packet too long: '..tostring(len))
  end
end

function WebSocket:formatPacket(p)
  local data
  if p.maskkey then
    data = B.strxor(p.data, p.maskkey)
  end
  return B.flat{ 0x80 + OPCODES(p.opcode), self:formatLength(#p.data, p.maskkey), p.data }
end

function WebSocket:readLoop()
  local ibuf = self.req.ibuf
  while true do
    local p = self:readPacket(ibuf)
    if not p then self.inbox:put(p) return end
    local r
    if p.opcode == 'Text' or p.opcode == 'Binary' then
      self.inbox:put(p)
    elseif p.opcode == 'Close' then
      self.outbox:put{ opcode = 'Close', data = p.data }
    elseif p.opcode == 'Ping' then
      self.outbox:put{ opcode = 'Pong', data = p.data }
    elseif p.opcode == 'Pong' then
    else
      error ('WebSocket reader: unknown opcode: '..tostring(p.opcode))
    end
  end
end

function WebSocket:writeLoop()
  while true do
    local p = self.outbox:recv()
    local ok, err = loop.write (self.req.sock, self:formatPacket(p))
    if not ok then
      if err == 'closed' then return end
      error(err)
    end
    if p.opcode == 'Close' then
      return
    end
  end
end

function WebSocket:argsToJS(...)
  local args = {...}
  for i=1,select('#',...) do
    if args[i] == nil then args[i] = json.null end
    if args[i] ~= args[i] then args[i] = json.null end -- NaN
  end
  return args
end

function WebSocket:sendText(data)
  self.outbox:put{ opcode = 'Text', data = data }
end

function WebSocket:sendBinary(data)
  self.outbox:put{ opcode = 'Binary', data = data }
end

function M.WebSocketHandler(proc, acceptor)
  return function (req)
    local accept_result = not acceptor or acceptor(req)
    if accept_result then
      -- FIXME: handle Sec-WebSocket-Version/Protocol and Extensions
      req:replyWithWebSocketAccept()
      local ws = WebSocket:new(req)
      proc(ws, accept_result)
    end
  end
end

return M
