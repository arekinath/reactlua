local ffi = require('ffi')
local poll = require('poll')
local socket = require('socket')
local bit = require('bit')
local fcntl = require('fcntl')

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
    local listen = {}
    setmetatable(listen, {__index = table})
    
    local read = {}
    setmetatable(read, {__index = table})
    
    local ca, err = socket.addrinfo.new(nil, port, socket.SOCK_STREAM, 0, {'passive'})
    assert(ca, err and "could not get addrinfo: " .. err)
    while ca ~= nil do
        local s, err = socket.new(ca.family, ca.socktype, ca.protocol)
		assert(s, err and "socket: " .. err)
		if s:bind(ca.addr, ca.addrlen) and s:listen() then
			listen:insert(s)
		else
			s:close()
		end
        ca = ca.next
    end
    
    assert(#listen > 0, "could not open any listen sockets")
    
    while true do
        -- make the fd list
        local p = poll.new(#listen + #read)
        for i,v in ipairs(listen) do
            p:insert(v.fd, {'in'})
        end
        for i,v in ipairs(read) do
            p:insert(v.fd, {'in', 'hup', 'err'})
        end
        
        -- do the poll
        local ret = p()
        assert(ret >= 0, "poll failed")
        
        -- process results
        local pi = 0
        for i,v in ipairs(listen) do
            if p[pi]:test('in') then
                local s = v:accept()
                print("got connection #" .. tostring(#read + 1))
                local msg = "hello world\n"
                local buf = ffi.new('char[?]', #msg + 1)
                ffi.copy(buf, msg)
                s:write(buf, #msg)
                fcntl.setflag(s.fd, 'nonblock')
                read:insert(s)
            end
            pi = pi + 1
        end
        for i,v in ipairs(read) do
			if p[pi]:test('err') or p[pi]:test('hup') then
                print('lost connection #' .. tostring(i))
                v:close()
                read:remove(i)
            elseif p[pi]:test('in') then
                local buf = ffi.new('char[?]', 128)
                local r = v:read(buf, 128)
                if (r <= 0) then
                    print('lost connection #' .. tostring(i))
                    v:close() 
                    read:remove(i)
                else
                    print("got chars on "..tostring(i)..": " .. ffi.string(buf, r))
                end
            end
            pi = pi + 1
        end
    end
end

return tcpserver