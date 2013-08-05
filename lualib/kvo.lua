local T = require'thread'
local D = require'util'

local M = {}
setmetatable(M, M)

-- private keys
local _observers = newproxy()
local _value = newproxy()
local observe_callback = nil



local mt = {}

function mt:__call(...)
  local o = setmetatable({}, self)
  return self.init and self.init(o, ...) or o
end

local function Class()
  local o = {}
  o.__index = o
  return setmetatable(o, mt)
end



local walk, walkattrs

local function joinkeys(a, b)
  if a then
    return a..'.'..b
  else
    return b
  end
end

function walk(ob, key, cbs)
  if type(ob) == 'table' then
    if ob[walk] then
      ob[walk](ob, key, cbs)
      return true
    elseif ob[M.observableAttributes] then
      walkattrs(ob, key, cbs)
      return true
    end
  end
end

function walkattrs(self, key, cbs)
  for _, k in ipairs(self[M.observableAttributes]) do
    local v = self[k]
    local childkey = joinkeys(key, k)
    if not walk(v, childkey, cbs) then
      if cbs.attribute then cbs.attribute(childkey, v) end
    end
  end
end

M.joinkeys = joinkeys
M.walk = walk
M.observableAttributes = newproxy()

function M.walkall(self, key, cbs)
  for k, v in pairs(self) do
    if type(k) == 'string' then
      local childkey = joinkeys(key, k)
      if not walk(v, childkey, cbs) then
        if cbs.attribute then cbs.attribute(childkey, v) end
      end
    end
  end
end




local Observable = Class()
Observable.__type = 'Observable'

function M:__call(...)
  return Observable(...)
end

function Observable:init(init, opts)
  self[_observers] = {}
  self[_value] = init
  self.version = 0
  if opts then
    self.read = opts.read
    self.write = opts.write
  end
end

function Observable:setcomputed(f, write)
  checks('Observable', 'function', '?function')
  if write then
    if self.write then error('the observable already has a write callback', 2) end
    self.write = write
  end

  local weakref = setmetatable({ self }, { __mode = 'v' })
  local dirty = true
  local color = true
  local list = {}

  local mark, note, update
  function mark()
    dirty = true
    T.Idle.call(update)
  end
  function note(ob, k)
    if list[ob] == nil then
      ob:watch(mark)
    end
    list[ob] = color
  end
  function update()
    dirty = false
    color = not color
    if weakref[1] then
      local old_oc = observe_callback
      observe_callback = note
      local new = f()
      observe_callback = old_oc
      weakref[1]:rawset(new)
    end
    for ob,c in pairs(list) do
      if c ~= color then
        ob:unwatch(mark)
        list[ob] = nil
      end
    end
    if dirty then mark() end
  end

  update()
  return self
end

function Observable:__call(...)
  local old = self[_value]
  if select('#', ...) == 0 then
    if observe_callback then observe_callback(self) end
    if self.seen then self.seen[T.current()] = self.version end
    if self.read then
      return self:read(old)
    else
      return old
    end
  else
    local function handle_write(...)
      if select('#', ...) > 0 then
        local new = ...
        if old ~= new then
          self[_value] = new
          self:notify(new)
        end
        return new
      end
    end
    if self.write then
      return handle_write(self:write(...))
    else
      return handle_write(...)
    end
  end
end

function Observable:rawset(new)
  if new ~= self[_value] then
    self[_value] = new
    self:notify(new)
  end
end

