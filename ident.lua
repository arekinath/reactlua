local bit = require('bit')
local ffi = require('ffi')
local socket = require('react.unix.socket')
local server = require('react.server')

local tostring = tostring
local tonumber = tonumber
local print = print

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
				line = line:gsub("[\r\n]", "")
				
				tbl.resp, line = line:match("^[0-9]+,%s?[0-9]+%s?%:%s?([^ :]+)%s?%:%s?(.+)")
				if tbl.resp == "USERID" then
					tbl.sys, tbl.user = line:match("^([^ :]+)%s?%:%s?([^ :]+)")
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