local log = require('log')

local string = string
local print = print
local table = table
local pairs = pairs
local type = type
local tostring = tostring

http = {}
local http = http
setfenv(1, http)

function _parse_url(ret, url)
	local prot, rest = url:match("^([a-z]+)%://(.+)$")
	if not prot then
		rest = url
		ret.protocol = "http"
	end
	ports = {http=80, https=443}
	ret.port = ports[ret.protocol]
	
	local host, path = rest:match("^([^/]+)(/.*)$")
	if not host or not path then return nil end
	ret.path = path
	
	local h, port = host:match("^([^%:])%:([0-9]+)$")
	if h and port then
		ret.host = h
		ret.port = port
	else
		ret.host = host
	end
	
	return ret
end

function _parse_proxy_salute(ret, line)
	line = line:gsub('[\r\n]', '')
	
	local method, url, ver = line:match("^([A-Z]+)%s+([^ ]+)%s+HTTP/([0-9%.]+)$")
	if not method or not url or not ver then return nil end
	
	ret.method = method
	ret.url = {}
	ret.url.raw = url
	ret.version = ver
	
	if http._parse_url(ret.url, ret.url.raw) == nil then return nil end
	
	return ret
end

function parse_proxy_headers(client, cb)
	local self = {}
	self.lines = {}
	
	function self.on_line(_, _, line)
		table.insert(self.lines, line)
		if #self.lines == 1 then
			if not _parse_proxy_salute(self, self.lines[1]) then
				log(client, "400 bad request")
				client:write("HTTP/1.0 400 Bad Request\r\n\r\n", function() client:close() end)
				return
			end
		elseif line == '\r\n' then
			return cb(self)
		end
		client:read_line(self.on_line)
	end
	
	client:read_line(self.on_line)
end

return http