-- callback API
function Observable:watch(fun)
  local o = self[_observers]
  assert(type(fun) == 'function', "function expected")
  o[#o+1] = fun
  return fun
end

function Observable:unwatch(fun)
  local o = self[_observers]
  for i=1,#o do
    if o[i] == fun then
      return table.remove(o, i)
    end
  end
  return fun
end

function Observable:notify(new)
  -- local p = {}
  -- D'notify request:'(tostring(p), new, self.dirty)
  if not self.dirty then
    self.version = self.version + 1
    local cnew
    if self.coalescing == false then
      cnew = new
    else
      self.dirty = true
    end
    T.queuecall(function ()
      -- D'notify execution:'(tostring(p), new, cnew, self[_value])
      self.dirty = nil
      local new = cnew or self[_value]
      for _,fun in ipairs(self[_observers]) do
        T.pcall(fun, new)
      end
      local n = #self
      for i=n,1,-1 do
        local thd = self[i]
        if self.version ~= self.seen[thd] then
          self.seen[thd] = self.version
          T.resume (thd, self, new)
        end
      end
    end)
  end
end

-- thread API
function Observable:poll()
  local s = self.seen
  if not s then s = setmetatable({}, { __mode = 'k' }) self.seen = s end
  local thd = T.current()
  if self.version == s[thd] then return false end
  return true, {self()}
end

function Observable:recv()
  return T.recvone(self)
end

function Observable:register_thread(thd)
  self[#self+1] = thd
end

function Observable:unregister_thread(thd)
  local i = table.index(self, thd)
  table.remove (self, i)
end

function Observable:__tostring()
  return 'o('..D.repr(self())..')'
end

Observable[walk] = function (self, key, cbs)
  if cbs.observable then cbs.observable(key, self) end
end



local ObservableDict = Class()
M.Dict = ObservableDict

function ObservableDict:init(init, opts)
  if init == nil then init = {} end
  assert(type(init) == 'table', 'the initial value of an ObservableDict has to be a table')
  rawset(self, _observers, {})
  rawset(self, _value, init)
  if opts then
    self.change = opts.change
  end
end

function ObservableDict:__index(k)
  if observe_callback then observe_callback(self, k) end
  local v = self[_value][k]
  if v == nil then return getmetatable(self)[k] end
  return v
end

function ObservableDict:__newindex(k,v)
  assert(type(k) == 'string', 'ObservableDict keys have to be strings')
  local new
  if self.change then new = self:change(k, v) end
  if new == nil then new = v end
  if new ~= nil and self[_value][k] ~= nil then self:notify('del', k) end
  self[_value][k] = new
  local action
  if v ~= nil then action = 'add' else action = 'del' end
  self:notify(action, k)
end

function ObservableDict:__call(new)
  assert(not new, 'you cannot set ObservableDict value')
  if observe_callback then observe_callback(self) end
  local keys = {}
  for k in pairs(self[_value]) do
    keys[#keys+1] = k
  end
  return unpack(keys)
end

ObservableDict.rawset = Observable.rawset

ObservableDict.watch = Observable.watch
ObservableDict.unwatch = Observable.unwatch

function ObservableDict:notify(action, key)
  local new = self[_value]
  self.version = self.version + 1
  for _,fun in ipairs(self[_observers]) do
    T.queuecall(function () fun(action, key) end)
  end
  local n = #self
  for i=n,1,-1 do
    local thd = self[i]
    self.seen[thd] = self.version
    T.resume (thd, self, action, key)
  end
end

function ObservableDict:__tostring()
  return 'o.Dict('..D.repr(self())..')'
end

function ObservableDict:each()
  if observe_callback then observe_callback(self) end
  return next, self[_value], nil
end

ObservableDict[walk] = function (self, key, cbs)
  if cbs.dict then cbs.dict(key, self) end
  if cbs.dict_item then
    for k, v in self:each() do
      if type(k) == 'string' then
        cbs.dict_item(key, k, v)
      end
    end
  end
end



function M.computed(f, write)
  local o
  o = Observable()
  return o:setcomputed(f, write)
end



--[[
local time = Observable(T.now())
Observable.time = time
T.go(function ()
  while true do
    T.sleep(.2)
    time(T.now())
  end
end)

function M.timer()
  local start = time()
  return M.computed(
  function ()
    return time() - start
  end,
  function (ob, new)
    start = time() - new
    return new
  end)
end
--]]



return M
