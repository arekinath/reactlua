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
		ret.url.port = ret.url.protocol			--default
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
	ret.version = line:sub(6)
	
	return ret
end

serv:listen(function(serv, parent, sock)
	local self = {}
	self.lines = {}
	
	print(sock, "new conn: " .. sock.remote.host .. ":" .. sock.remote.port)
	
	function self.process(head)
		local head = self.head
		local addr, err = socket.addrinfo.new(head.url.host, head.url.port, socket.SOCK_STREAM)
		if not addr then
			print(sock, "500 " .. head.url.raw)
			local resp = "HTTP/1.0 500 Internal Server Error\r\n\r\n"
			resp = resp .. "Proxy connect failed: " .. err .. "\r\n"
			print(err)
			sock:write(resp, function() sock:close() end)
			return
		end
		local s = socket.new(addr.family, addr.socktype, addr.protocol)
		local ok,err = s:connect(addr.addr, addr.addrlen)
		if not ok then
			print(sock, "500 " .. head.url.raw)
			local resp = "HTTP/1.0 500 Internal Server Error\r\n\r\n"
			resp = resp .. "Proxy connect failed: " .. err .. "\r\n"
			print(err)
			sock:write(resp, function() sock:close() end)
			return
		end
		
		s = serv:wrap(s)
		
		print(sock, s, "[" .. sock.remote.host .. "] '" .. head.method .. "' " .. head.url.raw)
		if head.method == 'CONNECT' then
			local resp = "HTTP/"..head.version.." 200 Connection Established\r\n\r\n"
			sock:write(resp, function()
				s:pipe(sock)
				sock:pipe(s)
			end)
		else
			local adv = ""
			local have_host = false
			local have_con = false
			-- reconstruct head part with just path
			self.lines[1] = head.method .. " " .. head.url.path .. " HTTP/1.0\r\n"
			for i,v in ipairs(self.lines) do
				if v:find('^Host%:') then
					v = 'Host: ' .. head.url.host .. "\r\n"
					have_host = true
				end
				if v:find('^Connection%:') then
					v = 'Connection: Close\r\n'
					have_con = true
				end
				if v ~= "\r\n" and not v:find('^Proxy') then
					adv = adv .. v
				end
			end
			if not have_host then
				adv = adv .. "Host: " .. head.url.host .. "\r\n"
			end
			if not have_con then
				adv = adv .. "Connection: Close\r\n"
			end
			print("adv = '" .. adv .. "'")
			s:write(adv .. "\r\n", function()
				s:pipe(sock)
				sock:pipe(s)
			end)
		end
	end
	
	function self.line_cb(_, _, line)
		table.insert(self.lines, line)
		if #self.lines == 1 then
			self.head = parse_header(self.lines[1])
			if not self.head then
				print(sock, "invalid request")
				sock:write("HTTP/1.0 400 Invalid Request\r\n\r\n", function(serv, sock) sock:close() end)
				return
			end
		elseif line == '\r\n' then
			return self.process(self.head)
		end
		sock:read_line(self.line_cb)
	end
	
	sock:read_line(self.line_cb)
end)
