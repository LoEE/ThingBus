#!/usr/bin/env thb
---
--- A very simple test runner with a transcript like interface
---
--- Usage:
---
---     thb :lotest [-i] filenames ...
---
--- Runs all the tests found in the specified files and checks their output.
--- If `-i` is given it runs an interactive repl in the same namespace as the
--- tests.
--- Run `thb :lotest lotest.lua` to see it in action.
---

--$ 2+2
--  4
--$ print"qwe"
--  qwe
--$ a = {}
--$ a[1] = "a"
--$ a.b = "c"
--$ a
--  { "a", b = "c" }
--$ 1/0
--  inf
--$ D'qwe'(1, 2, 3)
--  1 2 3
--$ 2+"asd"
--  💥 [string "lotest.lua"]:28: attempt to perform arithmetic on a string value


local T = require'thread'
local D = require'util'
D.prepend_thread_names = false
D.prepend_timestamps = false

-- parsing:
local function test_file_lines(name)
  local lines = io.lines(name)
  local in_output = false
  local n = 0
  return function ()
    local line = lines() n = n + 1
    if not line then return nil end
    local doc = string.match(line, '^%-%-[#%.]+ (.*)$')
    if doc then in_output = true return 'doc', doc, n, line end
    local input = string.match(line, '^%-%-%$ (.*)$')
    if input then in_output = true return 'input', input, n, line end
    local output = string.match(line, '^%-%-  (.*)$')
    if in_output and output then return 'output', output, n, line end
    in_output = false
    return 'other', nil, n, line
  end
end

local function test_blocks(test_lines)
  local blocks = {}
  local block, prev_kind
  for kind, data, n, line in test_lines do
    if (prev_kind ~= 'input' and prev_kind ~= 'doc') and (kind == 'input' or kind == 'doc') then
      block = { header = {}, input = {}, output = {} }
      blocks[#blocks+1] = block
    end
    if kind == 'input' then
      if not block.linenum then block.linenum = n end
      if data:startswith' ' then
        block.input[#block.input] = block.input[#block.input]..'\n'..data
      else
        block.input[#block.input + 1] = data
      end
    elseif kind == 'output' then
      block.output[#block.output + 1] = data
    elseif kind == 'doc' then
      block.header[#block.header + 1] = line
    end
    prev_kind = kind
  end
  return ipairs(blocks)
end

-- compilation
local test_env = {
}
setmetatable(test_env, {__index = _G})

local function loadline(str, name)
  local fun = loadstring("return "..str, name)
  if not fun then
    fun = loadstring(str, name)
  end
  setfenv(fun, test_env)
  return fun
end

local function serialize_result(ok, ...)
  if not ok then return "💥 "..(...) end
  if select('#', ...) == 0 then return end
  local results = {}
  for i=1,select('#', ...) do
    results[i] = D.repr((select(i, ...)))
  end
  return table.concat(results, " ")
end

local function test(name)
  for _,block in test_blocks(test_file_lines(name)) do
    local results = {}
    -- we overwrite the print function in the environment of the test functions
    -- so we can capture all the lines and compare them with the expected
    -- results
    function test_env.print(...)
      local args = {...}
      for _,ln in ipairs(string.split(table.concat(args, "\t"), '\n')) do
        results[#results+1] = ln
      end
    end
    if #block.header > 0 then
      D''()
      for i,line in ipairs(block.header) do
        D.yellow(line)()
      end
    end
    for i,line in ipairs(block.input) do
      D.green'--$'(D.unq(line)) --(string.gsub(table.concat(block.input, '\n'), '\n', '\n--$ '))))
      local code = loadline(string.rep("\n", block.linenum - 1 + i - 1)..line, name)
      -- `print` calls may add elements to `results` as a side-effect of running
      -- `code` so we need to delay the `#results+1` calculation
      local res = serialize_result(T.spcall(code, 0))
      results[#results+1] = res
    end
    test_env.print = nil
    results = table.concat(results, '\n')
    local expected = table.concat(block.output, '\n')
    if #block.output > 0 then
      if results == expected then
        D.blue'-- '(D.unq((string.gsub(results, '\n', '\n--  '))))
      else
        D.red'expected:'()
        D.blue'-- '(D.unq((string.gsub(expected, '\n', '\n--  '))))
        D.red'got:'()
        D.red'-- '(D.unq((string.gsub(results, '\n', '\n--  '))))
      end
    end
  end
end

local config = {}
if arg[1] == '-i' then
  config.interactive = true
  table.remove(arg, 1)
end

local files_to_test = arg
for _,name in ipairs(files_to_test) do
  -- FIXME: handle tests in subdirectories
  local rpath = os.realpath(name)
  if rpath then
    local p = os.dirname(rpath)
    package.path = p..'/?.luac;'..p..'/?/init.luac;'..p..'/?.lua;'..p..'/?/init.lua;'..package.path
    package.cpath = p..'/?.so;'..package.cpath
    os.program_path = p
  end
  test(name)
end

if config.interactive then
  local repl = require'repl'
  for k,v in pairs(test_env) do repl.ns[k] = v end
  repl.start(0)
  require'loop'.run()
end
