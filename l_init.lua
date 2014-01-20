-- os.platform needs to be set immediately (IDEA: do it from C)
os.executable_path, os.platform = ...

package.path = ''
package.cpath = ''

require'extensions'

local function addtoPATH(p)
  package.path = p..'/?.luac;'..p..'/?/init.luac;'..p..'/?.lua;'..p..'/?/init.lua;'..package.path
  package.cpath = p..'/?.so;'..package.cpath
end

os.executable_dir = os.dirname(os.executable_path)
addtoPATH(os.executable_dir..'/lualib')
addtoPATH(os.executable_dir..'/lualib/'..os.platform)

local main

local function drop_arguments(n)
  for i=0,#arg do
    arg[i] = arg[i+n]
  end
end

if not os.basename(arg[0]):startswith"thb" then
  -- FIXME: realpath does not work for executables in PATH
  os.program_path = os.dirname(os.realpath(arg[0]))
  addtoPATH(os.program_path)
  function main()
    local name = arg[0]
    if name:endswith".exe" then
      name = name:sub(1, -5)
    end
    dofile(name..'.lua')
  end
elseif arg[1] then
  if string.sub(arg[1], 1, 1) == ':' then
    arg[1] = os.executable_dir..'/'..string.sub(arg[1], 2)..'.lua'
  else
    local rpath = os.realpath(arg[1])
    if not rpath then io.stderr:write('error: file not found: '..arg[1]..'\n') os.exit(2) end
    os.program_path = os.dirname(os.realpath(arg[1]))
    addtoPATH(os.program_path)
  end
  function main()
    drop_arguments(1)
    dofile(arg[0])
  end
else
  function main()
    addtoPATH('.')
    local repl = require'repl'
    local loop = require'loop'
    repl.start(0)
    loop.run()
  end
end

main()
