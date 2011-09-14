local tcpserver = require('tcpserver')
local ffi = require('ffi')

local serv = tcpserver.new(1245)

serv:listen(function(serv, parent, sock)
	local self = {}
	
	sock:write("hello\n> ")
	
	self.cb = function(serv, sock, line)
		if line == 'exit\n' then
			sock:close()
		else
			sock:write("> ", function(serv, sock)
				sock:read_line(self.cb)
			end)
		end
	end
	sock:read_line(self.cb)
end)
