local ffi = require('ffi')
local poll = require('react.unix.poll')
local socket = require('react.unix.socket')
local bit = require('bit')
local server = require('react.server')
local fcntl = require('react.unix.fcntl')

local table = table
local ipairs = ipairs
local assert = assert
local print = print
local tostring = tostring
local setmetatable = setmetatable

tcpserver = {}
local tcpserver = tcpserver
setfenv(1, tcpserver)

function tcpserver.new(port)
    local w = server.new()
	local self = w
	w._port = port
	setmetatable(w, {__index = function(self, idx)
		if tcpserver[idx] then
			return tcpserver[idx]
		elseif server[idx] then
			return server[idx]
		end
	end })
    
	local gotone = false
    local ca, err = socket.addrinfo.new(nil, port, socket.SOCK_STREAM, 0, {'passive'})
    assert(ca, err and "could not get addrinfo: " .. err)
    while ca ~= nil do
        local s, err = socket.new(ca.family, ca.socktype, ca.protocol)
		assert(s, err and "socket: " .. err)
		if s:bind(ca.addr, ca.addrlen) and s:listen() then
			local sw = server.sockwrap.new(self, s)
			sw.notimeout = true
			sw:accept(function(serv, parent, sock)
				self._listen_callback(serv, parent, sock)
			end)
			gotone = true
		else
			s:close()
		end
        ca = ca.next
    end
    
    assert(gotone, "could not open any listen sockets")

	return self
end

function tcpserver:listen(cb)
	self._listen_callback = cb
	self:go()
end

return tcpserver