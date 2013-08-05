local D = require'util'
local T = require'thread'
local o = require'kvo'
local loop = require'loop'

X = {}

X.A = o('a')
X.B = o('b') X.B.coalescing = false
X.C = o('c')
X.i = o(0)

X.ABC = o.computed(function ()
  return D'ABC compute'(X.A()..X.B()..X.C())
end, function (self, str)
  D'ABC write:'(str)
  if #str == 3 then
    X.A(str:sub(1,1)) X.B(str:sub(2,2)) X.C(str:sub(3,3))
    return str
  end
end)

function S(k, v)
  D.cyan(k..' =')(v)
  X[k](v)
end

for k,v in pairs(X) do
  v:watch(function (new)
    D.green(k..' watch:')(new)
    if k == 'A' then S('i', X.i() + 1) end
  end)
end

T.go(function ()
  while true do
    T.recv{
      [X.ABC] = function (new) D.yellow'ABC recv:'(new, X.ABC.version, X.ABC.seen) end,
      [X.B] = D.yellow'B recv:',
      [X.i] = D.yellow'i recv:',
    }
  end
end)

S('B','B')
S('B','b')

S('ABC','QWE')
S('ABC','qwe')
S('ABC','QWEr')

T.go(function ()
  D.cyan'sleep'() T.sleep(.2)
  S('ABC','ABC')
  S('ABC','DEF')
  S('A','G') S('B','H') S('C','I')
  D.cyan'sleep'() T.sleep(.2)
  S('ABC','123')
end)

require'repl'.start(0)
loop.run()
