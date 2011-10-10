--[[
An ultra-simple TCP echo service in react.lua
]]

local tcpserver = require('react.tcpserver')

local port = arg[1] or 7777

local serv = tcpserver.new(port)
serv:listen(function(serv, parent, client)
	client:write("type characters to be echoed\r\n", function()
		client:pipe(client)
	end)
end)
