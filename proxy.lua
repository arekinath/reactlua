--[[
A basic http(s) proxy server in react.lua
]]

-- load libraries
local ffi = require('ffi')

local tcpserver = require('react.tcpserver')
local unbound = require('react.libs.unbound')
local ident = require('react.client.ident')

local http = require('example_helpers.http')
local log = require('example_helpers.log')

-- what port do we want?
local port = arg[1] or 8080

-- create the tcp server and boot up dns resolution
local serv = tcpserver.new(port)
unbound.link_to_server(serv)

-- this stores the count of failed ident requests for each host
local ident_fails = {}
setmetatable(ident_fails, {__index = function() return 0 end})

-- represents a connection to the proxy
local proxycon = {}

-- called when a new connection appears
function proxycon.new(serv, parent, client)
	local self = {}
	setmetatable(self, {__index = proxycon})
	
	self.client = client
	self.serv = serv
	local host = client.remote.host
	
	if ident_fails[host] < 5 then
		ident.resolve(serv, port, client.remote, function(id)
			if id.user then
				log.ident = id.user
			elseif not id.error then
				ident_fails[host] = ident_fails[host] + 1
			end
			http.parse_proxy_headers(client, function(head) self:find_remote(head) end)
		end)
	else
		http.parse_proxy_headers(client, function(head) self:find_remote(head) end)
	end
	
	return self
end

-- called to process a new request from the client
function proxycon:find_remote(head)
	self.head = head
	
	-- our mission here is to try to set up a remote socket
	-- so that we can pipe it back to our client
	
	-- we haven't got a valid remote socket yet
	local gotsock = false
	-- callback for potential remote sockets
	local sockback = function(serv, rsock)
		if rsock and not gotsock then
			gotsock = true
			self:proxy(rsock)
		elseif rsock then
			rsock:close()
		end
	end
	-- dns resolution callback
	local cb = function(err, result)
		if err == 0 then
			local family = nil
			if result.qtype == unbound.types.A then family = socket.AF_INET end
			if result.qtype == unbound.types.AAAA then family = socket.AF_INET6 end
			if family then
				for i,addr,len in result:addrs() do
					if self:try_connect(family, addr, len, sockback) and not gotsock then
						return 'again'
					end
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
	end
end

-- used by process()
function proxycon:try_connect(family, addr, len, cb)
	local s = serv:wrap(socket.new(family, socket.SOCK_STREAM, socket.IPPROTO_TCP))
	local a = socket.makeaddr(family, (self.head.url.port or 80), addr)
	return s:connect(ffi.cast('struct sockaddr*', a), ffi.sizeof(a[0]), cb)
end

-- the actual proxy method run once we have a remote socket
function proxycon:proxy(rsock)
	local head = self.head
	local client = self.client
	local serv = self.serv
	
	local before = head.url.raw:match("^([^%?]+)%?")
	log(client, head.method .. " " .. (before or head.url.raw))
			
	if head.method == 'CONNECT' then
		-- we want an SSL connection. this is an easy one!
		local resp = "HTTP/1.0 200 Connection Established\r\n\r\n"
		client:write(resp, function()
			-- pipe both sockets to each other
			rsock:pipe(client)
			client:pipe(rsock)
		end)
	else
		-- otherwise we got a plain http request. this is a little more tricky
		
		local adv = ""				-- reconstructed headers
		local have_host = false		-- do we have a valid hostname?
		local do_ka = false			-- should we do keepalive?
		
		-- reconstruct head part with just path
		if head.url.path == '' then head.url.path = '/' end
		head.lines[1] = head.method .. " " .. head.url.path .. " HTTP/1.1\r\n"
		
		-- now go through and filter the headers
		for i,v in ipairs(head.lines) do
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
		adv = adv .. "Connection: close\r\n"
		
		-- write the new headers to the remote side
		rsock:write(adv .. "\r\n", function()
			-- pipe the response back to our client
			rsock:pipe(client, nil, function()
				-- when the remote finishes sending data, close it
				rsock:close()
				-- if we want keepalive, start another request
				if do_ka then
					http.parse_proxy_headers(client, function(head) self:find_remote(head) end)
				else
					client:close()
				end
			end)
			-- also pipe the client to the remote (in case we have a POST or something)
			client:pipe(rsock)
		end)
	end
end

-- start the server listening for new connections
serv:listen(proxycon.new)
