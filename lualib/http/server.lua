local VERSION = "LoHTTPServer/0.1"

local loop = require'loop'
local socket = require'socket'
local lfs = require'lfs'
local Object = require'oo'
local T = require'thread'
local D = require'util'
local bio = require'bio'
local B = require'binary'
local sha = require'sha'

local codes

local M = {}

local MIME = Object:inherit{
  txt = 'text/plain; charset=utf-8',
  html = 'text/html; charset=utf-8',
  css = 'text/css; charset=utf-8',
  js = 'application/javascript; charset=utf-8',
}
M.MIME = MIME

function MIME.fromFilename (self, name)
  local ext = string.match(name, "%.([a-zA-Z0-9]+)$")
  return self[ext]
end

local function timefmt (time)
  return os.date ("!%a, %d %b %Y %H:%M:%S GMT", time)
end

local Request = Object:inherit()
M.Request = Request
local Reply = Object:inherit{
  ct_names = {
    text = "text/plain; charset=utf-8",
    json = "application/json; charset=utf-8",
  },
}
M.Reply = Reply

do
  -- HTTP parser
  local CHAR = "%z\1-\127"
  local CTL = "%z\1-\31\127"
  local CRLF = "\r\n"
  --local LWS = "["..CRLF.."]?[ \t]+"
  local TEXT = "[^%z\1-\8\10-\31]"
  local HEX = "[0-9a-fA-F]"
  local separators = '%(%)<>@,;:\\"/%[%]%?={} \t'
  local token = "[^"..CTL..separators.."\128-\255]+"
  local header = "^("..token.."): *(.*)$"

  function Request.parse(self, data)
    --local lineardata = string.gsub (data, LWS, " ")
    local lines = string.split (data, '\r\n')
    if #lines < 1 then error ("no request: " .. string.format ("%q", data)) end
    self.method, self.origurl, self.version = string.splitallv (lines[1], ' ')
    local url, query = string.match(self.origurl, '(.*)?(.*)')
    if url and query then
      self.url = url
      self.query = query
    else
      self.url = self.origurl
    end
    local h = {}
    for i=2,#lines do
      local name, value = string.match (lines[i], header)
      if not name or not value then error ('invalid header line: ' .. lines[i]) end
      h[#h+1] = {name, value}
    end
    self.headers = h
    self.done = false
    return self
  end
end

local function socketid (sock)
  return string.format ("%08s", string.match(tostring(sock), "([0-9a-fA-F]+)$"))
end

function Request.log(self, msg, ...)
  local date = os.date("!%Y-%m-%d %H:%M:%S")
  local str = string.format("%s %s % 5d: " .. msg, socketid(self.sock), date, self.id, ...)
  self.srv.logger (str)
end

function Request.header (self, name)
  name = string.lower(name)
  for _,header in ipairs(self.headers) do
    local hname, hvalue = unpack(header)
    if string.lower(hname) == name then return hvalue end
  end
  return nil
end

function Request.reply(self, status)
  if self.done then error ('request was already replied to', 2) end
  local reply = self.srv.Reply:new():make(self, status)
  return reply
end

function Request.replyWithFile (self, path, opts)
  local file, err = io.open(path, "rb")
  if not file then D('replyWithFile: ' .. err)() return end
  local attr = lfs.attributes(path)
  local mtime = timefmt(attr.modification)
  local etime = os.date('!*t')
  etime.year = etime.year + 1
  etime = timefmt(os.time(etime))

  local modified = self:header'If-Modified-Since' ~= mtime
  local r
  if modified then
    r = self:reply'OK'
  else
    r = self:reply'Not Modified'
  end

  r:header("Last-Modified", mtime)
  local cc = opts and opts.cache_control
  if not cc then cc = "max-age=0" end
  if type(cc) == 'string' then
    r:header("Cache-Control", cc);
  else
    cc(self, r, path, opts)
  end

  if modified then
    r:write (assert (file:read ("*a"))):sendAs (self.srv.MIME:fromFilename(path) or "text")
  else
    r:sendEmpty()
  end

  file:close()
end

local WebSocketGUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11'

function Request.replyWithWebSocketAccept (self, protocol)
  local key = self:header'Sec-WebSocket-Key'
  local nonce = B.b64_encode(sha.sha1(key .. WebSocketGUID))
  local r = self:reply'Switching Protocols'
  r:header('Upgrade', 'websocket')
  r:header('Connection', 'Upgrade')
  r:header('Sec-WebSocket-Accept', nonce)
  if protocol then r:header('Sec-WebSocket-Protocol', protocol) end
  r:sendEmpty()
end

local function timefmt (time)
  return os.date ("!%a, %d %b %Y %H:%M:%S GMT", time)
end


function Reply.make(self, req, status)
  self.req = req
  self.sock = req.sock
  local code = codes[status]
  if not code then error ("invalid HTTP status: " .. tostring(status), 2) end
  self.status = code
  self.data = {}
  self[#self + 1] = string.format ("%s %d %s\r\n", req.version, code, status)
  self:header ("Server", VERSION)
  self:header ("Date", timefmt(os.time()))
  return self
end

function Reply.header(self, name, value)
  self[#self + 1] = string.format ("%s: %s\r\n", name, value)
  return self
end

function Reply.sendRedirect (self, newurl)
  self:header ("Location", newurl)
  self:sendEmpty()
end

function Reply.sendEmpty (self)
  self:header ("Content-Length", 0)
  self[#self+1] = '\r\n'
  local hdata = table.concat (self)
  self.hlen = #hdata
  loop.write (self.sock, hdata)
  self.clen = 0
  self.req.done = self
end

function Reply.sendAs (self, content_type)
  local data = table.concat (self.data)
  content_type = self.ct_names[content_type] or content_type
  self:header ("Content-Type", content_type)
  self:header ("Content-Length", #data)
  self[#self+1] = '\r\n'
  local hdata = table.concat (self)
  self.hlen = #hdata
  loop.write (self.sock, hdata)
  self.clen = #data
  loop.write (self.sock, data)
  self.req.done = self
end

function Reply.write(self, data)
  local b = self.data
  b[#b+1] = data
  return self
end

function M.http_handler (srv, router, c)
  D.cyan(socketid(c) .. ' opened')()
  local inb = bio.IBuf:new(c)
  local n = 0
  while true do
    local data, err = inb:readuntil('\r\n\r\n')
    local stime = socket.gettime()
    if not data then
      if err == "eof" then
        c:close()
        break
      end
      D.cyan(socketid(c) .. ' read error: ')(err)
      break
    end
    local req = srv.Request:new():parse(data)
    local bodylen = tonumber (req:header ("Content-Length") or 0)
    req.srv = srv
    req.sock = c
    req.ibuf = inb
    n = n + 1
    req.id = n
    req.prefix = ""
    if bodylen > 0 then req.body = inb:read (bodylen) end

    req.websocket = (req:header'Upgrade' == 'websocket')
    if req.websocket then
      req:log ("%s %s [websocket]", req.method, req.origurl)
    end

    local ok, err = T.xpcall(router, T.identity, req, req.url, "")
    if not ok then
      req:log ("%s %s [error]:\n%s", req.method, req.origurl, err)
    end
    if not req.done then
      local reply = req:reply"Not Found":write("Resource not found: " .. req.url):sendAs"text"
    end

    if not req.websocket and not req.nolog then
      local etime = socket.gettime()
      local reply = req.done
      req:log ("%s %s [%d in:%d out:%d t:%.2f]", req.method, req.origurl, reply.status,
                                                 #data + 4 + bodylen, reply.hlen + reply.clen, (etime - stime) * 1000)
    end
  end
  c:close()
  D.cyan(socketid(c) .. ' closed')()
  srv[c] = nil
end

function M.default_logger (str)
  io.stderr:write(str .. '\n')
end

function M.start (router, options)
  local srv = {
    address = "*",
    port = 6886,
    router = router,
    logger = M.default_logger,
    Request = Request,
    Reply = Reply,
    MIME = MIME,
  }
  if options then for k,v in pairs(options) do srv[k] = v end end
  local lsock, err = socket.bind (srv.address, srv.port)
  if not lsock then
    error('cannot open server socket: '..err)
  end
  srv.lsock = lsock
  lsock:settimeout (0)
  loop.on_acceptable (lsock, function () local c = lsock:accept(); c:settimeout(0); srv[c] = T.go(M.http_handler, srv, router, c) end, true)
  return srv
end

--
-- HTTP status codes
--
-- from: http://greenbytes.de/tech/webdav/draft-ietf-httpbis-p2-semantics-17.html#overview.of.status.codes
codes = {}
M.codes = codes
local function S(code, name) codes[code] = name codes[name] = code end
S(100, "Continue")
S(101, "Switching Protocols")
S(200, "OK")
S(201, "Created")
S(202, "Accepted")
S(203, "Non-Authoritative Information")
S(204, "No Content")
S(205, "Reset Content")
S(206, "Partial Content")
S(300, "Multiple Choices")
S(301, "Moved Permanently")
S(302, "Found")
S(303, "See Other")
S(304, "Not Modified")
S(305, "Use Proxy")
S(307, "Temporary Redirect")
S(400, "Bad Request")
S(401, "Unauthorized")
S(402, "Payment Required")
S(403, "Forbidden")
S(404, "Not Found")
S(405, "Method Not Allowed")
S(406, "Not Acceptable")
S(407, "Proxy Authentication Required")
S(408, "Request Time-out")
S(409, "Conflict")
S(410, "Gone")
S(411, "Length Required")
S(412, "Precondition Failed")
S(413, "Request Representation Too Large")
S(414, "URI Too Long")
S(415, "Unsupported Media Type")
S(416, "Requested range not satisfiable")
S(417, "Expectation Failed")
S(426, "Upgrade Required")
S(500, "Internal Server Error")
S(501, "Not Implemented")
S(502, "Bad Gateway")
S(503, "Service Unavailable")
S(504, "Gateway Time-out")
S(505, "HTTP Version not supported")

return M
