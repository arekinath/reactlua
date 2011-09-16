local socket = require('socket')
local server = require('server')
local bit = require('bit')
local ffi = require('ffi')

ident = {}
local ident = ident
setfenv(1, ident)

function ident.resolve(serv, port, remote, cb)
	local ca, err = socket.addrinfo.new(remote.host, "ident", socket.SOCK_STREAM, 0, {'numerichost'})
	if not ca then
		cb({})
		return nil, err
	end
	local s, err = socket.new(ca.family, ca.socktype, ca.protocol)
	if not s then
		cb({})
		return nil, err
	end
	s = serv:wrap(s)
	s._close_cb = function() cb({}) end
	s.timeout = 1
	local ret, err = s:connect(ca.addr, ca.addrlen, function()
		s:write(tostring(port) .. ", " .. tostring(remote.port) .. "\n", function()
			s:read_line(function(_, _, line) 
				local tbl = {}
			
				local i,j = line:find("^[0-9]+, [0-9] %: ")
				line = line:sub(j+1)
				i,j = line:find("^[^ :]+ : ")
				tbl.resp = line:sub(i, j-3)
				line = line:sub(j+1)
				if tbl.resp == "USERID" then
					i,j = line:find("^[^ :]+ : ")
					tbl.sys = line:sub(i, j-3)
					line = line:sub(j+1)
					tbl.user = line
				elseif resp == "ERROR" then
					tbl.error = line
				end
				
				cb(tbl)
				s:close()
			end)
		end)
	end)
	return ret, err
end

return ident