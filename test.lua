local tcpserver = require('tcpserver')
local socket = require('socket')
local ffi = require('ffi')
local file = require('file')

local serv = tcpserver.new(arg[1] or 8080)

function parse_header(line)
	local ret = {}
	line = line:gsub('[\r\n]', '')
	
	local i,j = line:find("^[A-Z]+ ")
	if not i or not j then print("bad method") return nil end
	ret.method = line:sub(i, j-1)
	line = line:sub(j+1)
	
	ret.url = {}
	i,j = line:find("^[^ ]+ ")
	if not i or not j then print("no url") return nil end
	ret.url.raw = line:sub(i,j-1)
	line = line:sub(j+1)
	
	local url = ret.url.raw
	i,j = url:find("^[a-z]+://")
	if i and j then
		ret.url.protocol = url:sub(i,j-3)
		ret.url.port = url.protocol			--default
		url = url:sub(j+1)
	end
	
	i,j = url:find("^[^:/]+")
	if not i or not j then print("no hostname") return nil end
	ret.url.host = url:sub(i,j)
	url = url:sub(j+1)
	
	i,j = url:find("^:[^:/]+")
	if i and j then
		ret.url.port = url:sub(i+1, j)
		url = url:sub(j+1)
	end

	ret.url.path = url
	
	i,j = line:find("^HTTP/[0-9.]+")
	if not i or not j then print("no http sig") return nil end
	ret.version = line:sub(5)
	
	return ret
end

serv:listen(function(serv, parent, sock)
	local self = {}
	self.lines = {}
	
	self.line_cb = function(serv, sock, line)
		table.insert(self.lines, line)
		if line ~= '\r\n' then
			sock:read_line(self.line_cb)
		else
			-- this is the empty line, let's go
			local head = parse_header(self.lines[1])
			if not head or head.method ~= 'CONNECT' then
				print("invalid request")
				sock:write("HTTP/1.0 400 Invalid Request\r\n\r\n", function(serv, sock) sock:close() end)
				return
			end
			local addr = socket.addrinfo.new(head.url.host, head.url.port, socket.SOCK_STREAM)
			local s = socket.new(addr.family, addr.socktype, addr.protocol)
			local ok,err = s:connect(addr.addr, addr.addrlen)
			if not ok then
				print("500 " .. head.url.raw)
				local resp = [[HTTP/1.0 500 Internal Server Error\r
				\r
				Proxy connect failed:
				]] .. err .. "\r\n"
				sock:write(resp, function(serv, sock) sock:close() end)
			else
				print("200 " .. head.url.raw)
				local resp = "HTTP/1.0 200 Connection Established\r\n\r\n"
				sock:write(resp, function(serv, sock)
					s = serv:wrap(s)
					s:pipe(sock)
					sock:pipe(s)
				end)
			end
		end
	end
	
	sock:read_line(self.line_cb)
end)
