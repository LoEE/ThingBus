local T = require'thread'
local O = require'o'
local D = require'util'
local ev = require'ev'
local loop = require'loop'
local posix = require'posix'
local bio = require'bio'
local json = require'cjson'
local lfs = require'lfs'


local subproc = O()
subproc.__type = 'subproc'

subproc.new = O.constructor(function (self, cmd, ...)
    self._cmd = cmd
    self._args = {...}
end)

local function pipe(noinherit)
    local r, w = assert(posix.pipe())
    if noinherit == 'r' then io.setinherit(r, false) end
    if noinherit == 'w' then io.setinherit(w, false) end
    return { r = r, w = w }
end

function subproc:stdin(fd)
    if fd == 'pipe' then
        self._stdin = pipe('w')
    elseif io.getfd(fd) then
        self._stdin = { r = fd }
    elseif type(fd) == 'table' and fd.r then
        self._stdin = fd
    else
        return error('invalid file descriptor specifier: '..D.repr(fd))
    end
    return self
end

function subproc:stdout(fd)
    if fd == 'pipe' then
        self._stdout = pipe('r')
    elseif io.getfd(fd) then
        self._stdout = { w = fd }
    elseif type(fd) == 'table' and fd.w then
        self._stdout = fd
    else
        return error('invalid file descriptor specifier: '..D.repr(fd))
    end
    return self
end

function subproc:stderr(fd)
    if fd == 'pipe' then
        self._stderr = pipe('r')
    elseif io.getfd(fd) then
        self._stderr = { w = fd }
    elseif type(fd) == 'table' and fd.w then
        self._stderr = fd
    else
        return error('invalid file descriptor specifier: '..D.repr(fd))
    end
    return self
end

--- Sets environment variables for process that will be spawned.
--  @param envs Map (table) with name=value pairs for environment
--
function subproc:env(envs)
    if next(envs) then
        self._envs = envs
    end
end

function subproc:start()
    local pid = assert(posix.fork())
    if pid == 0 then
        if self._stdin then posix.dup2(self._stdin.r, 0) posix.close(self._stdin.r) end
        if self._stdout then posix.dup2(self._stdout.w, 1) posix.close(self._stdout.w) end
        if self._stderr then posix.dup2(self._stderr.w, 2) posix.close(self._stderr.w) end
        for i=3,30 do posix.close(i) end -- most descriptors in Lua are inheritable, clean it up with brute force

        if self._envs then
            for key, value in pairs(self._envs) do
                posix.setenv(key, value)
            end
        end
        local ok, err = posix.exec(self._cmd, unpack(self._args))
        if not ok then
            log:struct('subproc', { cmd = self._cmd, args = self._args, error = err })
            os.exit(127)
        end
    end

    self._pid = pid
    if self._stdin then posix.close(self._stdin.r) end
    if self._stdout then posix.close(self._stdout.w) end
    if self._stderr then posix.close(self._stderr.w) end

    return self
end

function subproc:wait()
    assert(self._pid, "subproc must be started before calling wait")
    if not self._status then
        local chn = T.Mailbox:new()
        local watcher = ev.Child.new(function (loop, child, events)
            chn:put(child:getstatus())
        end, self._pid, false)
        watcher:start(loop.default)
        self._status = chn:recv()
    end
    return self._status
end

function subproc:communicate(input)
    if not self._stdin then self:stdin'pipe' end
    if not self._stdout then self:stdout'pipe' end
    assert(self._stdin.w, 'stdin has no write endpoint')
    assert(self._stdout.r, 'stdout has no read endpoint')

    if not self._pid then
        self:start()
    end

    local chn = T.Mailbox:new()
    local thd = T.go(function ()
        local out = {}
        while true do
            local data, err = loop.read(self._stdout.r)
            if data then
                out[#out+1] = data
            else
                out = table.concat(out)
                if err == 'eof' then err = nil end
                io.raw_close(self._stdout.r)
                chn:put(out, err)
                return
            end
        end
    end)

    local errchn = T.Mailbox:new()
    T.go(function()
        if not self._stderr then
            errchn:put("", nil)
            return
        end
        local out = {}
        while true do
            local data, err = loop.read(self._stderr.r)
            if data then
                out[#out+1] = data
            else
                out = table.concat(out)
                if err == 'eof' then err = nil end
                io.raw_close(self._stderr.r)
                errchn:put(out, err)
                return
            end
        end
    end)

    loop.write(self._stdin.w, input)
    io.raw_close(self._stdin.w)

    local stdout, err = chn:recv()
    if err then error(err) end

    local stderr, err = errchn:recv()
    if err then error(err) end

    return stdout, stderr
end

-- function subproc:close()
--   io.raw_close(self._stdin.w)
--   io.raw_close(self._stdout.r)
--   io.raw_close(self._stderr.r)
-- end

function subproc.popen_lines(cmd)
    local fd, err = io.popen(cmd, "r")
    if not fd then log:struct('popen-error', { error = err, cmd = cmd, when = 'popen' }) return end
    local b = bio.IBuf:new(fd)
    return function ()
        local line, err = b:readuntil('\n')
        if err == 'eof' then return nil, fd:close() end
        if not line then log:struct('popen-error', { error = err, cmd = cmd, when = 'read-line' }) return end
        return line
    end
end

local function try_monitor_jlog(fname, cb)
    local lines = subproc.popen_lines("exec tail +0 -F "..fname)
    while true do
        local line = lines()
        if not line then break end
        local data = string.match(line, "^[%%0-9a-f._: -]*~ [0-9.]+ (%[.+%])$")
        if not data then
            data = string.match(line, "^[%%0-9a-f._:-]* (%[.+%])$")
        end
        -- D'»'(fname, line, data)
        if data then
            local ok, r = T.spcall(json.decode, data)
            if not ok then
                D.red'json parse error'(r, data)
            else
                cb(r)
            end
        end
    end
end

function subproc.monitor_jlog(fname, cb)
    T.go(function ()
        while true do try_monitor_jlog(fname, cb) end
    end)
end

local function last_modification(fname)
    local stat = lfs.attributes(fname)
    if not stat then return nil end
    return stat.modification
end

function subproc.monitor_file(fname, cb)
    T.go(function ()
        local last_tmod = nil
        while true do
            local tmod = last_modification(fname)
            if not tmod then
                cb(nil)
            elseif tmod ~= last_tmod then
                local fd, err = io.open(fname)
                if not fd then cb(nil, err) end
                cb(fd:read'*a', tmod)
                last_tmod = tmod
            end
            T.sleep(1)
        end
    end)
end

function subproc.monitor_service(dir, cb)
    subproc.monitor_file(dir..'/supervise/status', function ()
        local fd, err = io.open(dir..'/supervise/stat')
        if not fd then return cb(nil, err) end
        cb(fd:read'*a':strip())
    end)
end

function subproc.get_mem_usage()
    local fd, err = io.open("/proc/meminfo", 'r')
    if not fd and err == '/proc/meminfo: No such file or directory' then return end
    assert(fd, err)
    local meminfo = fd:read'*a'
    return
        tonumber(string.match(meminfo, 'MemTotal: +([0-9]+) kB')),
        tonumber(string.match(meminfo, 'MemAvailable: +([0-9]+) kB'))
end

--- Checks which path from provided set exsits in file system.
--  @param ... Multiple strings with path to check.
--  @returns First path that exists in the filesystem. Nil if none exists.
--
function subproc.find_file(...)
    for i=1,select('#', ...) do
        local path = select(i, ...)
        if io.open(path, 'r') then return path end
    end
end

return subproc
