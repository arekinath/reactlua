local log = require('log')

local string = string
local print = print
local table = table

http = {}
local http = http
setfenv(1, http)

function _parse_proxy_salute(ret, line)
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