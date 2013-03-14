local zip = require'zip'
local D = require'util'
z = assert(zip.open(os.executable_path))
for i=1,#z do
	D'file:'(z:stat(i))
	f = z:open(i)
	D'start:'(f:read(40))
	f:close()
end
z:add('test2.qwe', 'string', 'TEST DODAWANIA')
z:close()
