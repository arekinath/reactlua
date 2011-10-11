local log = {}

setmetatable(log, {__call = function(self, conn, txt)
	local front = "["
	if conn then front = front .. conn.remote.host .. ":" .. conn.remote.port end
	if log.ident then front = front .. "/" .. log.ident end
	front = front .. "] (" .. os.date("%Y%m%d-%X") .. ") " .. txt
	print(front)
end})

return log