local tcpserver = require('tcpserver')
local ffi = require('ffi')
local file = require('file')

local serv = tcpserver.new(1245)

serv:listen(function(serv, parent, sock)
	local self = {}
	
	sock:read_line(function(serv, sock, line)
		local file, err = file.open(line:gsub('[\r\n]',''), {'rdonly'})
		if not file then
			sock:write(err .. "\n", function(serv, sock)
				sock:close()
			end)
		end
		
		local f = serv:wrap(file)
		f:pipe(sock)
	end)
end)
