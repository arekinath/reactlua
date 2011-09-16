local tcpserver = require('tcpserver')
local socket = require('socket')
local ffi = require('ffi')
local file = require('file')
local fcntl = require('fcntl')
local http = require('http')
local unbound = require('unbound')
local log = require('log')

local serv = tcpserver.new(arg[1] or 8080)
unbound.link_to_server(serv)

serv:listen(function(serv, parent, client)
	local self = {}
	self.client = client
	self.serv = serv
	self.lines = {}
	
	function self.got_head(head)
		self.head = head
		self.process()
	end
	
	http.parse_proxy_headers(client, self.got_head)
	
	function self.try_connect(family, addr, len, cb)
		local s = serv:wrap(socket.new(family, socket.SOCK_STREAM, socket.IPPROTO_TCP))
		local a = socket.makeaddr(family, (self.head.url.port or 80), addr)
		return s:connect(ffi.cast('struct sockaddr*', a), ffi.sizeof(a[0]), cb)
	end
	
	function self.process()
		local gotsock = false
		local sockback = function(serv, rsock)
			if rsock and not gotsock then
				gotsock = true
				self.proxy(rsock)
			elseif rsock then
				rsock:close()
			end
		end
		local cb = function(err, result)
			if err == 0 then
				local family = nil
				if result.qtype == unbound.types.A then family = socket.AF_INET end
				if result.qtype == unbound.types.AAAA then family = socket.AF_INET6 end
				if family then
					for i,addr,len in result:addrs() do
						self.try_connect(family, addr, len, sockback)
					end
				end
			end
			if gotsock then return nil end
			return 'again'
		end
		
		local r, err = unbound.resolve(self.head.url.host, cb)
		if not r then
			local resp = "HTTP/1.0 500 Internal Server Error\r\n\r\n"
			resp = resp .. "Proxy connect failed: " .. err .. "\r\n"
			client:write(resp, function() client:close() end)
			return
		end
	end
	
	function self.proxy(rsock)
		local head = self.head
		
		log(client, head.method .. " " .. head.url.raw)
		if head.method == 'CONNECT' then
			local resp = "HTTP/"..head.version.." 200 Connection Established\r\n\r\n"
			client:write(resp, function()
				rsock:pipe(client)
				client:pipe(rsock)
			end)
		else
			local adv = ""
			local have_host = false
			local do_ka = false
			-- reconstruct head part with just path
			self.lines[1] = head.method .. " " .. head.url.path .. " HTTP/1.0\r\n"
			for i,v in ipairs(self.lines) do
				if v:find('^Host%:') then
					v = 'Host: ' .. head.url.host .. "\r\n"
					have_host = true
				end
				local j,k = v:find('^Proxy-Connection%: ')
				if j and k and v:sub(k):gsub("[\r\n]",""):lower() == 'keep-alive' then
					do_ka = true
				end
				if v ~= "\r\n" and not v:find('^Proxy') and not v:find('^Connection') then
					adv = adv .. v
				end
			end
			if not have_host then
				adv = adv .. "Host: " .. head.url.host .. "\r\n"
			end
			rsock:write(adv .. "\r\n", function()
				rsock:pipe(client, nil, function()
					rsock:close()
					if do_ka then
						http.parse_proxy_headers(client, self.got_head)
					else
						client:close()
					end
				end)
				client:pipe(rsock)
			end)
		end
	end
end)
