local tcpserver = require('tcpserver')
local socket = require('socket')
local ffi = require('ffi')
local file = require('file')
local unbound = require('unbound')

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
		local lkup = {http=80, https=443}
		ret.url.port = lkup[ret.url.protocol]
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
	
	function self.try_connect(family, addr, len)
		print("try_connect")
		local s = socket.new(family, socket.SOCK_STREAM, socket.IPPROTO_TCP)
		
		local ar = nil
		local port = socket.htons(tonumber(self.head.url.port or 80))
		if family == socket.AF_INET then
			a = ffi.new("struct sockaddr_in[?]", 1)
			if a[0].sin_len then a[0].sin_len = ffi.sizeof(a[0]) end
			a[0].sin_port = port
			a[0].sin_family = family
			ffi.copy(a[0].sin_addr, addr, ffi.sizeof(addr[0]))
		elseif family == socket.AF_INET6 then
			a = ffi.new("struct sockaddr_in6[?]", 1)
			if a[0].sin6_len then a[0].sin6_len = ffi.sizeof(a[0]) end
			a[0].sin6_port = port
			a[0].sin6_family = family
			ffi.copy(a[0].sin6_addr, addr, ffi.sizeof(addr[0]))
		end
		local ok,err = s:connect(ffi.cast('struct sockaddr*', a), ffi.sizeof(a[0]))
		if not ok then
			print("try_connect fail: ".. err or '')
			return nil, err
		end
		return s
	end
	
	function self.process(head)
		local head = self.head
		local v4, v6 = unbound.resolver.new(head.url.host)
		if not v4 or not v6 then
			local err = v6
			local resp = "HTTP/1.0 500 Internal Server Error\r\n\r\n"
			resp = resp .. "Proxy connect failed: " .. err .. "\r\n"
			print(err)
			sock:write(resp, function() sock:close() end)
			return
		end
		v4 = serv:wrap(v4)
		v6 = serv:wrap(v6)
		-- make sure they don't get gc'd
		self._v4 = v4
		self._v6 = v6
		
		local count = 0
		local wait_cb = function(_, v)
			count = count + 1
			local res, err = v:get_result()
			if count == 2 and (v6.result ~= nil or v4.result ~= nil) then
				if v6.result ~= nil then
					for i,addr,len in v6.result:addrs() do
						local rsock = self.try_connect(socket.AF_INET6, addr, len)
						if rsock then
							return self.proxy(rsock)
						end
					end
				end
				if v4.result ~= nil then
					for i,addr,len in v4.result:addrs() do
						local rsock = self.try_connect(socket.AF_INET, addr, len)
						if rsock then
							return self.proxy(rsock)
						end
					end
				end
			end
			if count == 2 then
				local resp = "HTTP/1.0 500 Internal Server Error\r\n\r\n"
				resp = resp .. "Proxy connect failed\r\n"
				sock:write(resp, function() sock:close() end)
			end
		end
		
		v4:wait_read(wait_cb)
		v6:wait_read(wait_cb)
	end
	
	function self.proxy(rsock)
		local head = self.head
		local s = serv:wrap(rsock)
		
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
	
	sock:read_line(self.line_cb)
end)
